# FTF v35 — Phase 0: environment FX foundation

Design: `FTF_v35_ENV_FX.md`. This note is what Phase 0 built. Nothing here
renders an effect yet; it is the state every effect will read.

Verified headless on Godot 4.7.2 (see "Verified" below). What is left for you
is the visual part: the overlay and the sky in a real window.

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
| `tools/env/env_selftest.gd` + `_boot.gd` | **new** — Phase 0 self-test (below) |
| `resources/track_fx/test_circuit_3_live_cover.tres` | **generated** — Utopia's 30 covered spans |
| `resources/track_fx/utopia_environment.tres` | **new** — Utopia's TrackEnvironment: the cover set + the five presets as allowed weather; default stays clear, dust 0 |
| `resources/tracks/test_circuit_3_live.tres` | `environment` = the above |
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

## Verified (headless, Godot 4.7.2)

**Self-test** — `godot --headless --fixed-fps 60 --path full_throttle_flux -s res://tools/env/env_selftest_boot.gd` — PASS, 0 failed:

- SplineSpan equals the pre-v35 MagneticZone maths on 20 000 random cases (max diff 0).
- Zone blending: overlaps, lap-seam wrap, neutral outside.
- On Utopia with one driven ship: probe active, grounded 481/481 ticks; spline
  distance 300.0 where UtopiaKit says 300 (road_xf works); 771 m driven with no
  backward steps; side rays see the walls; a covered test zone takes local
  wetness to 0.00 under rain; steering into the wall gives 1 `wall_hit` then
  `wall_scrape`s; snow sets frost 0.80; a mid-race change blends (wet 0.05
  after 1 s); the sun never moves (23.0 deg); Clear restores the authored
  coverage (0.52); the probe goes idle once the state is freed.
- Not checkable headless: the global uniform readback (dummy renderer).

**Handling unchanged** — `tools/dev/ai_race_probe.gd`, 8 ships, 40 s, same
checksum on main @ 232e2f6 and this branch:

| Track | main | v35 |
| --- | --- | --- |
| Utopia | 3950927593 | 3950927593 (also with the Utopia environment wired in) |
| Loop Lab (magnetic zones, 7 ships in zones) | 3042917252 | 3042917252 |

The ObjectDB / resources-in-use warnings at exit are identical on main.

**Utopia cover survey** — 30 spans; they match the greybox README: the Gate
hall over the grid (96–142 m), the Atrium tunnel (1616–1802 m, plus its ribs
and sky-bridges from 1348 m), the arcade arches every ~46 m and the slab hall
(2644–2782 m), the hairpin canopy (2912–3280 m), the telescoping portals every
60 m (3946–4132 m), the viaduct building (4360–4456 m), the spiral crossing
itself (4586–4778 m), the sea colonnade (5786–5952 m). Phase 4 note: many
spans are 6–12 m arches, a fraction of a second at race speed; precipitation
should ignore short spans or fade over a minimum time so rain doesn't flicker
under every arch.

## Checks left for the Phase 0 gate (visual)

1. Utopia race starts; the console prints
   `EnvironmentState: weather=Clear dust=0.00 zones=30 spline=6014 m sky=yes`.
2. Track looks exactly as before in clear weather.
3. F3: ground ~2 m when grounded; wall distances shrink as you hug a wall;
   spline distance increases smoothly and wraps at the line; red cross and
   SCRAPING on wall contact.
4. F4 through the presets: global values move over ~20 s; clouds thicken for
   rain/snow/fog without the sun moving; Shift+F4 snaps; back to Clear
   restores the original sky.
5. F4 to Rain, drive into the Atrium (1616 m): `covered` 1.00, local wet 0.00.
6. Restart the race and quit to menu: no errors; globals back to 0.
7. Optional: an AI training run is unaffected (probes idle).

## Known limits

- On fork branches the probe tracks MainSpline only; zones on branches are
  not supported yet (Lab tracks only).
