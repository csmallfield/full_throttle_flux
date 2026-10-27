# FTF v38: junctions on the track surface

Builder-track junctions (`TrackJunction`: the fork and rejoin on Builder Lab
and Fork Lab) were the last road on the grid, with no UV2 and no weather, so
the road switched to the cyan grid at every fork and rejoin. They now draw
the v38 track surface and carry the same data as a `TrackRoadSegment`. The
splitter wedge stays on the grid.

Same branch, `feature/v38-track-surface`. Phase notes:
`FTF_v38_TRACK_SURFACE.md` and `_P2.md` to `_P5B.md`.

## The rule for t where two paths meet
**The main path's frame wins wherever the main road's strip reaches. The
branch's frame covers the rest.** A junction now draws two meshes:

| Mesh | Covers | Frame (s, t) | Material |
|---|---|---|---|
| `Road` | path A's (MainSpline's) whole strip, lips included | A | A's |
| `RoadBranch` | path B's strip outside A's strip | B | B's |

Why this rule:
- **Each junction end meets its own road with the same s, t, class and half
  widths**: A's road at A's ends, B's road at B's open end. So there's no seam
  at the fork or the rejoin.
  - With the main frame everywhere (the design doc's suggestion), the branch
    side of the junction would be in A's frame (t up to about 60 m). The
    branch road starts in its own frame at the junction's open end, so the
    whole branch would get a hard seam across it there.
- **The only change of frame is along A's outer lip edge.** It reads as the
  main road's edge (its flat hazard lip) running through the fork, with the
  branch's lanes opening out beyond it, like a painted gore.
  - Splitting at the bisector of the two centre lines (each point to the
    nearer path) would also meet both roads cleanly. But it puts the seam
    down the middle of the overlap and cuts both roads' lanes. Driving
    straight on, the main road would visibly narrow.
- **Each path keeps its own material.** Zones, wear, decals and lights are
  per path and indexed by s. One mesh per path frame lets `TrackSurface` give
  each mesh its path's material and `path_length`, and lets `EnvSurfaces`
  set `along_main` per mesh.

Near the point, the branch's region is a sliver beyond A's lip. There, the
branch's own lip shows beside A's for a few metres (two hazard strips, out of
phase), narrowing to nothing at the point. The screenshots show no problem;
judge it at speed.

## What changed
### `TrackJunction` (`scripts/tracks/track_junction.gd`)
- **Each road mesh** is built like a road segment's flat surface:
  - a ring per metre along its path;
  - across: lip, 3 m surface strips, lip. These are the road polygon's
    columns, so the vertices line up with the road segments either side;
  - UV2 = (s, t), CUSTOM0 = (class, 19.5, 19.5, 0), TANGENT = travel.
  - Lips are EDGE_LIP, flat. The roads either side fade theirs flat into the
    junction, so the lip's hazard stripe continues across the end.
- **Cutting the branch out of A's strip:**
  - Each branch ring vertex is first classed against A's frame: in, out, or
    within 5 cm of the edge.
  - Triangles wholly out are kept. Triangles wholly in are dropped. Only
    triangles across the edge are clipped (`Geometry2D.clip_polygons`), and
    only against a local piece of A's strip.
  - A clipped vertex takes its triangle's s, t and tangent by barycentric
    interpolation, so it matches what the GPU would interpolate.
  - A's strip is carried 5 m past the point end when cutting. Otherwise the
    branch's first ring, a hair askew of A's, leaves centimetre slivers over
    the road before the fork.
- **Collision is unchanged**: the union outline, flat, with its skirt, on
  layer 1. Its body is now `RoadSkirtBody`, and the skirt's mesh is drawn on
  the surface material as underside, in A's frame.
- **New exports:**
  - `surface_half_width` (19.5);
  - `surface_strip` (3);
  - `splitter_material` (the grid; empty = `material`, the old behaviour).
- **New methods:** `road_mesh_for(path)` and `path_of(part)`.

### Wiring
- **Builders** (`tools/track_builder/track_build.gd`, `tools/fork_lab/build_fork_lab.gd`):
  `_junction` takes the road material (`ROAD_SURFACE_MAT`) and the splitter
  material (`ROAD_MAT`).
- **Scenes** (`builder_lab.tscn`, `fork_lab.tscn`): patched by text, as in
  earlier phases. On each junction, `material` now points to the existing
  `v38_surface` resource, plus one new `splitter_material` line. Four lines
  per scene, with no float or uid churn.
- **`TrackSurface._surface_segments(path)`** also returns the junction road
  drawn in that path's frame. So the per-path material, zone strip, wear,
  decals and variation reach the junction. This works at load and in the
  editor's live refresh ("10 segments" on Builder Lab: 6 road segments and 4
  junction roads).
