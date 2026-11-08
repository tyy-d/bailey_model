module BaileyModel

using Random, SHA

export Config, Seat, Exit, Layout, Person, Simulation, Frame, Playback,
       load_layout, validate_layout, initialize, step!, run!, heatmap_values,
       frame, status, check_invariants, export_run, layout_fingerprint,
       require_approval, approve_layout, preview_svg, select_frame!, advance!, reset!,
       ROOT, DEFAULT_DATA

const ROOT = dirname(@__DIR__)
const DEFAULT_DATA = joinpath(ROOT, "data")
const Cell = CartesianIndex{2}
# Direction indices are part of the deterministic tie-breaking contract.
const DIRECTIONS = (Cell(-1, 0), Cell(0, 1), Cell(1, 0), Cell(0, -1))

struct Config
    seed::Int
    p::Float64
    C::Int
    max_steps::Int
    function Config(; seed::Integer=2026, p::Real=0.5, C::Integer=4,
                    max_steps::Integer=10_000)
        seed >= 0 || throw(ArgumentError("seed must be nonnegative"))
        isfinite(p) && 0 < p <= 1 || throw(ArgumentError("p must be in (0,1]"))
        C >= 1 || throw(ArgumentError("C must be positive"))
        max_steps >= 1 || throw(ArgumentError("max_steps must be positive"))
        new(Int(seed), Float64(p), Int(C), Int(max_steps))
    end
end

struct Seat
    id::String
    row_name::String
    section::String
    order::Int
    cell::Cell
    front::Cell
end

struct Exit
    id::String
    cell::Cell
    label::String
end

struct Layout
    grid::Matrix{Char}
    seats::Vector{Seat}
    exits::Vector{Exit}
    exit_at::Dict{Cell,Int}
    distance2::Matrix{Int}
    fingerprint::String
end

function Layout(grid::Matrix{Char}, seats::Vector{Seat}, exits::Vector{Exit}; fingerprint="synthetic")
    isempty(exits) && throw(ArgumentError("layout needs at least one exit"))
    exit_at = Dict(e.cell => i for (i,e) in enumerate(exits))
    distance2 = [minimum(sum(abs2, Tuple(c-e.cell)) for e in exits)
                 for c in CartesianIndices(grid)]
    Layout(grid, seats, exits, exit_at, distance2, fingerprint)
end

"""Read the deliberately restricted, unquoted CSV format used by layout inputs."""
function read_table(path, header)
    lines = readlines(path)
    !isempty(lines) && split(lines[1], ',') == header ||
        throw(ArgumentError("$path: expected header $(join(header, ','))"))
    rows = [split(line, ','; keepempty=true) for line in lines[2:end]]
    all(length(r) == length(header) && all(!isempty, r) for r in rows) ||
        throw(ArgumentError("$path: empty value or incorrect column count"))
    rows
end

function layout_fingerprint(dir=DEFAULT_DATA)
    io = IOBuffer()
    for name in ("floorplan.csv", "seats.csv", "exits.csv", "sections.csv", "digitization.md")
        write(io, name, '\0', read(joinpath(dir, name)), '\0')
    end
    bytes2hex(sha256(take!(io)))
end

