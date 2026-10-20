# Full Throttle Flux — v30: magnetic lock zones + Loop Lab

A new greybox test track with a **vertical loop** and a **360° barrel roll**,
and the feature that makes them drivable: **magnetic lock zones**, stretches
of track (by distance along the MainSpline) where ships are held to the road.
Includes a first pass of AI support: AI races Loop Lab with a trained line.
The cinematic camera rig is not done yet.

## Files

| File | What |
|---|---|
| `scripts/tracks/magnetic_zone.gd` | `MagneticZone` resource: one zone's extent, ramps and behaviour |
| `scripts/tracks/magnetic_track.gd` | `MagneticTrack` node: zone list, spline frame queries, per-ship `Tracker` |
| `tools/loop_lab/build_loop_lab.gd` | Generator for `scenes/tracks/loop_lab.tscn` |
| `tools/loop_lab/check_loop_lab.gd` | Raycasts the built road against its spline frames every 10 m |
| `tools/dev/loop_lab_drive_boot.gd` + `loop_lab_driver.gd` | Headless autopilot harness (any track): zone stats, camera stats, A/B runs, chase-cam stills |
| `scenes/tracks/loop_lab.tscn` | The track (generated, don't hand-edit the curve; re-run the builder) |
| `resources/tracks/loop_lab.tres` | Track profile ("Loop Lab"), in the manifest; all modes including race |
| `resources/ai_data/loop_lab_default_racer_trained_line.tres` | Trained AI line for Loop Lab (default racer) |
| `tools/dev/ai_race_probe_boot.gd` + `ai_race_probe.gd` | Headless 8-ship race probe: laps, respawns, airborne-in-zone, seeded and checksummed for A/B |

Also changed:

- `ship_controller.gd`: magnetic zone support (below). Inert on tracks without a `MagneticTrack`.
- `ag_camera_2097.gd`: `magnetic_follow_boost` (tighter frame follow in zones), and a `slerp` fix.
- `track_respawn_manager.gd`: on tracks with zones, never respawns inside one, and respawns behind the ship.
- AI: `track_spline_helper.gd`, `ai_line_follower.gd`, `ai_control_decider.gd`, `ai_racing_line_baker.gd` (see "AI support"); `train_ai_lines.gd` has Loop Lab and a `--track=` filter.

## Magnetic zones

Add a `MagneticTrack` node to a track, point `spline_path` at the MainSpline,
and list `MagneticZone`s. Each zone is `start_distance`..`end_distance`
(metres along the spline) with `ramp_in` / `ramp_out` blend lengths. Ships find
the node through the `magnetic_track` group. Each ship tracks its distance
along the spline with a local search (±40 m around last tick), so on a loop
the exit lane is never confused with the entry lane running beside it.

### The knobs (per zone)

| Knob | Default | What |
|---|---|---|
| `magnet_strength` | 1.0 | **1 = magnetic**: gravity pulls into the road and the hover spring can pull the ship back down; a ship can crawl round upside down. **0 = momentum**: real world gravity, including the part pulling you off a ceiling, and the hover spring only pushes, so you need the speed. In between blends. |
| `slope_gravity_scale` | 1.0 | Speed lost climbing / gained falling. Multiplies the profile's `slope_gravity_factor`. 0 = free climb. |
| `hover_force_scale` | 2.0 | Multiplies `hover_force_max`. The loop asks the hover spring for more than flat track does (v²/r ≈ 180 u/s² at the bottom at full speed); at 1.0 the hull bottoms out. |
| `normal_smoothing` | 30 | Track-normal and body-alignment rate in the zone (profile default 9 lags a loop badly). |
| `contact_recovery` | on | If the hover ray misses, take the ground from the spline frame (within `recovery_range` hover heights and `recovery_half_width` metres of centre). Safety net; never needed in testing (0 recoveries at speed), but used when a momentum-mode ship peels off and comes back. |

`MagneticTrack.magnet_override` (−1 = off) forces one strength on every zone, for A/B testing.

### What changes in the ship (only where weight > 0)

- **Gravity, grounded:** along-road part = real gravity × slope factor × `slope_gravity_scale`; into/out-of-road part blends from real (magnet 0) to a fixed pull into the road (magnet 1). Outside zones the old slope-gravity formula is untouched.
- **Hover spring:** its pulling half fades with the magnet (at magnet 0 it only pushes, like real anti-grav).
- **Airborne:** gravity points between world down and into the road; the airborne "up" for thrust/boost/drag/airbrakes flattening is the road's up instead of world Y.
- **Walls vs road:** collision normals are classified against the track normal, not world Y. The old `absf(normal.y) < 0.5` test called the loop's vertical road a **wall** and would have bounced the ship off it.
- **Wall turn-away** rotates about the ship's own up, not world Y.
- **`up_direction`** follows the track normal, so `move_and_slide()` treats the road as floor on a loop wall or upside down (it was going to be "ceiling").
- **Safe positions** are not recorded inside zones.

## Loop Lab

Greybox (grid material, same 42 m road / 57 m wall-to-wall section as the test
circuits), 3.9 km, ~34 s flying lap with the default racer.

start → straight → **teardrop loop** (top radius 65 m, 180 m tall, steps 90 m right so the exit clears the entry by ~20 m of air) → straight → banked 180° → **barrel roll** (one full turn over 800 m) → banked 180° → closing straight with the grid → start

The loop and turns use **sin² curvature** (zero at entry and exit), so g-force
builds up instead of switching on. The builder solves the second turn and the
straights so the lap closes exactly (0.2 mm).

Rebuild after changing layout constants:

```
godot --headless --path . -s res://tools/loop_lab/build_loop_lab.gd
godot --headless --path . -s res://tools/loop_lab/check_loop_lab.gd
```

### Engine facts the builder relies on (measured)

- **Barrel rolls can't live on a closed Curve3D.** Tilts interpolate linearly, including across the closing segment, so the lap's net 360° of tilt would unwind as a second roll on the last segment. Loop Lab's curve is **open with the last point on top of the first**, and `path_joined = false`.
- **Tilts are solved, not authored.** The builder authors the road's desired up per point, then sets each tilt from Godot's own baked rotation-minimising up vectors. Max error 0.001° at control points, 0.04° between. The loop's helical twist comes out right without hand-tuning.
- **`path_simplify_angle` must be 0.** It merges collinear segments, and the roll is a straight line whose road *rotates*. At 1.0 (used on the other tracks) the roll would be simplified away.
- **The road surface is subdivided every 3 m across its width.** A twisting road is a ruled surface. One 39 m quad per ring splits into two triangles whose normals zigzag about 26° in pitch through the roll (measured), which the hover ray reads as a washboard. With 3 m strips the zigzag is about 2°. What's left (up to ~11° at 15 m off centre, mid-roll) is the road's true shape.
- The CSG road matches the curve's tilted frame to within 0.3° all the way through the roll.
- **Inverted road needs light from below.** On the loop top and mid-roll the driving surface faces the ground, so the sun can't reach it, and with a dark sky ground colour the first chase-cam stills were near black. Loop Lab has a shadowless upward `GroundFill` light and lighter sky ground tones. Dressed tracks with inversions will need the same thinking.

## Test results (headless autopilot, default racer)

Full throttle, zones at default (magnet 1):

| Zone | Grounded | Hover range | Speed | Ship vs road up | Camera framing |
|---|---|---|---|---|---|
| Loop | 100% | 1.44–2.76 | 104–120 | ≤ 6.9° | ship within 6.8° of view centre, distance steady |
| Barrel roll | 100% | 2.48–2.84 | 120 flat | ≤ 10.4° | within 5.7° |

Momentum mode on the loop only (`magnet 0` on "Loop"), steady speed:

| Speed | Result |
|---|---|
| full / 50 / 40 | Makes it. At 40 the hover height swells to 5.9 at the top as the ship goes light. |
| 34 | Peels off at the top, drops onto the lower part of the loop, carries on |
| 28 | Falls, respawns behind the loop, tries again |

This matches v²/r against gravity at the top: about 40 u/s needed at the 65 m top radius.

**Design note:** in momentum mode the **barrel roll is impossible at any speed.** A roll on a straight has no centripetal force, so with real gravity nothing holds you upside down. That's correct physics, not a bug. Rolls need some magnet; about 0.1 is enough with the default hover spring. Momentum mode makes sense for loops only.

**Roll rate:** a first version did the roll in 460 m (peak ~176°/s at full speed). It threw an off-centre ship into the wall: the road 15 m off centre pitched ~24° and the rotating frame pushed the ship outward. At 800 m with smoothstep (peak ~80°/s) it holds full speed with no wall contact. Rolls tighter than about 0.7°/m are worth testing by hand first.

### Regression

The harness is deterministic. Old (`main`) vs new controller, 1–2 autopilot laps each on Utopia, Swoopy, Hairpin Alley and The Drop: **bit-identical** lap times and respawn counts. Every changed line reduces to the old maths at zone weight 0, and the slerp fix below only takes its new path in the exact case where the engine's slerp fails.

### Slerp fix (camera and ship alignment)

`Vector3.slerp()` normalises `cross(a, b)` for its axis. On perfectly flat, dead-straight road (Loop Lab's grid and straights) the two vectors are parallel to float precision, the axis comes out non-unit, and `Basis` errors every frame ("axis must be normalized"). `ShipController.slerp_safe()` detects exactly that case with the same float32 maths and lerps instead. Never triggered on the existing tracks (they aren't perfectly flat), so they're unaffected.

## Running the harness

```
# full-speed lap(s) with per-zone stats
LL_LAPS=2 godot --headless --fixed-fps 60 --path . -s res://tools/dev/loop_lab_drive_boot.gd

# momentum-mode loop at a steady 40 u/s
LL_MAGNET=0 LL_MAGNET_ZONE=Loop LL_SPEED=40 LL_LAPS=1 godot --headless --fixed-fps 60 --path . -s res://tools/dev/loop_lab_drive_boot.gd

# any other track (zone-less tracks report everything as "open track")
LL_TRACK=test_circuit_6_live godot --headless --fixed-fps 60 --path . -s res://tools/dev/loop_lab_drive_boot.gd
```

Env: `LL_TRACK`, `LL_MAGNET`, `LL_MAGNET_ZONE`, `LL_SPEED`, `LL_LAT`, `LL_LAPS`, `LL_TRACE=1`, `LL_SHOTS`, `LL_SHOT_DIR`, `LL_OVERVIEW` (see the script header). It uses its own sim-time lap timer, because `RaceManager` times laps with the wall clock, which is meaningless under `--fixed-fps`.

## AI support

The AI measured everything that steers in world XZ (`.y = 0`, sign from `cross.y`). On a loop wall the XZ projection of "ahead" collapses, and over the top it reverses. **With the old code, all seven AI ships got stuck circling inside the loop for a whole 140 s race (0 laps).**

What changed. Each is inside magnetic zones only; outside them every expression reduces exactly to the old one (`v.slide(UP)` is `v` with y zeroed, `cross.dot(UP)` is `cross.y`):

- `TrackSplineHelper` finds the track's `MagneticTrack` and offers `zone_weight_at_offset()` and `steering_up_at_offset()` (world UP outside zones, the banked/rolled road up inside). Its fallback `get_curvature_at_offset()` counts only in-road turning inside zones.
- `AILineFollower`: `signed_line_curvature()` (the steering feedforward) and `_get_signed_curvature()` flatten onto the road plane. Over the loop top the XZ projection read as a 180° turn and slammed the feedforward to full lock.
- `AIControlDecider._calculate_steering()`: the heading error (to target, nose and slip-compensated velocity) is measured about the ship's track normal inside zones. Slip compensation uses `slerp_safe` (it hit the same parallel-vector error on Loop Lab's straights).
- `AIRacingLineBaker`: curvature inside zones is the in-road (geodesic) part only, since vertical curvature needs no steering. Zones are added to the cache key only when present, so zone-less tracks keep their hashes. Measured: this barely matters on Loop Lab (3D loop curvature 0.0135, which the speed model allows at ~117–120 u/s), but a 35 m loop would have been planned at ~60 u/s.
- The trainer needed nothing: it drives the real `ShipController`, so the zones just work. `train_ai_lines.gd --track=loop_lab` trains one track without touching the others' saved lines.