- **`EnvSurfaces`** walks into a junction's internal meshes:
  - each road mesh gets `along_main` from `path_of()` (1 for `Road` on
    MainSpline, 0 for `RoadBranch`);
  - the splitter gets the grid's weather wrapper as a wall;
  - junctions previously had no weather at all.

## Checks
- **`tools/dev/track_uv2_check.gd`** (now also checks junctions: each
  junction rebuilt, then both meshes): both labs ok.
  - t matches the vertex's real offset in its path frame to within 1.1 mm.
  - Classes, half widths and tangents are right. No `RoadBranch` vertex is
    inside A's strip.
  - Clipped `RoadBranch` vertices have up to 0.16 m of s error on Builder
    Lab's fork, a tight branch curve. That's linear interpolation inside a
    1 m ring quad, which the GPU does between any two rings too. It's
    reported, not gated.
- **`tools/dev/env_adopt_check.gd`** (now lists junction meshes): 0
  conflicts. Builder Lab's junction roads get the per-path materials (Fork
  Lab has no `TrackSurface`, so its junctions get the base material, as its
  roads do).
- **`tools/fork_lab/check_fork_lab.gd`**: identical to `main`. Seams step
  ≤ 7.8 mm; junction grid rays 3740 with 0 misses; wall rays 1582 with 0
  blocked.
- **Validator self-test: 26/26. Editor self-test** (`TB_EDITOR_SELFTEST=1`):
  0 errors, 0 warnings, scene file untouched. It now also prints that each
  junction road is on its path's material after a Build (all four are).
- **`tools/dev/track_surface_shots.gd`** at the junction distances, main and
  branch, both labs: RTX 3080, 1080p, MSAA 4x + SMAA, clear.
  - New in the tool:
    - `TS_PATH` (drive a branch);
    - pose `over` (70 m up, a whole junction in view);
    - `TS_DEBUG_POSES`;
    - junction roads now switch looks with the road segments.
  - Distances:

    | Track | Path | Distances (m) |
    |---|---|---|
    | Builder Lab | main | 5340, 5420, 5600, 5660 / 6430, 6620, 6785 |
    | Builder Lab | branch | 15, 150, 315 / 960, 1200, 1325 |
    | Fork Lab | main | 1170, 1250, 1355 / 2210, 2320, 2400 |
    | Fork Lab | branch | 10, 80, 160 / 810, 900, 990 |

  - **No visible seam at the fork or rejoin, on either path.** The bands, s/t
    and zones views run continuously through both junctions on both labs.
    The main road's bands carry straight through, and the branch's emerge
    beyond A's lip.
  - **Far-road flicker and brightness match the averaged reference** in every
    chase row: flicker within 0.00002 of the reference, brightness within
    0.0004.

## Cost
`gfx_bench`, Builder Lab, `GB_CONFIGS=v38`, two interleaved runs, 20 s each.
The bench's `grid_v37` baseline now puts junction roads back on the grid
with the road segments, so it stays the real v37 look. GPU frame time, median
(ms):

