# Full Throttle Flux — v18: flat-out styles, the analysis tool, and a tool bug fix

Extract at the **repository root**. Five files replaced, two added. Requires v17.

```
full_throttle_flux/scripts/ai/ai_ship_controller.gd      prefer_trained_line (tools opt out)
full_throttle_flux/tools/style_search.gd                 flat-out styles; tool fix
full_throttle_flux/tools/train_ai_lines.gd               tool fix
full_throttle_flux/tools/analyze_laps.gd                 NEW  human-vs-AI section analysis
full_throttle_flux/tools/analyze_laps.tscn               NEW
full_throttle_flux/resources/ai_data/test_circuit_7_live_default_racer_trained_line.tres
full_throttle_flux/docs/AI_TRAINING_REGIMEN.md           the analysis loop, documented
```

---

## Circuit 7: 63.93s → 62.65s

From six laps of your driving. Your fastest (61.92s, set in race mode) held **full throttle through 100% of the lap** and rotated with short airbrake taps — 9% of the lap against the AI's 22%. The AI was lifting to 0.6 throttle and slowing to 87–95 through corners you took at 110–115.

Three flat-out styles were added to the search. Each puts every target speed at the cap via an extreme `cornering_confidence`, so the AI never lifts or brakes, while the cornering airbrake still engages on yaw shortfall. Because it's expressed through the plan, it splices through assembly with no new machinery.

| style | lap |
|---|---|
| **flat_out_light** (airbrake 0.5, reserve 0.9) | **63.00s** — new best single style |
| confident (previous best) | 64.23s |
| flat_out (unlimited airbrake) | 66.53s |
| flat_out_ab (heavy airbrake) | 70.92s |

Flat-out with *light* airbrake — full throttle, taps to rotate — is your technique, and it won. Assembly anchored on it, swapped 2 of 14 segments, and measured **62.65s**, within 0.03s of the theoretical splice. The line is stamped with its lap time and handling hash (`0c95eae5`).

**Gap to you: 0.75s (1.2%), down from 1.97s (3.2%).**

## A bug I introduced in v16 — please read

When I made trained lines always win in race mode, I didn't exempt the offline tools. So the style search's AI silently loaded the **existing** trained line instead of the one being tested, and every frame that line's style gains overwrote four parameters of the style under test: airbrake, steering reserve, sensitivity and lookahead. Only speed and line variations were actually being searched.

It showed up as `airbrake_max` and `no_airbrake` both scoring exactly 65.03s on circuit 7 — identical to baseline, where on circuit 3 they'd been four seconds apart.

**Fix:** `AIShipController.prefer_trained_line` (default true, which races want). The style search and trainer set it false, and the style search keeps the controller's own copy of the line in sync when switching styles. Verified: the AI now reports `passed line (tools)`, and the styles separate properly — `airbrake_max` 67.27s, `no_airbrake` 64.85s.

**What it affected:** any style search or trainer run on a track that already had a trained line, between v16 and now. Circuit 3's committed line was stamped with a lap time, which only v16+ does, so it was re-run in that window. Saved results were still genuinely measured and only saved if they beat the best single style — nothing wrong shipped — but the search was narrower than it should have been.

**Recommendation: re-run `tools/style_search.tscn` on all four circuits.** The fix and the flat-out styles may both help 3, 5 and 6. About 25 minutes.

## The analysis tool

```
godot --headless --path . res://tools/analyze_laps.tscn
godot --headless --path . res://tools/analyze_laps.tscn -- --track=test_circuit_7_live
```

For every track with current-handling human laps in the library, it drives the trained AI for a flying lap, records it with the same `LapRecorder` you use, and compares the two across 16 equal-distance sections: time, speed, lateral position, airbrake use, throttle. Plus a technique summary — % full throttle, airbrake %, mean speed — which is where flat-out first showed up. Reports go to `res://recordings_analysis/<track>_<ship>.txt`, so you can send them to me directly instead of the raw laps if that's easier.

AI laps from the tool never touch your own recordings.

## What's left on circuit 7, and the next fix

The analysis on the new line:

- **Section 4: the AI is now 0.50s *faster* than you** — flat at 119.8 where you did 111.7.
- **Section 12: still +0.85s.** The AI drops to 0.61 throttle and 87 there.
- **Section 9: +0.55s** — coupling from carrying speed out of section 8.

Section 12 has a precise cause. The segmenter cuts where styles agree on speed, and with flat-out in the mix there are long stretches where they never agree — so it produced one segment **2,302 metres long**, a third of the track. `no_ab_confident` beat flat-out over that whole stretch by 0.27s, so the swap was correct at that granularity, but it buries the one corner where flat-out gains 0.85s.

**Next fix: a maximum segment length**, forcing a split so flat-out can win only the part it's good at. Small change, and circuit 7 is the test case.
