# Full Throttle Flux — v16: race mode now uses the trained AI

Extract at the **repository root**. Three files replaced. Built against your current `main`.

```
full_throttle_flux/scripts/ai/ai_ship_controller.gd   trained line always wins; provenance
full_throttle_flux/scripts/debug/ai_spectator.gd      provenance + lap times in the overlay
full_throttle_flux/tools/style_search.gd              stamps lap time on assembled lines
```

---

## What you were actually watching

**Not the trained AI.** Race mode never loaded a trained line, on any track, for any ship.

`RaceMode` bakes its own shared racing line and passes it into every `AIShipController.initialize()`. The trained-line loader I added in v11 only ran when the caller passed *no* line — so in an actual race it never ran. Every AI drove a fresh default bake, with default controller params and no style gains. The training tools were measuring an AI that never appeared in the game.

That's why the ship you watched wasn't on pace for anything we'd measured. It was the pre-training AI.

## The 50.933s line and the 51.42s one

**50.933s is `default_racer` on circuit 3 — the assembled line, and yes, it's the one to use.** It has been in your repo since v13 (`test_circuit_3_live_default_racer_trained_line.tres`). It just never got loaded.

**51.42s is `fast_racer` on circuit 3**, and it was never saved: its assembly failed to beat its best single style, and that run predates the uniform fallback. If you were racing with fast_racer selected, there was no trained circuit 3 line for it at all.

That matters because of how race mode picks profiles — both the AI ships and the shared bake use `GameManager.get_selected_ship()`, i.e. whatever *you* selected. Every AI in the field is the same ship as yours ("same ship for now", per the comment). So which trained line applies depends on your ship choice, not a fixed AI roster.

## Verified under race-mode conditions

A harness that reproduces RaceMode's exact call — shared bake passed in — on circuit 3 with `default_racer`:

```
line_source = TRAINED          (despite the shared bake being passed)
style gains = 14 segments      (12 no_ab_confident, 1 ab_last_resort, 1 very_confident)
L1s 52.02   L2 50.93   L3 50.93
```

Lap 1 includes the standing start; flying laps reproduce the assembled 50.933s exactly.

## The fix

`AIShipController.initialize()` now always checks for a trained line for **this ship's own profile** first, and it wins over whatever the caller passed. Precedence:

1. trained line for (track, this ship's `ship_id`)
2. the caller's shared bake
3. self bake
4. centreline fallback

Each AI records which of those it got in `line_source`.

### A second trap closed at the same time

`AIDataManager` loads **user recordings from `user://` before the project's own data**, and the line follower **prefers recorded laps over the baked line** by default (`prefer_baked_over_recorded = false`). So even with recordings deleted from the repo, an old local recording on your machine would silently take over steering. When a trained line is loaded, recordings are now explicitly demoted. If there's no trained line, behaviour is unchanged.

Worth checking your `user://` folder for stale `*_ai_data.tres` files regardless — anything that falls back to recordings will still use them.

## The overlay now answers "what am I looking at"

Two new lines at basic detail, so you don't need full detail to see them:

```
LINE  TRAINED for default_racer  50.933s  [14 segs]
AI    skill 1.00   avoid ON
```

or, when it isn't the trained AI, it says so plainly:

```
LINE  shared bake (untrained)  -- NOT the trained AI (fast_racer)
AI    skill 0.72 HANDICAPPED   avoid ON   FOLLOWING RECORDINGS
```

Anything on the `AI` line that differs from *skill 1.00, avoid off, no recordings* is a reason the watched ship won't match the trained time.

Your existing assembled lines were saved without their lap time (a v15 omission, now fixed), so they'll show `time not recorded` until you re-run `tools/style_search.tscn`.

## Lap times

```
LAPS  now 5.48   best flying 50.933 L2   (race timing)
      L1s 52.02  L2 50.93*  L3 50.93
```

- `L1s` flags lap 1 as a standing start.
- `best flying` excludes lap 1, since only flying laps are comparable to trained times. `*` marks it.
- `(race timing)` means the numbers come straight from `RaceManager`'s per-ship lap data, so the overlay can never disagree with the race HUD. In modes where RaceManager isn't tracking the ship (time trial, bare test scenes) it falls back to its own spline-crossing timer and says `(spline timing)`.
- Timing runs for every ship all the time, not just the watched one, so the history is there when you switch.

## What to expect when you watch the leader

On **Hard**, the lead AI gets skill 1.0, so on `default_racer` circuit 3 it should now run flying laps near 50.93s. It still won't match exactly, and the overlay will show you why:

- **Avoidance is on** in races, which modifies inputs whenever another ship is close.
- **Traffic.** Trained times are alone on track.
- **Grid position.** Training starts from pole; race AI start further back.

On **Medium** (skill 0.50–0.72) and **Easy** (0.25–0.45), `skill_level` scales target speeds down (to 85–96%), tightens use of the line toward centre, shortens lookahead and adds steering wobble. That's already your "handicap the max-difficulty AI" plan in embryo — which is good news, because it now sits on top of the trained line rather than an untrained one.

## Not validated

The keyboard side of the spectator is still untested — I can't drive input headlessly. The overlay text itself was rendered and checked in the harness above, including the provenance and lap lines.