function load_layout(dir=DEFAULT_DATA; expected_seats::Union{Int,Nothing}=315)
    lines = readlines(joinpath(dir, "floorplan.csv"))
    isempty(lines) && throw(ArgumentError("floorplan.csv is empty"))
    rows = [split(line, ','; keepempty=true) for line in lines]
    n = length(rows[1])
    n > 0 && all(length(r) == n for r in rows) || throw(ArgumentError("ragged floorplan CSV"))
    all(v in ("0", "s", "w") for r in rows for v in r) ||
        throw(ArgumentError("floorplan accepts only 0, s, w"))
    grid = [only(rows[r][c]) for r in eachindex(rows), c in 1:n]
    sr = read_table(joinpath(dir,"seats.csv"),
        ["seat_id","row_name","section","order","seat_row","seat_col","front_row","front_col"])
    seats = [Seat(r[1],r[2],r[3],parse(Int,r[4]),
                  Cell(parse(Int,r[5]),parse(Int,r[6])),Cell(parse(Int,r[7]),parse(Int,r[8]))) for r in sr]
    er = read_table(joinpath(dir,"exits.csv"), ["exit_id","row","col","label"])
    exits = [Exit(r[1],Cell(parse(Int,r[2]),parse(Int,r[3])),r[4]) for r in er]
    layout = Layout(grid, seats, exits; fingerprint=layout_fingerprint(dir))
    validate_layout(layout; expected_seats)
    sections=read_table(joinpath(dir,"sections.csv"),["section","label","start_col","end_col","AAA","BBB","CCC"])
    ids=[s[1] for s in sections]
    length(unique(ids))==length(ids) || throw(ArgumentError("duplicate physical section ID"))
    Set(ids)==Set(first(split(s.section,'-')) for s in seats) ||
        throw(ArgumentError("physical sections do not match seats"))
    previous_end=0
    for s in sections
        start_col,end_col=parse.(Int,s[3:4])
        1 <= start_col <= end_col <= size(grid,2) && start_col > previous_end ||
            throw(ArgumentError("invalid or overlapping section columns"))
        previous_end=end_col
        ss=filter(seat->first(split(seat.section,'-'))==s[1],seats)
        all(start_col <= seat.cell[2] <= end_col for seat in ss) ||
            throw(ArgumentError("seat outside its physical section"))
        counts=[count(seat->seat.row_name==row,ss) for row in ("AAA","BBB","CCC")]
        counts==parse.(Int,s[5:7]) || throw(ArgumentError("section chair counts disagree with seats"))
    end
    layout
end

walkable(l::Layout,c::Cell) = checkbounds(Bool,l.grid,c) && l.grid[c] == '0'
neighbors(l::Layout,c::Cell) = [(d,c+DIRECTIONS[d]) for d in 1:4 if walkable(l,c+DIRECTIONS[d])]

function validate_layout(l::Layout; expected_seats::Union{Int,Nothing}=315)
    all(c in ('0','s','w') for c in l.grid) || throw(ArgumentError("invalid terrain token"))
    expected_seats === nothing || length(l.seats) == expected_seats ||
        throw(ArgumentError("expected $expected_seats seats; got $(length(l.seats))"))
    length(unique(s.id for s in l.seats)) == length(l.seats) || throw(ArgumentError("duplicate seat ID"))
    length(unique(s.cell for s in l.seats)) == length(l.seats) || throw(ArgumentError("duplicate seat cell"))
    count(==('s'),l.grid) == length(l.seats) || throw(ArgumentError("unmapped seat cells"))
    length(unique(e.id for e in l.exits)) == length(l.exits) || throw(ArgumentError("duplicate exit ID"))
    length(l.exit_at) == length(l.exits) || throw(ArgumentError("duplicate exit cell"))
    for e in l.exits
        walkable(l,e.cell) || throw(ArgumentError("exit $(e.id) must be walkable"))
    end
    seen = Set(e.cell for e in l.exits)
    queue = collect(seen)
    i=1
    while i <= length(queue)
        c=queue[i]; i+=1
        for (_,n) in neighbors(l,c)
            n in seen && continue
            push!(seen,n); push!(queue,n)
        end
    end
    for s in l.seats
        checkbounds(Bool,l.grid,s.cell) && l.grid[s.cell]=='s' ||
            throw(ArgumentError("seat $(s.id) is not on s"))
        s.order > 0 || throw(ArgumentError("seat order must be positive"))
        s.front == s.cell+Cell(1,0) || throw(ArgumentError("seat $(s.id): front must be directly below seat"))
        walkable(l,s.front) || throw(ArgumentError("seat $(s.id): front is obstructed"))
        !haskey(l.exit_at,s.front) || throw(ArgumentError("seat front cannot be an exit"))
        s.front in seen || throw(ArgumentError("seat $(s.id) cannot reach an exit"))
    end
    # A section/row is a contiguous run of seats; gaps require a different section ID.
    for key in unique((s.row_name,s.section) for s in l.seats)
        ss=sort(filter(s->(s.row_name,s.section)==key,l.seats);by=s->s.order)
        [s.order for s in ss] == collect(1:length(ss)) || throw(ArgumentError("nonconsecutive seat orders in $key"))
        all(ss[j].cell == ss[j-1].cell+Cell(0,1) for j in 2:length(ss)) ||
            throw(ArgumentError("nonconsecutive seat cells in $key; split at gaps"))
    end
    true
