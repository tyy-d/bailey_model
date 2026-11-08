using Test, Random
include(joinpath(@__DIR__,"..","src","BaileyModel.jl"))
using .BaileyModel
const B=BaileyModel
const CI=CartesianIndex

function synthetic(grid,exits,positions;groups=collect(1:length(positions)),speeds=fill(5.0,length(positions)),C=4,max_steps=50,directions=fill(0,length(positions)))
    l=Layout(grid,Seat[],[Exit("E$i",e,"Synthetic exit") for (i,e) in enumerate(exits)])
    people=[Person(i,groups[i],"test-$i",speeds[i],ceil(Int,5/speeds[i]),pos,directions[i],true) for (i,pos) in enumerate(positions)]
    occ=[Int[] for _ in axes(grid,1),_ in axes(grid,2)]
    for p in people; push!(occ[p.position],p.id); end
    sim=Simulation(l,Config(;C,max_steps),people,occ,deepcopy(people),B.ExitEvent[],Frame[],0,0,0,0)
    check_invariants(sim); push!(sim.history,frame(sim)); sim
end

@testset "Configuration and floor plan" begin
    @test_throws ArgumentError Config(p=0)
    @test_throws ArgumentError Config(p=NaN)
    @test_throws ArgumentError Config(C=0)
    @test_throws ArgumentError Config(seed=-1)
    @test_throws ArgumentError Config(max_steps=0)
    l=load_layout()
    @test length(l.seats)==315
    @test count(==('s'),l.grid)==315
    @test length(l.exits)==4
    @test all(l.grid[1,c]=='w' || haskey(l.exit_at,CI(1,c)) for c in axes(l.grid,2))
    @test all(l.grid[r,c]=='0' for r in 2:3 for c in 2:size(l.grid,2)-1)
    @test validate_layout(l)
    @test !any(s->s.id=="CCC-324",l.seats)
    sim=initialize(l)
    @test check_invariants(sim)
    @test all(1<=p.speed<=5 && p.period==ceil(Int,5/p.speed) for p in sim.people)
    @test all(s.front==s.cell+CI(1,0) for s in l.seats)
    @test maximum(length.(sim.occupancy))<=sim.config.C
    @test isempty(initialize(l,Config(p=1)).people)
    @test status(initialize(l,Config(p=1)))==:evacuated
    bad=deepcopy(l.grid); bad[l.seats[1].front]='w'
    @test_throws ArgumentError validate_layout(Layout(bad,l.seats,l.exits))
    bad=deepcopy(l.grid); bad[2:end-1,:].='w'
    for s in l.seats; bad[s.cell]='s'; bad[s.front]='0'; end
    @test_throws ArgumentError validate_layout(Layout(bad,l.seats,l.exits))
    mktempdir() do d
        for name in ("floorplan.csv","seats.csv","exits.csv","sections.csv","digitization.md")
            cp(joinpath(DEFAULT_DATA,name),joinpath(d,name))
        end
        @test_throws ArgumentError require_approval(d)
        approve_layout(d)
        @test require_approval(d)
        open(joinpath(d,"digitization.md"),"a") do io; println(io,"changed"); end
        @test_throws ArgumentError require_approval(d)
        write(joinpath(d,"sections.csv"),"section,label,start_col,end_col,AAA,BBB,CCC\nLW,broken,4,25,0,0,0\n")
        @test_throws ArgumentError load_layout(d)
        write(joinpath(d,"floorplan.csv"),"0,s\nw\n")
        @test_throws ArgumentError load_layout(d)
        write(joinpath(d,"floorplan.csv"),"0,x\nw,w\n")
        @test_throws ArgumentError load_layout(d)
    end
end

