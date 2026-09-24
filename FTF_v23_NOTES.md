# Full Throttle Flux — v23: six second shots

Extract at the **repository root**. One file replaced. Requires v22.

```
full_throttle_flux/scripts/debug/cinematic_camera_rig.gd
```

---

## Measured

| camera | v22 | now |
|---|---|---|
| trackside | 9.7s | **5.7s** |
| crane | 13.6s | **6.2s** |
| pan | 13.6s | **6.8s** |

Mean distance from the ship dropped with them: trackside 236 → 192, crane 250 → 218, pan 341 → 287.

## The "further away" feeling

Nothing had moved except height, and you were right to notice anyway — the cause was the shot length itself. A planted camera's whole shot is the ship approaching, passing, then receding, so a 13 second shot spends most of its length with the ship far off, whatever the lens does. The distances above are the same fix as the durations.

Two things came in alongside:

- **Plant leads reduced.** Trackside and crane were planting up to 190–260 units ahead, so the ship spent the first seconds arriving from a long way off. Now ~1.5 seconds of approach (`trackside_lead_factor`, `crane_lead_factor`, both 1.5).
- **Minimum lens widened back** from 4° to 6° on trackside and pan. A 4° lens is a ~700mm equivalent — it makes a distant subject large, but the compression reads as *watching from far away*, which is exactly what you described.

Crane rise is now 3.5s (was 4.5) so the move still completes comfortably inside a 6 second shot, and the rise height came down from 22 to 18, since a high angle is steeper when the camera is closer.

## One thing worth knowing if you tune these further

The hold values are **straight-line** ranges, but on a track that curves the ship's distance from a plant grows much more slowly than the distance it drives. My first attempt used arithmetic — 470 units at 105 units/sec should be about 4.5 seconds — and measured 8.5. The values that shipped were arrived at by measuring, not calculating.

So if you want to change a shot length, scale the range by the ratio you want rather than converting from speed. Halving `trackside_max_range` roughly halves the shot.

All three cameras are exported in their own inspector groups. `*_hold_past` controls how long it holds after the pass, `*_max_range` is the hard cut, and whichever is smaller wins — on these tracks it's usually `max_range`.
