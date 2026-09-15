# Full Throttle Flux — v9 AI: airbrake cornering, feedforward, recovery

Extract at the **repository root**. Five files replaced, nothing added or deleted.

```
full_throttle_flux/scripts/ai/ai_control_decider.gd       (substantial rework)
full_throttle_flux/scripts/ai/ai_line_follower.gd         (signed curvature added)
full_throttle_flux/scripts/ai/ship_performance_model.gd   (yaw model reworked)
full_throttle_flux/scripts/ai/ai_racing_line_baker.gd     (corner airbrake config + hash)
full_throttle_flux/scripts/ai/ai_ship_controller.gd       (one line: pass perf model)
```

Baked lines re-bake automatically — `corner_airbrake_application` is now in the source hash.

---

## Measured

Circuit 7 (7100m), one AI ship, `default_racer`, skill 1.0, headless, 160s run.

| | v8 | v9 |
|---|---|---|
| Lap time | ~71.0s | **66.17s** |
| Mean speed | 97.7 | 102.0 |
| Straight-line speed | 117.3 | 120.0 |
| Airbrake use across a lap | ~0% | 20% |
| Stuck/recovery events | n/a | 0 |
| Mean line error | — | 1.35 m |
| Max line error | — | 10.45 m |

**6.8% faster.** Consecutive laps: 67.0, 66.17 — it's still improving as tyres… as the profile settles, which is just the first lap starting from a standing start.

The AI still writes only the same five input fields the player's `_read_input()` writes, and still derives every limit from the same `ShipProfile`. No physics advantage.

## What changed

**1. Airbrakes are now a cornering tool.** The decider computes the yaw rate the baked line requires (`kappa * v`), spends up to 80% of available steering yaw on it, and buys the shortfall from the inside airbrake up to `max_corner_airbrake` (0.9). This is the single biggest change: v8 used the airbrakes for `0.00/0.00` across an entire lap and cornered at 28–48 u/s with steering pinned at full lock, because the decider's own header still said *"airbrakes are for braking, not for turning"* — true in v7, wrong since v8 raised `airbrake_turn_rate` to 1.0 with speed-scaling authority.

**2. Steering feedforward.** `_calculate_steering()` now adds `required_yaw / available_yaw` as a feedforward term, with the pure-pursuit P gain dropped 10.5 → 6.5. A pure-P law has to accumulate heading error before it turns, which loses corner entry every single time.

**3. Throttle asymptote fixed.** The old law `floor + error * 0.1` reached equilibrium where thrust balanced drag *below* target — measured 117.3 u/s at throttle 0.87 against a target of 120, forever. Now it's a continuous law: full throttle under target, lifting linearly across the coast band, braking beyond it.

**4. Plan and execution reconciled.** `corner_speed()` now solves `v * kappa = steer_yaw(v) + airbrake_yaw(v, app)` in closed form, with `app` matching what the decider actually commands. In v8 I put a `brake_yaw` term in the model that the controller never delivered, so the line promised curvature the AI couldn't execute — it entered hot, ran wide, saturated steering and slammed the brakes. That's fixed, and the constant now lives in one place with a comment on both sides saying they must match.

**5. Stuck recovery.** Detects low speed under throttle, then rotates toward the line with full inside airbrake at reduced throttle (this ship has no reverse thrust — `_apply_thrust` returns early on `throttle_input <= 0`). Zero recoveries triggered on circuit 7, so it costs nothing when not needed.

---

## Where this leaves us, honestly

Phase 1 is done and it's worth 6.8%. That is real but it is **not yet "hard to beat"**, and the reason is worth reading before you decide what's next.

I expected yaw authority to be the binding constraint. It isn't any more — I tested that directly. Raising `max_corner_airbrake` from 0.6 to 0.9 (which raises planned corner speeds 15–20%) bought only 1.2% of lap time, and **left the tracking error completely unchanged at 1.35 m mean / 10.45 m max**. The AI now has enough rotational authority and a plan it can execute; what it lacks is the precision to actually drive the line it's been given.

A 10.45 m maximum excursion is the number that matters. The baker builds in 5.5 m of clearance per side (`ship_clearance 4.0 + line_margin 1.5`), so a 10 m error means the AI is occasionally outside the corridor the line was planned for. Every corner where that happens forces a big correction and costs far more than the corner speed limit does.

So the next work is tracking accuracy, not pace:

- **Lookahead tuning.** Pure pursuit with a speed-scaled lookahead inherently cuts corners. `crosstrack_gain` exists to fight that but is doing it after the fact. Worth measuring lookahead against tracking error directly rather than tuning by eye.
- **Slip compensation.** The steering law aims the *hull* at the target. Now that the AI slides (20% airbrake use), the hull heading and the velocity vector diverge, and nothing accounts for it. Feeding `ship.slip_angle` into the aim is likely a large, cheap win.
- **The trainer.** This is still the right answer for the last chunk. The harness I've been benchmarking with is most of it: it already runs the real `ShipController` against a baked line headlessly and records per-sample speed and lateral error. Turning it into a closed loop — lower the profile where the ship consistently runs wide, raise it where it tracks clean with margin, iterate to convergence — makes the line achievable by construction instead of analytically predicted. I'd want to do the two tracking fixes above first, because the trainer will otherwise spend its iterations compensating for a controller flaw rather than finding real pace.

My recommendation: take this patch, drive against it, and tell me whether the AI *feels* closer. Then let me do slip compensation and lookahead tuning as a focused pass — I think those are worth more than the trainer and they're a fraction of the work. The trainer after that.

I have not touched the camera intro or the hover settle in this patch, since you asked to focus entirely on the AI.