@testset "Group sampling and boundary shortening" begin
    rng=Xoshiro(91)
    draws=[B.group_size(rng,0.5,4) for _ in 1:20_000]
    @test 0.48 < count(==(0),draws)/length(draws) < 0.52
    @test 0.045 < count(==(4),draws)/length(draws) < 0.08
    @test extrema(draws)==(0,4)
    @test B.group_size(rng,1.0,4)==0
    # Tiny p forces capped draws; two rows/sections must shorten independently.
    grid=fill('0',6,6)
    seats=[Seat("A$i","A","A",i,CI(2,i+1),CI(3,i+1)) for i in 1:2]
    append!(seats,[Seat("B$i","B","B",i,CI(4,i+1),CI(5,i+1)) for i in 1:3])
    for s in seats; grid[s.cell]='s'; end
    l=Layout(grid,seats,[Exit("E",CI(1,1),"Exit")])
    sim=initialize(l,Config(p=1e-300))
    @test [p.group for p in sim.people]==[1,1,2,2,2]
    @test [p.seat_id for p in sim.people]==["A1","A2","B1","B2","B3"]
    @test all(1<=B.speed_draw(rng)<=5 for _ in 1:1000)
    # Seeded random synthetic audiences also replay exactly through full trajectories.
    a=initialize(l,Config(seed=4321,p=0.2,max_steps=30))
    b=initialize(l,Config(seed=4321,p=0.2,max_steps=30))
    run!(a); run!(b)
    @test [(f.positions,f.heat,f.exit_totals) for f in a.history]==[(f.positions,f.heat,f.exit_totals) for f in b.history]
end

@testset "Scheduling, exits, and heat" begin
    grid=fill('w',3,4); grid[2,2:3].='0'
    sim=synthetic(grid,[CI(2,3)],[CI(2,2)];speeds=[2.0])
    @test sim.people[1].period==3
    @test heatmap_values(sim)[2,2]==2.0
    @test heatmap_values(sim)[1,1]==0
    @test step!(sim).called==0
    @test step!(sim).called==0
    f=step!(sim)
    @test f.called==1 && f.remaining==0 && f.exit_totals==[1]
    @test status(sim)==:evacuated
    @test isempty(sim.occupancy[2,3])
    @test length(sim.events)==1
    @test step!(sim).step==3
    sim=synthetic(grid,[CI(2,3)],[CI(2,2),CI(2,2)];speeds=[2.0,4.0])
    @test heatmap_values(sim)[2,2]==4.0
end

@testset "Scores, cache, distance, and fixed order" begin
    grid=fill('w',5,5); grid[2:4,2:4].='0'
    sim=synthetic(grid,[CI(2,2)],[CI(3,3)];directions=[2])
    @test B.initial_direction(sim.layout,CI(3,3))==1
    @test B.choose_action(sim,sim.people[1]).direction==1 # distance penalty outranks cache
    sim.people[1].direction=4
    @test B.choose_action(sim,sim.people[1]).direction==4 # cache resolves equal scores
    sim.people[1].direction=0
    @test B.choose_action(sim,sim.people[1]).direction==1 # up before left for equal scores
    @test B.movement_score(sim,sim.people[1],CI(3,4)) ≈ -sqrt(5)*log(sqrt(5))
    @test B.movement_score(sim,sim.people[1],CI(2,3))==0.0 # D=1
    @test B.movement_score(sim,sim.people[1],CI(2,2))==100.0 # finite at exit, D=0
    sim=synthetic(grid,[CI(2,4)],[CI(3,3),CI(3,4)];groups=[1,1],directions=[1,0])
    @test B.movement_score(sim,sim.people[1],CI(3,4))==0.0 # friends cancel their occupancy cost
    @test B.choose_action(sim,sim.people[1]).direction==1 # friend cell ties empty cell; cache wins
    sim.people[2].group=2
    @test B.choose_action(sim,sim.people[1]).direction==1 # avoid other group
    sim=synthetic(grid,[CI(2,3)],[CI(3,3),CI(3,4)];groups=[1,1],directions=[2,0])
    @test B.choose_action(sim,sim.people[1]).destination==CI(2,3) # exit=100
end

