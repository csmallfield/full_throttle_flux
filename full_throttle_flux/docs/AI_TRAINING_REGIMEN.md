# AI Training Regimen

How to produce a fast, well-behaved AI opponent for a given **ship** on a given **track**, and what to check at each stage.

Everything here runs headless and offline. Nothing in this pipeline runs at game time — the output is a `BakedRacingLine` resource that ships with the game.

---

## The short version

```
godot --headless --path . res://tools/style_search.tscn     # ~6 min per ship per track
godot --headless --path . res://tools/train_ai_lines.tscn   # ~4 min per ship per track
```

Style search first, trainer second. The trainer seeds from whatever the style search saved, so running them the other way round throws work away.

Output lands in `res://resources/ai_data/<track_id>_<ship_id>_trained_line.tres` and `AIShipController` picks it up automatically.

---

## What the pipeline actually is

Five stages, each one feeding the next. They were built in this order and the order matters.

### 1. Bake — the racing line

`AIRacingLineBaker` samples the track spline, measures the drivable corridor by raycasting the walls, then solves for a **minimum-curvature** line inside that corridor.

Minimum curvature, not minimum length. This distinction is the single biggest source of AI pace in the whole system. The old elastic-band relaxation minimised path *length*, which converges to a line pinned inside-to-inside with sharp transitions. Measured on circuit 7, converging that solver made the AI **slower** (66.17s → 69.2s) even though it hugged the apexes exactly as intended. The minimum-curvature solver accepts a longer path to reduce peak curvature, which is what corner speed actually scales with.

The solver is a projected gradient descent on bending energy, run through a stride cascade (coarse to fine) because bending energy relaxes as n⁴ without one.

### 2. Speed profile — the analytic first guess

`ShipPerformanceModel.corner_speed()` solves `v * kappa = yaw_rate(v)` in closed form for every sample, then two feasibility passes make the profile reachable: you must be able to brake into every sample and you cannot exceed what full throttle delivers out of the previous one.

This is only a starting point. It ignores scrub while sliding, the controller's own tracking error, and hover transitions.

### 3. Style search — which technique, where

`tools/style_search.tscn`. Drives a menu of **styles** (different lookahead, airbrake commitment, brake aggression, steering gain, cornering confidence) around the track, times each one per track segment, and assembles the winners into one strategy.

Segment boundaries are placed where **speed variance across styles is lowest**, not at hand-labelled features. Segment times do not simply add up — the fastest way through a corner depends on the entry speed — so cutting where every style agrees on speed minimises the splice error.

Assembly is **anchored**: it starts from the best single style (a lap actually driven end to end, so zero splice risk) and only swaps a segment when another style beats it there by more than `MIN_SEGMENT_GAIN`. Unanchored splicing was measured at 52.03s against 51.45s for simply running the best single style. Every boundary is a chance for a style to inherit an entry speed it has never driven, so each swap must pay for that risk.

The tool refuses to save an assembly that fails to beat the best single style. A bad splice cannot ship.

### 4. Trainer — measured corner speeds

`tools/train_ai_lines.tscn`. Drives laps and adjusts the speed profile where the ship runs wide or leaves margin, hill-climbing on **measured lap time** with revert. It cannot finish worse than it started.

Seeds from an existing trained line if one is present, so run it after the style search.

### 5. Verify

Watch it. See "Watch mode" below.

---

## Adding a new ship

1. Create the `.tres` under `resources/ships/`. Set `ship_id` — it keys the output filename.
2. Add its path to `SHIP_PROFILES` at the top of `tools/style_search.gd` and `tools/train_ai_lines.gd`.
3. Run style search, then trainer.
4. Check the reported lap times against other ships in the same class.

**Check the profile is coherent before training.** `max_speed` is authoritative (a soft limiter enforces it), so `thrust_power` now governs how quickly the ship reaches top speed rather than what top speed is. A profile whose thrust can never reach its `max_speed` will train fine and feel wrong — `fast_racer` originally declared `max_speed = 600` against a real equilibrium of ~186, so its `speed_ratio` never passed 0.31 and it had almost no FOV or roll response at all.

Also note all retention coefficients are **per second**, not per frame. `ShipController._migrate_rate()` converts legacy per-frame values and warns, but a new profile should be authored in per-second units.

## Adding a new track

