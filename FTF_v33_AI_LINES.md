# Full Throttle Flux — v33: AI lines and the ship profile

The brief: the offline AI tools drove the wrong ship. `default_racer.tscn`
embeds `speed_demon.tres` (max 160 against 120, grip 2.0 against 4.0, steer
1.0 against 1.345, softer and lower hover), and neither `style_search.gd` nor
(before v32) `train_ai_lines.gd` assigned the profile they were training. So
the circuits' racing lines should have been planned for a different ship.

The tooling bug is real and now fixed so that it cannot pass silently again.
The measurements show **the four circuit lines were not trained on
speed_demon**, though. Loop Lab's line was. Circuit 5's line was broken for
another reason.

- **Circuits 3, 6 and 7:** each old line reproduces its stamped lap time on
  default_racer physics to within 0.05 s. On speed_demon it is 3.3–3.8 s
  slower. These lines predate the RC 5 ship scene that embeds speed_demon.
- **Circuit 5 (Swoopy):** the old line reproduces on neither ship. A single
  AI respawns 4 times in 2 laps, and 8-ship races at Hard produced
  135 respawns. Its plan was flat out into a 13 m hairpin.
- **Loop Lab:** trained on speed_demon in v30. It reproduces its stamp
  exactly on speed_demon (33.083 s) and not on default_racer.
- **Fork Lab:** v32 trained it with the right profile. Verified: both route
  lines reproduce their stamps on default_racer.

I rebuilt all four circuits from fresh bakes on default_racer. Then I kept
the better line per circuit, measured alone and in races:

| | old line | new line | kept |
|---|---|---|---|
| Utopia (c3) | 50.62 s | 50.70 s, identical corner speeds | **old** (0.08 s faster, races equal) |
| Swoopy (c5) | 73.45–76.38 s, 4 respawns | 70.17–70.23 s, 0 walls, 0 respawns | **new** |
| Hairpin Alley (c6) | 64.75 s, 6 wall hits | 64.63 s, 3 wall hits | **new** (races: half the wall contacts) |
| The Drop (c7) | 62.65 s, 1 wall hit | 62.40 s, 3 wall hits | **old** (races: new is 0.3 s/lap faster but has 2.3× the wall contacts) |
| Loop Lab | 32.60 s | 32.57 s | **new** (fresh bake, no speed_demon ancestry) |

## Files

| File | What |
|---|---|
| `scenes/ships/default_racer.tscn` | No embedded profile any more (was `hidden/speed_demon.tres`). |
| `scripts/ai/ai_line_trainer.gd` | `spawn_ship(profile)` sets the profile before `_ready()`. `driven_profile(ship)` checks the physics the ship applied against its profile. `save_trained_line(line, profile, driven_by)` stamps the hash the ship drove with, and refuses to save on a mismatch. |
| `tools/style_search.gd` | **Fix:** spawns through `spawn_ship` (it never set the profile). Saves pass the ship. New `--track=` filter. |
| `tools/train_ai_lines.gd` | Spawns through `spawn_ship`, saves pass the ship, and the log shows the seed's lap and hash. New `--fresh` flag ignores any saved line. |
| `scripts/ai/ai_ship_controller.gd` | Fork route lines get the same stale-handling warning as the main line. Warning only. |
| `tools/dev/ai_lap_probe.gd` + `_boot.gd` (new) | One AI drives any line file on any profile, timed the way the trainer times laps. Reports lap, mean target/driven speed, corner speeds, wall contacts, respawns and tracking error. |
| `tools/dev/ai_race_probe.gd` | Adds per-ship lap times in simulated seconds, wall contacts and the field spread at each lap line. All read-only; checksums unaffected. |
| `tools/dev/loop_lab_driver.gd`, `tools/fork_lab/fork_lab_driver.gd` | The autopilots no longer file laps in `user://recordings` (see "Found along the way"). |
| `resources/ai_data/test_circuit_5_live_…`, `test_circuit_6_live_…`, `loop_lab_…` | Retrained lines. Circuits 3 and 7 and Fork Lab are unchanged. |

