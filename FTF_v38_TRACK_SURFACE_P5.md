# FTF v38: track surface, phase 5a (decals, living lights, walls)

Phase 5 of the track surface ("rollout"). Earlier phases are in
`FTF_v38_TRACK_SURFACE.md` and `_P2.md` to `_P4.md`. This is **5a**:
- road decals in the four fonts;
- chevrons and arrows;
- living (flowing) lights;
- the walls joining the surface system.

**5b, the port to circuits 3, 5, 6 and 7, waits for your sign-off on the
builder-track look** (gate 3), as the doc and we agreed. Same branch,
`feature/v38-track-surface`.

**Budget: the low tier is over.** You chose decals and flow on both tiers;
the low tier is now +0.19–0.20 ms over the grid on the RTX 3080 against
≤ +0.1 ms. The options are under Cost.

## Try it
- **Builder Lab decals:**

  | Where | What |
  |---|---|
  | 110 m | **FULL THROTTLE** (Bartle, white) |
  | 140 m | **FLUX** (Bartle, glowing blue) |
  | 300 m on | 30 barcode serials `*FX-0n*` along the right edge |
  | 975 m | 6 yellow chevrons into the hottest corner |
  | 2,060 m | **SECTOR 2** (Audiowide) |
  | 3,600 m | 3 glowing blue arrows |
  | 4,310 m | **KEEP CLEAR** (Alien Block, yellow) at the grate_run seam |

- **Living lights:**
  - channel dot rows and LED rows flow along the track at 24 m/s;
  - brighter pulses run down the blue strips at 90 m/s;
  - the walls' strips and LEDs do the same.
- **Walls:** dark panels with seams, a yellow/black hazard band at the foot,
  a blue guide strip with pulses, a white LED row near the top, grime
  splashed up from the road, weather run-off, a light grey cap.

## What was built

### Fonts and credits
- The four OFL fonts are in `full_throttle_flux/fonts/<name>/`, each with
  its `OFL.txt`, unmodified.
- `CREDITS.md` at the repo root lists each font's role, copyright and
  licence.

### The glyph atlas
- `tools/track_surface/make_decal_atlas.gd` uses **Godot's own MSDF font
  renderer**: no external tool.
  - A spike decoded its glyphs at 4× magnification: sharp corners, clean
    stems.
  - It renders the characters each font's job needs (caps, digits, a few
    symbols; lowercase for Alien Block).
  - It shelf-packs 186 glyphs into one 2048×512 atlas,
    `resources/track_surface/decal_atlas.png`: RGB is the multichannel
    field, A the true distance.
- `resources/track_surface/decal_glyphs.tres` (`TrackSurfaceGlyphs`) holds
  each glyph's atlas rectangle, offset from the pen, advance, and **ink**:
  its average coverage, what it fades to far away.
- The atlas is imported with mipmaps, no alpha-border fix and no
  auto-compression.

### Decals
- **`SurfaceDecalKey`** (Track Builder):
  - shape (text, chevron, arrow);
  - font role (WORD, STENCIL, LABEL, SERIAL);
  - text (`#` counts copies);
  - size, width;
  - anchor and offset, as `BoostPadKey` (from the centre, or in from an edge
    of the driving surface, so decals follow width keys);
  - paint (white, yellow, red, blue: no orange), glow, opacity;
  - count, spacing, flipped.

  `TrackSurfacer` projects the keys onto their path into
  `TrackSurface.decals`. The validator warns about missing glyphs, empty
  text and keys far from the track, and has a new self-test case (26/26).
- **`TrackSurface`** lays the decals out at load:
  - one record per glyph or shape (4 RGBAF texels: rect in (s, t), atlas
    uv, kind / paint / glow / opacity, ink / stroke / flipped), sorted
    along s;
  - a per-metre strip of (first record, count). The shader loops over at
    most 24; the builder report says if a metre has more.
- **Shader** (`modules/decals.gdshaderinc`), run before wear so grime and
  scuffs cover the paint:
  - **glyphs:** MSDF median, screen-pixel distance from explicit gradients;
  - **chevrons and arrows:** analytic distance fields, box-filtered;
  - **far away:** everything fades to its ink average. Decals fade later
    than other patterns (from 3 px strokes, done at 1.5 px), because an MSDF
    edge stays exact down to there. Barcode bars are the thinnest and go
    first.
  - Paths without decals skip all of it (a uniform branch).

### Living lights
- `light_flow` (24 m/s) moves the dot and LED rows along the track.
- `light_pulse_*` (every 60 m, 8 m long, 90 m/s, +1.2 brightness) runs
  pulses down the blue strips.
- Only the filtered patterns' phase moves, wrapped to each pattern's period
  so float precision holds after hours of `TIME`: nothing new to alias, and
  far rows stay at their steady average.
- `track_surface_shots` freezes the animation while measuring (`TS_FREEZE=1`,
  the default). Moving lights are real motion, which the flicker measure
  can't tell from aliasing.