| Config | 1080p a | 1080p b | 1440p a | 1440p b |
|---|---|---|---|---|
| `grid_v37` | 1.60 | 1.60 | 2.45 | 2.46 |
| `surface_low` | 1.78 | 1.78 | 2.75 | 3.02 |
| `surface_high` | 1.83 | 1.83 | 2.81 | 2.97 |

- **Low tier at 1080p: +0.18 ms** over the grid, both runs. Within the
  ≤ +0.2 ms budget and in line with phase 5a (+0.19–0.20). The junctions are
  a small share of the lap's screen time, so their cost is inside the noise.
- **High tier at 1440p: +0.36 ms (run a), +0.51 ms (run b)** against the
  ≤ +0.5 ms budget. Run b looks noisy: its low tier costs more than its high
  tier, and its p99s are about 1 ms higher. Rerun before reading a trend
  into it.
- RTX 3080 only; the 1080 Ti run is still open.
- These runs come from this branch, which doesn't have v37.1's ship-judder
  fix (`79152df`, on `main` only), so the ship judders in its screenshots.
  It doesn't affect the GPU times.

## Open issues
- **The splitter is still on the grid.** It's a cyan grid block at the nose,
  now the only grid on a builder track, and it stands out more than before.
  Putting it on the wall material needs wall data (s, height, `EDGE_FACE`) on
  its faces.
- **Load time:** a junction now takes about 0.1–0.3 s to build (Builder Lab
  0.2–0.3 s, Fork Lab 0.1–0.2 s; GDScript, mostly the two ribbons). It isn't
  compared with the old build.
- **Width profiles at junctions are ignored**, as before. The junction
  assumes the standard section (`surface_half_width` 19.5, lips to 21.5).
- **The validator doesn't check junction surfaces.** `track_uv2_check` does.
- From the phase notes, still open: the 1080 Ti run, the placeholder wear
  texture, branch-wall weather mask (see P5).

## Files
- New: `FTF_v38_TRACK_SURFACE_JUNCTIONS.md`
- Changed:
  - `full_throttle_flux/scripts/tracks/track_junction.gd`
  - `full_throttle_flux/scripts/tracks/track_surface.gd`: `_surface_segments`
  - `full_throttle_flux/scripts/env/env_surfaces.gd`: junction meshes
  - `full_throttle_flux/tools/track_builder/track_build.gd`,
    `tools/fork_lab/build_fork_lab.gd`: `_junction` materials
  - `full_throttle_flux/tools/track_builder/track_builder.gd`: editor
    self-test lines
  - `full_throttle_flux/scenes/tracks/builder_lab.tscn`, `fork_lab.tscn`:
    junction materials (text patch)
  - `full_throttle_flux/tools/dev/track_uv2_check.gd`, `env_adopt_check.gd`,
    `track_surface_shots.gd`, `gfx_bench.gd`
  - `full_throttle_flux/docs/TRACK_AUTHORING.md`, `FTF_v38_TRACK_SURFACE.md`

## Screenshots
Not committed. In `%APPDATA%\Godot\app_userdata\full_throttle_flux\`:
- `track_surface_junctions\{bl,fl}_{main,branch}\<track>_<d>_<chase|over>_<surface|grid|average>.png`
  and `..._debug_<st|bands|panels|filter|zones|wear>.png`
- `gfx_bench_v38_junctions\{a,b}_<res>\`

```
TS_D=5340,5420,5600,5660,6430,6620,6785 TS_POSES=chase,over TS_DEBUG_POSES=chase,over godot --path full_throttle_flux -s res://tools/dev/track_surface_shots_boot.gd
TS_PATH=BranchSpline TS_D=15,150,315,960,1200,1325 TS_POSES=chase,over TS_DEBUG_POSES=chase,over godot --path full_throttle_flux -s res://tools/dev/track_surface_shots_boot.gd
UC_TRACK=fork_lab godot --headless --path full_throttle_flux -s res://tools/dev/track_uv2_check_boot.gd
```
