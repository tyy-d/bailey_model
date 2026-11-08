include(joinpath(@__DIR__,"..","src","BaileyModel.jl"))
using .BaileyModel

function main(args)
    isempty(args) && error("Usage: julia --project=. scripts/bailey.jl preview|validate|approve SHA|run [--seed N --p P --C N --max-steps N --output DIR]")
    command=first(args)
    if command=="preview"
        length(args)==1 || error("preview takes no arguments")
        layout=load_layout()
        mkpath(joinpath(ROOT,"output"))
        approval=joinpath(DEFAULT_DATA,"layout_approval.txt")
        reviewed=isfile(approval) && strip(read(approval,String))==layout.fingerprint
        println(preview_svg(layout,joinpath(ROOT,"output","layout_preview.svg");reviewed))
        println("SHA-256: ",layout.fingerprint)
    elseif command=="validate"
        length(args)==1 || error("validate takes no arguments")
        l=load_layout()
        # Initialization checks only: do not advance the unapproved model.
        sim=initialize(l)
        println("Valid: $(length(l.seats)) seats; $(length(l.exits)) exits; $(length(sim.people)) initialized people; $(size(l.grid)) grid.")
        println("SHA-256: ",l.fingerprint)
    elseif command=="approve"
        length(args)==2 || error("approve requires the exact SHA shown on the reviewed SVG")
        args[2]==layout_fingerprint() || error("Fingerprint does not match the current layout")
        svg=joinpath(ROOT,"output","layout_preview.svg")
        isfile(svg) && occursin(args[2],read(svg,String)) || error("Regenerate and inspect the current preview before approving")
        approve_layout()
        preview_svg(load_layout(),svg;reviewed=true)
        println("Recorded your approval of layout ",args[2])
    elseif command=="run"
        opts=Dict{String,String}()
        iseven(length(args)-1) || error("run options must be --name value pairs")
        for i in 2:2:length(args)
            key=args[i]
            key in ("--seed","--p","--C","--max-steps","--output") || error("Unknown option $key")
            haskey(opts,key) && error("Duplicate option $key")
            opts[key]=args[i+1]
        end
        cfg=Config(seed=parse(Int,get(opts,"--seed","2026")),p=parse(Float64,get(opts,"--p","0.5")),
                   C=parse(Int,get(opts,"--C","4")),max_steps=parse(Int,get(opts,"--max-steps","10000")))
        require_approval()
        sim=initialize(load_layout(),cfg)
        run!(sim)
        dir=get(opts,"--output",joinpath(ROOT,"output","runs","seed-$(cfg.seed)-$(time_ns())"))
        export_run(sim,dir)
        println("Status: $(status(sim)); step $(sim.step); remaining $(sim.history[end].remaining). Export: $dir")
    else
        error("Unknown command $command")
    end
end

if abspath(PROGRAM_FILE)==@__FILE__
    try
        main(ARGS)
    catch e
        println(stderr,sprint(showerror,e)); exit(1)
    end
end
