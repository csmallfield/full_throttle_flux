# Full Throttle Flux — v11: AI line trainer

Extract at the **repository root**. Four files replaced, two added.

```
full_throttle_flux/scripts/ai/ai_line_trainer.gd        NEW
full_throttle_flux/tools/train_ai_lines.gd              NEW
full_throttle_flux/tools/train_ai_lines.tscn            NEW
full_throttle_flux/scripts/ai/ai_racing_line_baker.gd   feasibility passes exposed, confidence 1.0
full_throttle_flux/scripts/ai/baked_racing_line.gd      bake version 4, trained metadata
full_throttle_flux/scripts/ai/ai_ship_controller.gd     prefers trained lines, track id fix
```

Requires v10 applied first. Bake version went to 4, so cached lines re-bake.

---

## Running it

```
godot --headless --path . res://tools/train_ai_lines.tscn
```

Optional: `-- --max-iterations=12 --time-scale=8`

Trains circuits 3, 5, 6 and 7 only, as requested. The track list is at the top of `tools/train_ai_lines.gd`. Roughly 3–4 minutes per track. Output goes to `res://resources/ai_data/<track>_<ship>_trained_line.tres`, and `AIShipController` picks it up automatically ahead of baking, with a bake-version check so a stale file is ignored rather than silently used.

**You need to run this yourself** — the trained lines are keyed to your exact `ShipProfile` values, so generating them against my working copy would hand you files that are wrong the moment you touch a handling parameter.

## Measured

Full run across all four circuits, `default_racer`, 12 iterations max:

| circuit | trained lap | mean target speed |
|---|---|---|
| 3 | 53.17s | 114.5 → 114.7 |
| 5 | 72.77s | 111.5 → 111.9 |
| 6 | 66.62s | 107.7 → 107.8 |
| 7 | **64.53s** (from 65.03) | 111.4 → 112.0 |

Circuit 7 is the one with a before/after baseline, since that's where I've been benchmarking: **0.5s, about 0.8%**. The other three are first measurements with no comparison point.

`cornering_confidence` is back to **1.0**. It was at 1.05 — openly compensating for the analytic model being wrong rather than describing anything real. The trainer replaces that one global number with a measurement per corner, which was the point of building it.

## How it works

Each iteration drives a full lap and records, per line sample, the worst **outward** tracking error and the speed actually achieved. Then it reduces target speed over the *approach* to samples where the ship ran wide (the cause of a wide exit is the entry speed, which is upstream), and raises it where the ship tracked cleanly. The edited profile is smoothed and pushed back through the baker's feasibility passes so it stays something the ship can brake into and accelerate out of.

Crucially it **hill-climbs on measured lap time**: a worse lap reverts to the best profile and retries with a smaller perturbation, and the best profile by lap time is what gets saved, never the last one. It cannot finish worse than it started.

Training runs at 8x by raising `Engine.time_scale` and `physics_ticks_per_second` together, which advances sim time faster while keeping per-step delta at its normal value. That is only valid because the v8 time normalisation made the handling tick-rate independent — before that, training at 8x would have produced a profile for a different game.

## Four things that were wrong first, in case you tune it

These are all fixed, but they're the failure modes to watch for if you change the update rule.

**It measured a partial lap.** Timing started wherever the ship was after warmup, reporting ~99% of a lap and flattering every result. It now arms at warmup, waits for the start/finish line, and times wrap to wrap.

**Reductions compounded.** A run of 20 wide samples each knocked 6% off 20 overlapping 60m windows, so one stretch could lose most of its target speed in a single iteration. It now builds a multiplier array and takes the worst case, applying each reduction once.

**The raise condition deadlocked.** Gating increases on "did the ship reach its current target" meant nothing ever qualified, because the analytic profile starts above what the ship can actually do. Every iteration got slower. Clean tracking alone now earns an increase.

**Isolated raises got flattened.** This is the one that unlocked the gain. Lifting a single sample does nothing — the feasibility passes pull it straight back, because you cannot brake into or accelerate out of a one-sample spike. Raises apply over a 30m window so whole corners move together. That was the difference between 64.97s and 64.53s.

The underlying lesson: "ran wide" does not reliably mean "went too fast" with this controller. Often it's tracking lag, and cutting speed there loses lap time without fixing anything. Hence lap time as the arbiter, and hence the trainer only blames speed for a wide sample when the ship actually reached ~95% of target there.

## A latent bug this turned up

Track ids were derived from the scene **root node name**, and those are not unique in this project:

- `test_circuit_3_live` and `test_circuit_4_live` are both rooted `TestCircuit3`
- `test_circuit_6_live` and `test_circuit_7_live` are both rooted `TestCircuit6`

I found it because the first full training run wrote circuits 6 and 7 to the same file and one silently overwrote the other. The bake cache has been living with this too — it survived only because its source hash includes the spline geometry, forcing a miss. A trained-line file has no such protection.

`AILineTrainer.track_id_for()` now derives the id from the scene file path, and `_guess_track_id()` uses it. Worth renaming those root nodes anyway, since anything else keyed on them has the same exposure.

## What I'd do next

The trainer is worth 0.8% on circuit 7. The minimum-curvature line in v10 was worth 2.3%. That ratio is the useful signal: **line geometry is where the remaining pace is, not the speed profile.**

The natural extension is to let the same hill-climb perturb lateral offsets as well as speeds. All the machinery is there — drive a lap, measure, perturb, revert if worse. Perturbing the line is strictly harder because a change at one sample moves curvature over a wide neighbourhood and the speed profile has to be recomputed each time, but it optimises the thing that actually matters.

Your recorded lap remains the best target and the best seed: 63.12s on circuit 7 with per-sample lateral offsets. Using it as the solver's initial guess instead of the corridor centre would sidestep the "recordings must be perfect" problem entirely — a seed only needs to be roughly right, not clean enough to blend into the control loop.