- `FxSettings` is not exposed in a menu yet; edit `user://fx_settings.tres`.
- No shader reads the globals yet — that starts in Phase 2 (dust) and Phase 4
  (`env_surface.gdshaderinc`).

---

# Phase 1: thrust trails and wingtip air streams

## Files

| | |
| --- | --- |
| `scripts/fx/trail_ribbon.gd` | **new** — `TrailRibbon`: distance-sampled ribbon, centripetal Catmull-Rom, head pinned to the socket, width/opacity taper by age and length, capped by lifetime and metres, `clear()` on teleport |
| `shaders/fx/trail_common.gdshaderinc` | **new** — camera-facing expansion in the vertex shader (works for any camera: chase, cinematic rig, spectator), noise, soft edge |
| `shaders/fx/trail_energy.gdshader` | **new** — thrust: additive, unshaded, HDR so the glow blooms it, scrolling energy noise, white-hot core near the nozzle, no fog (fades by distance instead) |
| `shaders/fx/trail_air.gdshader` | **new** — air streams: alpha-blended, fogged, slow swirl noise |
| `resources/fx/trail_energy.tres`, `trail_air.tres` | **new** — the two shared materials (per-ship colour goes in vertex colour, so every ship shares them) |
| `scripts/fx/ship_fx_profile.gd`, `resources/fx/default_ship_fx.tres` | **new** — `ShipFxProfile`: colours, sizes, boost response, air-stream response, fallback socket offsets |
| `scripts/fx/ship_fx.gd` | **new** — `ShipFx`: per ship; finds or creates sockets, builds the ribbons, drives them every frame, LOD |
| `scenes/ships/variants/variant_red_yellow.tscn` | `FX_Thrust_L/R`, `FX_Wingtip_L/R`, `FX_Airbrake_L/R`, `FX_Belly` markers |
| `scripts/resources/weather_preset.gd`, `scripts/env/environment_state.gd` | `humidity` (rain 0.9, snow 0.7, fog 1.0, dust storm 0.0, clear 0.3) |
| `scripts/ships/ship_controller.gd` | attaches `ShipFx` next to the probe |
| `scripts/env/env_debug_overlay.gd` | humidity, trail CPU per frame, the camera ship's FX LOD and point counts |
| `tools/env/render_trails(_boot).gd` | **new** — chase-cam stills (straight, weave, boost, rain, side) |

## How it behaves

- **Sockets** come from the model: the variant now has markers. Positions were
  measured from the mesh (twin engine pods at x ≈ ±0.45 at the tail, wingtips
  at x ±1.92), the airbrake and belly ones are estimates for Phase 2: check
  them in the editor. Without markers (e.g. `default_racer.tscn` spawned
  without the visual pool) `ShipFx` creates them from the profile fallbacks,
  undoing that scene's 1.808 ShipMesh scale.
- **Thrust**: idle glow 0.3, full at full throttle, smoothed so blips don't
  strobe. Boost overspeed lengthens (x1.6), brightens (x1.8), widens (x1.3)
  and whitens the trail.
