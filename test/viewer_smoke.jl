# Optional native GUI integration check. Synthetic data only: no balcony run.
using Test
include(joinpath(@__DIR__,"..","viewer","viewer.jl"))

grid=fill('0',6,12)
grid[1,:].='w'; grid[end,:].='w'; grid[:,1].='w'; grid[:,end].='w'
grid[1,10]='0'
seats=[Seat("S$i","A","A",i,CartesianIndex(3,i+2),CartesianIndex(4,i+2)) for i in 1:5]
for s in seats; grid[s.cell]='s'; end
layout=Layout(grid,seats,[Exit("E1",CartesianIndex(1,10),"Synthetic exit")])
sim=initialize(layout,Config(p=1e-300,max_steps=8))
ui=build_viewer(sim)
@test ui.ax.yreversed[]
@test ui.current[].step==0
ui.step.clicks[]+=1
@test ui.current[].step==1
@test ui.slider.value[]==1
ui.step.clicks[]+=1
@test ui.current[].step==2
set_close_to!(ui.slider,0)
@test ui.current[].step==0
@test ui.playback.sim.step==2
ui.step.clicks[]+=1
@test ui.current[].step==1 # replay, not a new step
@test ui.playback.sim.step==2
ui.play.clicks[]+=1
@test ui.playing[] && ui.play.label[]=="Pause"
ui.play.clicks[]+=1
@test !ui.playing[]
ui.reset.clicks[]+=1
@test ui.current[].step==0 && length(ui.playback.sim.history)==1
@test ui.current[].heat==sim.history[1].heat
for _ in 1:8; ui.step.clicks[]+=1; end
@test ui.current[].status in (:evacuated,:max_steps)
@test !ui.playing[]
# Native off-screen render exercises the actual GLMakie backend and all widgets.
save(joinpath(tempdir(),"bailey-viewer-smoke.png"),ui.fig)
GLMakie.closeall()
println("Viewer controls and native rendering passed (synthetic layout).")
