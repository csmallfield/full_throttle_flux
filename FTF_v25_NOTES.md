# Full Throttle Flux — v25: ten wild cameras

Extract at the **repository root**. One file replaced. Requires v24.

```
full_throttle_flux/scripts/debug/cinematic_camera_rig.gd
```

23 cameras now. The original 13 come first in the Y cycle, the new ten after, so nothing you already use moves.

---

## The new ten

| name | what it does |
|---|---|
| **handheld** | Operator at the track edge on an 82° lens. Never steady, and the aim runs through an underdamped spring so it overshoots the ship and settles back instead of tracking cleanly. Passes within 3 units. |
| **overtake** | Russian arm that comes up from behind, draws level, pulls ahead, drops back. Lens widens to 62° alongside and tightens to 34° as it falls away, so the pass reads as a pass. 7s per cycle. |
| **kamikaze** | Planted up to 430 units up the road, then flown straight at the ship at closing speed. Measured 314 units down to an 11-unit near-miss, then it replants ahead. |
| **vertigo** | Dolly and zoom in opposite directions. Measured distance 12→55 while the lens counter-moves 54°→15°, so the ship holds its size in frame and the track behind it stretches and compresses. Reverses every 5s. |
| **roadkill** | Sitting on the track surface, almost in the racing line, on a 96° lens. The pan rate scales with closeness, so it whips as the ship arrives and can't keep up. Passes within 3 units. |
| **helilost** | A helicopter that keeps losing the ship. Drifts ahead, gets left behind when the ship pulls away, then hauls back on. Follow rate drops to 0.12 during the loss and jumps to 2.6 to recover. |
| **whip** | Parked close to the racing line, dead still on a 74° lens, then snaps through the pass at a rotation rate no real operator could manage. |
| **crashzoom** | Chase position, punched 70°→25° in a quarter second every 3.5s and eased back out. The move is the point, not the framing. |
| **skim** | A hand's width off the surface right behind the ship, on the widest lens in the rig at 94°. All speed, nothing readable. |
| **crossing** | Cable cam strung across the track at its own constant speed. Sometimes it meets the ship, sometimes it misses — which is the interesting part. |

## Tuning

New inspector group, **Wild cameras**: `handheld_shake`, `overtake_period`, `kamikaze_closing_bonus`, `vertigo_period`, `crashzoom_period`, `helilost_period`.

The one new mechanism is `_spring()` — an underdamped spring that overshoots and settles, used for the handheld aim. It's there for any camera that should feel operated rather than driven by maths; raise its damping toward 1.0 to calm a camera down, drop it to make one hunt.

## Verified

All 23 cameras produce finite, sane transforms across a 68-second lap on circuit 7: **zero invalid frames**. Distance and lens ranges measured per camera; the figures quoted above are from that run.

**Not verified:** how they look. The numbers say the moves are doing what they should, but which of these are keepers is entirely your call.

## Two things you may want to change

**The cycle is now 23 long.** Stepping to `crossing` means 22 presses of Y. If that gets tiresome, an obvious addition is a second key that jumps straight to the start of the wild set — the split is clean, index 13 onward. Say the word.

**`overtake` ranges wider than intended**, out to 74 units at the extremes of its pass against a design figure nearer 60, because the follow lag adds to the programmed offset. It still looks like an overtake; it just swings further out than the numbers suggest. Lower `overtake_period` to tighten it, or I can compensate the offset directly.
