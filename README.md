# Bailey balcony simulation

A Julia agent simulation of the straightened second-floor balcony. The simulation core uses only Julia standard libraries; the interactive viewer has its own pinned GLMakie environment.

**The baseline layout has been reviewed.** The user accepted excluding the additional upward stair because its connection to an outside corridor is unconfirmed. Its entrance remains a closed `w` boundary; nearby passages stay walkable. See [the digitization notes](data/digitization.md) for the source chair runs, exit interpretation, and simplifications. The PDF actually says 316 chairs; this requested 315-chair model explicitly omits `CCC-324`. Local approval is fingerprinted; a fresh checkout or later layout changes still require recording approval as described below.

## Inspect and approve the layout

From the repository root, using Julia 1.12 (validated with 1.12.4):

```sh
julia --project=. scripts/bailey.jl validate
julia --project=. scripts/bailey.jl preview
```

Open `output/layout_preview.svg` (seat identifiers appear as tooltips) or the supplied `output/layout_preview.png`. Compare with PDF pages 5 and 7. Review the seat omission, source chair labels, aisle connectivity, schematic columns, four stair-access exits, and relocation of stage-end accesses to the back boundary. Each CSV row is a grid row, from top to bottom. Coordinates are 1-based.

After you approve the geometry, record the **exact SHA-256 printed on the reviewed SVG**, replacing `PASTE_SHA256`:

```sh
julia --project=. scripts/bailey.jl approve PASTE_SHA256
```

This records a local `data/layout_approval.txt`, excluded from version control. Editing a layout CSV or the digitization notes invalidates approval. The command also rejects a preview with a stale fingerprint. The check is a review workflow, not an access-control system; low-level functions remain available for tests and experiments.

To revise the layout, edit the CSVs directly, or update the manual chair transcription in `scripts/digitize.jl` and regenerate with `julia --project=. scripts/digitize.jl`. Regeneration overwrites the four CSVs and canonical SVG. An optional `scripts/render_preview.cjs` produces the PNG with Node and `sharp`; rerender it after changing the SVG.

## Interactive viewer

```sh
julia --project=viewer -e 'using Pkg; Pkg.instantiate()'
julia --project=viewer viewer/viewer.jl
```

The native GLMakie window needs a working graphical desktop/OpenGL context. The first load compiles dependencies and can take several minutes. The viewer has Play/Pause, Single step, Reset seed, a steps-per-second slider, and a history slider. Scrubbing changes only the displayed frame. Advancing from an earlier frame replays saved history before generating new steps. Reset restores the original people, groups, speeds, and directions. Exports include all generated history, even if the displayed frame is earlier.

To customize a viewer run in the Julia REPL:

```julia
include("viewer/viewer.jl")
require_approval()
config = Config(seed=2026, p=0.5, C=4, max_steps=10_000)
show_viewer(initialize(load_layout(), config))
```

Heat is `n * minimum(V)` for the people currently in each cell; empty cells are zero. The color scale stays fixed at `[0,5C]`. Seats, walls, and exits have distinct colors. Counts and statuses correspond to the displayed frame. `max_steps` means the audience has **not** necessarily evacuated.

## Headless run and exports

After layout approval:

```sh
julia --project=. scripts/bailey.jl run --seed 2026 --p 0.5 --C 4 --max-steps 10000 --output output/runs/example
```

Output paths must not already exist. The CLI defaults to a unique run directory if `--output` is omitted. Files:

| CSV | Contents |
|---|---|
| `config.csv` | Seed, p, C, maximum steps, Julia version, RNG, layout fingerprint, terminal/current status |
| `people.csv` | Initial person/group/seat IDs, speed, call period, spawn, direction |
| `groups.csv` | Realized group sizes after boundary shortening |
| `steps.csv` | Step zero and subsequent remaining/exited counts, calls, accepted moves, rejections, per-exit totals, status |
| `exit_events.csv` | One row per evacuated person |
| `positions.csv` | Each person's location at each saved step; `(0,0)` marks exited people |

All time values are simulation steps. Native viewer exports may have `running` status if you export before completion. `evacuated` and `max_steps` are the terminal statuses. Histories are retained in memory; large maximum-step settings and dense populations increase memory and export size.

## Exact model rules

