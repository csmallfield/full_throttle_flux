# Full Throttle Flux — v14: line geometry variants

Extract at the **repository root**. Two files replaced. Requires v13.

```
full_throttle_flux/scripts/ai/ai_racing_line_baker.gd   apex shift, centre bias, rebuild_from_laterals
full_throttle_flux/tools/style_search.gd                geometry variants (opt-in), geometry crossfade
```

**Default behaviour is unchanged.** With `USE_GEOMETRY_VARIANTS = false` the style search reproduces v13's circuit 3 result exactly: 50.933s. Verified.

---

## The short version: it doesn't make the AI faster

You asked for per-segment line geometry. It's built, it works, and it costs lap time. I've left it off by default and kept it because your other reason for wanting it — variance between opponents — is where it genuinely pays.

## What was built

Two post-solve transforms on the baker, both cheap and both meaningful:

**`apex_shift_meters`** shifts the whole solved lateral profile along the track. This is early vs late apex, and it's almost free — the solver already knows *where* to be, this changes *when* it gets there. Positive delays the apex, trading entry speed for exit speed.

**`centre_bias`** pulls the solved line back toward the centreline. A slower, safer shape with more room for tracking error.

Both re-clamp to the corridor afterwards, so a shifted line can never end up inside a wall.

Plus `rebuild_from_laterals()`, which recomputes curvature and the whole speed profile for a line whose lateral offsets were changed externally. Necessary because a spliced shape is one that no variant actually solved, so its curvature belongs to none of them and the speeds must be derived fresh.

## What it measured

Circuit 3, as whole laps:

| variant | lap |
|---|---|
| min-curvature (current) | **51.45s** |
| centre_safe (bias 0.35) | 52.95s |
| apex_early | 54.40s |
| shortest_path (elastic band) | 56.45s |
| apex_late | 58.12s |

Every geometry variant is substantially slower than the min-curvature line. They *do* win individual segments — `shortest_path` took 3, `apex_late` and `apex_late_conf` one each — but splicing them in produced **51.27s against 50.93s** for assembling control styles alone.

The disruption at a geometry boundary costs more than the better local shape gains. That's consistent with everything else we've found: the min-curvature solver was the single biggest win in this whole sequence, and deviating from it locally doesn't pay.

## A bug worth recording

The first geometry splice measured **63.95s** — a 24% regression — and I briefly thought the concept was unsound. It wasn't.

My crossfade blended each sample toward a straight chord joining the two sides of every boundary. With 14 boundaries and a 120m window that flattened roughly half the track's apexes toward chords. The fix interpolates between the two *source geometries evaluated at the same sample*, so the result is always a genuine blend of two solved lines and is never flattened, with smoothstep weighting so there's no kink at the seams. It also skips boundaries where the style doesn't actually change.

That took it from 63.95s to 51.27s. The remaining 0.34s deficit against v13 is the real cost of geometry splicing, not a bug.

Worth noting for the variance work: **any blend of two racing lines needs to be a blend of the lines, not a blend toward the geometry between them.** The naive version is very wrong and doesn't look obviously wrong in code.

## Why this is still the right groundwork for variance

You said geometry variation would matter later for creating variance between opponents, and I think that's where its value actually is. What you now have:

- Four distinct, drivable, measurably different line shapes, all corridor-clamped and all producing valid speed profiles.
- A spread of roughly 7 seconds across them on circuit 3 (51.45s to 58.12s) — that is a usable difficulty and personality range without touching ship performance, which keeps your "AI ships have no performance advantage" guarantee intact.
- A working crossfade, so an opponent can transition between shapes mid-lap rather than being locked to one.

`apex_late` at 58.12s isn't a bad line — it's a *different* line, and a field where one opponent habitually turns in late and another hugs the shortest path will read as different drivers rather than the same driver with a handicap multiplier.

## To turn it on

Set `USE_GEOMETRY_VARIANTS = true` at the top of `tools/style_search.gd`. The six variants in `GEOMETRY_STYLES` join the search, the assembly splices geometry where a variant wins a segment, and the line is rebuilt and re-measured. It will save only if it beats the best single style, as always.

## Where I'd look next for pace

Not geometry. The two observations that still stand out:

- The styles that win most often are both "raise cornering confidence", which says that axis is under-sampled. There is probably a better value between 1.10 and 1.20, and it likely differs by segment. That's a one-line change to the style menu and costs one run.
- 14 segments over 7100m averages 500m each. Finer segmentation means more swap opportunities, but circuit 6 already showed the splice cost is real, so it would need measuring rather than assuming.

Against your circuit 7 lap the AI is at 63.93s to your 63.12s. The remaining 1.3% may simply be the last bit that a hand-tuned search doesn't reach.