1. Add the scene path to `TRACKS` in both tools.
2. **Check the root node name is unique.** Track ids derive from the scene *file* name now, but several existing tracks share a root node name (`test_circuit_3_live` and `test_circuit_4_live` are both rooted `TestCircuit3`; 6 and 7 are both `TestCircuit6`). Anything else keyed on node names has the same exposure.
3. Watch the bake output for the corridor ray-miss ratio. A high miss ratio means walls are not on collision layer 4, or the track's drivable geometry is not all described by the spline the AI follows. `test_circuit_4_live` has two separate `Path3D` nodes and only one is visible to the AI: 74% of wall rays missed, the corridor fell back to a flat 12m, curvature came out near zero, and the speed profile was a flat 120 across the whole track. The AI drove into a wall at full speed and ground along it for 35 seconds.

## When to retrain

Retrain after **any** change to:

- `ShipProfile` handling values (grip, drag, thrust, max_speed, airbrake behaviour)
- the racing line solver or its parameters
- `AIControlDecider` gains or logic
- track geometry or the spline

Bake caches invalidate themselves via a source hash that covers the profile and spline, and `bake_version` guards the trained-line format.

Trained lines store the ship's **handling hash** (`ShipProfile.handling_hash()`) from v17 on. If you change a handling value, the AI still loads the line but reports it as `TRAINED (STALE: handling changed since training)` in the console and the spectator overlay. Re-run the style search to clear it. Lines made before v17 have no hash and report as `unverified` until re-run.

---

## Watch mode

`AISpectator`, added automatically by `ModeBase` when `debug_spectator_enabled` is true. Dormant until you press a key.

| key | action |
|---|---|
| F9 | toggle spectator |
| `[` / `]` | previous / next ship |
| `\` | back to the player's ship |
| F10 | overlay detail: off / basic / full |
| F11 | freeze the readout |

Full detail shows speed, slip angle, yaw rate, visual roll, the raw inputs the AI is writing, its required-versus-available yaw budget, its target speed and how far off it is, and the per-sample style gains in effect at that point on the track.

It works by reassigning the chase camera's `ship` property and re-snapping — `AGCamera2097` reads everything else off the ship. It discovers ships by scanning the tree, so it works in race, time trial or a bare test scene without those modes registering anything.

Set `debug_spectator_enabled = false` on the mode for release builds.

---

## Things that are known not to work

Recorded, so nobody re-derives them.

**Training the style gains.** Extending the hill-climb to perturb per-sample cornering airbrake and steering reserve made every perturbation worse than perturbing speeds alone (53.02s against 51.33s), all reverted. The style search already picked those gains per segment from measured laps, so a blind nudge from tracking error steps away from a measured optimum. Ships behind `train_style_gains = false`.

**Per-segment line geometry.** Four geometry variants (late apex, early apex, centre bias, shortest path) were built and searched. Every one is substantially slower as a whole lap than the min-curvature line, and splicing them per segment produced 51.27s against 50.93s for control styles alone. Ships behind `USE_GEOMETRY_VARIANTS = false`. Kept because it is the right basis for **opponent variance** — four distinct drivable lines with a 7-second spread on circuit 3, without touching ship performance.

**A wider corridor.** Cutting `ship_clearance` from 4.0 to 2.5 to 1.5 raised max curvature from 0.0746 to 0.0888 to 0.1005. The extra width lets the line reach into regions where the surface probe is noisy and the solver chases that noise.

**Global `cornering_confidence` as a tuning knob.** It sat at 1.05 for a while, which is openly compensating for the analytic model being wrong rather than describing anything. The trainer and style search replace it with per-segment measurement. It is back at 1.0 as the honest starting point.

---

## Diagnostics worth knowing

**The simulation is deterministic.** Two runs of the same style produced identical lap times to four decimal places. This is what makes the whole search cheap — one lap per style, no repeats. If you ever add per-frame randomness to the AI (skill jitter, avoidance noise), every style needs repeat runs and the compute budget multiplies.

**Training runs at 8x** by raising `Engine.time_scale` and `physics_ticks_per_second` together, which advances sim time faster while keeping per-step delta at its normal value. This is only valid because the handling model is tick-rate independent. Before that change, top speed halved when the tick rate doubled — training at 8x would have produced a profile for a different game.

**`speed_ratio` is clamped to 0–1** and `max_speed` is genuinely enforced. Everything keyed to it (FOV, camera distance, roll scaling, rumble threshold, HUD, AI planning) can rely on that.

---

## Current results

`default_racer`, the four gameworthy circuits:

| circuit | lap | notes |
|---|---|---|
| 3 | 50.93s | assembled |
| 5 | 71.70s | assembled |
| 6 | 65.43s | best single style; assembly refused |
| 7 | 63.93s | assembled; human reference 63.12s |

Circuit 7 has a recorded human lap at 63.12s, so the AI is within 1.3% of a good human there.

`fast_racer` (all-rounder Starling):

| circuit | lap | notes |
|---|---|---|
| 3 | 51.42s | best single style; assembly refused |
| 5 | 71.48s | assembled |
| 6 | 65.47s | assembled |
| 7 | pending | |

### A balance result worth knowing

On circuit 3 the two ships are within **0.03s of each other** (51.42s vs 51.45s) despite `fast_racer` carrying `max_speed` 142 against 120 and `thrust_power` 90 against 65. Circuit 3 is corner-limited rather than top-speed-limited, so an entire speed class buys nothing there.

Circuit 5 is only marginally better: 71.48s against 71.70s, 0.3%.

If a Starling is meant to feel meaningfully quicker than a Sparrow, either the class needs to differ in more than top speed and thrust, or the tracks need longer straights for that advantage to express. This is the sort of thing to settle before designing seven more ships, and it is now a measurement rather than a judgement call.


---

## Player recordings

Every lap the player drives is recorded automatically — **on ships whose profile has `recordable = true`** — and the best ten per bucket are kept. Recordings are a data source only. Since v17 nothing in the AI steers by them.

### Buckets

```
user://recordings/<track>/<ship>/<handling_hash>/<mode>/<flying|standing>/<ms>_<unix>.res
```

- **Handling hash** — a lap only ranks against laps driven on identical handling. Changing a profile starts a fresh bucket; old buckets stay on disk as an archive.
- **Mode** — `time_trial`, `endless` or `race`. Race laps include traffic and avoidance, so they never rank against clean laps.
- **Pool** — lap 1 is a standing start from the grid and ranks separately from flying laps.

Laps covering less than 90% of the track are rejected as cut or broken.

Turn `recordable` on only once a ship is a real candidate for the game. Laps driven on a profile you're still inventing rank against a handling model that won't survive.

### Collecting from testers

Testers press **EXPORT RECORDINGS** on the main menu. It writes one zip to their Desktop containing their laps and a manifest (anonymous tester id, build version, the handling hashes of every recordable ship).

Drop received zips into `res://recordings_inbox/` and run:

```
godot --headless --path . res://tools/import_recordings.tscn
```

It merges every package — plus your own local laps — into `res://recordings_library/`, keeping the best ten **per tester** per bucket, so one fast, prolific tester can't crowd out a different line from someone else. Imported packages move to `recordings_inbox/processed/`.

It then prints the benchmark that matters: best human flying lap against the trained AI's measured peak, per track and ship, current handling only.

Tester ids are random and per-install, deliberately not the OS user name. `user://tester.cfg` has an optional `name` field testers can fill in by hand.


---

## The analysis loop

The workflow that found the flat-out technique on circuit 7:

1. **Drive** — record laps in any mode (recording is automatic on `recordable` ships).
2. **Export** from the main menu, drop the zip in `res://recordings_inbox/`.
3. **Import** — `tools/import_recordings.tscn`. Prints human vs AI per track.
4. **Analyse** — `tools/analyze_laps.tscn` (optionally `-- --track=<id>`). Drives the trained AI for a flying lap, records it with the same `LapRecorder`, and compares it with the best human lap across 16 equal-distance sections: time, speed, lateral position, airbrake use and throttle. It also prints a technique summary — % of the lap at full throttle, airbrake use, mean speed — which is usually where a new technique shows up first. Reports are written to `res://recordings_analysis/`.
5. **Translate** what the human does into a style in `tools/style_search.gd`, run the search, re-analyse.

Circuit 7 went from 63.93s to 62.65s this way, from six laps of human driving. The human lap held full throttle through 100% of the lap with 9% airbrake; the AI was at 91% throttle and 19% airbrake. The fix was a style, not code.

### Tools must test the line they pass

`AIShipController.prefer_trained_line` defaults to true, which races want: the trained line replaces whatever the caller passes. The offline tools set it to **false**. Between v16 and v18 they didn't, so the style search silently loaded the existing trained line, and its per-sample style gains overwrote four parameters of every style under test — airbrake, steering reserve, sensitivity and lookahead. Style searches run on a track that already had a trained line during that window searched a narrowed space; their saved results were still genuinely measured, just not as good as they could have been. Re-run them.