end

mutable struct Person
    id::Int
    group::Int
    seat_id::String
    speed::Float64
    period::Int
    position::Cell
    direction::Int
    active::Bool
end

struct Action
    person::Int
    destination::Cell
    direction::Int
end

struct ExitEvent
    step::Int
    person::Int
    group::Int
    exit::Int
end

struct Frame
    step::Int
    positions::Vector{Cell} # Cell(0,0) means exited
    heat::Matrix{Float64}
    remaining::Int
    exit_totals::Vector{Int}
    moved::Int
    rejected::Int
    called::Int
    status::Symbol
end

mutable struct Simulation
    layout::Layout
    config::Config
    people::Vector{Person}
    occupancy::Matrix{Vector{Int}}
    initial_people::Vector{Person}
    events::Vector{ExitEvent}
    history::Vector{Frame}
    step::Int
    moved::Int
    rejected::Int
    called::Int
end

"""Zero-based geometric, capped without an unbounded rejection loop."""
function group_size(rng, p, C)
    p == 1 && return 0
    # Geometric inverse CDF; min before conversion avoids overflow for tiny p.
    Int(min(floor(log1p(-rand(rng))/log1p(-p)), C))
end

function speed_draw(rng)
    while true
        v=3+randn(rng)
        1 <= v <= 5 && return v
    end
end

function initial_direction(l,c)
    ns=neighbors(l,c)
    isempty(ns) && return 0
    first(sort(ns;by=x->(l.distance2[x[2]],x[1])))[1]
end

function initialize(l::Layout, cfg::Config=Config())
    validate_layout(l;expected_seats=nothing)
    rng=Xoshiro(cfg.seed)
    occupancy=[Int[] for _ in axes(l.grid,1), _ in axes(l.grid,2)]
    # Assign ALL groups before speed draws so speed rejection cannot alter membership.
    sorted=sort(l.seats;by=s->Tuple(s.cell))
    assignments=Tuple{Seat,Int}[]
    i=1; group=0
    while i <= length(sorted)
        s=sorted[i]
        g=group_size(rng,cfg.p,cfg.C)
        if g==0
            i+=1; continue
        end
        group+=1
        j=i
        while j <= length(sorted) && j < i+g
            t=sorted[j]
            (t.row_name==s.row_name && t.section==s.section && t.order==s.order+j-i) || break
            push!(assignments,(t,group)); j+=1
        end
        i=j
    end
    people=Person[]
    for (seat,g) in assignments
        v=speed_draw(rng); id=length(people)+1
        push!(people,Person(id,g,seat.id,v,ceil(Int,5/v),seat.front,initial_direction(l,seat.front),true))
        push!(occupancy[seat.front],id)
    end
    any(length(cell)>cfg.C for cell in occupancy) && throw(ArgumentError("initial spawn occupancy exceeds C"))
    sim=Simulation(l,cfg,people,occupancy,deepcopy(people),ExitEvent[],Frame[],0,0,0,0)
    check_invariants(sim)
    push!(sim.history,frame(sim))
    sim
end

function status(sim::Simulation)
    all(!p.active for p in sim.people) && return :evacuated
    sim.step >= sim.config.max_steps && return :max_steps
    :running
