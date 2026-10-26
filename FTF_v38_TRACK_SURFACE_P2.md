# FTF v38: track surface, phase 2 (core modules)

Phase 2 of the track surface (phase 1: `FTF_v38_TRACK_SURFACE.md`). It adds
the modules that make the industrial look: ribbed plates, hex grates, vents,
guide lights in the channels, LED rows and painted lines on the edge bands,
hazard diagonals on the lips. It also adds the tangent frame they need and a
first industrial palette. Everything stays procedural: no textures. The
profile is still hard-coded until phase 3. Same branch,
`feature/v38-track-surface`.

**Gate 2 is yours:** hand test at speed against refs 2, 5 and 9. I built
from the doc's descriptions of the references, not the images.

**Gate 1 was not formally passed** (no 1080 Ti run, no live lap). We agreed
to go ahead and flag it. The low tier now costs slightly more than the grid
(see Cost), so the 1080 Ti run matters more than before.

## Try it in game
Same keys as phase 1: **9** cycles the debug views, **Shift+9** switches the
tier. The tier now does something:

| Tier | What it draws |
|---|---|
| Low | Everything except normal detail and grate parallax. Ribs are an albedo pattern, holes a flat average |
| **High** | Rib normals (with Toksvig roughness) and parallax grate holes |

## The cross-section (13 bands, hard-coded)
| # | Band | Width | Module |
|---|---|---|---|
| 0 | Edge | 1.2 m | painted line at the outer edge, white LED dots |
| 1 | Channel | 0.35 m | red dot lights |
| 2 | Grate | 2.4 m | hex grate, recessed |
| 3 | Channel | 0.3 m | blue light strip |
| 4 | Ribbed plate | 5.0 m | longitudinal grooves |
| 5 | Channel | 0.25 m | plain |
| 6 | **Plate (flex)** | **≈20 m** | vents |
| 7–12 | mirror of 5–0 | | |

- **Lips**: yellow and black hazard diagonals.
- **Underside**: dark.
- A channel always separates two different modules, so a band switch is
  never a hard edge between two patterns.

## What was built

### Tangent frame (`TrackRoadSegment`)
- **ARRAY_TANGENT** = the direction of travel. Caps get the frame's right.
- The shader builds (along, across, up) from TANGENT and NORMAL, exactly:
  no screen-space derivatives, which are noisiest at grazing angles.
- `track_uv2_check` now also checks it: the tangent dots with the curve's
  forward at 1.00000 on every segment of both labs.

### Modules (`shaders/track/modules/`)
Every module writes into one `TSurf` struct (`surface_common.gdshaderinc`).
The main shader resolves it once: normal from slope, Toksvig roughness,
then weather. Each module:
- gets its footprints passed in and never takes derivatives itself;
- box-filters everything and fades to its average;
- fades normals before albedo;
- records its fade for the filter-level view;
- stays out of the boost pads' orange (about 20–40° hue).

The modules:
- **`ribs`**: a trapezoid groove wave across t (16 cm pitch, 40% groove).
  - Normal slope = finite difference of the height over the footprint.
    That's exact up close and flattens by itself once grooves get small,
    and it also fades explicitly at twice the albedo's threshold.
  - The slope variance lost goes to roughness.
- **`grate`**: hex cells (36 cm, 5 cm bars, 8 cm frame), never transparent.
  - On the high tier the hole is a recess with parallax: the floor shifts
    with the view, and the far wall shows where the view ray hits it.
  - Faint teal under-glow.
  - Cells repeat along both s and t, so the footprint is the larger of the two.
- **`vents`**: louvre boxes (5 × 7 m, 30 cm slots) in the flex plate, one
  chance every 140 m, placed by a hash until phase 3's zone strip.
  - The slots repeat along s, so they're the first thing to fade.
  - Faint red heat in the slots.
- **`lights`**: blue strips and red dot rows in the channels, white LED dots
  on the edge bands.
  - These thin features along s are evaluated **inside the band lookup**,
    for every band the pixel's footprint touches. A strip narrower than a
    pixel still adds exactly its coverage.
  - Dot rows fade to their duty cycle.
  - HDR fix (see Decisions): sub-pixel lights ease to `light_far_energy`.
- **`edges`**: a painted white line on each edge band's outer edge, and the
  hazard diagonals on the lips (45° in (s, t), 1.1 m period).

