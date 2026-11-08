xml_escape(x)=replace(string(x),'&'=>"&amp;",'<'=>"&lt;",'>'=>"&gt;",'"'=>"&quot;")

"""Write a dependency-free, labeled SVG for human inspection; no simulation runs."""
function preview_svg(l::Layout,path; reviewed::Bool=false)
    cell=12; left=110; top=160; width=max(1300,left+size(l.grid,2)*cell+50); height=560
    open(path,"w") do io
        println(io,"""<svg xmlns="http://www.w3.org/2000/svg" width="$width" height="$height" viewBox="0 0 $width $height">
        <rect width="100%" height="100%" fill="#f8fafc"/>
        <g font-family="Arial, sans-serif" fill="#172033">
        <text x="30" y="35" font-size="24" font-weight="bold">Bailey balcony — straightened layout / $(reviewed ? "REVIEWED BASELINE" : "REVIEW PENDING")</text>
        <text x="30" y="63" font-size="15">315 seats · PDF pages 5 and 7 · seat-based schematic · not a physical scale drawing</text>
        <text x="30" y="88" font-size="14">Left stage end → left wing → rear center → right wing → right stage end. Front of seats faces down.</text>""")
        for r in axes(l.grid,1), c in axes(l.grid,2)
            token=l.grid[r,c]
            color=token=='s' ? "#d19a45" : token=='w' ? "#334155" : "#ffffff"
            x=left+(c-1)*cell; y=top+(r-1)*cell
            println(io,"<rect x=\"$x\" y=\"$y\" width=\"$cell\" height=\"$cell\" fill=\"$color\" stroke=\"#cbd5e1\" stroke-width=\"0.4\"/>")
        end
        for (name,r) in (("Back access",2),("CCC seats",4),("CCC passage",5),("BBB seats",6),("BBB passage",7),("AAA seats",8),("AAA passage",9))
            println(io,"<text x=\"8\" y=\"$(top+(r-0.25)*cell)\" font-size=\"11\">$name</text>")
        end
        for e in l.exits
            x=left+(e.cell[2]-1)*cell
            println(io,"<rect x=\"$x\" y=\"$top\" width=\"$cell\" height=\"$cell\" fill=\"#14b8a6\"/>")
            # Stagger exit labels to avoid collisions at the ends.
            anchor=e.cell[2]<5 ? "start" : e.cell[2]>size(l.grid,2)-5 ? "end" : "middle"
            println(io,"<text x=\"$(x+6)\" y=\"130\" text-anchor=\"$anchor\" font-size=\"13\" font-weight=\"bold\">$(xml_escape(e.id*": "*e.label))</text>")
            println(io,"<path d=\"M $(x+6) 136 V $top\" stroke=\"#0f766e\"/>")
        end
        # Seat tooltips preserve the exact source numbering.
        for s in l.seats
            x=left+(s.cell[2]-1)*cell; y=top+(s.cell[1]-1)*cell
            println(io,"<rect x=\"$x\" y=\"$y\" width=\"$cell\" height=\"$cell\" fill=\"transparent\"><title>$(xml_escape(s.id)) / $(xml_escape(s.section)) / spawn $(Tuple(s.front))</title></rect>")
        end
        # Mark the intentionally omitted seat at the end of the LC outer row.
        omitted=filter(s->s.id=="CCC-322",l.seats)
        if !isempty(omitted)
            c=only(omitted).cell[2]+1
            x=left+(c-1)*cell; y=top+3*cell
            println(io,"<rect x=\"$x\" y=\"$y\" width=\"$cell\" height=\"$cell\" fill=\"#fecaca\" stroke=\"#dc2626\" stroke-width=\"2\"/>")
            println(io,"<path d=\"M $(x+6) $(y+12) V 345\" stroke=\"#dc2626\"/>")
            println(io,"<text x=\"$(x+6)\" y=\"364\" text-anchor=\"middle\" fill=\"#b91c1c\" font-size=\"13\">CCC-324 omitted: source 316 → requested 315</text>")
        end
        for section in unique(s.section for s in l.seats if s.row_name=="AAA")
            ss=filter(s->s.section==section && s.row_name=="AAA",l.seats)
            col=(minimum(s.cell[2] for s in ss)+maximum(s.cell[2] for s in ss))/2
            n=count(s->first(split(s.section,'-'))==section,l.seats)
            println(io,"<text x=\"$(left+(col-0.5)*cell)\" y=\"302\" text-anchor=\"middle\" font-size=\"14\" font-weight=\"bold\">$section: $n seats</text>")
        end
        println(io,"""<text x="30" y="412" font-size="15">Legend: white = walkable (0) · ochre = seats (s) · slate = walls / columns (w) · teal = absorbing exits</text>
        <text x="30" y="439" font-size="14">Every seat spawns directly below into its row passage. Dark cells in CCC represent columns; radial aisles connect all passages.</text>
        <text x="30" y="466" font-size="14">Review: chair counts and source labels; aisle topology; four exit positions; omitted seat; schematic widths and end-exit relocation.</text>
        <text x="30" y="493" font-size="13">Rows/columns in CSV are 1-based, origin upper left. Exact seat identifiers are available as SVG tooltips and in seats.csv.</text>
        <text x="30" y="529" font-size="11">Layout SHA-256: $(l.fingerprint)</text>
        </g></svg>""")
    end
    path
end
