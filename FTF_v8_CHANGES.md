# Full Throttle Flux — v8 handling & camera rework

Extract at the **repository root** (the folder containing `full_throttle_flux/`). Eight files are replaced; nothing is added or deleted.

```
full_throttle_flux/scripts/ag_camera_2097.gd            (full rewrite)
full_throttle_flux/scripts/ships/ship_controller.gd
full_throttle_flux/scripts/resources/ship_profile.gd
full_throttle_flux/scripts/ai/ship_performance_model.gd
full_throttle_flux/scripts/ai/ai_racing_line_baker.gd   (hash inputs only)
full_throttle_flux/scripts/ai/baked_racing_line.gd      (bake version 2 → 3)
full_throttle_flux/resources/ships/fast_racer.tres
full_throttle_flux/resources/ships/hidden/speed_demon.tres
```

`default_racer.tres` is untouched — it overrode no drag values, so it inherits the new defaults.

**Baked AI lines will re-bake on first run.** `CURRENT_BAKE_VERSION` went to 3 and the source hash now includes the new handling fields, so `user://baked_lines/` invalidates itself. The committed `resources/ai_data/*.tres` recordings are unaffected, but AI pace will differ — see "What to watch" below.

---

## Measured before / after

All figures from a headless harness driving `default_racer` at full throttle with a 1.1 s full-airbrake + 0.6 steer corner input, 60 Hz physics.

| | v1 | v8 |
|---|---|---|
| Terminal speed (declared max 120) | 134.2 | 120.0 |
| `speed_ratio` peak | 1.119 | 1.000 |
| Speed at corner exit | 52–88 | 97–112 |
| Speed lost per corner | 34% | 11% |
| Yaw rate in corner | 46–47 °/s | 69–72 °/s |
| Slip angle peak | 22° | 19.4° |
| Slip 1.3 s after release | 7.3° | 0.0° |
| Visual roll peak | 71–80° | 28–30° |
| FOV range | 81–116° | 78–86° |
| Camera distance, 30 → 134 u/s | 6.9 → 6.2 | 6.6 → 9.4 |
| Terminal speed at 120 Hz physics | 65.7 | 120.0 |

That last row is the one I'd treat as the real win: the game is no longer welded to a 60 Hz tick.

---

## 1. Time normalisation

Every decay coefficient is now **per second**, not per physics frame. `pow(retain, delta)` for retention, `1 - exp(-rate * delta)` for smoothing weights. Affects drag, air drag, airbrake drag, grip, scrub, track-normal smoothing, track alignment, roll, shake, and every camera rate.

Profile values converted as `per_second = per_frame ^ 60`:

| field | old (per frame) | new (per second) |
|---|---|---|
| `drag_coefficient` | 0.992 | 0.617 |
| `air_drag` | 0.97 | 0.161 |
| `airbrake_drag` | 0.98 | 0.298 → retuned to 0.90 |
| dual-airbrake | 0.85 | 0.000055 → new field at 0.30 |

`ShipController._migrate_rate()` detects a legacy per-frame value (anything in 0.95–1.0), converts it, and pushes a warning naming the field and the ship. Old `.tres` files keep working. `track_normal_smoothing` warns but does not auto-convert, since 0.15 is a legitimate per-second rate — set it to ~9.0.

Note the old dual-airbrake value: 0.85 per frame is 0.000055 per second, i.e. a dead stop in about a fifth of a second. The new `dual_airbrake_drag` default of 0.30 is a strong but survivable emergency brake.

## 2. `max_speed` is authoritative

New `_apply_speed_limit()` clamps to `max_speed`, with decaying headroom for boost (`overspeed_damping`, default 2.5/s). `get_speed_ratio()` now clamps to 0–1; `get_speed_ratio_raw()` and `get_boost_overspeed()` are there if you want to detect overspeed.

This matters beyond the camera: `speed_ratio` feeds FOV, roll scaling, the rumble threshold, the HUD and AI planning, and all of them were running 12% hot. `ship_performance_model.gd` already documented the 134-vs-120 gap; it now models the limiter instead of working around it.

`fast_racer.tres` had `max_speed = 600` against a real equilibrium of ~186 — unreachable, so `speed_ratio` never passed 0.31 and that ship had almost no FOV or roll response at all. Set to 142 so it is genuinely a step above default.

## 3. Airbrake rebalance

Split into two independent mechanisms:

- **`grip`** rotates the velocity vector toward the ship's facing at a true rad/s rate, preserving magnitude. Now a real rotation, not a vector lerp, so the AI model's `v ≤ grip / κ` bound is exact rather than approximate.
- **`lateral_scrub` / `airbrake_lateral_scrub`** destroy lateral velocity outright. This is the speed cost of sliding, and it scales as `sin²(slip)` — a clean committed turn is cheap, a big slide is expensive.

Longitudinal airbrake drag dropped from 0.298/s to 0.90/s. Airbrake yaw authority went 0.5 → 1.0 rad/s and now scales *up* with speed (`0.55 → 1.0`), inverting v1's behaviour where the airbrake was weakest exactly where it should dominate.

`_apply_grip()` is now called every physics frame. In v1 it lived at the end of `_apply_steering()`, which early-returned on zero stick, so an airbrake-only turn never redirected velocity — that is the 7.3°-of-residual-slip row in the table.

## 4. Camera

The whole reason v1 couldn't be tuned: `follow_speed` was simultaneously setting resting distance, speed pullback, how far the ship could rotate in frame, and shake recovery, because all four came out of one world-space lerp lag.

- **Position** uses velocity feedforward (`_cam_position += ship.velocity * delta` before converging), which removes the speed-proportional lag entirely. `base_distance` and `speed_distance` now mean what they say.
- **Orientation** is a separate camera-owned forward/up pair. `yaw_follow_rate` is the single dynamism knob — lower it for more ship rotation inside the frame and more whip on the catch-up. Start at 7.0, try 5.5 if you want it looser.
- **`up_follow_rate`** makes the horizon roll with the track normal. v1 passed `Vector3.UP` to `looking_at`, which discarded all bank and would have flipped outright past vertical.
- **Aim** blends between the nose and the velocity vector (`look_velocity_blend`, default 0.45). v1 was effectively 1.0, which is why rotation-in-frame exactly equalled slip angle and the camera could never lead a corner.
- **Bank** picks up a fraction of ship roll plus yaw rate, capped at 14°.
- **Swing** raised from 0.45 to 1.6 (v1 shipped a fifth of its own documented recommendation) and is driven by `measured_yaw_rate` rather than `rotation.y`, which was an Euler angle of a basis rebuilt from the surface normal each frame and jumped on banked geometry.
- **Shake** no longer feeds back into the follow position.
- Runs in `_process`, not `_physics_process`.

## 5. Visual rotation

Bank is a second-order spring driven by **measured yaw rate and slip angle**, not button state. `roll_damping_ratio` at 0.62 gives the overshoot-and-settle that a first-order lerp cannot produce — you can see it in the telemetry as roll crossing slightly past zero on corner exit.

v1's additive `steer * 45° + airbrake * 75°` asked for 120° of bank and delivered 71–80°. Capped at `roll_max_angle`, default 32°.

New `visual_yaw_from_slip` yaws the mesh further into the slide (default 0.40 of slip, capped 9°) so the nose visibly points into the corner.

## 6. FOV

`base_fov 74 + speed_fov 10 * ratio`, plus an acceleration term and a boost kick, all smoothed and hard-clamped to 55–105.

v1 ran 116° on straights and 81° mid-corner — a 35° lens breathing in and out of every corner, zooming *in* when you turned. Two causes: `speed_ratio` exceeding 1.0, and Godot's `lerp()` not clamping, so `max_fov = 110` was never enforced. `ShipController.apply_boost()` now calls `apply_fov_kick()` so the widening is an event rather than a constant ramp.

---

## What to watch when you test

1. **AI pace.** The performance model now includes airbrake yaw authority in corner-speed planning, so the AI will carry more speed through corners. If it starts running wide, drop `cornering_confidence` from 0.98 toward 0.90 before touching anything else.
2. **Airbrake turn rate.** 1.0 rad/s is double v1. Corner radius is `v / ω`, and since corner speed roughly doubled too, the actual radius is close to v1's — but it will feel much more immediate. If it's twitchy, `airbrake_turn_rate` is the first dial.
3. **Grip stayed at 4.0.** It's your core handling stat and it feeds the AI corner model, so I left it alone. If exits feel too snappy, 3.0–3.5 will give a longer settle. Re-bake after changing it.
4. **`yaw_follow_rate` vs `look_velocity_blend`** interact. If the ship feels like it's sliding out of frame, raise the first; if the camera feels like it's ignoring the slide, raise the second.
5. **Physics interpolation.** Now that the physics is tick-independent you can raise the tick rate, or enable `physics/common/physics_interpolation` in project settings for smooth 120/144 Hz rendering. I left both alone rather than change engine settings under you.

Post-processing (radial blur, speed lines) is still not in — that was deliberately deferred, and it'll land better on this base.
