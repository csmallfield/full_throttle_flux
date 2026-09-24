# Full Throttle Flux — v22: clean view and camera tuning

Extract at the **repository root**. Two files replaced. Requires v21.

```
full_throttle_flux/scripts/debug/cinematic_camera_rig.gd   shot lengths, heights, orbit ramp
full_throttle_flux/scripts/debug/ai_spectator.gd           H = clean view
```

Every value below is an `@export`, grouped by camera in the inspector, so you can tune them without me.

---

## 1. Clean view — H

Hides every visible `CanvasLayer` in the tree: race HUD, debug HUD, now-playing display, and the spectator overlay itself. H again restores them.

Only layers that were visible get remembered, so turning it off never switches on something that was already hidden — a pause menu or the results screen stays hidden. The overlay also stops refreshing while clean, so it costs nothing during a capture.

## 2–4. Shot lengths and heights

The distances were the wrong thing to reason about. What matters is how long a shot lasts, and these ships cover ~105 units/sec on circuit 7, so I measured cut frequency over a full lap and worked backwards.

| camera | before | after | height above ship |
|---|---|---|---|
| trackside | 3.1s | **9.7s** | 0.7 → 10.6 |
| crane | 2.8s | **13.6s** | 12.1 → 21.0 |
| pan | 4.9s | **13.6s** | 10.5 → 12.9 |

The crane was the worst of the three: it replanted after 2.8 seconds while its rise takes 4.5, so **the move never once completed** — you were only ever seeing the first two thirds of a crane-up, then a cut.

Two things this surfaced that you couldn't have known to ask for:

**The crane now zooms.** Trackside and pan already adapted their lens to distance; the crane had a fixed 42–50°. Once it holds for 13 seconds the ship covers a long way — measured 717 units out, still on a 42° lens, so the shot ended on a speck. It now tightens as the ship recedes, same as the others.

**Pan needed trimming back.** My first pass gave it a 34-second hold, which sounds right for a locked tripod but ended with the ship invisible even at the narrowest lens. Settled at ~13s.

I also opened the minimum lens on trackside and pan from 6°/8° to 4°, so they can hold a distant subject properly.

## 5. Orbit speed ramp

The orbit eases between a slow drift and a fast sweep instead of turning at one constant rate. Measured **0.15 to 1.10 rad/s**, cycling every ~3 seconds. Previously a flat 0.25.

Three exports control it: `orbit_speed_min`, `orbit_speed_max`, `orbit_ramp_rate` (cycles per second). Raising the max makes the fast part whip past; lowering the ramp rate makes each phase last longer.

## Verified

All 54 scripts compile. Cut frequency, heights, lens angles and orbit rate all measured over a 68-second run on circuit 7 with the AI driving.

**Not verified:** how it looks, and the H key itself — I still can't drive input headlessly.

## Note on your spectator changes

Your copy had diverged from mine: the QWERTZ handling that matches both `keycode` and `physical_keycode` (Y and Z swap on a German layout), the comma/period alternatives for ship switching, and gamepad support. I patched around all of it rather than replacing the file, so those are intact — worth a quick diff on your side to confirm.
