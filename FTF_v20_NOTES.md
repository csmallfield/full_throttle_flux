# Full Throttle Flux — v20: ships keep flying after the finish

Extract at the **repository root**. Two files replaced. Requires v19.

```
full_throttle_flux/scripts/modes/race_mode.gd         keep flying; player handover
full_throttle_flux/scripts/recording/lap_recorder.gd  stop()
```

---

## What was happening

Two separate causes, both deliberate-looking but wrong once the race is over.

**AI ships:** `_on_ship_finished()` cleared `ai_active` the instant a ship crossed the line, and `_on_all_ships_finished()` did it to the rest. With nothing steering, a ship at 110 units/sec coasts straight into the first wall it meets.

**The player's ship:** `_on_race_manager_finished()` called `lock_controls()`, which zeroes throttle, steering, pitch and both airbrakes every frame. The ship just sat there.

## The fix

New `keep_flying_after_finish` export on RaceMode, default **true**. Set it false to get the old behaviour back.

- Finished AI ships keep driving their trained line.
- The player's ship is handed to a fresh `AIShipController` at skill 1.0, with avoidance following your `ai_avoidance_enabled` setting.

`lock_controls()` is still called on the player ship, deliberately. `_read_input()` returns early on `ai_controlled` *before* it reaches the lock, so the AI's inputs stand — and if the handover ever fails to initialise, the lock is still there to stop the pad driving a ship nobody is watching.

Every ship, including the now-AI-driven player ship, is re-registered with every controller's avoidance, so the field still avoids each other during the cool-down.

The takeover AI loads the trained line for the player's ship as normal, so it flies the same peak line the opponents do.

## One thing this had to get right

**Recording stops at the handover.** `LapRecorder.stop()` is called before control transfers. Otherwise the cool-down laps the AI flies would be filed as *your* laps, and since they're flown on the trained line at skill 1.0 they'd be fast enough to take over the top ten and quietly poison the data you're collecting.

## Cleanup

On mode teardown the takeover AI is freed and `ai_controlled` is set back to false on the player's ship, so a restart that reuses the ship doesn't find itself still under AI control.

## Verified

All 53 scripts compile; the new export and `LapRecorder.stop()` both resolve.

**Not verified:** the behaviour itself. A full race needs a selected ship, HUD, countdown and results, which I can't drive headlessly. What to watch for on your first race:

- `RaceMode: player ship handed over to AI for the cool-down` in the console when you cross the line.
- The field still moving behind the results screen.
- No new laps appearing in your recordings from after the finish.
