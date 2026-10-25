# FTF v35 — Phase 0: environment FX foundation

Design: `FTF_v35_ENV_FX.md`. This note is what Phase 0 built. Nothing here
renders an effect yet; it is the state every effect will read.

**Not run in the engine yet.** Written against Godot 4.7, syntax-checked with
gdtoolkit only. First job on your machine: the checks at the end.

## Files

| | |
| --- | --- |
| `scripts/tracks/spline_span.gd` | **new** — `SplineSpan.weight()`: the distance-span maths from `MagneticZone.weight_at()`, moved unchanged |
| `scripts/tracks/magnetic_zone.gd` | `weight_at()`, `_wrap()`, `_smooth01()` delegate to `SplineSpan` (same numbers) |
| `scripts/tracks/spline_tracker.gd` | **new** — `SplineTracker`: per-tick distance along a Path3D, the same local search as `MagneticTrack.Tracker`, plus `road_xf` (below) |
| `scripts/env/track_fx_zone.gd` | **new** — `TrackFxZone`: start/end/ramps on MainSpline; `dust_scale`, `covered`, `standing_water`, `snow_drift` |
| `scripts/env/track_fx_zone_set.gd` | **new** — `TrackFxZoneSet`: a saved list of zones, for generated sets |
| `scripts/env/track_fx_zones.gd` | **new** — optional scene node + `sample_zones()` (dust_scale multiplies, the rest take the strongest) |
| `scripts/resources/track_environment.gd` | **new** — `TrackEnvironment`: `dust`, `dust_color`, `default_weather`, `allowed_weather`, `zones`, `zone_sets` |
| `scripts/resources/track_profile.gd` | new `Environment` group: `environment: TrackEnvironment` |
| `scripts/resources/weather_preset.gd` | **new** — `WeatherPreset`: kind, intensity, surface targets, wind, sky overrides |
| `resources/weather/*.tres` | **new** — first-pass presets: clear, rain, snow, fog, dust storm (medium) |
| `scripts/env/environment_state.gd` | **new** — `EnvironmentState`, see below |
| `scripts/env/ship_env_probe.gd` | **new** — `ShipEnvProbe`, see below |
| `scripts/env/fx_settings.gd` | **new** — `FxSettings`: Low/Medium/High, per-ship LOD by camera distance (camera target always FULL) |
| `scripts/env/env_debug_overlay.gd` | **new** — F3 overlay, debug builds only |
| `tools/env/survey_cover.gd` | **new** — headless survey that writes covered spans (tunnels, buildings, bridges) as a zone set |
| `scripts/ships/ship_controller.gd` | `wall_hit` / `wall_scrape` signals with contact point and closing speed; attaches a `ShipEnvProbe` in `_ready` |
| `scripts/modes/mode_base.gd` | `EnvironmentState.install()` right after the track is added, before ships spawn |
| `project.godot` | `[shader_globals]`: `env_wetness`, `env_frost`, `env_dust`, `env_precip`, `env_wind`, `env_dust_color` |

## Handling and AI are untouched

- `MagneticZone` maths moved, not changed. `MagneticTrack.Tracker` is left as
  it was (it has its own copy of the search) so no magnetic-zone lap can move.
- The ship signals are emitted after the wall response and change no state
  the physics reads. The new `_wall_contact_age` only feeds the signals.
- `ShipEnvProbe` is idle without an `EnvironmentState` (AI trainer, dev sims,
  menus): no rays, no spline search, one timer check per tick.

## EnvironmentState

Installed by `ModeBase._load_track()`. Holds wetness, frost, dust,
precipitation (0..1), wind (unit direction in world X/Z + m/s) and dust
colour; publishes them as global uniforms only when they change. Any shader:

```glsl
global uniform float env_wetness;
global uniform vec4 env_wind;   // xy = direction (world X, Z), z = m/s
```

- **Weather**: `apply_weather(preset, instant)`. The race starts instantly in
  `TrackEnvironment.default_weather` (none = clear, zero visual change). A
  mid-race change moves the surface over `surface_change_time` and blends the
  sky over `sky_transition_time`.
- **Sky — change from the proposal.** It does *not* call
  `UtopiaSkyController.transition_to()`: the presets also carry sun azimuth,
  elevation, colours and exposure, so rain on Swoopy would have moved the sun.
  Instead it takes only the weather keys of a preset (`coverage`,
  `cloud_density`, `cloud_absorption`, `cloud_shadow_color`, `cirrus_amount`,
  `wind_speed`, `god_ray_intensity`) plus the preset's fog overrides, and
  snapshots the track's authored values so "clear" returns exactly to them.
