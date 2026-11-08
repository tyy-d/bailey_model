# Manual balcony transcription — reviewed baseline

Source: `CMCM_2026_Bail(ey)ing_Out.pdf`, page 5 (second-floor circulation and stairs) and page 7 (numbered balcony chairs, rotated upright for inspection).

## Source correction and explicit omission

The page-7 chair summary reads **316**, not 315. The earlier planning statement that it read 315 was incorrect. The requested model nevertheless contains **315** chairs: `CCC-324` in the left-center section is deliberately omitted and its cell is walkable. This is an explicit modeling deviation, not a claim that the source contains 315 chairs. Wheelchair places are not added. The user reviewed the layout and authorized continuing with this baseline.

## Transcribed chair runs

The strip unfolds from the left stage end, around the rear of the balcony, to the right stage end. Left/even seat numbers run upward; right/odd numbers run downward in the unfolded strip. Source chair-number endpoints were read visually rather than inferred from the printed chair-width subtotals.

| Section | AAA (front) | BBB (middle) | CCC (back) | Model total |
|---|---|---|---|---|
| LW, left wing | 102–144 even (22) | 102–144 even (22) | 102–124 even (12) | 56 |
| LA, left arc | 202–238 even (19) | 202–242 even (21) | 202–224 even (12) | 52 |
| LC, left center | 302–338 even (19) | 302–340 even (20) | 302–322 even (11); 324 omitted | 50 |
| RC, right center | 337–301 odd (19) | 339–301 odd (20) | 323–301 odd (12) | 51 |
| RA, right arc | 237–201 odd (19) | 241–201 odd (21) | 223–201 odd (12) | 52 |
| RW, right wing | 141–101 odd (21) | 141–101 odd (21) | 123–101 odd (12) | 54 |
| Total | 119 | 125 | 71 | **315** |

## Geometry and exit interpretation

- One seat occupies one `s` cell. Its front is the walkable cell immediately below it. `s` and `w` are permanently impassable. Rows AAA/BBB/CCC occur at grid rows 8/6/4; row passages are 9/7/5. Back circulation occupies rows 2–3.
- Six source seating sections are separated by two-cell radial aisles. Two-cell access aisles also occur at the stage ends. This preserves connectivity, not measured lengths, widths, stair geometry, or curvature. Unequal row lengths are left-aligned within each unfolded section.
- CCC chairs occur in triples between columns. Columns are schematic one-cell `w` markers at triple boundaries; they are not a surveyed structural-column plan. Their positions and the exterior boundary are simplified. Each triple has its own group section identifier so a group cannot cross a column.
- Page 5 shows four marked stair access routes: stage-left, left foyer, right foyer, stage-right. These become E1–E4. Foyer accesses lie at LA/LC and RC/RA boundaries. Stage-end access points are unfolded onto the back boundary at the two ends. All stop at the route entrance; downstream stairs and corridors are excluded.
- The central radial aisle is not an exit. No first-floor exits, elevator, service rooms, open-to-below areas, or projection-room route are modeled. This is the audience balcony seating strip, not the whole second-floor building envelope.
- The additional upward stair is excluded by agreement with the user: its connection to an outside corridor is unconfirmed. Its entrance is represented by the closed `w` boundary, not an absorbing exit. Adjacent circulation remains walkable. This is a modeling assumption about an excluded route, not a conclusion that upward stairs cannot be evacuation routes. Retain E1–E4 only; revisit this assumption if its destination is confirmed.
- Exit width is one cell per route, not a measured doorway width. Exits absorb immediately and have no rate or capacity limit.

## Checks performed by the agent

- Visually inspected the full page-5 plan and full page-7 seating map, then enlarged the numbered chair runs and chair summary.
- Cross-checked six section totals, the four circulation-route positions, column-separated outer-row triples, and left/right numbering asymmetry.
- Programmatic validation checks 315 unique mapped seat cells, unobstructed front cells, consecutive group runs, valid exits, and a walkable path from every spawn to an exit.
- The user checked the layout, raised the omitted upward stair, and accepted treating its entrance as blocked before authorizing continuation. Widths, column placement, the omitted chair, and stage-end exit relocation remain explicit schematic assumptions.

Approval is tied to the SHA-256 of all four layout CSVs and this note. Editing any of them invalidates approval. Regenerate the preview after edits; do not approve a stale preview.
