# Full Throttle Flux — v27: kamikaze, crossing, fisheye pair

Extract at the **repository root**. One file replaced. Requires v26.

25 cameras now — `fisheye_rear` is appended at the end of the cycle.

---

## Your notes

**kamikaze — was flying under the track.** It took its position straight from the spline, and a spline is a *centreline, not a surface*: on elevation changes and banked sections its point sits well below the track. Every other camera clears the ground; this one never did, which is why it worked near the ground and saw nothing elsewhere. Measured across a lap: minimum height above the surface now **3.21 metres, zero frames below**.

**crossing — slower and higher.** The crossing rate went from 0.33 to **0.14**, roughly seven seconds instead of three, so it reads as a crossing rather than a flyby. Height 6.5 → 12 with clearance raised 4 → 9. Measured minimum height **9.00, zero frames below** — it was catching the track on climbs before.

**fisheye — more standoff.** Mounts stand off the hull about 1.9x further. Measured distance went from 2.8–3.4 to **4.5–6.7**. It's a single `fisheye_standoff` export, so you can dial it from there without touching the four mount positions.

**fisheye_rear — new.** Same idea mounted behind the tail looking forward up the hull, 118°, four mounts blending every 3.5s. Its cycle is offset by half a period from the front unit, so the two are never on the same mount at the same time — worth having if you ever cut between them.

## A bug the measurements caught

**skim was spending 55 frames a lap up to 3 metres under the track**, and you hadn't reported it — presumably because it reads as a flicker rather than an obviously broken shot.

The cause is subtle and worth knowing, because it applies to any low camera added later. Clearing the ground on the *target* position isn't enough: `_place()` then smooths toward that target from wherever the camera was, and the interpolated point can sit below the surface even though both ends are above it. Cameras placed through `_look()` are immune, since they're written directly rather than interpolated.

`_place()` now takes an optional `clear_after`, which re-applies clearance to the *smoothed* position. Enabled on `skim` and `lowchase`, the two low ones. Both now measure a minimum height of exactly 0.30, their configured clearance, with zero frames below.

## Verified

25 cameras, zero invalid frames over a 68-second lap on circuit 7. Ground clearance sampled per frame for every camera that runs near the surface.

**Not verified:** how it looks.

## New exports

`crossing_rate`, `crossing_height`, `crossing_clearance`, `fisheye_standoff` — all in the **Wild cameras** group.
