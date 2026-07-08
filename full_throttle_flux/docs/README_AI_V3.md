# Full Throttle Flux — Competitive Spline AI (Phase 1 + 2)

Drop-in delivery. Verified with Godot 4.5-stable headless (Jolt physics)
at three levels:

1. **Compile**: every script type-checks with autoloads registered.
2. **Bake**: run end-to-end against the real `test_circuit_2` spline + wall
   collision geometry (2048 samples, ~550ms cold bake / ~10ms cached, 2.4%
   ray misses, zero corridor violations).
3. **Closed-loop driving**: a real `ShipController` (default profile) driven
   by the new AI stack around the real track collision geometry for 2 laps:

   | Metric | Baked line | Geometric fallback | Profile theoretical |
   |---|---|---|---|
   | Lap time | **151.7s** (151.9 / 151.5) | 152.4s | 144.3s |
   | Avg speed | 109 | 110 | 116 |
   | Wall scrapes | 4 per 2 laps | 1 per lap | — |
   | Respawns / stuck | 0 / 0 | 0 / 0 | — |

   The AI runs ~95% of the theoretical profile pace. The remaining scrapes
   are all one corner: the ~190m elevation drop near offset 0.91, where the
   ship goes airborne (zero grip in the air, velocity can't turn) and lands
   wide -- a physics reality, not a planning bug, and it reads as human.
   Note: this circuit is ~80% flat-out at these ship limits, which is why
   the fallback nearly matches the baked line here; the baked line's edge
   grows with corner density.

## Files

| File | Status | Path in project |
|---|---|---|
| `ship_performance_model.gd` | **NEW** | `res://scripts/ai/` |
| `baked_racing_line.gd` | **NEW** | `res://scripts/ai/` |
| `ai_racing_line_baker.gd` | **NEW** | `res://scripts/ai/` |
| `ai_line_follower.gd` | modified | `res://scripts/ai/` |
| `ai_control_decider.gd` | modified | `res://scripts/ai/` |
| `ai_ship_controller.gd` | modified | `res://scripts/ai/` |
| `track_spline_helper.gd` | modified (additive) | `res://scripts/ai/` |
| `race_mode.gd` | modified | `res://scripts/modes/` |

No scene changes required. No changes to ship physics, recorded-lap
recording/playback, avoidance, or position tracking.

## What was broken (recap) and what fixes it

1. **Brake output was discarded.** The ship has no brake input; dual
   airbrakes are the only real brake. The decider now merges its brake
   command into both airbrake channels. Your entire late-braking capability
   was previously unreachable.
2. **Speed targets ignored distance-to-corner** (AI lifted 120m early).
   Now: the baked speed profile encodes braking points by construction
   (backward pass); the geometric fallback uses
   `max_entry_speed(corner_speed, distance)` from the perf model.
3. **Airbrakes triggered from 120m-lookahead curvature** and dragged speed
   everywhere. Now they fire only as (a) commanded braking or (b) understeer
   recovery (steering saturated at speed). Note: in this physics, airbraking
   mid-corner *reduces* achievable path curvature (grip 4.0 → 0.5 caps how
   fast velocity can rotate). Full-grip full-lock is the fast way through a
   corner; airbrakes are for the braking zone before it.
4. **Track width was wrong (21m vs ~16.2m walls)** — apex targets were
   inside the walls. The baker now *measures* the corridor per sample with
   raycasts against layer-4 walls; the geometric fallback default is a
   conservative 12m.
5. **Hard difficulty capped skill at 0.80** and skill multiplied speed
   (0.70–1.0 governor). Hard is now 0.78–1.0; skill applies honest margins
   (earlier braking, slightly shallower line, control smoothing, low-skill
   steering wobble) — same ship limits at every level.
6. **Early apex** in the geometric fallback (cut began 70m out) — phase
   constants retuned toward a late apex. This path matters less now: the
   baked line replaces it as the default.

## New architecture

```
RaceMode.setup_race()
  └─ _bake_racing_line()  (once per race; disk-cached per track+ship hash)
       └─ AIRacingLineBaker.bake()
            1. sample spline (~6m spacing, 256–2048 samples)
            2. find REAL surface per sample (drop ray vs ground layer),
               measure corridor via lateral rays vs wall layer 4
            3. elastic-band relaxation → minimum-curvature line in corridor
            4. true curvature of optimized line
            5. speed profile: corner limits (from ShipPerformanceModel)
               → backward braking pass → forward acceleration pass
  └─ ai_controller.initialize(track, track_ai_data, baked_racing_line)

AILineFollower target priority: recorded laps > baked line > geometric.
(Flip recorded/baked with `prefer_baked_over_recorded`.)
```

The baked output has the same shape as your recorded-lap data
(per-offset lateral + speed), so recorded laps are now optional garnish
rather than a requirement — exactly the labor problem you wanted gone.
`ShipPerformanceModel` derives every limit from the profile + the actual
`ship_controller.gd` code: corner speed
`v = steer_speed / (κ + 0.3·steer_speed/max_speed)` (from `_apply_steering`),
braking `Δv/m = (1−m)/dt` (from `_apply_airbrakes` + drag), acceleration by
integrating `_apply_thrust`. No invented constants; one confidence margin.

## Findings you should know about (not fixed here — your call)

- **No max-speed clamp exists in `ship_controller.gd`.** True top speed is
  the thrust/drag equilibrium: **~134** with default profile values, above
  `max_speed` (120). The player holding W reaches it. The AI currently
  *respects* `max_speed` (`respect_profile_max_speed = true` in the baker
  and follower) so it won't surprise you — but that means a player can
  out-top-speed the AI by ~12%. Either add a clamp to the ship, or set
  those flags false. Recommend the clamp.
- **Your track geometry is rotated ~1° relative to the racing spline.**
  The `groundGeo`/`wall*Geo` CSG nodes carry a `Transform3D` with a
  0.0181 rad X-rotation; with `path_local = false` that transform applies
  on top of the path extrusion, displacing the physical track up to ~30m
  vertically (and a few meters laterally) from the spline at |z| ≈ 1700.
  Hovering/steering hide it, but it skews anything spline-referenced
  (position tracker, recorded laterals, my first raycast attempt). The
  baker now self-corrects by locating the real surface first, but you
  should zero those CSG transforms — it looks accidental.
- **`Curve3D.sample_baked_up_vector` does not apply tilt by default**, so
  your existing lateral-offset math runs in an unbanked frame while the
  track (CSG `PATH_FOLLOW`) is banked up to ~80°. I added an optional
  `apply_tilt` parameter to `TrackSplineHelper` (default `false` = exact
  legacy behavior, so recorded-lap playback is untouched). The baked-line
  path uses `true`. Long-term, consider migrating the recorder to the
  tilted frame too (re-record after switching — frames must match).

## Multi-track tuning (v3.1)

Defaults were swept and validated in closed-loop simulation across FOUR
tracks (test_circuit_2, 3, 5, 6 -- circuit 4 excluded, see below). Final
defaults: `cornering_confidence 0.98`, `planned_brake_application 0.7`,
`line_margin 1.5`, `sample_spacing_target 3.0` (max_samples 4096).

| Track | Old defaults | New defaults | Theoretical | Scrapes |
|---|---|---|---|---|
| c2 (16.8km, flat-out) | 153.0s | 152.1s | 144.8s | 0 |
| c3 (6.0km) | 64.8s | 63.6s | 61.2s | 0 |
| c5 (8.3km, banked) | 91.0s | 87.2s | 85.1s | 0 |
| c6 (7.0km, twisty) | 80.6s | 78.0s | 77.4s | 0 |

Findings from the sweep:
- The controller tracks the plan at 100-105% everywhere, so pace lives in
  the PLAN knobs (confidence, margins), not the controller.
- **Higher sample density alone made laps SLOWER** (sharper curvature peaks
  produce a faster plan that tracks worse); it only helps combined with the
  confidence/margin changes. Both are now default.
- **The missing max-speed clamp is worth ~8s/lap on flat-out tracks**: with
  `respect_profile_max_speed = false` the AI laps c2 in 143.9s (vs 152.1
  capped), at the cost of ~1 scrape/lap. A player holding W reaches ~134
  today, so the current player-vs-AI state (player 134, AI 120) is the one
  indefensible configuration: either clamp the ship at max_speed, or uncap
  the AI. Recommend the clamp.
- **test_circuit_4 is structurally unsupported**: its MainSpline is a 1km
  4-point stub; the drivable circuit appears to be the second Path3D node.
  Everything spline-based (AI, position tracking, respawn) binds to
  MainSpline -- move the real circuit's curve into MainSpline (one spline
  per track) and the AI will handle it like the others.