- **Air streams**: show above 45 % of max speed, full at 90 %; opacity from load
  (|yaw rate| x speed, outside tip more, plus that side's airbrake) and from
  humidity, so they are faint on a dry day and clear in rain or fog.
- **LOD** (`FxSettings`): camera target and near ships get both; FAR ships keep
  only the thrust trail with straight segments; OFF ships stop emitting.
- **Respawn** clears the trails (no ribbon across the map).
- Purely visual: `ShipFx` only reads the ship.

## Verified

- Self-test (now with a trails section) — PASS: sockets found on the variant,
  trail built (40 points), head pinned to the nozzle (gap 0.0000 m), air
  streams appear at speed in rain, length within its cap, respawn clears.
- **Handling unchanged with trails live**: `ai_race_probe` checksums still
  equal main (Utopia 3950927593, Loop Lab 3042917252).
- **Cost**: 8 driven ships, 32 ribbons, no camera LOD (worst case): trail CPU
  avg 0.82 ms, worst 1.29 ms per frame on the cloud CPU. Real races are lower
  (far ships drop to thrust-only). If it ever shows up in profiling, the
  upgrade is the shader-ribbon backend from the design.
- **Rendered** under xvfb on software Vulkan (`render_trails`): first pass
  read as solid white rods (HDR energy saturating, 30 m long) and the air
  streams were invisible; tuned to energy 1.6, fade power 3, 14 m, 0.4 m wide
  at the nozzle; air streams 0.65 opacity, 0.4 base load, 0.5 m tail width.
- The engine run also caught a real shader bug (varyings can't be written in a
  helper function); fixed with a `TRAIL_VARYINGS` macro in `vertex()`.

```
xvfb-run -a godot --path full_throttle_flux --resolution 1280x720 --fixed-fps 60 -s res://tools/env/render_trails_boot.gd -- /tmp/trails
```

## For your eye (in game)

1. Trail colour and brightness against each track's sky and road; the
   additive trail has no fog, check it in the Fog preset.
2. Boost response, and idle glow on the grid.
3. Air streams: Rain or Fog (F4), then hard turns and airbrakes.
4. Socket positions on the model (thrust markers should sit in the pods).
5. Tuning lives in `default_ship_fx.tres` and the two trail materials.

## Not yet

- No motion-blur interaction check in a real window (transparent FX should not
  write motion vectors; verify no smearing).
- Per-ship trail colours wait on the class / team decision (open question).

---

# Phase 2: dust, spray and snow powder

## Files

| | |
| --- | --- |
| `scripts/fx/fx_pools.gd` | **new** — `FxPools`: per race, one world-space GPUParticles3D per look (dust, spray, powder) fed by every ship with `emit()`; wind pushes all pools; dust tinted with the track's `dust_color` |
| `scripts/fx/fx_particle_preset.gd`, `resources/fx/particles_{dust,spray,powder}.tres` | **new** — budgets per quality tier, motion, size growth, look |
| `shaders/fx/dust_puff.gdshader` | **new** — billboard, sun-lit, soft against geometry (depth), noise erosion with age, faded within ~7 m of the camera |
| `scripts/fx/ship_dust.gd` | **new** — `ShipDust`: ground, wall L/R and airbrake L/R emitters per ship |
| `scripts/fx/fx_prewarm.gd` | **new autoload** `FxPrewarm` — see "The RNG catch" |
| `scripts/fx/ship_fx.gd`, `ship_fx_profile.gd` | ShipDust wiring, dust LOD (FULL 1, NEAR 0.6, FAR 0.2, OFF 0), dust parameters; a total ship-FX CPU timer |
| `scripts/fx/trail_ribbon.gd` | vertex loop unrolled (~25 % cheaper) |
| `scripts/env/env_debug_overlay.gd` | dust kind and per-emitter rates, pool emissions per frame, total FX CPU |
| `tools/env/render_dust(_boot).gd` | **new** — stills: dust, airbrake, wall, side, spray, powder |

## How it behaves

Rate per emitter (particles/s) = surface × speed × term × LOD × quality:

- **surface** is the probe's LOCAL surface: track dust × `dust_scale` zones,
  damped by wetness. Above `dust_wet_switch` (0.3) the same emitters throw
  **spray**, above `dust_frost_switch` (0.35) **snow powder**. Covered zones are
  dry, so a tunnel in the rain kicks up dust again.
- **speed**: from 15 u/s, full at 100 u/s.
- **ground term**: full at hover height, fades to 0 at 3× hover height (jumps),
  +30 % when the hull dips below hover height (landings).
- **walls**: within 4 m, quadratic with closeness, pushed off the wall.
- **airbrakes**: on the ground under each brake socket × that brake's input,
  thrown outward.
- Particles start with 65 % of the ship's velocity (the wake drags the dust)
  plus rise and spread, then drag, turbulence and the race wind take over.
- Spawns are spread along the path each emitter covered since the last frame.

Godot details found by testing in the renderer: `emit_particle()` only spawns
while `emitting` is **false**; per-particle scale and colour passed to it are
overridden by the process material (so: size from the preset, colour from the
material); position and velocity work.

## The RNG catch (and why there's a new autoload)

With dust on, the race checksums changed (Utopia 4098609093, Loop Lab
1671971390). Handling was fine. Of everything the FX create, only the
**GPUParticles3D constructor draws from Godot's global random generator** (to
seed itself), and the AI uses that generator: `ai_control_decider` (line
wobble), `ai_ship_controller` (route bias, shortcut rolls). The probe seeds it
just before launching the race, so three emitters built during setup shifted
every AI roll after them.