### AA helper changes (`surface_aa.gdshaderinc`)
- `aa_filter_width` (1.5): `aa_lines` filters over 1.5 footprints.
- `aa_fade_px` 2 → 3: periodic patterns fade from 6 px down to 3 px per period.
- The hazard diagonals get double footprint on top of that.

Why: in phase 1 the only periodic pattern was a thin, low-contrast seam. The
phase 2 stripes are high-contrast square waves, where a plain box filter
still rings at 2–4 px periods (measured below). The cost is slightly softer
seams up close.

### Optimizations
These came after the first bench, with no change to the image (the metrics
matched to 0.00%):
- The band loop stops once it's past the pixel's footprint.
- The track frame and view vector are only built where they're used.
- NORMAL is only written when it changes.

### Tools
- `track_surface_shots`:
  - `TS_PARAMS` overrides material parameters (A/B a module);
  - `TS_TIER` picks the tier;
  - `TS_POSES` picks the poses;
  - the far region is now the top fifth of road rows **in the centre half
    of the columns**. In the low pose, the raised lips right beside the
    camera reach the horizon rows at the image sides.
- `track_uv2_check` checks tangents.

## Decisions and deviations
Agreed before building:
- Proceed past gate 1 and flag it.
- Same branch.
- Tangents from `TrackRoadSegment`, not screen derivatives.
- Pure procedural, no textures.

Taken during the build (flagged here):
- **No orange anywhere.** Reference 2 has orange edge lights, but the doc
  reserves the boost pads' colour range (pads are `(1, 0.5, 0)`). Edge
  lights are white and red, the hazard yellow is 47° hue, and the vent heat
  is red.
- **Vents placed by hash**, as a stand-in for phase 3's zone keys.
- **Stronger filtering for high-contrast stripes** (AA helper changes
  above). It's a global change: phase 1's seams are now slightly softer.
- **HDR dimming of distant lights.**
  - Coverage is filtered before tonemapping, so a light at 30% coverage
    and energy 3 writes 0.9 and still looks almost full brightness.
  - Distant lights would read too bright and swim as their coverage shifts.
    The lights flickered even in the averaged reference.
  - Lights ease from `light_energy` (3) to `light_far_energy` (0.8) as they
    drop below a few pixels: the doc's "dimmed average".

## Gate
### Clean in motion (RTX 3080, 1080p, MSAA 4x + SMAA, clear weather)
Same method as phase 1 (camera creeps 1.2 cm a frame, 16 frames, road
pixels only), with the corrected far region. Far flicker, and far
brightness as sRGB luma:

| d | Pose | Flicker: grid | surface | average | Brightness: surface | average |
|---|---|---|---|---|---|---|
| 200 | chase | 0.00153 | 0.00116 | 0.00112 | 0.361 | 0.359 |
| 200 | low | 0.00127 | 0.00094 | 0.00092 | 0.394 | 0.392 |
| 200 | top | 0.00176 | 0.00077 | 0.00064 | 0.309 | 0.310 |
| 850 | chase | 0.00161 | 0.00131 | 0.00131 | 0.297 | 0.296 |
| 850 | low | 0.00221 | 0.00184 | 0.00185 | 0.317 | 0.317 |
| 850 | top | 0.00171 | 0.00063 | 0.00055 | 0.255 | 0.255 |
| 2400 | chase | 0.00102 | 0.00057 | 0.00049 | 0.135 | 0.136 |
| 2400 | low | 0.00319 | 0.00433 | 0.00430 | 0.084 | 0.083 |
| 2400 | top* | 0.01404 | 0.01082 | 0.00787 | 0.222 | 0.231 |

\* Inside the loop: its "far" road is only metres from the camera, so the
flicker there is resolved detail moving. That pose isn't meaningful for
aliasing.

Reading it:
- **No pattern aliasing.** Far flicker is within 0.99–1.20× of the averaged
  reference (1.00–1.04× in chase and low, up to 1.20× from 30 m up, where
  the far road is still resolved).
- **No brightening.** The surface is never more than 0.5% brighter than
  its reference far away.
- **How it got there.** The first build was at 1.8–2.6× in the low pose.
  A/B with `TS_PARAMS` showed it came from:
  - the hazard diagonals (main cause);
  - the rib grooves;
  - the channel lights (the HDR effect).

  The filter and HDR changes above fixed all three.
- **2400 low**: the grid flickers less than the surface there. That's the
  lights in the loop (they flicker the same in the averaged reference):
  real moving emissive detail.
- **Not measured: human eyes.** Gate 2 is your hand test at speed. Screenshots below.

