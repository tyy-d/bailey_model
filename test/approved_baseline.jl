# Explicit integration check for the approved balcony; not part of unit tests.
using Test
include(joinpath(@__DIR__,"..","viewer","viewer.jl"))
require_approval()
sim=initialize(load_layout(),Config())
run!(sim)
@test check_invariants(sim)
baseline=isempty(ARGS) ? joinpath(ROOT,"output","runs","unit-group-seed-2026") : abspath(only(ARGS))
isdir(baseline) || error("Generate $baseline with the current scoring rule before this check")
mktempdir() do dir
    repeat=joinpath(dir,"repeat")
    export_run(sim,repeat)
    for name in readdir(baseline)
        @test read(joinpath(repeat,name))==read(joinpath(baseline,name))
    end
end
ui=build_viewer(sim)
@test ui.current[].step==0
@test ui.ax.yreversed[]
save(joinpath(ROOT,"output","baseline_initial.png"),ui.fig)
ui.refresh(select_frame!(ui.playback,length(sim.history)))
@test ui.current[].remaining==sim.history[end].remaining
@test ui.current[].heat==sim.history[end].heat
@test ui.slider.value[]==sim.step
save(joinpath(ROOT,"output","baseline_final.png"),ui.fig)
GLMakie.closeall()
println("Approved balcony: all six CSV exports reproduced byte-for-byte; initial/final native renders saved.")