Results (8-ship `RaceMode` races, 140 s, `ai_race_probe`):

| Setup | Result |
|---|---|
| Trained line (33.08 s lap), default zones, two grid seeds | Every AI ship 3 laps, 0 respawns, never airborne in a zone, skills 0.50–0.72, avoidance on |
| Loop in momentum mode (magnet 0 on "Loop") | Same: 3 laps each, 0 respawns (AI carries well over 40 u/s over the top) |
| Old AI code, same race | 0 laps, all ships stuck circling the loop |

The trained line runs the loop and the roll at a flat 120 target.

**Regression:** seeded 8-ship races (75 s) on Utopia, Swoopy, Hairpin Alley and The Drop give **bit-identical** checksums of every ship's final transform and velocity, old AI code vs new. The probe seeds the global RNG because the player's grid slot and each AI's wobble phase use it; unseeded, identical code gives different races.

```
PROBE_TRACK=loop_lab PROBE_SECONDS=140 godot --headless --fixed-fps 60 --path . -s res://tools/dev/ai_race_probe_boot.gd
godot --headless --path . res://tools/train_ai_lines.tscn -- --track=loop_lab
```

Env: `PROBE_TRACK`, `PROBE_SECONDS`, `PROBE_SEED`, `PROBE_MAGNET`, `PROBE_MAGNET_ZONE`.

## Not done yet / next

- **AI edge cases not covered:** an AI that falls off (only possible with magnet < ~0.1 on a roll) respawns behind the zone and tries again, but nothing teaches it to carry more speed. The AI debug markers still offset by world Y.
- **Cinematic camera rig** places every shot relative to world up.
- **Things to feel by hand:** whether magnet 1 on the loop is too forgiving; `magnetic_follow_boost` (1.8 cuts the camera's pitch lag in the loop from ~33° to ~28°; 1.0 is the old camera); `slope_gravity_scale` on the loop (default loses ~16 u/s at full throttle).
