# Full Throttle Flux — v12: driving styles, per-segment assembly

Extract at the **repository root**. Two files replaced, two added. Requires v11.

```
full_throttle_flux/tools/style_search.gd              NEW
full_throttle_flux/tools/style_search.tscn            NEW
full_throttle_flux/scripts/ai/baked_racing_line.gd    per-sample style gains
full_throttle_flux/scripts/ai/ai_ship_controller.gd   applies style gains each frame
```

```
godot --headless --path . res://tools/style_search.tscn
```

Runs circuits 3, 5, 6 and 7. Saves the assembled strategy via the same trained-line path the v11 trainer uses, so `AIShipController` picks it up automatically.

---

## Circuit 3 result

| | lap |
|---|---|
| baseline (v11 defaults) | 53.62s |
| v11 trained | 53.17s |
| best single style (`no_ab_confident`) | 51.45s |
| **assembled strategy** | **50.93s** |

**5.0% faster than baseline, 4.2% faster than the v11 trained line.** For comparison, the whole trainer was worth 0.8%.

## The headline finding: v9 was wrong about airbrakes

The styles that reduce or remove cornering airbrake take the top four places. `airbrake_max` is close to the worst on the board.

| style | lap |
|---|---|
| no_ab_confident | 51.45s |
| no_ab_smooth | 51.58s |
| ab_last_resort | 52.03s |
| no_airbrake | 52.52s |
| baseline | 53.62s |
| airbrake_max | 56.25s |

In v9 I made airbrakes a cornering tool because the AI was cornering with half the player's yaw authority. That was true at the time. But once v10 gave it a minimum-curvature line, steering alone became largely sufficient, and the airbrake's scrub cost started outweighing the extra yaw. `corner_steer_reserve` at 0.80 was calling on it far too eagerly.

The evidence was already in hand and I misread it. Your recorded lap used **5% airbrake** against my AI's 20%. I took that as "the AI's line is worse so it needs more rotation" and fixed the line — correct, but only half the story. It also meant "airbrakes are expensive, and a good driver barely touches them."

**Caveat: this is one circuit.** Circuit 3 is the fastest and least technical of the four. It is entirely plausible that tighter tracks need the airbrake and this reverses — which is an argument for per-segment styles rather than a new global default. Run the tool on 5, 6 and 7 before changing any defaults.

## The sim is deterministic

53.617s vs 53.617s on a repeat run, delta 0.0000. One lap per style is sufficient — no repeats needed. That is what makes this whole approach cheap: 15 styles is about four minutes on circuit 3.

## Segmentation

Boundaries are placed where **speed variance across styles is lowest**, not at hand-labelled features. Segment times do not simply add up: the fastest way through a corner depends on the entry speed, so splicing style B's straight onto style A's corner hands A a state it has never driven. Cutting where every style agrees on speed — typically mid-straight near max — minimises that error, and it is a measurable criterion rather than a judgement call.

14 segments on circuit 3, and the winners are genuinely mixed: `flow` takes 3, `baseline` 3, `conservative` 2, `very_confident` 2, `ab_last_resort` 2. `airbrake_max`, second-worst overall, wins short tight segments outright. That is the "strong player switches technique by section" hypothesis showing up in data.

## Assembly is anchored, and that matters

The first version took the winner of every segment. Result: **52.03s**, against 51.45s for simply running the best single style everywhere, and against a theoretical 50.80s. The theory was optimistic by 1.23s and the splice actively *lost* 0.58s.

Assembly now anchors on the best single style — a lap actually driven end to end, carrying no splice risk — and only swaps a segment when another style beats the anchor there by more than `MIN_SEGMENT_GAIN` (0.08s). On circuit 3 that swaps 2 of 14 segments and produces 50.93s, within 0.13s of theoretical.

Every boundary is a chance for a style to inherit an entry speed it has never driven, so each swap has to pay for that risk rather than just edging ahead on paper. If you raise the swap count, expect the measured result to drift away from the theoretical one.

Style gains are blended over 40m at boundaries so parameters do not step mid-corner, and the spliced speed profile goes back through the baker's feasibility passes. Speeds are deliberately *not* smoothed — the anchor profile is already feasible and blurring it would change every segment rather than just the swapped ones.

The tool refuses to save an assembled line that fails to beat the best single style. A bad splice cannot ship.

## Runtime

`BakedRacingLine` now carries four optional per-sample arrays — `style_airbrake`, `style_reserve`, `style_lookahead`, `style_sensitivity` — plus a `style_log` recording which style won which segment. Values are absolute parameter values, not multipliers, so a line authored by one version of the tool cannot be silently rescaled by another. Empty arrays mean no style data and the controller keeps its own defaults, so every existing line still works unchanged.

`AIShipController._apply_style_gains()` reads them each frame from the current spline offset.

## One bug worth knowing about

The anchored assembly initially measured 52.10s, and I nearly concluded the whole approach was unsound. It was my own ordering bug: `_apply_style()` reassigns `follower.baked_line`, and I was calling it *after* installing the assembled line, so the follower drove the plain bake while the gains came from the assembled one. Fixing the order took it from 52.10 to 50.93.

Worth flagging because it is the failure mode of this design generally: the line and the gains must stay in sync, and nothing in the type system enforces it.

## Next

The obvious step is your step 5, which I have not done: feed the assembled strategy into the v11 hill-climb as a seed and refine the speed profile against the new technique mix. The trainer takes any `BakedRacingLine`, and the assembled one is now saved where it looks for it, so this should mostly work already — but I have not measured it, and the trainer will need to preserve the style gain arrays through its iterations, which I have not checked.

After that, the per-sample style gains are an obvious target for the same hill-climb: perturb `style_airbrake` and `style_reserve` continuously rather than adopting them in segment-sized blocks.
