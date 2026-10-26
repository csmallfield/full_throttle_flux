# FTF v38: track surface, phase 3 (authoring)

Phase 3 of the track surface (phase 1: `FTF_v38_TRACK_SURFACE.md`, phase 2:
`FTF_v38_TRACK_SURFACE_P2.md`). The hard-coded cross-section becomes data you
author in the Track Builder:
- profile resources with presets;
- `SurfaceZoneKey`s that pick a profile per stretch of track, with blends
  or hard seams;
- flex bands;
- a per-track variation.

Same branch, `feature/v38-track-surface`. How to use it is in
`docs/TRACK_AUTHORING.md` §3.7.

**Gates:** gate 2 (your hand test at speed) still hasn't happened. We agreed
to proceed: every look parameter is now in resources and stays editable. The
restated low-tier budget still holds (see Cost).

## Try it
- **Builder Lab now has four surface zones:**

  | From | Profile | Transition |
  |---|---|---|
  | 30 m | industrial | |
  | 2,050 m | service | 40 m blend |
  | 4,300 m | grate_run | hard seam |
  | 6,600 m | industrial | 60 m blend |

  The branch carries on with grate_run from the fork.
- In the editor, move a key under `TrackBuilder/SurfaceZoneKeys` or change
  its preset: the road updates about 0.2 s later.
- **Key 9** now cycles one more debug view, **zones**: a hue per profile,
  blends in between, hard seams white.

## What was built

### Resources (`scripts/tracks/`)
| Resource | What |
|---|---|
| `TrackSurfaceBand` | One band: type (plate, channel, edge, ribbed, grate), width in metres or flex weight, light kind (channels), vents (plates) |
| `TrackSurfaceProfile` | The bands left to right, `mirror` (left edge to centre, repeated in reverse). `problems()` checks the band count, a channel between different kinds of band, and that a flex band exists |
| `TrackSurfaceVariation` | A track's overrides of the shared style: light, plate, hazard, edge line, grate and vent colours, light energy, panel tint, vent chance. Alpha 0 / below 0 = keep the style's value |
| `TrackSurfaceZone` | One resolved zone (written by the builder, never by hand) |

- **The style is the material.** `shaders/track/track_surface_material.tres`
  is the look every track shares; there's no separate `TrackSurfaceStyle`
  class (see Decisions).
- **Presets** in `resources/track_surface/profiles/`:
  - **industrial**: phase 2's layout;
  - **service**: plate lanes, a wide ribbed centre;
  - **grate_run**: wide grates, smooth outer and centre lanes.

  `tools/track_surface/sync_surface_presets.gd` makes any that are missing
  (never overwrites one), and writes industrial into the base material as
  the fallback band table.

### Track Builder (`tools/track_builder/`)
- **`SurfaceZoneKey`** (a `ProfileKey`, like `GreebleZoneKey`): `preset`
  dropdown or a `profile` dropped in, `blend_in` (metres, 0 = hard seam),
  `seed`. A blue gate and label mark each zone, and a blend draws its
  length.
- **`TrackSurfacer`** resolves the keys against the built splines, like
  `TrackGreebler`, and reuses its projection:
  - the lap wraps;
  - branches inherit the main zone at the fork;
  - reusing zone resources keeps the scene stable across rebuilds.
- **`TrackBuilder`** gets a Surface group: `surface_variation`,
  `surface_live`, `surface_markers`, **Refresh surface**, **Remove surface
  zones**.
- **Build** writes the `TrackSurface` node.
- **Validator** (`_check_surface_zones`):
  - a key over 30 m from the track: error;
  - two keys within 2 m: warning;
  - a key without a profile, or a profile's own problems: warning;
  - more than 4 profiles on one path: error;
  - the node missing or out of date: warning.
- **Validator self-test:** 4 new cases (key far, 5 profiles, lanes without a
  channel, zones out of date). **25/25 pass.**
- **Editor self-test** (`TB_EDITOR_SELFTEST=1`) also moves a surface key and
  swaps its preset: the live refresh rewrites the zones and the road gets
  its per-path material. 0 errors, 0 warnings, scene file untouched.

