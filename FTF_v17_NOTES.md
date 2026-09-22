# Full Throttle Flux — v17: peak AI only, always-on recordings

Built against your current `main`.

**Two steps, in this order:**

1. Extract the zip at the **repository root**. 25 files: 14 replaced, 11 new.
2. Run the deletion script from the repository root:
   ```
   powershell -ExecutionPolicy Bypass -File .\apply_v17_deletions.ps1
   ```
   It removes 13 files and folders a zip can't delete, plus your old `%APPDATA%\...\ai_recordings\` folder. Every path is listed explicitly — no wildcards — and it reports each one as `removed` or `absent`.

Then open the project in the editor once so it rescans classes.

---

## 1. No more blending

The recorded-lap control path is gone, end to end:

- **Deleted:** `AIDataManager`, `TrackAIData`, `AIRecordedLap`, `AIRacingSample`, `AILapRecorder` (the old F4 recorder), `AIDebugTester`, and their scenes.
- **Line follower:** recorded-target steering removed; the baked line is the only source, with the geometric centreline as fallback.
- **Control decider:** recorded throttle/brake/airbrake hint blending and its skill-dependent weights removed.
- **Race mode:** no longer loads recordings for the AI.
- `AIShipController.initialize(track, line)` — the recordings parameter is gone from the signature, and every caller is updated.

The `user://`-first loader that could silently override the trained line no longer exists.

The two junk tracks (`test_circuit`, `test_circuit_2`) instanced the debug tester; that node is removed from both so they still load. Neither is in the track manifest.

**Verified:** all 52 scripts in `scripts/` and `tools/` compile.

## 2. Peak AI

- `fast_racer` removed from both training lists and its two trained lines deleted. The profile file stays, with `recordable` off, for when the Starling class is designed properly.
- **Race mode skips its shared bake** when the selected ship has a trained line for the track — it was computing a fallback nobody used.
- **Startup messages now say what each AI actually loaded.** Instead of the misleading "No AI data found", you'll see per AI:
  ```
  AIShipController: default_racer on test_circuit_3_live -> line: TRAINED (skill 1.00, avoidance enabled)
  ```

### Handling hash — stale lines are now visible

`ShipProfile.handling_hash()` fingerprints everything that can change a lap time. Visual-only fields (roll, hover animation, camera shake, audio thresholds) are excluded, and any **new** physics field is included automatically, so the safe default is to invalidate rather than silently keep.

Trained lines store the hash. When the AI loads one:

- `TRAINED` — handling unchanged since training.
- `TRAINED (STALE: handling changed since training)` — plus a console warning. Retrain.
- `TRAINED (unverified: predates handling hash)` — **your current lines**, made before v17. Re-run the style search to stamp them.

Verified: the hash is stable across loads, ignores a change to `roll_max_angle`, and changes when `grip` changes.

## 3. Recordings

`LapRecorder` is attached to the player's ship by `ModeBase` in every mode, and records only if the profile has **`recordable = true`**. `default_racer.tres` is marked recordable; nothing else is.

- **Unit:** laps. Lap boundaries and lap times come from `RaceManager.lap_completed` — the same event the HUD uses, fired exactly once per player lap in every mode — so recorded times always match what the player saw.
- **Buckets:** track / ship / handling hash / mode / pool (flying or standing), best 10 each. A handling change starts a fresh bucket; old ones stay as an archive.
- **Rejection:** laps covering under 90% of the track are discarded as cut or broken.
- **Contents:** per 50ms — time, spline offset, lateral offset, speed, throttle, steer, both airbrakes, world position.

**Verified end to end** on circuit 3: recorded a lap at 50.933s, 1019 samples, 100% coverage; exported; imported; filed under the tester. Top-10 eviction tested with 12 laps — kept exactly the best ten in order. The coverage check also caught a real case in testing: a 0.6-second "lap" when the ship started behind the line, rejected at 1% coverage.

**Size:** about 35KB per lap as compressed binary. Ten laps × four tracks is roughly 1.4MB per ship — well under my earlier estimate.

### Export — main menu

**EXPORT RECORDINGS** sits between Leaderboards and Quit, in the focus chain for pad navigation. It zips every local lap plus a `manifest.json` (tester id, build version, current handling hashes) to the Desktop and shows the path. Falls back to the user data folder if there's no Desktop.

Tester ids are random and per-install, never the OS user name. `user://tester.cfg` has an optional `name` field.

### Import — your side

```
godot --headless --path . res://tools/import_recordings.tscn
```

Drop tester zips into `res://recordings_inbox/`. The tool merges them and your own local laps into `res://recordings_library/`, keeping the best 10 **per tester** per bucket — so a fast, different line from a new tester is never crowded out by one prolific tester. Processed zips move to `recordings_inbox/processed/`.

Then it prints the benchmark:

```
test_circuit_3_live   default_racer   time_trial   human 50.933s [e5373622]   AI 50.933s (+0.0%)
```

That test row is the AI driving itself, so +0.0% is expected. With real human laps, a negative number means the AI is faster than the best human — that's what maximum difficulty should look like.

I'd add `recordings_inbox/` to `.gitignore`. Whether `recordings_library/` goes into git is your call; at 35KB a lap it's small enough.

---

## Not verified

- **The main menu button** — keyboard/pad input can't be driven headlessly. The export function it calls is tested; the button wiring isn't.
- **Recording during a live race or time trial.** The recorder was tested driven directly, not via RaceManager events in a real session. Your first time trial is the real test — the console prints one line per lap: kept with its rank, not in the top 10, or rejected with a reason.
- **Lap 1 as standing start.** It relies on RaceManager counting the first line crossing correctly. If lap 1 turns up in the flying pool, that's where to look.