Options weighed: give the AI its own RNGs (robust, but changes AI code and
breaks every existing baseline), or reseed after building the pools (hacky,
diverges from main once). Chosen: **`FxPrewarm` builds 12 GPUParticles3D at
startup**, before anything seeds the generator, and races borrow and return
them. No AI change, checksums equal main again, and Phase 3/4 particle
systems borrow from the same stash. Worth knowing for later: anything that
constructs a GPUParticles3D mid-race will shift the AI's random stream.

## Verified

- Self-test dust section — PASS: three pools; dry track emits dust (94 in 2 s
  at track dust 0.3, NEAR LOD) and almost no spray; the left airbrake throws
  dust on the left only; rain switches to spray (237, no dust); snow to powder
  (173); a dust storm raises the ground rate (134/s vs 47 dry); emitter nodes go
  back to the stash after the race (12 / 12).
- Race checksums equal main with dust running: Utopia 3950927593, Loop Lab
  3042917252.
- Cost on this 2-vCPU box (about 2× slower than the Phase 1 one), 8 ships, no
  camera LOD: all ship FX including dust avg 1.8–2.1 ms/frame (ribbons
  1.4–1.7, dust ~0.35).
- Rendered (dusty Utopia, test-only dust 0.7): first pass was a thin, sparse
  plume and hard round puffs (30 % inherited velocity spread it over ~190 m);
  tuned to 65 % inherit, ~3× rates, wider spawn under the hull, softer puffs,
  bigger budgets. Now a visible plume, airbrake clouds, a haze along the wall,
  a white spray wake, snow puffs. Render camera has no `ship`, so those ships
  ran at NEAR LOD (0.6); the player in game gets FULL.

## For your eye

1. Pick the dusty track (`TrackEnvironment.dust`, e.g. 0.6) or use the Dust
   storm preset (F4).
2. Puffs still read a little "cotton ball" up close: next step would be a
   noise flipbook texture or more, smaller particles.
3. Readability in a pack: the near-camera fade (1.5–7 m) and LOD are the knobs.
4. Airbrake and belly socket positions on the model are still estimates.

---

# Phase 2b: dust overhaul (many small textured puffs)

Asked for: much better dust: many more, smaller particles, a noise texture,
the full deal. Iterated against software-Vulkan renders until the chase view
read as a soft billowing plume.

## What changed