`race_mode.gd`, `track_respawn_manager.gd` and the ship respawn code are not
touched. Neither is anything else in `scripts/ships/`.

## Root cause and fix

**The bug.** `ShipController` copies every handling value out of `profile`
in `_ready()`. A ship instanced from `default_racer.tscn` without a profile
assigned drives speed_demon. `style_search.gd` instanced it and never
assigned one. The style search therefore drove speed_demon, and so did the
AI controller's performance model, which reads `ship.profile`. It still baked
and saved with default_racer's model and hash. `save_trained_line(line,
profile)` stamps the hash of the profile it was handed. So the stale-line
check in `AIShipController` compared a label with a label and always passed.

**Audit of every place a ship is instanced:**

| Spawner | Profile before `_ready`? |
|---|---|
| `race_mode.gd` `_spawn_player_ship`, `_spawn_ai_ship` | yes. The AI ships get `GameManager.get_selected_ship()` before `add_child` |
| `mode_base.gd` `_spawn_ship` (time trial, endless) | yes |
| `tools/train_ai_lines.gd` | yes since v32. Now via `spawn_ship` |
| `tools/style_search.gd` | **no** (fixed) |
| `tools/analyze_laps.gd`, `tools/fork_lab/jump_sim.gd` | yes |
| `tools/dev/*` probes and drivers, `fork_lab_driver`, `race_smoke`, `mb_profile`, `scripts/test/race_mode_test.gd` | spawn via `race_launcher` → the modes above |
| `render_shots`, `render_motion_shots` | instance the mesh only, no `ShipController` |
| `.tscn` files instancing the ship scene | none |

**The fix has three layers. Each would catch the bug on its own.**

1. **The trap is gone.** `default_racer.tscn` has no embedded profile. A
   spawner that forgets one gets `ShipController: No profile assigned!`
   instead of a different ship. No game path relied on the embedded value:
   every spawner above assigns one. The c3/c7/Fork Lab checksums prove it
   (see Regression).
2. **One spawn path for the tools.** `AILineTrainer.spawn_ship(profile)`
   instances `profile.ship_scene` (or the default scene) and assigns the
   profile before the caller adds it to the tree.
3. **Stamps come from the ship that drove.** `save_trained_line(..., driven_by
   = ship)` calls `driven_profile(ship)`. It compares ten handling values the
   controller actually applied (`_max_speed`, `_grip`, `_steer_speed`,
   `_hover_height`, …) with `ship.profile`. Then it checks that hash against
   the profile being saved. A mismatch is an error, and nothing is written.
   A profile swapped after `_ready()` is caught too, because the label
   changes and the physics don't. A renamed controller field fails loudly
   rather than vouching for an unchecked ship.

Checked with a throwaway script (not committed). All five cases behave:
- `spawn_ship` → verified.
- A raw scene with no profile → error, refused.
- A profile swapped after `_ready` → "ship drives with max_speed=160.0 but
  its profile default_racer says 120.0", refused.
- A speed_demon ship saved as default_racer → `ERR_INVALID_DATA`, and no
  file is written.

**Rejected alternatives:**
- *Embed `default_racer.tres` in the scene.* That is a cycle: the profile's
  `ship_scene` is this scene. It would also keep a silent default, just a
  less wrong one.
- *Guards only, keep speed_demon embedded.* The guard protects saved lines,
  but any future tool or test scene would still silently drive the wrong
  ship. Removing the default costs nothing.
- *A runtime race-time guard.* `AIShipController` already warns when a
  line's `profile_hash` differs from the ship's. That check was sound; its
  input was wrong. With honest stamps it works. I added the same warning to
  the fork route-line path, which lacked it.

## Evidence: what each old line was trained on

One AI at skill 1.0, alone, driving the committed line. `ai_lap_probe` times
it the way the trainer does: 6 s warm-up, then whole laps from the line, in
simulated seconds at `--fixed-fps 60`. Two flying laps each.

| Line | Stamped lap | On default_racer | On speed_demon | Trained on |
|---|---|---|---|---|
| c3 Utopia | 50.633 | 50.617 / 50.667 | 53.933 / 53.883 | default_racer |
| c5 Swoopy | 69.433 | 76.383 / 73.450, **4 respawns** | 73.700 / 76.083 | neither reproduces |
| c6 Hairpin Alley | 64.700 | 64.750 / 64.783 | 68.067 / 68.200 | default_racer |
| c7 The Drop | 62.650 | 62.650 / 62.700 | 66.450 / 66.533 | default_racer |
| Loop Lab | 33.083 | 32.600 / 32.600 | 33.183 / **33.083** | **speed_demon** |
| Fork Lab main route | 29.833 | 29.867 / 29.933 | 31.133 / 31.200 | default_racer |
| Fork Lab shortcut | 28.417 | 28.417 / 28.500 | 29.417 / 29.417 | default_racer |

There is no git history before RC 5, but the dates fit. The circuit lines
date from v18. `default_racer_old.tscn`, which embeds `default_racer.tres`,
was presumably the ship scene then. Loop Lab (v30) came after the RC 5
scene. A second check: the new style search on c3 gives `no_ab_confident`
51.450 s, exactly v12's number.

**Circuit 5** also fails on the pre-RC 5 scene (`AL_SCENE=…default_racer_old.tscn`):
73.233 s with a respawn, then 69.750 s. Its plan targeted 120 u/s into the
13 m and 34 m hairpins (at 7611 m and 6300 m), relying on airbrake taps.
That fails most laps on the current build, and I can't say what changed
since it was saved. Perhaps it was saved from a lucky lap.

## Rebuild

The old lines are copied to the scratchpad and remain in git history. I
deleted each circuit's line from `resources/ai_data` first, so nothing could
seed from it. Then I ran `style_search --track=X` from fresh bakes
(`use_cache = false`) and `train_ai_lines --track=X`, which seeds from the
new style-search output. Every log confirms `default_racer … passed line
(tools)` and handling `0c95eae5`.

| Circuit | Best single style | Assembled | Trainer | Probe (2 laps) |
|---|---|---|---|---|
| c3 | no_ab_confident 51.450 | 50.700 (2/14 swapped) | 50.70, no gain in 5 iterations | 50.700 / 50.700 |
| c5 | confident 72.117 | 70.217 (5/14) | 70.18 | 70.233 / 70.167 |
| c6 | flat_out_light 65.283 | 64.667 (3/14) | 64.57 | 64.633 / 64.683 |
| c7 | flat_out_light 62.717 | 62.383 (1/14) | 62.40 | 62.467 / 62.400 |
| Loop Lab | — | — | fresh bake 32.57; seeded from old 32.58 | 32.583 / 32.567 |

The trainer barely moves these lines. Its perturbations are reverted and the
step shrinks out within 5–10 iterations. The style search does the work.
Swoopy's winner moved from flat_out_light everywhere to a `confident` anchor
with 5 swaps: flat-out no longer survives it.

The trainer's 8× laps and the probe's 1× laps differ by up to 0.07 s on c6
and c7. Each is deterministic on its own.

### Single AI, old → new (default_racer, skill 1.0)

| | lap | mean target | mean driven | corner target | corner driven | wall hits (ticks) |
|---|---|---|---|---|---|---|
| c3 | 50.62 → 50.70 | 116.3 → 116.3 | 114.1 → 114.1 | 111.2 → 111.2 | 108.3 → 108.3 | 1 (11) → 1 (11) |
| c5 | 73.45 + 4 resp → 70.17 | 118.5 → 114.2 | 115.2 → 113.0 | 117.6 → 109.5 | 109.2 → 108.1 | 3 (19) → 0 (0) |
| c6 | 64.75 → 64.63 | 116.3 → 111.7 | 110.1 → 108.2 | 109.3 → 98.3 | 91.6 → 90.4 | 6 (104) → 3 (41) |
| c7 | 62.65 → 62.40 | 115.5 → 116.9 | 113.3 → 113.7 | 107.3 → 112.1 | 101.9 → 103.6 | 1 (22) → 3 (39) |
| Loop Lab | 32.60 → 32.57 | 118.8 → 119.1 | 117.6 → 117.8 | 111.0 → 113.1 | 106.9 → 107.5 | 0 → 0 |

Corners are curvature peaks tighter than R 350 m, at least 150 m apart.
Corner speed is the minimum within ±60 m. Old and new lines share the same
geometry (same corners at the same distances), so the columns compare
directly. Tightest corners where it matters:
- **c5:** 13 m hairpin, target 120 → 29.5, driven 3.5 (respawn) → 33.0.
  34 m: 120 → 70.9, driven 3.5 → 71.8.
- **c6:** 18 m: target 120 → 40.5, driven 31.2 → 42.5. 21 m: target 120 →
  45.9, driven 19.3 → 46.8.

Both old lines planned full speed into hairpins and hit the wall. The new
ones brake for them and come out faster.

### 8-ship races, old → new

`ai_race_probe`, 240 s (3 laps), seeds 1234, 7 and 42 at each difficulty.
Every cell covers 7 AIs × 3 seeds. Lap times are in simulated seconds; lap 1
(standing start) is excluded from the flying-lap means. Wall hits are rising
edges of the ship's scrape state. Spread is the gap between the first and
last AI over the final lap line.

| Circuit | Diff | Respawns | Wall hits | Mean flying lap | Best lap | Spread, final lap |
|---|---|---|---|---|---|---|
| c3 | easy | 0 → 0 | 185 → 193 | 56.35 → 56.43 | 55.13 → 55.17 | 7.6 → 7.8 |
| c3 | medium | 0 → 0 | 126 → 134 | 53.52 → 53.56 | 52.33 → 52.40 | 7.5 → 7.5 |
| c3 | hard | 0 → 0 | 123 → 124 | 51.37 → 51.46 | 50.62 → 50.70 | 5.4 → 6.2 |
| **c5** | easy | **4 → 0** | **372 → 93** | 77.50 → 78.76 | 75.43 → 77.12 | 10.3 → 8.8 |
| **c5** | medium | **16 → 0** | **346 → 68** | 74.78 → 74.99 | 71.98 → 73.28 | 11.1 → 10.1 |
| **c5** | hard | **135 → 0** | **285 → 20** | **74.13 → 71.27** | 69.10 → 70.17 | **19.2 → 7.7** |
| **c6** | easy | 0 → 0 | **564 → 240** | 71.01 → 71.89 | 69.20 → 70.10 | 10.5 → 12.2 |
| **c6** | medium | 0 → 0 | **569 → 248** | 68.18 → 68.24 | 66.73 → 66.85 | 10.0 → 9.3 |
| **c6** | hard | 0 → 0 | **508 → 209** | 65.49 → 65.41 | 64.63 → 64.58 | 6.4 → 6.2 |
| c7 | easy | 0 → 0 | 137 → 331 | 69.62 → 69.34 | 68.05 → 67.55 | 11.2 → 12.2 |
| c7 | medium | 0 → 0 | 92 → 205 | 66.32 → 65.71 | 65.13 → 64.60 | 8.5 → 8.2 |
| c7 | hard | 0 → 0 | 96 → 221 | 63.51 → 63.23 | 62.23 → 62.37 | 6.7 → 6.1 |

The c3 and c7 "new" rows are the candidates I did **not** ship.

On c5 at Hard, one old-line AI never completed a lap: it was stuck in a
respawn loop.

At Easy on c5 and c6 the new lines are about 1 s/lap slower. The lower
targets compound with the Easy skill scaling. Medium and Hard are level or
faster.

Loop Lab, 140 s at medium, seeds 1234/7/42: no respawns either side. Wall
hits 0/3/8 → 0/3/8. Mean flying lap 34.14/34.15/34.27 → 34.05/34.06/34.23;
best lap 33.57 → 33.48.

### Faster or slower?

- **Utopia and The Drop:** unchanged, because their lines were already
  right.
- **Swoopy:** much faster where it counts. Hard races average 2.9 s/lap
  quicker, with no crashes or respawn loops, and the field spread is
  cut from 19.2 s to 7.7 s.
  The old line's 69.4 s plan was faster on paper and crashed in practice.
- **Hairpin Alley:** the same pace with half the wall contact. The AI now
  brakes for the 18 m and 21 m hairpins instead of bouncing off them.
- **Loop Lab:** 0.03 s/lap faster alone and about 0.1 s in races. The point
  was to retire a speed_demon line, not to gain pace.

### Against the player autopilot and human laps

`loop_lab_drive` (centreline autopilot, flat out, 3 laps):

| Track | Laps | Respawns |
|---|---|---|
| c3 | 63.28 / 63.43 | 3 |
| c5 | 88.98 / 94.10 | 2 (only 2 laps in the 210 s cap) |
| c6 | 75.07 / 73.25 | 0 |
| c7 | 74.08 / 72.57 | 0 |

The AI beats it on every circuit, before and after:

| | Easy | Hard |
|---|---|---|
| c3 | 7 s/lap | 12 s/lap |
| c5 | 10–15 s/lap | 18–23 s/lap |
| c6 | 1.4–3 s/lap | 8 s/lap |
| c7 | 3–4.5 s/lap | 9 s/lap |

It is a centreline test harness with no racing line, so it isn't a pace
reference.

**Human laps.** None are available here. `user://recordings` in this
sandbox holds only autopilot laps, whose "lap times" are wall clock under
`--fixed-fps` (e.g. 3.66 s on Utopia). There is no `recordings_library/` in
the repo. The only human reference is in the notes: The Drop at 63.12 s
(v11/v18, default_racer). The kept c7 line does 62.65 s alone; Hard races
average 63.51 s with a best of 62.23 s. To compare against your own laps,
run `tools/analyze_laps.tscn` on your machine. It now gets lines whose
stamps are honest.

## New baselines

| Track | `ai_race_probe` (seed 1234) | `cine_rig_probe` |
|---|---|---|
| c3 Utopia (75 s / 45 s) | 3929678988 (unchanged) | 3621838145 (unchanged) |
| c5 Swoopy | **3790437673** (was 2744688434) | **2900775167** (was 1427140778) |
| c6 Hairpin Alley | **2668530540** (was 2544408098) | **110340458** (was 1324755775) |
| c7 The Drop | 133359682 (unchanged) | 2300779685 (unchanged) |
| Loop Lab (140 s / 75 s) | **3860760227** (was 675169125) | **3358873327** (was 1087435003) |
| Fork Lab (150 s) | 3551594432 (unchanged) | — |

## Regression

- **Player-only autopilot**, 3 laps per circuit, before → after: the lap
  times and respawn counts are bit-identical (table above).
- **Ship physics code untouched:**
  `git diff feature/fork-jump-lab -- full_throttle_flux/scripts/ships/` is
  empty. The ship scene only lost its embedded profile, which no game
  spawner uses.
- **Unchanged checksums**:
  - c3 and c7 (AI and rig) and Fork Lab match v32 exactly. Their lines did
    not change; everything else in this branch did. So the scene change,
    the new probe output, the controller's route warning and the tool
    changes do not alter a race.
  - Loop Lab changed only because it was retrained. The old line, run from
    a copy of this branch, reproduces 675169125.
- No `SCRIPT ERROR` in any probe, training or race log.

## Found along the way

1. **The autopilots were overwriting player recordings.** Under `--fixed-fps`,
   RaceManager's wall-clock lap times are a few seconds. `LapRecorder` filed
   every `loop_lab_drive` / `fork_lab_drive` lap as a time-trial lap, and
   `RecordingStore` keeps the 10 fastest per bucket and **deletes the rest**.
   Run on your machine, the autopilot would push your real laps out. Both
   drivers now switch their ship's recorder off; lap times are unchanged.
   The other session's worktree doesn't have this fix yet. Its runs today
   wrote such laps into this sandbox's `user://recordings`, which is shared
   by project name.
2. **Circuit 5's committed line was unsafe on the current build**, with
   respawn loops at every difficulty. It is fixed by the retrain. Worth
   knowing if you have been tuning anything on Swoopy against that AI.
3. **The trainer adds little on top of the style search** on these tracks
   (≤0.1 s, often 0). Not a bug; it is where the remaining pace isn't.
4. **The RC 5 ship scene changed more than the profile.** Its collision
   capsule differs from `default_racer_old.tscn`:
   - RC 5 scene: radius 0.63, height 6.3 effective (0.585 scale), default
     `safe_margin`.
   - Old scene: radius 0.81, height 6.7 effective (1.3 scale),
     `safe_margin` 0.1.

   The RC 5 scene is what the game spawns, so lines are now trained on it.
   The old c3/c7 lines happen to reproduce on both scenes to within 0.02 s.

## Decisions

- **Kept the old c3 and c7 lines.** They are proven default_racer lines.
  c3's rebuild is 0.08 s slower with identical corner speeds. c7's is
  0.3 s/lap faster in races but scrapes walls 2.3× as often, which reads
  worse and costs more in traffic. The pipeline is deterministic, so
  `style_search --track=test_circuit_7_live` then
  `train_ai_lines --track=test_circuit_7_live` regenerates the faster c7
  candidate if you prefer pace.
- **Fresh bake over seeding** everywhere, including Loop Lab. Seeded and
  fresh measured within 0.02 s there, and the fresh one has no speed_demon
  ancestry.
- **Fork Lab** verified, not retrained.

## Open issues

- Wall contact is still common with the shipped lines, in wall hits per AI
  per lap:

  | | Easy | Hard |
  |---|---|---|
  | c3 | 2.9 | 2.0 |
  | c5 | 1.7 | 0.3 |
  | c6 | 3.8 | 3.3 |
  | c7 | 2.2 | 1.5 |

  They are short scrapes, about 10–13 ticks (~0.2 s) each on average.
  Single AIs alone hit 0–3 times per lap, so traffic accounts for part of
  it. The line can't fix the rest: it is the
  controller and avoidance. Easy AIs are skill-scaled versions of the same
  plan.
- `docs/AI_TRAINING_REGIMEN.md`'s "Current results" table is stale (v15
  numbers). Not edited, to keep notes in this file.
- The c6 and c7 trainer stamps differ from the 1× probe by up to 0.07 s
  (8× against 1× physics stepping). Each is deterministic on its own.

## Running it

```
# one AI on a line file: lap, speeds, corners, walls (AL_PROFILE, AL_SCENE, AL_ROUTE, AL_CORNERS=1)
AL_TRACK=test_circuit_5_live AL_LINE=res://resources/ai_data/test_circuit_5_live_default_racer_trained_line.tres \
  godot --headless --fixed-fps 60 --path . -s res://tools/dev/ai_lap_probe_boot.gd
# rebuild one circuit from scratch
godot --headless --path . res://tools/style_search.tscn -- --track=test_circuit_5_live
godot --headless --path . res://tools/train_ai_lines.tscn -- --track=test_circuit_5_live
# train from a fresh bake, ignoring the saved line
godot --headless --path . res://tools/train_ai_lines.tscn -- --track=loop_lab --fresh
# race probe now also prints PROBELAP / PROBEFIELD lines
PROBE_TRACK=test_circuit_5_live PROBE_SECONDS=240 PROBE_SEED=7 PROBE_DIFFICULTY=2 \
  godot --headless --fixed-fps 60 --path . -s res://tools/dev/ai_race_probe_boot.gd
```