### Cost (RTX 3080 only)
Same bench as phase 1, final shader, two interleaved runs, 20 s each.
GPU frame time median, ms:

| Config | 1080p a | 1080p b | 1440p a | 1440p b |
|---|---|---|---|---|
| `grid_v37` | 1.59 | 1.62 | 2.49 | 2.50 |
| `surface_low` | 1.67 | 1.68 | 2.58 | 2.57 |
| `surface_high` | 1.67 | 1.69 | 2.59 | 2.56 |

- **High tier at 1440p: +0.08 ms over the grid. Inside the +0.5 ms budget.**
- **Low tier at 1080p: +0.07 ms over the grid. This FAILS the strict gate**
  ("no more than the grid costs"), on the 3080. Scaled by ALU, the 1080 Ti
  could be around +0.2 ms.
- **The cost is per-pixel overhead, not the modules.** Removing pieces at
  1080p (surface vs grid):

  | What's removed | Surface vs grid |
  |---|---|
  | Nothing (full surface) | +0.09 ms |
  | Lights and LEDs | +0.06 ms |
  | Rib/grate/vent modules | +0.09 ms |
  | Hazard | +0.08 ms |

  - The modules are coherent per-band branches, so they're nearly free.
  - What costs is what every road pixel pays: the 13-band loop with its
    light checks, two extra dot-row filters, the extra derivatives, and the
    tangent varyings.
  - The loop optimizations took +0.09 down to +0.07. Low and high cost the
    same because normals and parallax are cheap.
- **Options** (your call):
  1. Accept a small low-tier overhead and restate the budget, e.g.
     "≤ +0.1 ms on the 3080, verify on the 1080 Ti".
  2. Make the low tier draw less: grates and ribs as flat averages, no
     LEDs. That gives up some look on low for parity.
  3. Wait for the 1080 Ti numbers before deciding.

## Screenshots
In `%APPDATA%\Godot\app_userdata\full_throttle_flux\`:
- `track_surface\builder_lab_<d>_<pose>_<grid|surface|average>.png`, `_chase_debug_*.png`,
  `track_surface.csv`. Best views for gate 2:
  - `builder_lab_0850_chase_surface.png`
  - `builder_lab_0200_top_surface.png`
  - `builder_lab_2400_top_surface.png`
- `gfx_bench_v38_p2\bench_<res>\builder_lab_<config>_00.png` (chase cam at
  speed) and `gfx_bench.csv`.

## Checks
- `track_uv2_check`: both labs ok, tangents exact.
- Track Builder validator, Builder Lab: 0 errors, 1 warning (the same on `main`).
- `env_selftest`: as on `main`, the CPU-timing check fails (ship FX above
  3 ms/frame on this machine).
  - "head pinned to the nozzle" also fails intermittently, on the phase 1
    commit too (0.0 then 0.048 m in two runs there).
  - It's a timing-sensitive trail test on circuit 3, which this work
    doesn't touch.

## Open issues for phase 3+
- **The low-tier budget** (above): decide before more modules land.
- **Gate 2 tuning**: ribs and grates are subtle from the chase cam.
  Parameters to tune:
  - `rib_dark`, `rib_pitch`;
  - `grate_cell`, `grate_bar_color`, `grate_glow_energy`;
  - `light_energy`, `light_far_energy`.
- **Vents by hash** → phase 3 zone keys. Profile constants → the
  `TrackSurfaceProfile` data texture. The band loop's per-pixel cost should
  be measured again when it becomes a texture fetch.
- **Light flow animation**: phase 5 (the lights are static).
- From phase 1, still open:
  - junctions on the grid;
  - branch walls' weather mask;
  - the 1080 Ti run;
  - the circuits.
- Vertex data is now UV2 + CUSTOM0 + TANGENT on every segment, walls too:
  40 bytes more per vertex.

## Files
- `full_throttle_flux/shaders/track/modules/surface_common.gdshaderinc`,
  `ribs`, `grate`, `vents`, `lights`, `edges` (`.gdshaderinc`, new)
- `full_throttle_flux/shaders/track/track_surface.gdshader`: 13 bands,
  module dispatch, tier, Toksvig, normals
- `full_throttle_flux/shaders/track/surface_aa.gdshaderinc`: `aa_filter_width`, `aa_fade_px` 3
- `full_throttle_flux/scripts/tracks/track_road_segment.gd`: tangents
- `full_throttle_flux/tools/dev/track_surface_shots.gd`, `track_uv2_check.gd`