- Scan seat cells in upper-left row-major order: CCC, BBB, AAA. Draw `G=min(Geometric(p),C)` with support `0,1,…`; `G=0` leaves one seat empty. Otherwise occupy the next G consecutive seats in the same row and section, shortening at the boundary. CCC column gaps split group sections. There is no independent occupancy probability π.
- Draw all group assignments before drawing speeds, using one `Random.Xoshiro(seed)`. Each occupant has an independently rejected-normal speed `3+randn(rng)` in `[1,5]`, fixed for the run. Every occupant starts in their seat's front cell.
- Call person i only at steps `k,2k,…`, where `k=ceil(Int,5/Vᵢ)`. Calls are not randomized or staggered. A person can attempt at most one cell move per call.
- Use up/right/down/left neighbors. Seats and walls cannot be entered or crossed. Initial heading selects the legal neighbor closest to any exit by Euclidean distance; exact distance ties use the direction order.
- All eligible actions use the same pre-resolution occupancy. Exit score is exactly 100; other scores are `same_group_count-total_count-D*log(D)`, where D is the candidate cell's Euclidean distance to the closest exit and log is the natural logarithm. Same-group occupants cancel their occupancy cost, while other-group occupants incur a penalty of one each. Full cells remain candidates. Among highest scores, prefer the cache, then direction order; there is no distance tie-breaker. Cache the selected direction before resolution, including rejected actions. With no legal neighbors, wait. The initial heading and exit-distance action-resolution order remain unchanged.
- Resolve cached actions by Euclidean distance of each person's **pre-move** position to the nearest exit, then person ID. Check capacity against the evolving occupancy. Accepted moves free the source cell immediately. Full destinations reject without retry. A swap between two full cells is therefore rejected rather than coordinated atomically.
- An accepted exit move removes the person immediately. Exit cells never store people and do not have a throughput limit. Shared `C` limits both sampled group size and non-exit cell occupancy; it does not force a group to remain together.
- Stop at complete evacuation or the step limit. There is no hidden path planning, rerouting, or anti-cycle logic. Local scores and direction persistence can cause wandering or permanent non-evacuation; an incomplete run is a valid reported outcome of these rules.

Use the same Julia version for exact random-sequence replay. The viewer's dependencies are pinned in `viewer/Manifest.toml`; configuration and layout fingerprints accompany every export.

## Validation

```sh
julia --project=. test/runtests.jl
julia --project=viewer test/viewer_smoke.jl
```

Core tests cover layout validity and reachability, zero-based geometric draws, boundary shortening, speed bounds, due-step scheduling, ties, group scores, snapshot decisions, capacity rejection, sequential space reuse, conflict order, immediate exits, conservation, heat, reproducibility, history navigation, reset, stopping, CSV exports, and stale approval detection. Actual balcony initialization is checked without advancing it. All trajectory tests use synthetic layouts. The optional viewer smoke test exercises native rendering and widget callbacks using a synthetic audience only.

The core is also available as `using BaileyModel` with `--project=.`. The exported APIs are `Config`, `load_layout`, `initialize`, `step!`, `run!`, `frame`, `heatmap_values`, `status`, `export_run`, validation/review helpers, and `Playback` with `select_frame!`, `advance!`, and `reset!`.

## Reviewed baseline result

The reviewed layout retains four exits and blocks the unconfirmed upward-stair route. With seed 2026, p=0.5, C=4, and 10,000 maximum steps, the initial audience is 213 people. With `same_group_count-total_count-D*log(D)`, all 213 evacuate by step 108 (E1: 37, E2: 69, E3: 70, E4: 37); status is `evacuated`. The earlier coefficient-2 score with the distance penalty produced 207 exits and 6 remaining at step 10,000 (`output/runs/distance-penalty-seed-2026/`). The original score without the distance penalty produced 66 exits and 147 remaining (`output/runs/baseline-seed-2026/`). Earlier exports are preserved. No path planning or anti-cycle behavior was added.

The current complete exports are in `output/runs/unit-group-seed-2026/`. Native viewer renders are `output/baseline_initial.png` and `output/baseline_final.png`, refreshed for the current scoring rule. Restart any already-open viewer to load changes to the scoring code. To repeat the full approved-layout integration check, including byte-for-byte comparison of all six CSV exports and native rendering:

```sh
julia --project=viewer test/approved_baseline.jl
```

This optional check requires the recorded approval and the current export directory. Unlike the unit tests, it runs the actual balcony model. The current exports include 109 frames and 23,217 person-position records.

Large run exports and machine-local approval files are excluded from Git. On a fresh checkout, review and approve the layout using the commands above, then generate the current reference exports before running the integration check:

```sh
julia --project=. scripts/bailey.jl run --output output/runs/unit-group-seed-2026
```
