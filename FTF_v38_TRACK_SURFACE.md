# FTF v38: track surface, phase 1 (foundation)

The first step from the temporary grid to a procedural industrial "uber"
surface on the road of Track Builder tracks (Builder Lab, Fork Lab). Phase 1
builds only the foundation: the coordinate frame, the band lookup, panels and
the anti-aliasing discipline, and proves it's clean and affordable before
any look work. The palette is a neutral placeholder.

Design doc: *FTF Track Surface Shader — Design Doc* (claude.ai artifact
2cW92pxkyTic7oBCau9SLR). Branch `feature/v38-track-surface`, not merged.

**Phase 2 (core modules) is in `FTF_v38_TRACK_SURFACE_P2.md`, phase 3
(authoring) in `FTF_v38_TRACK_SURFACE_P3.md`, phase 4 (wear and weather) in
`FTF_v38_TRACK_SURFACE_P4.md`, phase 5a (decals, living lights, walls) in
`FTF_v38_TRACK_SURFACE_P5.md`, phase 5b (the circuit port) in
`FTF_v38_TRACK_SURFACE_P5B.md`, junctions on the surface in
`FTF_v38_TRACK_SURFACE_JUNCTIONS.md`.** It changes
two things described here:
- `aa_lines` now filters over 1.5 footprints and fades at 6→3 px;
- the far-flicker metric now uses the centre half of the columns.

The tables below are the phase 1 record.

**Budget change after phase 2:** the low tier's gate "no more than the grid
costs" is restated as **≤ +0.1 ms GPU over the v37 grid on the RTX 3080 at
1080p, to be verified on a GTX 1080 Ti**. Phase 1 met the original gate;
phase 2 costs +0.07 ms (see the phase 2 notes).

**Budget change after phase 5a:** restated again, as **≤ +0.2 ms GPU over the
v37 grid on the RTX 3080 at 1080p, to be verified on a GTX 1080 Ti**, so the
low tier keeps decals and living lights (phase 5a: +0.19–0.20 ms). The high
tier's budget is unchanged: ≤ +0.5 ms on the 3080 at 1440p.

## Try it in game
| Key | What | Options (default in bold) |
|---|---|---|
| 9 | Track surface debug view | **off** · s/t · band ids · panel ids · filter level |
| Shift+9 | Track surface quality tier | Low · **High** (same look in phase 1) |

The tier is saved in `user://graphics.cfg`; `FTF_SURFACE_TIER=0|1` pins it.
The debug view isn't saved. See `DEBUG_KEYS.md`.

Debug views:
- **s/t**: red ramps every 10 m along (white line at s = 0), green across,
  blue = edge class (surface 0, lip ½, underside 1).
- **band ids**: one hue per band; lips white, underside black.
- **panel ids**: one hue per panel; seams dark.
- **filter level**: green = full detail, red = faded to its average.

## Found on the way (two existing bugs, fixed first)
1. **Races had lost the v37 filtered grid.** `shaders/env/track_surface.gdshader`
   (the weather wrapper `EnvSurfaces` swaps onto the grid material at race
   start) was written in v35 in parallel with v37, and still drew the v36
   fixed-pixel grid. So in every race the road and walls went back to the
   aliasing lines v37 removed, and the v37 bench (which never runs
   `EnvSurfaces`) measured a grid players didn't see. Both shaders now
   include one copy of the grid, `shaders/grid_filtered.gdshaderinc`.
   `EnvSurfaces` recognises a grid material by that include as well as by
   `major_grid_every`. Separate commit.
2. **Builder tracks had no weather at all.** `EnvSurfaces` walked only
   non-internal children, and a `TrackRoadSegment`'s mesh is internal, so on
   Builder Lab `adopt()` found 0 materials. It now reaches each segment's
   mesh (`TrackRoadSegment.mesh_instance()`), with `u_scale` = the segment's
   `u_distance` on MainSpline and `road_v0/v1` from its polygon. Builder
   **walls** (still on the grid) now get weather too, and a main road with
   the new surface turns the per-distance zone mask on for builder tracks.

## What was built

### Coordinates (`TrackRoadSegment`)
- **UV2** = (metres along the path, metres across from the centre line,
  +x = right) of the **actual** vertex, after the width profile. UV is
  unchanged. Checked by `tools/dev/track_uv2_check.gd` on every road segment
  of both labs: t within 0.2 mm of the vertex's real offset in the frame.
