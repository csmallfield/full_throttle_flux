# Full Throttle Flux — v13: assembled strategies for all circuits

Extract at the **repository root**. Three scripts replaced, three data files added. Requires v12.

```
full_throttle_flux/scripts/ai/ai_line_trainer.gd    gain training (off), seeding support
full_throttle_flux/tools/train_ai_lines.gd          seeds from existing trained lines
full_throttle_flux/tools/style_search.gd            zero-swap passthrough fix
full_throttle_flux/resources/ai_data/test_circuit_3_live_default_racer_trained_line.tres
full_throttle_flux/resources/ai_data/test_circuit_5_live_default_racer_trained_line.tres
full_throttle_flux/resources/ai_data/test_circuit_7_live_default_racer_trained_line.tres
```

**The three `.tres` files are generated output, keyed to the current `default_racer.tres`.** If you have changed any handling value, delete them and re-run `tools/style_search.tscn` (~25 minutes for all four circuits). They are included so you get the improved AI without waiting.

Circuit 6 is deliberately absent — see below.

---

## Results, all four circuits

| circuit | v11 trained | v13 | gain |
|---|---|---|---|
| 3 | 53.17s | **50.93s** | 4.2% |
| 5 | 72.77s | **71.70s** | 1.5% |
| 6 | 66.62s | 65.43s* | 1.8% |
| 7 | 64.53s | **63.93s** | 0.9% |

\* circuit 6's assembled line was refused (see below); the 65.43s is available by running its best single style.

**Circuit 7 is 63.93s against your recorded 63.12s. The AI is within 1.3% of you**, from 12.5% off at v8.

## Correction: the airbrake finding was overstated

Last round I told you "v9 was wrong about airbrakes" based on circuit 3. Across all four, circuit 3 is the outlier. Winning anchors:

| circuit | anchor style | airbrake |
|---|---|---|
| 3 | `no_ab_confident` | off |
| 5 | `confident` | default |
| 6 | `very_confident` | default |
| 7 | `confident` | default |

On three of four circuits the winner **keeps the default airbrake** and wins by raising cornering confidence instead. Circuit 3 is the fastest and least technical track and the only one where removing the airbrake helps.

Had I acted on that as a global default change — which is what I was proposing — I would have made three circuits slower on one circuit's evidence. The per-segment style mechanism is what makes this safe: the answer genuinely differs by track, and now it differs by *section* too.

## Circuit 6 produced a clean negative, and the guard caught it

Zero of 14 segments beat the anchor by the 0.08s swap threshold, so the assembly was the anchor with nothing swapped — and it still measured 0.1s slower (65.53s vs 65.43s).

That 0.1s was mine: with no swaps, assembly still re-ran the feasibility passes using uniform segment lengths where the baker had used measured ones, which perturbs the profile slightly. Fixed with a passthrough when `swaps == 0`.

The important part is that `style_search` refused to save it. A splice that fails to beat the best single style cannot ship, and that guard fired before I found the bug. Re-run circuit 6 with this patch and it should save.

## Speed refinement is exhausted

Seeding the v11 trainer from the assembled circuit-3 line confirmed three things:

- Style gains survive training intact (the trainer only rewrites `target_speeds`).
- Iteration 1 reproduces 50.933s exactly — the gains really are being applied, and the sim remains deterministic.
- Every subsequent perturbation was reverted.

The speed profile is at a local optimum once style assembly is in place. `tools/train_ai_lines.gd` now seeds from an existing trained line instead of always baking fresh, so running it after a style search refines rather than discards.

## A dead end, recorded rather than deleted

Since speeds were exhausted, I extended the hill-climb to perturb the per-sample style gains directly — more airbrake and less steering reserve where the ship runs wide, the reverse where it tracks clean.

**It was measured and it does not work.** Enabled, every perturbation came out worse than perturbing speeds alone: 53.02s against 51.33s on the equivalent iteration, all reverted. The likely reason is that the style search already chose those gains per segment from measured laps, so a blind nudge based on tracking error steps *away* from a measured optimum rather than toward one.

It ships behind `train_style_gains = false`, correctly wired into the revert bookkeeping, with that measurement in the comment. Don't enable it expecting a win — but it's cheap to re-test if the style menu or the error attribution changes.

## Where the remaining 1.3% might be

Against your circuit 7 lap, honestly assessed:

- **More styles.** 15 is a small menu and it was hand-written. The two that win most often are both "raise confidence", which suggests the confidence axis is under-sampled — there is probably a better value between 1.10 and 1.20, and it likely differs by segment.
- **Finer segmentation.** 14 segments across 7100m averages 500m each. More segments means more swap opportunities but also more boundaries to lose time at, and circuit 6 shows the splice cost is real.
- **Line geometry per segment.** Every style shares one line shape per confidence value. The min-curvature solver was worth more than anything since, and nothing yet varies the *line* by section.

I'd put the last one first if you want to keep going. It's also the hardest.