@testset "Snapshot decisions and sequential resolution" begin
    grid=fill('w',3,6); grid[2,2:5].='0'
    # Closer occupant exits first, freeing capacity for the following cached action.
    sim=synthetic(grid,[CI(2,5)],[CI(2,4),CI(2,3)];groups=[1,1],C=1,directions=[2,2])
    f=step!(sim)
    @test !sim.people[1].active
    @test sim.people[2].position==CI(2,4)
    @test f.moved==2 && f.rejected==0
    # Four non-group occupants make the exitward cell less attractive. The friend
    # in the opposite cell leaves later, but both decisions must use the snapshot.
    sim=synthetic(grid,[CI(2,5)],[CI(2,3),CI(2,2),fill(CI(2,4),4)...];
        groups=[1,1,fill(2,4)...],speeds=[5.,5.,fill(1.,4)...],C=4,directions=fill(2,6))
    step!(sim)
    @test sim.people[1].position==CI(2,2)
    @test sim.people[2].position==CI(2,3)
    # Not-due occupant blocks a cached action; rejected person retains selected cache.
    sim=synthetic(grid,[CI(2,5)],[CI(2,3),CI(2,4)];groups=[1,1],speeds=[5.,1.],C=1,directions=[4,2])
    f=step!(sim)
    @test sim.people[1].position==CI(2,3) && f.rejected==1
    @test sim.people[1].direction==2
    # Two equidistant contenders for one empty cell: stable person ID wins.
    grid=fill('w',5,5); grid[2,3]='0'; grid[3,2:4].='0'
    sim=synthetic(grid,[CI(2,3)],[CI(3,2),CI(3,4)];C=1,directions=[2,4])
    f=step!(sim)
    @test sim.people[1].position==CI(3,3)
    @test sim.people[2].position==CI(3,4)
    @test f.rejected==1
    # Exit absorption is unlimited, even with C=1.
    grid=fill('w',5,5); grid[3,2:4].='0'
    sim=synthetic(grid,[CI(3,3)],[CI(3,2),CI(3,4)];C=1)
    step!(sim)
    @test status(sim)==:evacuated && length(sim.events)==2
end

@testset "Reproducibility, playback, export, and stopping" begin
    # Reproducibility of actual balcony INITIALIZATION; no unapproved full runs.
    l=load_layout(); a=initialize(l); b=initialize(l)
    signature(s)=[(p.id,p.group,p.seat_id,p.speed,p.period,p.position,p.direction) for p in s.people]
    @test signature(a)==signature(b)
    grid=fill('w',3,6); grid[2,2:5].='0'
    make()=synthetic(grid,[CI(2,5)],[CI(2,2),CI(2,3)];groups=[1,1],max_steps=20,directions=[2,2])
    a=make(); b=make(); run!(a); run!(b)
    @test signature(a)==signature(b)
    @test [(f.positions,f.heat,f.exit_totals) for f in a.history]==[(f.positions,f.heat,f.exit_totals) for f in b.history]
    @test all(f.remaining+sum(f.exit_totals)==length(a.people) for f in a.history)
    @test all(maximum(f.heat)<=5*a.config.C for f in a.history)
    playback=Playback(make())
    advance!(playback); advance!(playback)
    latest=signature(playback.sim)
    f=select_frame!(playback,1)
    @test f.step==0
    @test signature(playback.sim)==latest
    @test advance!(playback).step==1
    reset!(playback)
    @test playback.index==1 && length(playback.sim.history)==1 && playback.sim.step==0
    @test signature(playback.sim)==signature(make())
    @test_throws BoundsError select_frame!(playback,2)
    blocked=fill('w',5,5); blocked[2,2]='0'; blocked[4,4]='0'
    sim=synthetic(blocked,[CI(2,2)],[CI(4,4)];max_steps=3)
    run!(sim)
    @test status(sim)==:max_steps && sim.history[end].remaining==1
    @test length(sim.history)==4
    mktempdir() do d
        out=joinpath(d,"run")
        export_run(a,out)
        @test sort(readdir(out))==sort(["config.csv","people.csv","groups.csv","steps.csv","exit_events.csv","positions.csv"])
        @test length(readlines(joinpath(out,"steps.csv")))==length(a.history)+1
        @test length(readlines(joinpath(out,"positions.csv")))==length(a.history)*length(a.people)+1
        @test_throws ArgumentError export_run(a,out)
    end
end