end

function movement_score(sim::Simulation,p::Person,n::Cell)
    haskey(sim.layout.exit_at,n) && return 100.0
    ids=sim.occupancy[n]
    D=sqrt(sim.layout.distance2[n])
    # Natural logarithm; extend D*log(D) continuously to zero.
    penalty=D==0 ? 0.0 : D*log(D)
    count(id->sim.people[id].group==p.group,ids)-length(ids)-penalty
end

function choose_action(sim::Simulation,p::Person)
    ns=neighbors(sim.layout,p.position)
    isempty(ns) && return nothing
    best=maximum(movement_score(sim,p,n) for (_,n) in ns)
    candidates=filter(x->movement_score(sim,p,x[2])==best,ns)
    chosen=first(sort(candidates;by=x->(x[1]==p.direction ? 0 : 1,x[1])))
    Action(p.id,chosen[2],chosen[1])
end

function step!(sim::Simulation)
    status(sim)==:running || return sim.history[end]
    sim.step+=1
    sim.moved=0; sim.rejected=0; sim.called=0
    actions=Action[]
    for p in sim.people
        p.active && sim.step % p.period == 0 || continue
        sim.called+=1
        a=choose_action(sim,p)
        a===nothing && continue
        p.direction=a.direction
        push!(actions,a)
    end
    # All actions were chosen above; now occupancy mutates in exit-distance order.
    sort!(actions;by=a->(sim.layout.distance2[sim.people[a.person].position],a.person))
    for a in actions
        p=sim.people[a.person]
        exit=get(sim.layout.exit_at,a.destination,0)
        if exit==0 && length(sim.occupancy[a.destination]) >= sim.config.C
            sim.rejected+=1
            continue
        end
        source=sim.occupancy[p.position]
        deleteat!(source,findfirst(==(p.id),source))
        if exit!=0
            p.active=false
            p.position=Cell(0,0)
            push!(sim.events,ExitEvent(sim.step,p.id,p.group,exit))
        else
            p.position=a.destination
            push!(sim.occupancy[p.position],p.id)
        end
        sim.moved+=1
    end
    check_invariants(sim)
    f=frame(sim); push!(sim.history,f); f
end

function heatmap_values(sim::Simulation)
    [isempty(ids) ? 0.0 : length(ids)*minimum(sim.people[id].speed for id in ids)
     for ids in sim.occupancy]
end

function frame(sim::Simulation)
    totals=zeros(Int,length(sim.layout.exits))
    for e in sim.events; totals[e.exit]+=1; end
    Frame(sim.step,[p.position for p in sim.people],heatmap_values(sim),
          count(p->p.active,sim.people),totals,sim.moved,sim.rejected,sim.called,status(sim))
end

function check_invariants(sim::Simulation)
    seen=Int[]
    for c in CartesianIndices(sim.occupancy)
        ids=sim.occupancy[c]
        length(ids) <= sim.config.C || error("capacity exceeded at $c")
        isempty(ids) || walkable(sim.layout,c) || error("person on obstruction")
        isempty(ids) || !haskey(sim.layout.exit_at,c) || error("person retained on exit")
        for id in ids
            p=sim.people[id]
            p.id==id && p.active && p.position==c || error("person/occupancy mismatch")
            push!(seen,id)
        end
    end
    sort!(seen)
    seen==[p.id for p in sim.people if p.active] || error("missing or duplicated person")
    inactive=[p.id for p in sim.people if !p.active]
    sort([e.person for e in sim.events])==inactive || error("exit conservation failed")
    all(p.active || p.position==Cell(0,0) for p in sim.people) || error("exited person has a position")
    true
end

function run!(sim::Simulation)
    while status(sim)==:running; step!(sim); end
    sim
end

"""History navigation never rewinds or mutates the live simulation."""
mutable struct Playback
    sim::Simulation
    index::Int
