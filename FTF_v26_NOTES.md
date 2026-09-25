# Full Throttle Flux — v26: wild camera revisions + fisheye

Extract at the **repository root**. Two files replaced. Requires v25.

```
full_throttle_flux/scripts/debug/cinematic_camera_rig.gd
full_throttle_flux/scripts/debug/ai_spectator.gd    supplies the track spline
```

24 cameras now.

---

## The rig can see the track now

Several of your notes came down to the same root cause: the rig only knew where the *ship* was, never where the *track* was. It now takes the spline helper from the AI, which fixed three of the requests directly.

## Your notes

**handheld — clamped.** Plants are pulled back toward the centreline. Measured worst case went from unbounded (wandering into scenery) to 16.5 units. I set the clamp at 6× hull rather than 9×, because height on a banked section adds to the measured lateral, so 9 was still reading out near 20.

**kamikaze — now flies the spline.** It walks *backwards along the track* against race direction, so it follows the racing surface through corners instead of flying into the wall on the outside. Take length is an export (`kamikaze_take_seconds`, 4.6s) and the plant distance is computed from closing speed so **contact lands mid-take** with roughly two seconds either side. Measured a 2.1-unit near-miss and a 500-unit start.

**vertigo — slower and varied.** Period 5s → 8s, and each take approaches from a different angle: behind, ahead, side, three-quarter, overhead.

**roadkill — actually on the track.** Its lateral offset now comes from the spline rather than from the ship, so it sits on the racing surface even when the ship is running wide. Measured max 3.3 units off centreline, against being reliably outside the track before.

**helilost — softer.** Lead and follow-rate both move on cosine curves now instead of stepping between two values. That step was the abruptness you saw.

**crashzoom — holds added, frontal angles.** Punch in over 0.35s, **hold tight ~1.9s**, punch out, hold wide ~2.2s. Period 3.5s → 5s. Angles cycle through frontal and three-quarter only, which is where a zoom punch has something to push into.

**skim — moved to the front.** Now ahead of the ship looking back, sliding between four positions (low centre, both quarters, above) every 4.5s. Transitions, not cuts.

**fisheye — new.** Hard-mounted on the nose looking back down the hull at 118°. Four mounts: on the deck looking up, both three-quarters, and above looking down, blending every 3.5s so the hull swings through frame.

## Verified

24 cameras, **zero invalid frames** over a 68-second lap on circuit 7. Distance, lens and distance-off-centreline measured per camera.

One bug the measurements caught: walking the kamikaze camera backwards past the start of the spline returned a *negative* offset, which my code read as "no spline position" and produced an infinite camera distance. Wrapped now.

**Not verified:** how any of it looks.

## Two you may still want to look at

**`whip` passes within 1.2 units** of the ship — dramatic, but close enough that it may clip through the hull on some passes. Easy to back off if it does.

**`overtake` still swings to 74 units** at the extremes, unchanged from v25, since you didn't flag it. Say the word if it bothers you.
