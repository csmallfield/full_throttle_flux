# FTF v38: track surface, phase 4 (wear and weather)

Phase 4 of the track surface. Earlier phases are in
`FTF_v38_TRACK_SURFACE.md`, `_P2.md` and `_P3.md`. The road now wears where
it's used:
- polish along the AI's racing line;
- grime in the recesses and toward the edges;
- per-panel age;
- scuffs;
- heat scorch where ships brake or corner hard;
- in weather, water, snow and dust collect in channels and grates first.

Same branch, `feature/v38-track-surface`. The how-to is in
`docs/TRACK_AUTHORING.md` §3.7 ("Wear").

**Budget: the low tier is now exactly at its ≤ +0.1 ms on the RTX 3080**
(see Cost). There's no low-tier headroom left for phase 5 without trimming
something. Gate 2 (your hand test) and the 1080 Ti run are still
outstanding.

## Try it
- **Key 9** cycles one more debug view, **wear**: grime red, polish green,
  scorch blue.
- **Builder Lab:**
  - the racing line runs polished through every zone;
  - the tightest corners (hottest around 1,076 m on the main track, 530 m on
    the branch) carry a blue-violet heat tint on the line.
- **Rain** (F4 in game): puddles form in the channels and grate holes before
  the flat plates.

## What was built

### The bake (`TrackSurface`, at load)
When the track loads, `TrackSurface` reads the trained `BakedRacingLine` for
`default_racer`:
- **main track:** its own line;
- **each branch:** its route line, projected onto the BranchSpline;
- **missing line:** a note, and no polish there.

It derives three things per metre:

| Value | From |
|---|---|
| Racing line t | the line's lateral offset (same right-handed frame as the road) |
| Corridor half-width | `corridor_max - corridor_min` |
| Heat (0..1) | braking (v·dv/ds over `BRAKE_REF` 45 u/s²), or cornering load as the airbrake's stand-in (see Decisions); smeared ±8 m |

Retrain the AI line and the wear follows.

### One fetch still (the strip, repacked)
The per-metre texel holds exact integers, unpacked bitwise in the shader:

| Channel | Holds |
|---|---|
| R | profile slots A, B (2 bits each), zone seeds A, B (10 bits each) |
| G | transition start (m) |
| B | blend length (8 bits), heat (6 bits), zone wear (6 bits) |
| A | racing line t (12 bits, 1.6 cm steps), corridor half-width (7 bits, 0.25 m), has-line flag |

Zones, transitions and wear all come from that **one `texelFetch` per
pixel**.

### The wear module (`shaders/track/modules/wear.gdshaderinc`)
Layered last, so it modulates everything above:
- **Polish:** a smooth, slightly brighter strip, `polish_width` (0.4) of
  the corridor's half-width, at least 3 m wide.
- **Grime:** in recesses and toward the edges, swept off the line.
  - Recesses come from a new `TSurf.recess` that every module fills
    (filtered): channels, seams, rib grooves, grate holes, vent slots.
- **Panel age:** a per-panel hash varies the age.
  - 5% of panels are "replaced", cleaner and smoother.
  - Faded with the panel variation, so tiny panels average out.
- **Scuffs** (high tier): long scratches along s, brightest on the line.
- **Scorch:** heat × age, 90% on the line. Blue-violet temper colours,
  nothing in the boost pads' orange.
- **Scale:** everything is scaled by `wear_age` (style default 0.5;
  variation-overridable) times the zone's `wear`.

### Detail texture (placeholder)
`resources/track_surface/wear_detail.png`, 512² RGBA, tiling, made by
`tools/track_surface/make_wear_detail.gd`:

| Channel | Content |
|---|---|
| R | grime fbm |
| G | scratch streaks along +V |
| B | stains |
| A | speckle |

- Imported with **mipmaps, no alpha-border fix, no auto-compression**,
  since all four channels are data.
- Sampled with `filter_linear_mipmap_anisotropic` and **explicit gradients**
  (`textureGrad`, taken at the top of `fragment()`), so zone branching can't
  upset mip selection and the hardware filters it at any distance.
- The low tier doesn't sample it.
- Replace it with a hand-made one in the same layout whenever you like.