end
Playback(sim::Simulation)=Playback(sim,1)
function select_frame!(p::Playback,index::Integer)
    1 <= index <= length(p.sim.history) || throw(BoundsError(p.sim.history,index))
    p.index=Int(index); p.sim.history[p.index]
end
function advance!(p::Playback)
    if p.index < length(p.sim.history)
        p.index+=1
    elseif status(p.sim)==:running
        step!(p.sim); p.index=length(p.sim.history)
    end
    p.sim.history[p.index]
end
function reset!(p::Playback)
    old=p.sim
    people=deepcopy(old.initial_people)
    occupancy=[Int[] for _ in axes(old.layout.grid,1),_ in axes(old.layout.grid,2)]
    for person in people; push!(occupancy[person.position],person.id); end
    p.sim=Simulation(old.layout,old.config,people,occupancy,deepcopy(people),ExitEvent[],Frame[],0,0,0,0)
    check_invariants(p.sim)
    push!(p.sim.history,frame(p.sim))
    p.index=1; p.sim.history[1]
end

function require_approval(dir=DEFAULT_DATA)
    file=joinpath(dir,"layout_approval.txt")
    isfile(file) && strip(read(file,String))==layout_fingerprint(dir) ||
        throw(ArgumentError("Layout review required: inspect output/layout_preview.svg and data/digitization.md, then approve this exact layout. See README."))
    true
end

"""Call only after the human has reviewed and approved the labeled preview."""
function approve_layout(dir=DEFAULT_DATA)
    load_layout(dir)
    write(joinpath(dir,"layout_approval.txt"),layout_fingerprint(dir)*"\n")
end

csv_escape(x) = "\""*replace(string(x),'"'=>"\"\"")*"\""
function write_csv(path,header,rows)
    open(path,"w") do io
        println(io,join(csv_escape.(header),','))
        for row in rows; println(io,join(csv_escape.(row),',')); end
    end
end

function export_run(sim::Simulation,dir)
    # Refuse to overwrite a previous run accidentally.
    ispath(dir) && throw(ArgumentError("output directory already exists: $dir"))
    mkpath(dir)
    c=sim.config
    write_csv(joinpath(dir,"config.csv"),["key","value"],
        [("seed",c.seed),("p",c.p),("C",c.C),("max_steps",c.max_steps),
         ("julia_version",VERSION),("rng","Random.Xoshiro"),("layout_sha256",sim.layout.fingerprint),
         ("time_unit","simulation step"),("movement_score","same_group_count-total_count-D*log(D); exits=100; natural log"),
         ("tie_breakers","cached direction; up/right/down/left"),("status",status(sim))])
    write_csv(joinpath(dir,"people.csv"),["person_id","group_id","seat_id","speed","period","initial_row","initial_col","initial_direction"],
        [(p.id,p.group,p.seat_id,p.speed,p.period,p.position[1],p.position[2],p.direction) for p in sim.initial_people])
    write_csv(joinpath(dir,"groups.csv"),["group_id","size"],
        [(g,count(p->p.group==g,sim.initial_people)) for g in sort(unique(p.group for p in sim.initial_people))])
    write_csv(joinpath(dir,"steps.csv"),vcat(["step","remaining","exited","called","moved","rejected","status"],
        ["exit_"*e.id for e in sim.layout.exits]),
        [vcat(Any[f.step,f.remaining,length(sim.people)-f.remaining,f.called,f.moved,f.rejected,f.status],f.exit_totals) for f in sim.history])
    write_csv(joinpath(dir,"exit_events.csv"),["step","person_id","group_id","exit_id"],
        [(e.step,e.person,e.group,sim.layout.exits[e.exit].id) for e in sim.events])
    write_csv(joinpath(dir,"positions.csv"),["step","person_id","row","col","active"],
        ((f.step,id,pos[1],pos[2],pos!=Cell(0,0)) for f in sim.history for (id,pos) in enumerate(f.positions)))
    dir
end

include("preview.jl")

end
