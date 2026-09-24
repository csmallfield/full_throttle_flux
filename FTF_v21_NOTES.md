# Full Throttle Flux — v21: cinematic cameras (ported from MotorRig)

Extract at the **repository root**. One file replaced, one added. Requires v20.

```
full_throttle_flux/scripts/debug/cinematic_camera_rig.gd   NEW
full_throttle_flux/scripts/debug/ai_spectator.gd           Y cycles cameras
```

**Open the project in the editor once after extracting** — `CinematicCameraRig` is a new class and needs a global rescan.

---

## Using it

F9 as before, then **Y** cycles cameras, **shift+Y** goes back. The overlay shows which one is live. Everything else is unchanged: `[` and `]` still switch ships, and the rig follows.

```
chase -> cockpit -> heli -> front -> side -> flank -> bumper -> trackside
      -> crane -> drone -> lowchase -> pan -> tail -> orbit -> chase
```

Fourteen in the cycle. Switching ships while on a cinematic camera keeps that camera and re-points it, snapping so it never sweeps across the level.

## What was ported

All of them. Every camera is updated every physics tick whether or not it's on screen, exactly as in MotorRig, so switching never jumps and a camera you come back to has been tracking the whole time.

Four needed rethinking, because they were built around a car:

| MotorRig | here | why |
|---|---|---|
| `driver` (DriverCam node) | `cockpit` | FTF ships have no DriverCam; derived from hull bounds instead |
| `wheel` (front hardpoint, wheel radius) | `flank` | no wheels — rigid low mount on the left flank |
| `rearwheel` (rear hardpoint) | `tail` | same, at the back looking forward |
| `chase` (spring arm) | dropped | `AGCamera2097` already is the chase camera, and it's better here. It's first in the cycle instead. |

The rigid mounts use the ship's own transform, so they inherit the hull's bank and pitch — which on these ships is a lot more than a car's, and the flank and tail cameras get most of their character from it.

## Two things the port needed

**Velocity feedforward.** MotorRig's cars run at ~30 units/sec, where a first-order follow lags a couple of metres. These ships run at 120, and the lag is speed ÷ sharpness. Ported straight across, the measurements were wrong in a way that would have looked broken:

| camera | intended | as ported | fixed |
|---|---|---|---|
| front | ~15 ahead | **4.1** (being run over) | 14.8 |
| drone | ~12 behind | **49.1** (left behind) | 13.4 |
| side | ~10 | 24.0 | 10.3 |
| lowchase | ~11 | 24.9 | 11.4 |

Same fix as the game chase camera: add velocity before converging. Planted cameras (crane) opt out — their target doesn't move with the ship, so feedforward would only push them off their own plant.

**Distances scale with top speed as well as hull size.** MotorRig scales framing by vehicle size alone. A trackside camera planted 30m ahead of a 120 unit/sec ship is passed before it finishes panning, so plant distances and replant thresholds now also scale by `max_speed` against a 120 reference. Hull size still drives the rest: measured 6.7 units long here, giving a 1.34x scale on every distance and height.

## Verified

All 54 scripts compile. Every one of the 13 cameras produces a finite, sane transform on a moving ship on circuit 7 — distance, height above the ship, FOV and a valid orientation basis, checked 10 seconds into a lap.

**Not verified:** how any of it actually looks, and the Y key itself (no way to drive input headlessly). The numbers say the framing is right; whether `trackside` at 113 units with a 6.8° lens reads well on your tracks is a judgement only you can make.

## One tradeoff worth knowing

The rig runs in `_physics_process`, as MotorRig does, because the ground-clearance raycasts have to happen in the physics frame. At 60Hz physics on a higher-refresh display that means the cinematic cameras will judder slightly where `AGCamera2097` (which runs in `_process`) does not.

Two fixes, both now safe: enable `physics/common/physics_interpolation` in project settings, or raise the physics tick rate. The v8 time normalisation means raising the tick no longer changes the handling. Worth doing before capturing any footage with these.