### At load (`TrackSurface`, generated)
For each path (MainSpline, each BranchSpline), it duplicates the road's
material and fills it:
- **Band tables**: up to 4 profiles × 16 bands in uniform arrays
  (`surf_bands`, `surf_profiles`).
- **Zone strip**: one RGBAF texel per metre of path, wrapping onto more rows
  past 16,384 m. Each texel holds the profile slot(s), the transition there
  (start and length, 0 = hard), and the two zone seeds.
- **The variation's overrides.**

It then puts that material on the path's road segments. A track without
the node (Fork Lab, a builder track with no keys) draws the base material's
own table: industrial.

### Shader
- **Band loop:** reads the profile from `surf_bands` (a constant buffer)
  instead of constants. The early exit and the module dispatch are
  unchanged.
- **One `texelFetch` of the strip per pixel:**
  - **outside a transition:** one profile;
  - **inside a blend:** both profiles, cross-faded (only those pixels pay
    for two);
  - **hard seam:** switched over the pixel footprint (filtered, no jaggy
    line), with a seam line across.
- **Zone seeds** vary panel offsets, tints and vents per zone.
- **Edge bands** now find their outer side from their position, so any
  profile can put them anywhere.
- With no zones, the image is identical to phase 2: same metrics to the
  fifth digit.

## Decisions and deviations
Agreed before building:
- **Uniform arrays for the band tables, not the doc's data texture.** A
  texture would cost a fetch per band-loop step (13–16 per pixel, double in
  blends) against 0.03 ms of low-tier headroom. Only the per-metre zone strip
  is a texture.
- **Decal keys deferred to phase 5,** with decal rendering, so no key is
  ever dead UI.
- **The variation lives on the TrackBuilder** (`surface_variation`).
  Build writes it into the TrackSurface node.

Taken during the build:
- **No `TrackSurfaceStyle` class.** The shared material already is the
  style: every look parameter, editable in the inspector. A wrapper resource
  would only duplicate it.
- **No per-zone variation override yet.** The doc's `SurfaceZoneKey` has an
  optional local variation. Variations are material-level and a path has one
  material, so a per-zone override needs per-zone parameters in the strip or
  the uniform arrays. Left for later.
- **Vents still placed by hash** (`vent_every`, `vent_chance`), now with
  per-zone seeds. Vent zones as keys would come with decals in phase 5.
- **Builder Lab keys were added by a script** (load, add keys, Refresh
  surface, save), not by a Build. A Build re-derives every float and drifted
  them in phase 1.
  - The first try ran the script directly with `-s`. Autoload-dependent
    scripts failed to compile there, and the StartFinishLine node was saved
    without its script. I reverted that and redid it with the boot pattern.
  - Four doubles re-serialized at their last digit; I restored them by hand.
  - The scene diff is now the surface data plus one `ext_resource` line
    that moved.

## Gate
### Clean in motion (RTX 3080, 1080p, MSAA 4x + SMAA, clear weather)
Same method as phase 2, with the zones in force. Far flicker, and far
brightness as sRGB luma:

| d | Where | Pose | Flicker: surface | average | Brightness: surface | average |
|---|---|---|---|---|---|---|
| 200 | industrial | chase | 0.00114 | 0.00112 | 0.360 | 0.359 |
| 200 | industrial | low | 0.00098 | 0.00095 | 0.402 | 0.402 |
| 850 | industrial | chase | 0.00135 | 0.00134 | 0.298 | 0.297 |
| 850 | industrial | low | 0.00189 | 0.00187 | 0.318 | 0.318 |
| 2070 | service, mid blend | chase | 0.00047 | 0.00046 | 0.184 | 0.184 |
| 2400 | service | chase | 0.00051 | 0.00046 | 0.127 | 0.128 |
| 3000 | service | chase | 0.00125 | 0.00124 | 0.281 | 0.282 |
| 4295 | hard seam ahead | chase | 0.00125 | 0.00124 | 0.275 | 0.275 |
| 5000 | grate_run | chase | 0.00114 | 0.00109 | 0.207 | 0.206 |

- Every row is within 0.97–1.11× of the averaged reference.
- Brightness is never more than 0.4% above it.
- Blends and hard seams add no flicker.
- **Not checked by eye at speed**: that's gate 2.

