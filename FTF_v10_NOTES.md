# Full Throttle Flux — v10: minimum-curvature racing line, slip compensation, race-start camera

Extract at the **repository root**. Four files replaced, nothing added or deleted.

```
full_throttle_flux/scripts/ai/ai_racing_line_baker.gd   (min-curvature solver)
full_throttle_flux/scripts/ai/ai_control_decider.gd     (slip compensation)
full_throttle_flux/scripts/ag_camera_2097.gd            (cinematic intro)
full_throttle_flux/scripts/ships/ship_controller.gd     (hover settle on spawn)
```

**Requires v9 applied first** — the decider and baker build on it.

Baked lines re-bake automatically; the solver settings are in the source hash. First bake is ~10s (was ~0.5s) because the curvature solve runs a stride cascade. That's bake-time only, not runtime.

---

## Results — circuit 7, default_racer, skill 1.0, AI only

| | v8 | v9 | **v10** |
|---|---|---|---|
| Lap time | 71.0s | 66.17s | **64.62s** |
| Mean speed | 97.7 | 102.0 | 105.6 |
| Mean line error | — | 1.33 m | 1.21 m |
| Max line error (after start) | — | 10.45 m | 8.87 m |
| Airbrake use | ~0% | 20% | 19% |
| Recovery events | — | 0 | 0 |
| **vs your recorded lap (63.12s)** | +12.5% | +4.8% | **+2.4%** |

Still no physics advantage: the AI writes the same five input fields your `_read_input()` writes, and every limit derives from the same `ShipProfile`.

---

## 1. The racing line — and the wrong turn I took first

You were right that the line hugs the middle. I confirmed it against your recorded lap: the baked line used a mean of **32% of the available corridor half-width**, pinned to an edge on 7.6% of samples, while your lap reached 24.8m of lateral against the bake's 18.5m and went deeper on **54% of samples**. You also did it on **5% airbrake against the AI's 20%** — the AI was buying rotation to compensate for a worse line and paying for it in scrub.

I found the mechanism: the relaxation is Laplacian diffusion, so after 800 iterations at alpha 0.35 information had travelled ~24 samples — roughly 71m of a 7100m track — and `convergence_epsilon` stopped it earlier still. It could not see past the corner it was in, which is precisely your "multiple turns in advance" observation.

**Then I fixed it the wrong way and it got slower.** A multigrid cascade converged the elastic band properly: corridor utilisation went 32% → 81%, it hugged the inside exactly as intended, and the lap went **66.17s → 69.2s**. Tracking error actually *improved*, so the AI drove the new line better. The line itself was worse.

The reason is the objective. Pulling each sample toward the midpoint of its neighbours is the gradient of `sum |p[i+1] - p[i]|^2` — that is **tension**, so the elastic band minimises **path length**, not curvature. Converged against the corridor clamp it degenerates into the shortest loop: pinned inside-to-inside, paying for tight apexes with sharp transitions. v9's line was fast *by accident* — under-converged, and the leftover bias toward centre happened to sit closer to a good line than the converged answer.

`_minimize_curvature()` replaces it with projected gradient descent on the bending energy `sum |p[i-1] - 2p[i] + p[i+1]|^2`, subject to the corridor, through the same stride cascade (bending energy relaxes as n^4, so the cascade is not optional). This objective will accept a **longer** path to reduce peak curvature, which is the trade a racing line actually makes.

| | v9 band | band converged | min-curvature |
|---|---|---|---|
| mean kappa | 0.00472 | 0.00456 | **0.00449** |
| p95 kappa | 0.0153 | 0.0214 | 0.0184 |
| max kappa | 0.0764 | 0.0762 | **0.0721** |
| planned profile speed | 110.5 | 108.7 | **111.2** |
| corridor utilisation | 32% | 81% | 67% |
| your lap goes deeper | 54% | 16% | 34% |

It lands between the timid line and the over-committed one, which is what the theory predicts, and beats both on every curvature measure.

Things I tested and rejected, so you don't repeat them:

- **Iterations beyond 600 per level do nothing.** Identical output at 600, 2000, 6000 and 15000. `convergence_epsilon` was the binding constraint, so I lowered it to 0.0002 — worth 0.1s of planned lap and a better max kappa (0.0746 → 0.0721).
- **A wider corridor makes it worse.** Cutting `ship_clearance` 4.0 → 2.5 → 1.5 raised max kappa from 0.0746 to 0.0888 to 0.1005. The extra width lets the line reach into regions where the surface probe is noisy, and the solver chases that noise. Left at 4.0 / 1.5.

The old elastic band is still there behind `use_min_curvature = false` if you want to A/B it.

## 2. Slip compensation

`_calculate_steering()` measured the error between the **hull heading** and the target. The ship travels along its velocity vector, and since v9 made the AI genuinely slide (19% airbrake), every degree of slip was an uncorrected path error — structural, not occasional. It now measures from the velocity vector, so the controller steers the **path** rather than the nose. Worth 65.77 → 65.25s.

Guarded two ways: it only engages above `slip_compensation_min_speed` (12 u/s), and only while the velocity still broadly agrees with where the ship points (`dot > 0.3`), so a spin can't feed back into the steering. Set `slip_compensation = 0.0` for v9 behaviour.

## 3. Cornering confidence 0.98 → 1.05

This started as a diagnostic. The AI was running 6.7 u/s below its own planned profile, and I wanted to know whether it was plan-limited or execution-limited. Raising the plan gained 0.6s, so it is **still plan-limited** — there is more available.

Be aware what this is: planned corner speeds now deliberately exceed what the analytic model says is achievable. It works here because the model is conservative, but it is a global fudge compensating for a modelling gap, and it will behave differently on a tighter track. If you see the AI running wide on a circuit with slower corners, this is the first thing to drop back toward 1.0.

## 4. Race-start camera nod

Fixed at the source rather than hidden. `ShipController.settle_on_surface()` snaps the ship to hover equilibrium on spawn (deferred, since the race mode positions it after `_ready()`), and is also called on respawn.

| | before | after |
|---|---|---|
| Hover ray distance | 1.59 → 3.39 → 2.41 → 2.78 (ringing) | 2.751, flat from frame 2 |
| Peak vertical velocity | +12.7 u/s | 0.000 |
| Camera pitch | −8.9° → −23.4° → −5.0° → −21.3° | smooth −48° → −4.54° over 2.6s |

The camera then plays a cinematic entry from high and off-axis, easing in over `intro_duration` (2.6s) with an ease-out cubic so it is settled before lights-out. It runs once on first acquisition; `reset_to_ship()` after a respawn deliberately skips it. Call `begin_intro(duration)` from your countdown if you'd rather drive it explicitly, and `is_intro_playing()` if anything needs to know.

Also fixed: `_snap_to_ship()` used to omit the `ship_up * aim_height` term that `_update_aim()` applies every frame, so frame one began with a 1-unit aim mismatch the spring had to chase out.

---

## What's left, and what I'd do

The gap to your recorded lap is 2.4% and the AI is **still plan-limited**, not execution-limited — that's the measurement that matters for deciding what's next.

That points at the trainer rather than more controller work. Measure the real per-corner limit by running the actual `ShipController` against the line headlessly and iterating the speed profile where it consistently runs wide or leaves margin, instead of applying a global `cornering_confidence` fudge that has to be right for every corner on every track at once. The benchmark harness I've been using through all of this is most of the machinery already.

Your recorded lap is the natural validation target — 63.12s with per-sample lateral offsets to compare against. It's also a much better initial guess for the solver than the corridor centre, and seeding from it sidesteps the "recordings must be perfect" problem you raised: it only needs to be roughly right to start from, not clean enough to blend into the control loop.

Two smaller things I noticed but did not chase: the AI's steady-state max line error is 8.87m against a corridor clearance of 5.5m, so it still occasionally sits outside the corridor its line was planned for; and `planned_brake_application` at 0.7 has not been re-validated since v8 weakened the airbrake's longitudinal drag from 0.298/s to 0.90/s, so braking distances may be mismodelled in one direction or the other.