- **Wind** direction comes from the sky controller (same vector its shader
  gets) unless the preset overrides it, so clouds and FX agree.
- **Globals outlive scenes**: `_exit_tree()` resets them, so menus and the next
  track are dry.
- **Local surface** formulas live here (`local_wetness()` etc.) so the probe,
  precipitation and later the road shader agree: covered = dry and unfrozen,
  standing water / drifts add on top of the open-air value, dust scales.

## ShipEnvProbe

Child of every ship, `process_physics_priority` 110 (after ships and the
contact resolver). Per tick:

- **Ground**: from the controller's `ground_distance` and smoothed track normal.
  Change from the proposal: no hover-ray hit point stored in the controller;
  the derived point is within centimetres on any road a ship stays grounded on.
- **Walls**: two side rays along the ship's right axis, wall mask 4, 12 m.
- **Spline distance**: change from the proposal — its own `SplineTracker`
  every tick instead of `RacePositionTracker` at 10 Hz. Exact, robust at
  crossovers, and mapped through **`road_xf`** (groundGeo's own transform, as
  `UtopiaKit` uses) so distances agree with UtopiaKit and the survey on the
  four circuits, whose road sits up to ~21 m off the raw spline.
- **Zones and local surface** from EnvironmentState.
- **Hits**: `wall_hit` on the first tick of a contact, `wall_scrape` after; a gap
  under 0.1 s is still the same contact (move_and_slide doesn't report a slide
  every tick).

## Zones without editing track scenes

Zones can live in the track's `TrackEnvironment` (on the TrackProfile .tres)
as well as in a `TrackFxZones` node. The circuits need no scene edits; builder
tracks can use the node later (FxKey). Also changed from the proposal:
`TrackEnvironment.dust` is a 0..1 value rather than a clean/dusty/sandy enum.

## Covered spans: `survey_cover.gd`

The city meshes have no collision, so the tool adds temporary trimesh
collision (own layer, never saved), finds the road through UtopiaKit every
2 m, and casts up from three points across it. 2 of 3 hits within 80 m =
covered; gaps under 10 m merge; runs under 8 m (lamp arms, the start gantry)
drop. The track crossing over itself counts as cover.

```
godot --headless --path full_throttle_flux -s res://tools/env/survey_cover.gd
godot --headless --path full_throttle_flux -s res://tools/env/survey_cover.gd -- res://scenes/tracks/test_circuit_5_live.tscn
```

Writes `resources/track_fx/<scene>_cover.tres`. Sanity check on Utopia: the
README puts the Atrium tunnel in the canyon district, 1300–1900 m.

## Debug overlay

Debug builds, top right. **F3** show/hide · **F4** next weather (blended) ·
**Shift+F4** next, instant · **Ctrl+F4** previous, instant. Shows the global
values and the probe of whatever ship the camera follows (works with the F9
AI spectator), and draws it in the world: green = ground point, orange/cyan =
left/right wall rays, red cross = last wall hit. F3/F4 because F6, F7, F9–F11
are taken and F8 stops the game in the editor.

## Checks for the Phase 0 gate

1. Project opens with no script errors; Utopia race starts; the console prints
   `EnvironmentState: weather=Clear ... spline=<length> m sky=yes`.
2. Track looks exactly as before in clear weather.
3. F3: ground ~2 m when grounded; wall distances shrink as you hug a wall;
   spline distance increases smoothly and wraps at the line; red cross and
   SCRAPING on wall contact.
4. F4 through the presets: global values move over ~20 s; clouds thicken for
   rain/snow/fog without the sun moving; Shift+F4 snaps; back to Clear
   restores the original sky.
5. Run `survey_cover.gd` on Utopia, create a `TrackEnvironment` on
   `test_circuit_3_live.tres` with the generated set in `zone_sets` and
   `rain_medium` as default: in the overlay `covered` goes to 1.00 and local
   wet to 0.00 inside the Atrium tunnel.
6. Restart the race and quit to menu: no errors; globals back to 0.
7. Optional: an AI training run is unaffected (probes idle).

## Known limits

- On fork branches the probe tracks MainSpline only; zones on branches are
  not supported yet (Lab tracks only).
- `FxSettings` is not exposed in a menu yet; edit `user://fx_settings.tres`.
- No shader reads the globals yet — that starts in Phase 2 (dust) and Phase 4
  (`env_surface.gdshaderinc`).