### Walls
- **`shaders/track/track_wall.gdshader`** + `track_wall_material.tres`, on
  every builder wall segment. Junctions keep the grid.
- It reads s and, new in `TrackRoadSegment`, each vertex's **height in the
  section** (CUSTOM0.w), plus a new edge class **EDGE_FACE** (a near-vertical
  edge facing the centre line).
  - Wall tops class as lips. A lip now needs a normal clearly up (y > 0.3),
    so near-vertical outer faces aren't lips.
  - The road's classes are unchanged (checked).
- It reuses the shared AA, hazard, light and wear pieces. It's light: walls
  cover a lot of screen, and they measured **free** against the grid walls.
- `EnvSurfaces` adopts the wall shader like the road's. Every wall mesh
  gets `along_main` (0 on branches), which **fixes the branch walls'
  weather mask** (an open issue since phase 1): `adopt()` now reports 0
  conflicts on Builder Lab.
- The builders (`track_build.gd`, `build_fork_lab.gd`) put walls on the new
  material. The two lab scenes were patched to match: 10 wall segments each,
  material lines only.

### Tools
- `gfx_bench`: grid mode 3 (the v38 road, grid walls).
- `track_surface_shots`: walls in every look and in the measured mask;
  `TS_FREEZE`.
- `sync_surface_presets` is now a boot plus a run script, so it compiles
  after the autoloads (it printed errors since phase 4), and it makes the
  wall material.

## Decisions and deviations
Agreed:
- **5a + walls now; the circuit port after your sign-off.**
- **Godot's built-in MSDF** (no external tool needed).
- **Decals and flow on both tiers.** This takes the low tier over budget
  (see Cost).
- **`CREDITS.md`** for the font credits.

Taken during the build:
- **No automatic panel serials.** The doc says "a hash-picked subset of
  panels". Panels are placed in the shader (band layout per pixel), so
  serials are authored instead: a `SurfaceDecalKey` with `count`/`spacing`
  and a `#` counter.
- **Text orientation:** left to right across the road, tops pointing along
  the track, readable for an approaching ship. `flipped` serves
  the other way.
- **Decal sizes:** BBH Bartle is very wide; FULL THROTTLE needed 2.2 m
  letters to fit a 39 m road (4.5 m ran off both sides).
- **The decal fade threshold** was loosened after the first render. At the
  shared helpers' threshold, 2.2 m letters seen from 30 m faded to boxes,
  although the MSDF still had them exact.
- **The wall look** replaces the cyan grid on builder walls. It's the
  doc's industrial grammar; whether it's right for the walls is your call
  at sign-off.

## Gate
### Clean in motion (RTX 3080, 1080p, MSAA 4x + SMAA, clear weather, lights frozen)
The road and walls are now both in the measured mask. Far flicker, and far
brightness as sRGB luma:

| d | Pose | Flicker: grid | surface | average | Brightness: surface | average |
|---|---|---|---|---|---|---|
| 200 | chase | 0.00172 | 0.00023 | 0.00023 | 0.462 | 0.462 |
| 200 | low | 0.00253 | 0.00180 | 0.00180 | 0.535 | 0.535 |
| 200 | top | 0.00199 | 0.00092 | 0.00087 | 0.325 | 0.326 |
| 850 | chase | 0.00209 | 0.00087 | 0.00087 | 0.306 | 0.306 |
| 850 | low | 0.00301 | 0.00084 | 0.00084 | 0.418 | 0.418 |
| 850 | top | 0.00200 | 0.00096 | 0.00092 | 0.255 | 0.255 |
| 2400 | chase | 0.00111 | 0.00069 | 0.00066 | 0.145 | 0.145 |

- **Flicker:** within 1.00–1.06× of the averaged reference in every pose
  (inside-the-loop excluded).
- **Brightness:** within 0.6%, never more than 0.2% above.
- **The v37 grid** (road and walls) flickers 1.6–7× more than the surface
  on the far road.