## Tuning guide

- `AIRacingLineBaker.cornering_confidence` (0.98): the single most
  important knob. 1.0 = theoretical steering limit (validated clean on all
  four test tracks); lower it first if a new track or ship profile washes
  wide. Watch corner exits with debug draw on.
- `AIRacingLineBaker.planned_brake_application` (0.5): higher = later,
  shorter braking zones. The controller has smoothing lag, so leave headroom
  below the decider's max (1.0) or the AI can't track its own plan.
- `AIRacingLineBaker.line_margin` (2.5m): corridor shrink so the optimized
  line stays a tracking-error's distance off the walls. In simulation this
  was the difference between 36 wall scrapes and 4 -- and it made laps
  FASTER (161s -> 152s), because scrape-stalls cost far more than the
  slightly tighter line. Lower it only with data.
- `AIRacingLineBaker.ship_clearance` (4.0m): wall margin. Lower for more
  aggressive lines; expect scrapes below ~3.
- Follower skill margins: `skill_speed_margin_min` (0.85),
  `anticipation_time_novice/expert` (0.8/0.3s -- converted to meters by
  current speed) shape the difficulty spread.
- `AILineFollower.crosstrack_gain` (0.8): cancels pure-pursuit corner
  cutting. `baked_steer_lookahead_min/max` (18/42m): pursuit lookahead in
  baked mode -- longer values cut inside the line and point at inside walls.
