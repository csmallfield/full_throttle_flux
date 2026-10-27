# FTF v37.2: judder on the cinematic cameras

v37.1 fixed the chase camera, but the spectator's cinematic cameras
(`CinematicCameraRig`, cycled with the spectator's camera key) still
juddered, worst when the frame rate dropped.

## Cause
The rig moves all its cameras in `_physics_process`, and they inherited
physics interpolation OFF from the root (v37.1 turns the root off and only
the ships on). So every rig camera stepped once per physics tick, while
the ship in front of it was drawn smoothly every frame:
- above 60 fps, the camera stood still for some frames while the ship moved;
- when the frame rate dipped, some frames carried two ticks and others none,
  so the steps got bigger and less even. That's the "strong judder at the
  moments the frame rate drops".

## Fix (`scripts/debug/cinematic_camera_rig.gd`)
- **The rig is physics-interpolated** (`PHYSICS_INTERPOLATION_MODE_ON`), so
  Godot draws its cameras between ticks on the same timeline as the ships.
  Where each camera goes on each tick is unchanged.
- **Cuts aren't interpolated.** A camera that moves further than 3x the
  ship's move plus 3 m (x hull scale), or turns more than 0.6 rad, in one
  tick has replanted (trackside, crane, pan leapfrogs and so on): its
  interpolation is reset, so it appears at the new spot instead of sliding
  there over one tick. `snap()` resets every camera.
- **The active camera's FOV is blended per frame** between its last two
  tick values. Physics interpolation doesn't cover FOV, so the zooming
  cameras (trackside, crane, pan, crashzoom) still stepped at 60 Hz.

## Measured
`tools/dev/judder_probe.gd` now takes `JP_CAM` (a rig camera), `JP_FX`
(FX quality for the run, never saved) and `JP_HITCH` (random busy frames of
up to N ms, to force frame-rate drops). It projects through where the
camera is drawn, skips frames where the ship is behind the camera or well
off screen, and prints percentiles so a planted camera's cuts don't
dominate. Builder Lab, FX high, uncapped (about 300 fps; about 150 with
25 ms hitches), 60 Hz physics, RTX 3080. p90 of the frame-to-frame change
in the ship's screen motion:

| Camera | Before | After | Before, hitches | After, hitches |
|---|---|---|---|---|
| side | 302 px | 0.15 px | 334 px | 0.52 px |
| orbit | 146 px | 0.29 px | 156 px | 1.13 px |
| drone | 96 px | 0.10 px | 100 px | 0.51 px |
| lowchase | 54 px | 0.05 px | 61 px | 0.29 px |
| trackside | 91 px | 3.0 px | 95 px | 11.5 px |
| crane | 50 px | 2.6 px | 55 px | 13.1 px |
| pan | 52 px | 3.0 px | 60 px | 14.3 px |
| chase (v37.1, unchanged) | | 0.05 px | | 0.4 px |

- **What's left on the planted cameras** is mostly real. A long lens close to
  a passing ship moves it a long way across the screen in a 25 ms frame, and
  the per-frame metric counts uneven frame times as judder even when the
  motion is smooth in time.
- **Placement is unchanged:** `tools/dev/cine_rig_probe.gd` gives identical
  per-camera stats before and after on Loop Lab, and on Builder Lab with
  snaps and camera cycling every 97 ticks.

## Not covered
- **A hand test in the spectator** at high FX and shadows.
- **The cut threshold is a heuristic.** A replant shorter than about 3x the
  ship's per-tick move is drawn sliding over one tick (16 ms).