At the decals, `track_surface_decals\`:

| d | What | Chase | Top |
|---|---|---|---|
| 95 | FULL THROTTLE, FLUX | 1.00× | 1.22×* |
| 290 | serials | 1.00× | 1.04× |
| 965 | chevrons | 1.00× | 1.06× |
| 2045 | SECTOR 2 | 1.00× | 1.00× |
| 3585 | arrows | 1.08× | 1.00× |
| 4295 | KEEP CLEAR | 1.05× | 0.99× |

\* That top pose has the whole word, resolved, in its far rows: real detail
against its averaged reference.

### Cost (RTX 3080 only)
`gfx_bench`, Builder Lab, `GB_CONFIGS=v38`, two interleaved runs. GPU frame
time median, ms:

| Config | 1080p a | 1080p b | 1440p a | 1440p b |
|---|---|---|---|---|
| `grid_v37` (road and walls on the grid) | 1.59 | 1.60 | 2.43 | 2.44 |
| `surface_low` | 1.78 | 1.80 | 2.75 | 2.75 |
| `surface_high` | 1.83 | 1.84 | 2.81 | 2.81 |

- **High tier at 1440p: +0.38 ms.** Within ≤ +0.5 ms, with about 0.12 ms
  left.
- **Low tier at 1080p: +0.19–0.20 ms. Over ≤ +0.1 ms.**
- **Where it went** (low tier, 1080p, 12 s A/Bs):

  | Piece | Cost |
  |---|---|
  | Walls (v38 walls vs grid walls) | ~0 ms |
  | Decals (the per-pixel strip fetch, plus records where there are decals) | ~0.05 ms |
  | Living lights | ~0.02 ms |
  | Phase 4's surface | +0.10 ms |
  | Remainder (noise) | ~0.02 ms |

- **Options** (your call):
  1. **Decals and flow off on the low tier**, as the doc had it. That's
     about +0.12–0.13 ms. Close; the last few hundredths could come from
     dropping panel age on low.
  2. **Restate the low-tier budget**, e.g. ≤ +0.2 ms on the 3080, still to
     verify on a 1080 Ti.
  3. **Decals only on paths that have them**, which is already the case;
     Builder Lab's main path has decals, so it pays.

## Checks
- Validator self-test 26/26 (new: decal text the font can't draw).
- Editor self-test: 5 zones, 7 decals, per-path material, 0 errors, 0
  warnings, scene untouched.
- `track_uv2_check`: both labs ok.
- Edge classes:
  - road `[lip, surface, lip, other, other, other]` (unchanged);
  - left wall `[lip, lip, other, other, face]`;
  - right wall `[lip, lip, face, other, other]`.
- `env_adopt_check`: walls adopted, `along_main` 1 on MainSpline and 0 on
  the branch, 0 conflicts.
- `env_selftest`: the two known failures only.
- Track Builder validator on Builder Lab: 0 errors, the same 1 warning as
  on `main`.

## Screenshots
In `%APPDATA%\Godot\app_userdata\full_throttle_flux\`:
- `track_surface_decals\builder_lab_<0095|0290|0965|2045|3585|4295>_<chase|top>_*.png`:
  every decal, chase and from above.
- `track_surface\`: the standard poses, with the walls.
- `gfx_bench_v38_p5\`: chase cam at speed.

## Open for 5b and after
- **Gates 2 and 3**: your hand test at speed and look sign-off on Builder
  Lab. That unblocks the circuit port.
- **The low-tier budget** (above).
- **The circuit port** (5b): circuits 3, 5, 6 and 7 are CSG, and need
  metres-across rebuilt from the known road width (doc: Coordinates), the
  walls' face/top split, and a `TrackSurface` node or equivalent for zones
  and decals.
- **Junctions** still on the grid.
- **The 1080 Ti run.**
- **Placeholder wear texture** (from phase 4).
- **Decal blending** with the polish line: paint wears like the plate, but
  decals don't yet wear faster on the racing line.

## Files
- New:
  - `CREDITS.md`
  - `full_throttle_flux/fonts/**` (4 fonts + OFL.txt)
  - `full_throttle_flux/scripts/tracks/track_surface_decal.gd`,
    `track_surface_glyphs.gd`
  - `full_throttle_flux/tools/track_builder/surface_decal_key.gd`
  - `full_throttle_flux/tools/track_surface/make_decal_atlas.gd`,
    `sync_surface_presets_run.gd`
  - `full_throttle_flux/resources/track_surface/decal_atlas.png`,
    `decal_glyphs.tres`
  - `full_throttle_flux/shaders/track/modules/decals.gdshaderinc`
  - `full_throttle_flux/shaders/track/track_wall.gdshader`,
    `track_wall_material.tres`
- Changed:
  - `full_throttle_flux/scripts/tracks/track_road_segment.gd`: EDGE_FACE,
    vertex height, `surface_half_widths_at`
  - `track_surface.gd`: decal layout
  - `full_throttle_flux/shaders/track/track_surface.gdshader`: decals, flow
  - `modules/lights.gdshaderinc`: flow, pulses
  - `full_throttle_flux/scripts/env/env_surfaces.gd`: the wall shader
  - `full_throttle_flux/tools/track_builder/track_surfacer.gd`,
    `track_builder.gd`, `track_build.gd`, `track_validator.gd`,
    `validator_selftest.gd`
  - `full_throttle_flux/tools/fork_lab/build_fork_lab.gd`
  - `full_throttle_flux/scenes/tracks/builder_lab.tscn`, `fork_lab.tscn`
  - `full_throttle_flux/tools/dev/gfx_bench.gd`, `track_surface_shots.gd`
  - `full_throttle_flux/tools/track_surface/sync_surface_presets.gd`
  - `full_throttle_flux/docs/TRACK_AUTHORING.md` (§3.7 walls, §3.8 decals,
    tools)