- Decider feel: `coast_band`, `brake_response_range`, `smoothing_rate_*`,
  `steer_wobble_amplitude_max`.
- Bake cache lives in `user://baked_lines/` — it invalidates automatically
  when the spline, profile, or baker config changes (content hash). Delete
  the folder to force rebakes.

## Validation checklist for your first run

1. Race mode, Hard, test_circuit_2. Console should show
   `AIRacingLineBaker: baked N samples in ~500ms` then per-AI
   `data: baked line (N samples)`.
2. Enable `debug_draw_enabled` on one AI: green preview should hug
   outside-apex-outside lines and stay off the walls.
3. Watch braking: AI should hold full speed deep into corner approach,
   brake hard and late (dual airbrakes flare), corner at full grip, drive
   out. If it brakes comically late and overshoots: lower
   `planned_brake_application` or `cornering_confidence`.
4. Wall contact should now be rare. If a specific corner still clips,
   check its measured width in the baked resource (half_widths arrays).
5. Second run of the same track+ship should log `cache hit` (~10ms).

## Phase 3 hooks (variation, when you're ready)

The single target-line interface makes pilot personalities cheap:
per-pilot perturbation of `cornering_confidence` and brake application
(risk profile), a low-frequency lateral offset field added to the baked
laterals (line personality), per-pilot `anticipation_window` (smoothness),
wobble amplitude/frequency (precision), and avoidance aggression (already
per-skill). Boost pads are the other obvious win: bend the baked line
through pads on straights and let the profile's forward pass carry the
extra speed — the sample format already tolerates speeds above the corner
limits.