- **CUSTOM0** (RGBA float) = (edge class, left half width, right half width, 0).
  - Edge class per polygon edge: 0 driving surface (flat at y = 0, facing
    up), 1 lip (facing up, raised end), 2 underside / sides / caps. Classed
    on the drawn polygon, so a lip stays a lip while it fades flat.
  - Half widths: how far the surface reaches either side at that ring, so
    fixed bands sit on the real edges. They match the width profile
    exactly (same check).
- **Instance uniform `path_length`** on the mesh: the path's baked length,
  for snapping panels to the lap.

### The shader (`shaders/track/track_surface.gdshader`)
- Assigned to road segments only, via `shaders/track/track_surface_material.tres`.
  Walls and junctions keep the grid.
- **Bands** across t, hard-coded, 9 of them, left to right:

  | Band | Width |
  |---|---|
  | Edge | 1.5 m |
  | Channel | 0.4 m |
  | Plate lane | 6 m |
  | Channel | 0.3 m |
  | **Centre lane** | **flex** |
  | Channel | 0.3 m |
  | Plate lane | 6 m |
  | Channel | 0.4 m |
  | Edge | 1.5 m |

  Fixed bands stack inward from each real edge; flex bands share the rest
  by weight (about 22.6 m at the reference width). If a road is narrower
  than the fixed bands, they squeeze proportionally. Lookup is one loop of
  9; channels are box-filtered coverage, so they never alias in t.