| | |
| --- | --- |
| `tools/env/bake_dust_atlas.py` | **new** — bakes `assets/fx/dust_puffs.png`: 8 × 8 puffs at 128 px; each a lumpy cluster of soft blobs carved by domain-warped fbm, a quarter stretched into wisps, irregular noise-eroded edge, zero at the tile border. RG = normal, B = thickness, A = density. Deterministic (seed 35). `python3 tools/env/bake_dust_atlas.py [out.png] [--preview p.png]` (numpy, Pillow) |
| `assets/fx/dust_puffs.png` | **new**, imported with mipmaps |
| `shaders/fx/dust_puff.gdshader` | rewritten: atlas tile per puff from a STABLE random (`anim_offset`, CUSTOM.z); normals spun with the billboard and sun-lit (wrap diffuse + back-light through thin parts); thin wisps dissolve first with age; thick cores slightly darker; soft depth 0.35 m; faded 1.5–6 m from the camera. Fixes the old shader's seed coming from the particle's moving position (the pattern swam) |
| `scripts/fx/fx_pools.gd` | per look: **carriers** (invisible, script-emitted) + **puffs** (GPU sub-emitter). Two prewarmed nodes per look |
| `scripts/fx/fx_particle_preset.gd`, `particles_*.tres` | carrier and puff settings |
| `scripts/fx/fx_prewarm.gd` | 16 nodes; freed at exit |
| `scripts/fx/ship_dust.gd`, `ship_fx_profile.gd` | carriers spawn 0.6 m above the road; carrier rates (ground 280/s, wall 180/s, airbrake 220/s at full); inherit 92 %; spread 7 m/s |
| `tools/env/render_dust.gd` | camera with a `ship` (lead ship at FULL LOD like the player), `RENDER_ONLY=dust,airbrake` |

## How it works

