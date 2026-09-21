# Full Throttle Flux — v15: watch mode, multi-ship training, regimen docs

Extract at the **repository root**. One file replaced, five added. Requires v14.

```
full_throttle_flux/scripts/debug/ai_spectator.gd       NEW  watch mode
full_throttle_flux/scripts/modes/mode_base.gd          hooks the spectator in
full_throttle_flux/tools/style_search.gd               multi-ship, uniform fallback
full_throttle_flux/docs/AI_TRAINING_REGIMEN.md         NEW  the pipeline, documented
full_throttle_flux/resources/ai_data/test_circuit_5_live_fast_racer_trained_line.tres
full_throttle_flux/resources/ai_data/test_circuit_6_live_fast_racer_trained_line.tres
```

---

## Watch mode

`AISpectator` is added automatically by `ModeBase` behind `debug_spectator_enabled`, and stays dormant until you press a key.

| key | action |
|---|---|
| F9 | toggle spectator |
| `[` / `]` | previous / next ship |
| `\` | back to the player's ship |
| F10 | overlay detail: off / basic / full |
| F11 | freeze the readout |

Full detail shows speed and speed ratio, slip angle, yaw rate, visual roll, the raw inputs the AI is writing, its required-versus-available yaw budget, its target speed and the error against it, the lateral offset of the line it is chasing, and the per-sample style gains in effect at that point on the track.

It works by reassigning the chase camera's `ship` property and re-snapping — `AGCamera2097` reads everything else off the ship, and `reset_to_ship()` deliberately skips the cinematic intro. Ships are found by scanning the tree, so it works in race, time trial or a bare test scene without any mode registering anything with it. Raw keycodes, so no `project.godot` input map changes.

**Not runtime-tested.** I have no way to exercise keyboard input headlessly. The logic is simple and the camera reassignment path is the same one respawns already use, but treat the first run as a test. Set `debug_spectator_enabled = false` for release builds.

## Multi-ship training

`style_search.gd` now loops `SHIP_PROFILES` × `TRACKS`, and honours a profile's own `ship_scene` when it sets one.

New: a **uniform-anchor fallback**. When the spliced assembly fails to beat the best single style, the tool previously saved nothing — which meant the AI fell back to baking a default line at runtime and driving with default controller params, substantially slower than the style we had just measured. It now saves the anchor style as a flat uniform strategy instead: its own line, its own gains everywhere, zero splice risk, and a lap time actually driven. Every ship/track pair ends up with something measured.

## fast_racer results

| circuit | lap | notes |
|---|---|---|
| 3 | 51.42s | best single style; assembly refused |
| 5 | 71.48s | assembled |
| 6 | 65.47s | assembled |
| 7 | incomplete | run did not finish before I ran out of budget |

**Circuit 7 needs re-running.** Re-run `tools/style_search.tscn` and it will pick up where the data is missing; circuits 3, 5 and 6 will simply be reproduced.

Circuit 3 also predates the uniform-anchor fallback, so it currently has no saved line for `fast_racer`. Re-running fixes that too.

### The balance finding

On circuit 3 the two ships are within **0.03 seconds** of each other — 51.42s for `fast_racer` against 51.45s for `default_racer` — despite `fast_racer` carrying `max_speed` 142 against 120 and `thrust_power` 90 against 65.

Circuit 3 is corner-limited, not top-speed-limited, so an entire speed class buys nothing there. Circuit 5 is only marginally better at 0.3%.

This is worth settling before designing seven more ships. Either a class needs to differ in more than top speed and thrust — grip, steer rate, airbrake authority, hover behaviour — or the tracks need longer straights for a speed advantage to express itself. Either way it is now a measurement rather than a judgement call.

## The regimen document

`docs/AI_TRAINING_REGIMEN.md` covers the five-stage pipeline with the reasoning behind each choice, how to add a ship or a track and what to check first, when to retrain, the diagnostics that matter, and a "known not to work" section recording the three dead ends we measured — trained style gains, per-segment line geometry, and a wider corridor — so nobody re-derives them.

The two pitfalls most likely to bite when adding content are in there: a profile whose thrust can never reach its declared `max_speed` (which is what `fast_racer` originally had at 600), and a track whose walls or drivable geometry are not visible to the corridor raycasts.