### Cost (RTX 3080 only)
`gfx_bench`, Builder Lab, `GB_CONFIGS=v38`, two interleaved runs, 20 s each.
The lap runs through every zone. GPU frame time median, ms:

| Config | 1080p a | 1080p b | 1440p a | 1440p b |
|---|---|---|---|---|
| `grid_v37` | 1.59 | 1.61 | 2.48 | 2.45 |
| `surface_low` | 1.67 | 1.69 | 2.59 | 2.60 |
| `surface_high` | 1.68 | 1.69 | 2.58 | 2.59 |

- **Low tier at 1080p: +0.08 ms over the grid.** Within the restated
  ≤ +0.1 ms. Phase 2 was +0.07: the strip fetch and uniform reads cost about
  0.01 ms, inside the noise.
- **High tier at 1440p: +0.12 ms.** Within ≤ +0.5 ms.
- **Still unverified on a GTX 1080 Ti.** The low tier has 0.02 ms of
  headroom left on the 3080, which is thin for phase 4's wear strip
  (another fetch).

## Checks
- `track_uv2_check`: both labs ok.
- Track Builder validator, Builder Lab: 0 errors. Surface stats: 5 zones,
  MainSpline 3 profiles, BranchSpline 1. The one warning is the same as on
  `main`.
- Validator self-test: 25/25. Editor self-test: 0 errors, 0 warnings.
- `env_adopt_check`: the per-path materials are adopted, with `along_main`
  set per segment.
- `env_selftest`: the two known failures, as on `main` and phase 2 (CPU
  timing; the intermittent nozzle test).

## Open issues for phase 4+
- **Low-tier headroom is 0.02 ms on the 3080.** Phase 4's wear strip adds a
  fetch. Consider packing it into the zone strip's texel row (one fetch
  for both), and run the 1080 Ti before phase 4 lands.
- **Per-zone variation overrides** (above).
- **Fork Lab has no Track Builder**, so it can't take surface keys; it draws
  the default. Its own builder could write a `TrackSurface` node if needed.
- **Blends cost two profile evaluations.** Fine for tens of metres; very
  long blends on low-end cards would show.
- From phases 1–2, still open:
  - junctions on the grid;
  - branch walls' weather mask;
  - gate 2, and the 1080 Ti run;
  - the circuits.

## Files
- New:
  - `full_throttle_flux/scripts/tracks/track_surface.gd`,
    `track_surface_band.gd`, `track_surface_profile.gd`,
    `track_surface_variation.gd`, `track_surface_zone.gd`
  - `full_throttle_flux/tools/track_builder/surface_zone_key.gd`,
    `track_surfacer.gd`
  - `full_throttle_flux/tools/track_surface/sync_surface_presets.gd`
  - `full_throttle_flux/resources/track_surface/profiles/profile_{industrial,service,grate_run}.tres`
- Changed:
  - `full_throttle_flux/shaders/track/track_surface.gdshader`: band tables,
    zone strip, blends, seams, zones view
  - `track_surface_material.tres`: the fallback table
  - `full_throttle_flux/tools/track_builder/track_builder.gd`,
    `track_build.gd`, `track_validator.gd`, `validator_selftest.gd`
  - `full_throttle_flux/scenes/tracks/builder_lab.tscn`: SurfaceZoneKeys
    and the TrackSurface node
  - `full_throttle_flux/scripts/rendering/graphics_settings.gd`: the zones
    view
  - `full_throttle_flux/tools/dev/track_surface_shots.gd`: every per-path
    material, the zones view
  - `full_throttle_flux/docs/TRACK_AUTHORING.md` §3.7, `DEBUG_KEYS.md`

## Screenshots
In `%APPDATA%\Godot\app_userdata\full_throttle_flux\`:
- `track_surface\`: the standard poses, now with `_chase_debug_zones.png`.
- `track_surface_zones\builder_lab_<2070|4295|3000|5000>_chase_*.png`:
  - mid blend;
  - the hard seam;
  - service;
  - grate_run.

  Each comes with its zones view.
- `gfx_bench_v38_p3\`: chase cam at speed.