Ships emit invisible **carriers** with 92 % of the ship's velocity. They ride
along under the ship for 0.45 s, decelerating, and lay up to 60 small textured
**puffs** per second each, on the GPU. Dust puffs stay where they are laid
(spray keeps its carrier's velocity: a rooster tail), burst upward up to
4 m/s, grow ×4.5, live ~1.6 s. Result: around 7 000 puffs/s from the player's
ship at full dust, for ~5 script calls per frame.

## Findings worth keeping

- **Sub-emitter cap**: a carrier lays at most ONE puff per simulation step,
  and GPUParticles3D simulates at `fixed_fps = 30` by default. Measured: a
  carrier made 24 puffs over 0.8 s whether asked for 30/s or 90/s. Carriers
  now run at 60 Hz (`FxPools.CARRIER_HZ`); more density = more carriers.
- **Chase camera physics**: a stationary puff is between the ship and a chase
  camera 13 m back for only ~0.1 s at 120 u/s. Slow carriers drop behind the
  camera before laying most of their puffs, and any fade-in hides exactly the
  puffs the camera can see. Hence fast carriers, fade-in 0.
- **Soft particles vs the road**: puffs laid on the road surface were erased
  by the soft-depth blend (half the quad below the road). Spawn 0.6 m up,
  upward burst, 0.35 m blend.
- **Density beats size**: a few big opaque puffs read as clods; many fainter
  ones (opacity 0.2) overlap into haze.

## Render iterations (chase cam, dusty test Utopia)

1. Atlas + carriers: good puff shapes, ~10 puffs on screen.
2. Stationary puffs: worse (puffs buried in the road, faded in out of view).
3. Lifted, FULL LOD camera: side view shows a trail, chase view still empty.
4. Fade-in off, wider bursts: a few more.
5. Carriers at 60 Hz: some more.
6. Carriers ride with the ship: a real plume, but lumpy.
7. Softer, more transparent: lumps with gaps.
8. 2× carriers, bigger and fainter puffs: soft billowing plume, rolling
   airbrake cloud, wall haze, white spray mist, snowy powder. Kept.

## Verified

- Self-test PASS (dry: 103 dust carriers in 2 s and no spray; airbrake left
  only; rain → spray; snow → powder; dust storm ×2.8; stash 16/16).
- Race checksums equal main (Utopia 3950927593, Loop Lab 3042917252).
- Cost (2-vCPU box, 8 ships, no camera LOD): all ship FX avg 1.46 ms/frame
  CPU. GPU cost unmeasured here (software renderer): watch the overdraw of
  the airbrake cloud close to the camera on your 3080, and lower
  `FxSettings.quality` budgets if needed.

## Knobs

`resources/fx/particles_dust.tres` (opacity, grow, lifetime, burst,
turbulence, erosion), `default_ship_fx.tres` (carrier rates, inherit,
spread), `FxPools.CARRIER_HZ`, re-bake the atlas for a different puff
character.

# Phase 3: wall hits (sparks, wall dust, scrape marks, flash)

## What's new

| | |
| --- | --- |
| `scripts/fx/fx_impacts.gd` | **new** — race-wide, under the EnvironmentState: one spark emitter (prewarmed GPUParticles3D, velocity-aligned streaks, white-hot → orange → dull red, gravity), a ring of 96 scrape-mark Decals (25 s life, last 6 s fading; glow when fresh, cools in 1.2 s), 6 pooled OmniLights for hit flashes (0.16 s). Own RNG |
| `scripts/fx/ship_impacts.gd` | **new** — per ship, listens to `wall_hit` / `wall_scrape`. Hit: sparks 10–80 by closing speed (40 u/s = full), flash above 25 %, a puff of the current surface kind (dust / spray / powder), a mark. Scrape: 4 sparks/s per u/s of speed carrying 80 % of the ship's velocity (they trail behind), wall dust 60 carriers/s, marks |
| `shaders/fx/spark.gdshader` | **new** — camera-facing streak along the particle's velocity, additive HDR |
| `tools/env/bake_scuff.py` → `assets/fx/scuff_albedo.png`, `scuff_emission.png` | **new** — scorch + bare-metal scratch lines, emission for the hot glow (seed 35) |
| `ship_fx.gd` | builds ShipImpacts; ship meshes moved to their own render layer (19) so marks never paint the ship; re-tagged every second (the visual pool can swap meshes) |
| `ship_fx_profile.gd` | "Wall hits (Phase 3)" group |
| `ship_dust.gd` | `surface_amount()` public (wall puffs use it) |
| `env_debug_overlay.gd` | impacts line (sparks / marks / flashes totals) |
| `tools/env/render_impacts.gd` | stills: hit, scrape, scrape_side, marks_hot, marks_cold, scrape_wet. `IMPACT_CLEAN=1` = no dust, `IMPACT_LOG=1` = path + mark placement log |

## How it behaves

- Sparks are quenched on wet surfaces (−60 % at full wetness). At LOD OFF a
  ship makes no sparks but still leaves marks.
- **Continuous contact = one unbroken line.** Riding a wall really produces a
  stream of small glancing `wall_hit`s with few `wall_scrape`s in between; at
  first each laid a 1.4 m mark, 5–6 m apart (dotted). Now any contact within
  0.3 s of the last (physics ticks, not wall time) bridges from the previous
  mark to the new point; marks are laid every max(1.4 m, speed × 0.07 s), so
  96 decals cover a long slide.
- Marks project onto whatever is inside their 0.6 m-deep box: pillars and
  rails at the wall get scuffed too (reads fine).

## Verified

- Self-test PASS: sparks on contact, marks laid and on the wall, marks skip
  the ship layer, all 5 ship meshes on layer 19, hard hit flashes, wall
  contact kicks up surface particles, prewarm stash 16/16. All ship FX
  1.5–1.7 ms/frame (8 ships, 2 vCPUs).
- Mark placement: centred within 2 cm of the wall, normal matches the wall.
- Race checksums equal main (Utopia 3950927593, Loop Lab 3042917252).
- Renders: hit = spray of streaks + orange flash; scrape = glowing line along
  the wall behind the ship with sparks trailing; marks cool from an orange
  line to faint grey scratches.

## For your eye

- On Utopia's near-black walls a cold mark is subtle (bright scratches only;
  the scorch is invisible on black). Lighter walls will show the scorch.
- With heavy dust, wall dust plus ship dust can bury the sparks at scrape
  speed; wall dust was cut from 150 to 60 carriers/s for that. Tune
  `scrape_dust_rate` / `hit_dust_carriers` if it's still too much.
