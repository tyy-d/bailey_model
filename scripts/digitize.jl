# Manual transcription of the numbered chair runs on PDF p7. This is not OCR.
# Run from any directory; inspect data/digitization.md before editing these runs.
include(joinpath(@__DIR__,"..","src","BaileyModel.jl"))
using .BaileyModel

function digitize(dir=DEFAULT_DATA)
    mkpath(dir)
    # Left stage end -> left rear -> rear center -> right rear -> right stage end.
    specs = [
        ("LW","Left wing",22,collect(102:2:144),collect(102:2:144),collect(102:2:124)),
        ("LA","Left arc",21,collect(202:2:238),collect(202:2:242),collect(202:2:224)),
        ("LC","Left center",20,collect(302:2:338),collect(302:2:340),collect(302:2:324)),
        ("RC","Right center",20,collect(337:-2:301),collect(339:-2:301),collect(323:-2:301)),
        ("RA","Right arc",21,collect(237:-2:201),collect(241:-2:201),collect(223:-2:201)),
        ("RW","Right wing",21,collect(141:-2:101),collect(141:-2:101),collect(123:-2:101)),
    ]
    # Widths include 2-cell radial aisles and 2-cell stage-end access aisles.
    ncols=2+4+sum(s[3] for s in specs)+2*(length(specs)-1)
    grid=fill('0',10,ncols)
    grid[1,:].='w'; grid[end,:].='w'; grid[:,1].='w'; grid[:,end].='w'
    seats=Vector{Any}(); sections=Vector{Any}(); starts=Int[]
    start=4
    for (id,label,width,aaa,bbb,ccc) in specs
        push!(starts,start)
        push!(sections,(id,label,start,start+width-1,length(aaa),length(bbb),length(ccc)-(id=="LC" ? 1 : 0)))
        for (row_name,r,numbers) in (("CCC",4,ccc),("BBB",6,bbb),("AAA",8,aaa))
            run=1; order=0
            for (j,number) in enumerate(numbers)
                # Outer seats occur in triples separated by columns. Inner rows are continuous.
                offset=row_name=="CCC" ? 1+(j-1)+div(j-1,3) : j-1
                col=start+offset
                if row_name=="CCC" && j>1 && (j-1)%3==0
                    run+=1; order=0
                end
                # Explicit, reviewable deviation from the source's 316 chairs.
                row_name=="CCC" && id=="LC" && number==324 && continue
                order+=1
                grid[r,col]='s'
                # For CCC, columns break groups; names retain physical section plus run.
                section=row_name=="CCC" ? "$id-$run" : id
                push!(seats,("$row_name-$number",row_name,section,order,r,col,r+1,col))
            end
            if row_name=="CCC"
                for offset in (0,4,8,12,16)
                    grid[r,start+offset]='w'
                end
            end
        end
        start+=width+2
    end
    # The four stair access points shown on p5. End exits are unfolded onto the back boundary.
    exitcols=[2,starts[3]-1,starts[5]-1,ncols-1]
    labels=["Stage-left stair access","Left foyer stair access","Right foyer stair access","Stage-right stair access"]
    for col in exitcols; grid[1,col]='0'; end
    open(joinpath(dir,"floorplan.csv"),"w") do io
        for r in axes(grid,1); println(io,join(grid[r,:],',')); end
    end
    # Input CSV is intentionally simple and unquoted. All identifiers exclude commas.
    function table(name,header,rows)
        open(joinpath(dir,name),"w") do io
            println(io,header)
            for row in rows; println(io,join(row,',')); end
        end
    end
    table("seats.csv","seat_id,row_name,section,order,seat_row,seat_col,front_row,front_col",sort(seats;by=s->(s[5],s[6])))
    table("exits.csv","exit_id,row,col,label",[("E$i",1,col,labels[i]) for (i,col) in enumerate(exitcols)])
    table("sections.csv","section,label,start_col,end_col,AAA,BBB,CCC",sections)
    println("Wrote $(length(seats)) seats to $dir")
end

if abspath(PROGRAM_FILE)==@__FILE__
    digitize()
    l=load_layout()
    mkpath(joinpath(ROOT,"output"))
    preview_svg(l,joinpath(ROOT,"output","layout_preview.svg"))
    println("Validated layout. Preview: output/layout_preview.svg. Human review remains pending.")
end