- **Panels** on plate and edge bands (lips carry on the nearer edge band's):
  - Transverse seams every `panel_len` (6 m), snapped per path so
    `path_length / panel_len` is whole: no seam jump at the start line.
  - Each band's seams are offset by a hash of the band, so they never line up.
  - A per-panel hash gives ±8% tint and ±0.08 roughness. The variation
    fades to its mean once panels are too small to resolve.
- **Weather**: includes `env_surface.gdshaderinc` and calls
  `env_surface_apply()` itself. `EnvSurfaces` doesn't swap it; it sets the
  instance uniform `along_main` (1 on MainSpline: s indexes the zone mask;
  0 on branches, whose s is branch metres).

### AA helpers (`shaders/track/surface_aa.gdshaderinc`)
Every later module must use these:
- `aa_fw(x)`: footprint as the gradient length (better than `fwidth` on
  anisotropic footprints).
- `aa_fw_s(s)`: the same widened by `aa_s_bias` (1.5). Detail repeating
  along s compresses most at the chase-cam angle, so it fades earlier.
- `aa_step`, `aa_pulse` (one band or stripe) and `aa_lines` (periodic
  lines): exact box filters.
- `aa_lines` also fades to the exact average w / period once a period is
  under `aa_fade_px` (2) pixels; the fade starts at 4.
- `aa_fade(period, fw)` and `aa_cell_value`: fade any per-cell value to its mean.

Because everything far away is the true average, nothing can brighten
toward the horizon (measured below).

### Quality tier and debug views
- `GraphicsSettings` publishes two global shader uniforms (declared in
  `project.godot`): `track_surface_tier` (0 low, 1 high) and
  `track_surface_debug` (0–4).
- Keys go through `DebugKeys` (9, Shift+9).
- Both tiers render the same in phase 1. The tier is the hook for phase 2
  (low drops normal detail, parallax and decals).

### Tools
- `tools/dev/track_surface_shots.gd`: renders fixed poses (chase, low,
  top) at chosen distances on Builder Lab, three ways:
  - `grid`: the v37 grid on the road;
  - `surface`: the v38 surface;
  - `average`: the surface with every pattern forced to its average, the
    reference for "no brightening".

  It also saves the debug views and measures flicker and far/near
  brightness on road pixels only (where the grid and average renders differ).
- `tools/dev/gfx_bench.gd`:
  - grid mode 2 = the v38 surface (0/1 put builder roads back on the grid
    for the baseline);
  - a tier field, and `V38_CONFIGS`;
  - `GB_ENV=1` (default) runs `EnvSurfaces.adopt()` as a race does, so
    every row draws with its race shaders.
- `tools/dev/track_uv2_check.gd`: the UV2 / CUSTOM0 check.
- `tools/dev/env_adopt_check.gd`: prints what `adopt()` did to each segment.

## Decisions and deviations from the doc
Agreed before building:
- **CUSTOM0 per edge** for classification and local width, instead of the
  normal in the track frame. The doc asks for metres across, but fixed edge
  bands also need the local edge positions, which UV2 alone can't give.
- **Material assignment in both builders** (`tools/track_builder/track_build.gd`,
  `tools/fork_lab/build_fork_lab.gd`: `ROAD_SURFACE_MAT` for road segments
  only), and the two lab scenes patched to match by hand.
  - A Track Builder rebuild of Builder Lab gave the same material change
    plus last-digit float drift in unrelated transforms, so I kept the
    hand patch: 6 road segments per lab, one new `ext_resource`.
- **The v37 grid fix** went first, as its own commit.
- **Junctions stay on the grid** in phase 1 (open issue).

Taken during the build (small, flagged here):
- **`path_length` as an instance uniform**, not one material per path. The
  doc expects per-path material instances because textures can't be
  instance uniforms. Phase 1 has no textures, so one shared material
  serves every path; phase 3's per-path data texture brings per-path
  instances back.
- **panel_len 6 m** (4 m at first). On a 22 m centre lane, 4 m panels read
  as full-width transverse stripes, the strobing the doc warns about.
- **Placeholder palette**: dark grey plates (0.24, metallic 0.5,
  roughness 0.5), warmer edge bands, near-black channels. Phase 2 owns the look.
- **Builder walls now get weather** (follows from bug 2). It's a visible
  change in wet or snowy presets on the labs.

## Gate
### Clean in motion (RTX 3080, 1080p, MSAA 4x + SMAA, clear weather)
`track_surface_shots` at 200 m (straight), 850 m (width keys) and 2400 m (a
loop). The camera creeps 1.2 cm a frame for 16 frames (sub-pixel far away),
and only road pixels are counted. "Far" is the top fifth of the road's
rows, toward the horizon.

| d | Pose | Far flicker: grid | surface | average | Far brightness: surface | average |
|---|---|---|---|---|---|---|
| 200 | chase | 0.00152 | 0.00097 | 0.00093 | 0.358 | 0.360 |
| 200 | low | 0.00150 | 0.00064 | 0.00058 | 0.380 | 0.380 |
| 200 | top | 0.00175 | 0.00070 | 0.00066 | 0.343 | 0.342 |
| 850 | chase | 0.00153 | 0.00116 | 0.00115 | 0.275 | 0.274 |
| 850 | low | 0.00233 | 0.00148 | 0.00146 | 0.287 | 0.288 |
| 850 | top | 0.00160 | 0.00032 | 0.00029 | 0.268 | 0.270 |
| 2400 | chase | 0.00104 | 0.00035 | 0.00034 | 0.123 | 0.123 |
| 2400 | low | 0.00340 | 0.00119 | 0.00117 | 0.066 | 0.066 |
| 2400 | top | 0.01120 | 0.00244 | 0.00232 | 0.238 | 0.236 |

Reading it:
- **No shimmer, crawl or moiré from the pattern.**
  - On the far road the surface flickers no more than its own averaged
    reference: within 13% in every pose, mostly within 5%.
  - The v37 grid flickers 1.3–5× more than the surface there.
  - Across the whole road the surface flickers more than the average near
    the camera. That's real detail (seams) moving past, not aliasing.
- **No brightening toward the horizon.** Far-road brightness matches the
  averaged reference to within 0.8% everywhere, with the sign going both
  ways, so the difference isn't a bias. What remains is real Fresnel.
- **Full-speed chase**: the bench lap below runs the real chase camera
  with motion blur. Its frames at 3 s (see Screenshots) show a clean road.
- **Still needs human eyes in motion.** The measurements are a proxy;
  judge a live lap at full speed and in free cam. The doc says to tune
  with motion blur off (key 6).

### Cost (RTX 3080; no GTX 1080 Ti available, so flagged)
`gfx_bench` on Builder Lab: AI lap on the trained line, real chase camera
and motion blur, v37 settings (MSAA 4x + SMAA, High shadows, v37 profile),
`EnvSurfaces` adopted, 4 s warm-up then 20 s measured, vsync off. Each
config ran twice, interleaved.

GPU frame time, median (p99), ms:

| Config | 1080p run a | 1080p run b | 1440p run a | 1440p run b |
|---|---|---|---|---|
| `grid_v37` (road on the v37 grid) | 1.59 (2.06) | 1.61 (1.89) | 2.45 (3.20) | 2.50 (5.73) |
| `surface_low` | 1.59 (1.88) | 1.61 (1.89) | 2.48 (5.71) | 2.50 (5.77) |
| `surface_high` | 1.59 (1.87) | 1.61 (1.89) | 2.45 (5.70) | 2.49 (5.78) |

The 1440p p99s of about 5.7 ms appear on the grid rows too: hitches of the
lap, not the shader.

- **Low tier vs the grid at 1080p: same cost.** The difference is at most
  0.00 ms, inside the 0.02 ms run-to-run noise.
- **High tier vs the grid at 1440p: same cost**, within ±0.03 ms, far inside +0.5 ms.
- **Flagged: measured on the RTX 3080 only, not the GTX 1080 Ti.** Two caveats:
  - Builder Lab is light: whole frames take 1.6–2.5 ms, so the road shader
    is a small part of them. The bench can't show a per-pass cost below
    about 0.03 ms.
  - The old card is weaker on ALU per pixel. The surface is ALU-only (no
    texture fetches), with a 9-step band loop, two hashes and the env
    include, so it should scale like the grid. That's unproven until it
    runs on a 1080 Ti.

## Screenshots
Not committed: the repo keeps no images. Regenerate with the tools; the
files land in `%APPDATA%\Godot\app_userdata\full_throttle_flux\`:
- `track_surface\builder_lab_<d>_<pose>_<grid|surface|average>.png`
- `track_surface\builder_lab_<d>_chase_debug_<st|bands|panels|filter>.png`
- `track_surface\track_surface.csv`
- `gfx_bench_v38\bench_1920x1080\` and `bench_2560x1440\`:
  `builder_lab_<config>_00.png` (chase cam at speed, 3 s in), `gfx_bench.csv`
  (copied there from this run; the bench itself writes to `GB_OUT`,
  default `gfx_bench\`)

```
godot --path full_throttle_flux -s res://tools/dev/track_surface_shots_boot.gd
GB_TRACKS=builder_lab GB_CONFIGS=v38 GB_SHOTS=3 godot --path full_throttle_flux -s res://tools/dev/gfx_bench_boot.gd
```

## Open issues for phase 2
- **Junctions** (`TrackJunction`) are still on the grid, without UV2, and
  without weather (`EnvSurfaces` doesn't reach their internal mesh). There
  are visible material changes at the fork and rejoin. They need a rule
  for t where two paths meet (e.g. the main path's frame).
- **Branch walls share the grid material with main walls**, so they inherit
  the main `u_scale` (a counted conflict in `adopt()`). Their weather zone
  mask is read at the wrong distance. The wall port to this system fixes it.
- **The 1080 Ti gate is unmeasured.** Rerun the bench on it before phase 2
  adds texture fetches, where the old card is weakest.
- **Normals and specular**: phase 1 has no normal detail, so the
  Toksvig-style roughness rise has nothing to act on yet. Add it with the
  first normal module (ribs), and fade normals before albedo.
- **Vertex data**: every `TrackRoadSegment` (walls too) now carries UV2 and
  CUSTOM0, 24 bytes more per vertex (about 10 MB on Builder Lab's roads and
  walls). Walls could skip it until they join the system.
- **`grid_v36` A/B (Shift+7) in a race** swaps the shared grid material's
  shader, which drops the weather wrapper on walls until restart. That's
  existing behaviour and an A/B tool only.
- The circuits (CSG) are untouched. Their port needs metres across from
  the known road width (doc: Coordinates).

## Files
- `full_throttle_flux/shaders/track/track_surface.gdshader`,
  `surface_aa.gdshaderinc`, `track_surface_material.tres` (new)
- `full_throttle_flux/shaders/grid_filtered.gdshaderinc` (new),
  `grid_shader.gdshader`, `env/track_surface.gdshader`
- `full_throttle_flux/scripts/tracks/track_road_segment.gd`: UV2, CUSTOM0,
  `path_length`, `edge_classes`, `surface_half_widths`, `mesh_instance`,
  `driving_surface_v`
- `full_throttle_flux/scripts/env/env_surfaces.gd`: grid signatures,
  segment meshes, the surface shader
- `full_throttle_flux/scripts/rendering/graphics_settings.gd`: tier, debug
  view, keys 9 / Shift+9
- `full_throttle_flux/project.godot`: globals `track_surface_debug`, `track_surface_tier`
- `full_throttle_flux/tools/track_builder/track_build.gd`,
  `tools/fork_lab/build_fork_lab.gd`: `ROAD_SURFACE_MAT`
- `full_throttle_flux/scenes/tracks/builder_lab.tscn`, `fork_lab.tscn`:
  road segments on the new material
- `full_throttle_flux/tools/dev/gfx_bench.gd`, `track_surface_shots.gd`,
  `track_uv2_check.gd`, `env_adopt_check.gd` (+ boots)
- `DEBUG_KEYS.md`