- Spark size (`streak_width` 0.045 m, `streak_length` 0.7 m in
  `spark.gdshader`) was judged on a 720p software render; at 1440p+ they
  may want to be thinner.

## Knobs

`default_ship_fx.tres` → Wall hits group; `FxImpacts` constants (MARKS,
MARK_LIFE, MARK_COOL, MARK_GLOW); `spark.gdshader` uniforms; re-bake the
scuff for a different mark look.

# Phase 4: weather (in progress)

Kept up to date per piece, in case the session's context is compacted.

## Done so far

| | |
| --- | --- |
| `shaders/env/env_surface.gdshaderinc` | **new** — one call at the end of fragment(): wet (darker, smoother, puddles from world noise on flat ground, rain rings in puddles, run-off streaks on vertical faces), frozen (frost tint, snow on up-facing ground thinned on the racing groove, ice in the groove, sparkle), dusty (dust colour, rougher, heavier at the edges). Reads the env globals + the per-distance zone mask with the SAME formulas as the ship probe |
| `shaders/env/track_surface.gdshader` | **new** — the grid shader's exact look + env_surface + line glow |
| `scripts/env/env_surfaces.gd` | **new** — at race start swaps the SHADER of every grid-shader material on the track (road + walls, circuits and builder tracks) and fills `surface_kind`, `u_scale`, `road_v0/v1` from the CSG node. Never reassigns the node's `material` (that would rebuild the CSG mesh and collision). Also builds the zone mask |
| `scripts/env/weather_fx.gd` + `shaders/env/precip_*.gdshader` | **new** — rain / snow / grit. Near: one prewarmed GPUParticles3D with a custom process shader: no emission, every particle falls forever from a fixed seed and is wrapped into a 44×26×44 m box around the camera (full at any speed); the draw pass stretches each along its velocity relative to the camera. Far: a cylinder with procedural streaks / flecks / wind sheets. Cut out while the camera's ship is in a covered zone |
| `scripts/resources/weather_preset.gd` | + `sky_mood`, `fog_tint`, `fog_tint_dust`, `sun_scale`, `height_fog_density`, `height_fog_top`, `fog_sky_affect`, `line_glow` |
| `resources/weather/*.tres` | 13 presets: clear + rain / snow / fog / dust storm × light, medium, heavy ("Blizzard", "Mist" as names) |
| `environment_state.gd` | installs surfaces + mask + WeatherFx; sky mood / fog tint / sun / height fog (relative to the road's mean height) blended and restored; SSR on above wetness 0.15 (Medium/High quality), restored after; `env_line_glow` |
| `project.godot` | globals `env_track_mask` (sampler2D), `env_track_length`, `env_line_glow` |
| `tools/env/render_weather.gd` | stills per preset: chase + low road view (`WEATHERS=`, `RENDER_ONLY=`) |
| `tools/env/weather_profile.gd` | **for your 3080**: GPU ms per preset in a real 8-ship race vs clear |
| `tools/env/probe_csg_uv.gd` | dev probe of the CSG UV mapping |

## Findings worth keeping

- **CSG road UVs give the shader the spline distance for free**: UV.x ×
  `path_u_distance` = metres along MainSpline (within 0.3 m on Utopia). So
  the per-distance mask works in the shader with no extra data: tunnels are
  dry exactly where the ship probe says they are.
- **CSGPolygon3D reverses a counter-clockwise polygon** before extruding;
  outline vertex i then sits at UV.y = i / (2n). Utopia's driving surface is
  UV.y 3/12..4/12 (first guess 1/12..2/12 was the far side of the bottom).
  The selftest now checks this on the real mesh.
- Godot `fog_density` is exponential per metre: Utopia's authored 0.00014 is
  near-clear; fog weather needs 0.003–0.012.
- Height fog only works below `fog_height`, so presets set it relative to the
  track's average road height.
- Volumetric fog stays off (it is tied to the sky controller's
  `volumetric_shafts` and is the expensive option); weather uses distance +
  height fog.