### Weather
- `EnvSurface` gets a `recess` field.
- `env_surface_apply()` fills recesses first:
  - **rain:** puddles in channels and grate holes as soon as it's wet;
  - **snow:** drifts in the grooves;
  - **dust:** settles in the slots.
- The grid wrapper passes 0, so walls and circuits are unchanged. The env
  self-test agrees.

### Authoring
- `SurfaceZoneKey.wear` (0–2, default 1), carried into `TrackSurfaceZone`
  and the validator's signature.
- `TrackSurfaceVariation`: `wear_age`, `grime_color`, `scorch_color`.

## Decisions and deviations
Agreed before building:
- **Wear packed into the zone fetch,** not the doc's separate wear strip.
  It stays one fetch per pixel; the wear values step per metre, which is
  invisible in these soft fields.
- **A generated placeholder detail texture,** not procedural noise.
  Mipmapped and anisotropic, it filters itself and is cheaper than fbm.
- **The low tier gets a subset:** polish, grime, panel age and scorch, with
  no texture and no scuffs.
- **Baked at load** from the trained line, so it never goes stale.

Taken during the build (flagged):
- **Cornering load stands in for airbrake.**
  - The doc names braking and airbrake data, but Builder Lab's trained
    speed profile is a flat 120 u/s: the AI never brakes there.
  - The lines carry no airbrake record (`style_airbrake` is empty).
  - Heat is therefore max(braking, 0.6 × a ramp of v²·curvature over
    25–60 u/s²): ships airbrake through hard corners. On the circuits,
    braking dominates (decelerations up to ~130 u/s²).
- **Vent heat glow off by default, and it fades with the slots.**
  - The phase 3 zone seeds moved a vent into the top view.
  - Averaged from 30 m up, its red glow read as a solid red pad: a gameplay
    marker, which the doc's readability rule forbids.
  - `vent_glow_energy` is now 0 (the doc calls the glow optional), and when
    it's enabled it fades out with the slots.
- **Scorch stays 90% on the line.** My first version put 30% of it
  everywhere, which tinted the whole road in hot corners.

## Gate
### Clean in motion (RTX 3080, 1080p, MSAA 4x + SMAA, clear weather)
Same method as phases 2–3, wear on (age 0.5). Far flicker, and far
brightness as sRGB luma:

| d | Where | Pose | Flicker: surface | average | Brightness: surface | average |
|---|---|---|---|---|---|---|
| 200 | industrial | chase | 0.00125 | 0.00123 | 0.361 | 0.361 |
| 200 | industrial | low | 0.00103 | 0.00101 | 0.399 | 0.398 |
| 200 | industrial | top | 0.00081 | 0.00074 | 0.312 | 0.314 |
| 850 | industrial | chase | 0.00141 | 0.00139 | 0.293 | 0.293 |
| 850 | industrial | low | 0.00194 | 0.00191 | 0.315 | 0.314 |
| 850 | industrial | top | 0.00064 | 0.00059 | 0.242 | 0.243 |
| 2070 | mid blend | chase | 0.00055 | 0.00054 | 0.205 | 0.205 |
| 2400 | service | chase | 0.00064 | 0.00059 | 0.141 | 0.141 |
| 4295 | hard seam | chase | 0.00125 | 0.00125 | 0.279 | 0.278 |
| 5000 | grate_run | chase | 0.00117 | 0.00113 | 0.203 | 0.201 |

- **Flicker:** every row is within 0.96–1.09× of the averaged reference
  (the inside-the-loop pose excluded, as before).
- **Brightness:** within 1.2%. The largest is grate_run at 5,000 m, 1.2%
  *above* its reference. The wear texture is mip-filtered in both renders,
  so this is the scuffs and polish at mid distance. Small, but it's the
  first time a row came out brighter rather than darker.
- The texture is filtered by its mips; the strip-driven fields vary over
  metres, so they don't alias.

### Cost (RTX 3080 only)
`gfx_bench`, Builder Lab, `GB_CONFIGS=v38`, two interleaved runs. GPU frame
time median, ms:

| Config | 1080p a | 1080p b | 1440p a | 1440p b |
|---|---|---|---|---|
| `grid_v37` | 1.59 | 1.61 | 2.43 | 2.45 |
| `surface_low` | 1.69 | 1.71 | 2.60 | 2.60 |
| `surface_high` | 1.73 | 1.73 | 2.64 | 2.64 |

- **Low tier at 1080p: +0.10 ms over the grid. At the ≤ +0.1 ms budget,
  no headroom.**
- **High tier at 1440p: +0.20 ms.** Within ≤ +0.5 ms.
- Measured before the final scorch tweak, which is two multiplies.
- **Before phase 5** (decals, living lights), the low tier needs room:
  - drop panel age on low (one hash);
  - or move the grime edge term into the strip;
  - or accept a restated budget.

  The 1080 Ti run would tell whether the 3080's margin matters.

## Checks
- Validator self-test: 25/25. Editor self-test: 0 errors, 0 warnings,
  scene file untouched.
- `env_selftest`: the road and walls are still adopted by the weather
  shader. Only the two known failures remain (CPU timing; the intermittent
  nozzle test).
- The bake on Builder Lab:

  | Path | Racing line t | Corridor half-width | Hottest point |
  |---|---|---|---|
  | MainSpline | −15.6 to +15.6 m | 10.1–17.1 m | 0.60 at 1,076 m |
  | BranchSpline | −12.0 to +15.6 m | 12.0–17.1 m | 0.50 at 530 m |

  Both are inside the road's ±19.5 m surface.

## Screenshots
In `%APPDATA%\Godot\app_userdata\full_throttle_flux\`:
- `track_surface\`: the standard poses, now with `_debug_wear.png`.
- `track_surface_wear\builder_lab_1060_*`: the hottest corner, surface and
  wear view.
- `track_surface_wet\builder_lab_0850_*`: wetness 0.85, puddles in the
  recesses.
- `track_surface_zones\`: the blend, seam and profiles, with wear.
- `gfx_bench_v38_p4\`: chase cam at speed.

## Open issues for phase 5
- **Low-tier budget: no headroom** (above). Decide before decals and
  living lights.
- **The airbrake stand-in.** If the AI recorded actual airbrake use per
  sample, scorch could use it directly.
- **Placeholder detail texture:** replace with a hand-made set when there
  is one (doc open question 5).
- **Wear on tracks without a TrackSurface** (Fork Lab): none yet, since the
  bake lives in TrackSurface.
- **Puddles** use the env world-noise threshold plus recesses. A
  racing-line "dry groove" in rain (ships blowing water off the line)
  would be a natural next step from the polish field.
- From phases 1–3, still open:
  - junctions on the grid;
  - branch walls' weather mask;
  - gate 2, and the 1080 Ti run;
  - the circuits;
  - decal keys (phase 5).

## Files
- New:
  - `full_throttle_flux/shaders/track/modules/wear.gdshaderinc`
  - `full_throttle_flux/tools/track_surface/make_wear_detail.gd`
  - `full_throttle_flux/resources/track_surface/wear_detail.png` (+ `.import`)
- Changed:
  - `full_throttle_flux/scripts/tracks/track_surface.gd`: the bake, the
    packed strip
  - `track_surface_zone.gd`, `track_surface_variation.gd`
  - `full_throttle_flux/shaders/track/track_surface.gdshader`: unpacking,
    wear, the wear view, recess to env
  - modules `surface_common`, `ribs`, `grate`, `vents` (recess; vent glow)
  - `full_throttle_flux/shaders/env/env_surface.gdshaderinc`,
    `env/track_surface.gdshader`: recess
  - `full_throttle_flux/tools/track_builder/surface_zone_key.gd`,
    `track_surfacer.gd`: zone wear
  - `full_throttle_flux/tools/track_surface/sync_surface_presets.gd`: the
    detail texture
  - `track_surface_material.tres`
  - `full_throttle_flux/tools/dev/track_surface_shots.gd`: `TS_GLOBALS`,
    the wear view
  - `full_throttle_flux/scripts/rendering/graphics_settings.gd`
  - `full_throttle_flux/docs/TRACK_AUTHORING.md`, `DEBUG_KEYS.md`
