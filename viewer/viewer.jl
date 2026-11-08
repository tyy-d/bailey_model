include(joinpath(@__DIR__,"..","src","BaileyModel.jl"))
using .BaileyModel
using GLMakie

function build_viewer(sim::Simulation)
    playback=Playback(sim)
    current=Observable(sim.history[1])
    playing=Observable(false)
    syncing=Ref(false)
    fig=Figure(size=(1500,720),fontsize=14)
    Label(fig[1,1:2],"Bailey balcony evacuation",fontsize=24,font=:bold)
    Label(fig[2,1:2],"Heat = population × slowest speed   |   time unit: simulation step   |   schematic geometry")
    ax=Axis(fig[3,1],xlabel="Unfolded balcony column",ylabel="Grid row",yreversed=true,
            title="Seats: ochre  ·  Walls/columns: slate  ·  Exits: teal")
    l=sim.layout; nr,nc=size(l.grid)
    values=lift(f->permutedims(f.heat),current)
    hm=heatmap!(ax,1:nc,1:nr,values;colormap=:inferno,colorrange=(0.0,5.0*sim.config.C))
    terrain=fill(NaN,nc,nr)
    for r in 1:nr,c in 1:nc
        l.grid[r,c]=='s' && (terrain[c,r]=1)
        l.grid[r,c]=='w' && (terrain[c,r]=2)
        haskey(l.exit_at,CartesianIndex(r,c)) && (terrain[c,r]=3)
    end
    heatmap!(ax,1:nc,1:nr,terrain;colormap=["#d19a45","#334155","#14b8a6"],
             colorrange=(1,3),nan_color=:transparent)
    for e in l.exits
        text!(ax,e.cell[2],e.cell[1];text=e.id,color=:white,fontsize=11,align=(:center,:center))
    end
    # Explicit reversed limits preserve the CSV's upper-left origin. An ascending
    # limits! call would override Axis(yreversed=true).
    limits!(ax,0.5,nc+0.5,nr+0.5,0.5)
    Colorbar(fig[3,2],hm;label="H = n × min(V)")
    summary=lift(current) do f
        exits=join(["$(l.exits[i].id): $(n)" for (i,n) in enumerate(f.exit_totals)],"   ")
        "Step $(f.step)   |   Remaining $(f.remaining) / $(length(sim.people))   |   $(f.status)\n"*
        "Exited: $exits   |   Called $(f.called), accepted $(f.moved), rejected $(f.rejected)"
    end
    Label(fig[4,1:2],summary)
    slider=Slider(fig[5,1:2];range=0:1,startvalue=0)
    controls=GridLayout(fig[6,1:2])
    play=Button(controls[1,1],label="Play")
    step=Button(controls[1,2],label="Single step")
    reset=Button(controls[1,3],label="Reset seed")
    export_button=Button(controls[1,4],label="Export generated history")
    speed=Slider(controls[1,5];range=1:60,startvalue=10)
    Label(controls[1,6],lift(x->"$(round(Int,x)) steps/s",speed.value))
    message=Observable("Scrub saved history; Play or Single step generates new history at its end. Reset reinitializes the same seed.")
    Label(fig[7,1:2],message;fontsize=12)
    function refresh(f)
        syncing[]=true
        try
            slider.range[]=0:max(1,length(playback.sim.history)-1)
            set_close_to!(slider,f.step)
            current[]=f
        finally
            syncing[]=false
        end
        if f.status!=:running && playback.index==length(playback.sim.history)
            playing[]=false
        end
        f
    end
    on(slider.value) do value
        syncing[] && return
        playing[]=false
        idx=clamp(round(Int,value)+1,1,length(playback.sim.history))
        refresh(select_frame!(playback,idx))
    end
    on(play.clicks) do _
        playing[]=!playing[]
    end
    on(playing) do value
        play.label[]=value ? "Pause" : "Play"
    end
    on(step.clicks) do _
        playing[]=false; refresh(advance!(playback))
    end
    on(reset.clicks) do _
        playing[]=false; refresh(reset!(playback))
    end
    on(export_button.clicks) do _
        dir=joinpath(ROOT,"output","runs","viewer-$(time_ns())")
        try
            export_run(playback.sim,dir)
            message[]="Exported generated history through step $(playback.sim.step): $dir"
        catch e
            message[]="Export failed: "*sprint(showerror,e)
        end
    end
    refresh(current[])
    (;fig,ax,playback,current,playing,slider,play,step,reset,export_button,speed,message,refresh)
end

function show_viewer(sim::Simulation)
    ui=build_viewer(sim)
    screen=display(ui.fig)
    println("Viewer ready: Play/Pause, Single step, Reset seed, and history controls are available.")
    @async begin
        while isopen(screen)
            if ui.playing[]
                try
                    ui.refresh(advance!(ui.playback))
                catch e
                    ui.playing[]=false
                    ui.message[]="Simulation error: "*sprint(showerror,e)
                end
            end
            sleep(1/ui.speed.value[])
        end
    end
    wait(screen)
    ui
end

if abspath(PROGRAM_FILE)==@__FILE__
    # No actual balcony simulation is created or advanced until review is recorded.
    require_approval()
    cfg=Config() # Edit or call show_viewer(initialize(layout, Config(...))) in the REPL.
    show_viewer(initialize(load_layout(),cfg))
end
