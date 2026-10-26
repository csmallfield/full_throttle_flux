# FTF v37.1: ship judder fix

The player ship juddered against the chase camera at any frame rate above
60. The track looked smooth, but the ship didn't fly smoothly. The bug dates
from v35, not v38. Branch `fix/ship-judder`, off main.

## Cause
- **The ship** (`ShipController`, a CharacterBody3D) moves only in
  `_physics_process`, 60 times a second. Physics interpolation was off, so it
  was drawn wherever the last tick left it.
- **The chase camera** (`AGCamera2097`) runs in `_process`, once per rendered
  frame. Since v35 it also leads the ship by `ship.velocity * delta`.
- So the camera glided while the ship jumped about 2 m per tick at racing
  speed. On screen the ship lurched forward and drifted back, about 60 times
  a second.

## Fix
- **Physics interpolation on** (`physics/common/physics_interpolation`), but
  **scoped to the ships:**
  - `GraphicsSettings` sets the scene root to OFF.
  - `ShipController` opts back in with ON; its mesh, thrusters and other
    children inherit it.
  - Everything moved in `_process` keeps its old behaviour, so none of it
    needed changing: cameras, the weather that follows the camera, greebles,
    FX.
- **`physics/common/physics_jitter_fix` set to 0**, as Godot recommends with
  interpolation.
- **The camera** reads `ship.get_global_transform_interpolated()` (via
  `_ship_xform()`) wherever it read the ship's transform. The camera itself
  is OFF, since it already moves every frame.
- **Placement resets:** `settle_on_surface()` (which runs after grid
  placement, respawn and the trainer's lap restart) and `respawn()` call
  `reset_physics_interpolation()`. The ship appears at its new spot instead
  of gliding over to it.
- **Dust** (`ShipDust`) emits from the drawn (interpolated) belly and brakes,
  not from the physics pose up to a tick ahead.
- **Unchanged:** the other per-frame readers of ship state (HUD, audio, FX
  LOD, the spectator's lap timer) use it for timing, levels or distances, not
  placement. Gameplay physics is untouched; interpolation only changes where
  things are drawn.

## Measured
`tools/dev/judder_probe.gd` runs an AI ship with the real chase camera,
records where the ship lands on screen every frame, and reports the RMS of
the frame-to-frame change in its screen motion. `JP_INTERP=0` gives the old
behaviour in the same build. RTX 3080, 60 Hz physics, vsync off.

| Track, render rate | Before | After |
|---|---|---|
| Builder Lab, 75 fps | 20.6 px | 0.21 px |
| Builder Lab, 144 fps | 30.8 px | 0.13 px |
| Builder Lab, 165 fps | 29.2 px | 0.10 px |
| Builder Lab, 240 fps | 25.2 px | 0.06 px |
| Utopia, ~140 fps | 35.3 px | 0.19 px |
| Hairpin Alley, ~113 fps (20 s) | | 0.52 px |

**What's measured:** the probe samples on `RenderingServer.frame_pre_draw`,
after every `_process`. An earlier version sampled on `process_frame`,
before the camera had moved, and read frame-pacing noise as judder.

## Not covered
- **A hand test at speed:** the probe measures the ship body's origin. The
  mesh's roll, pitch and rumble are set on physics ticks too, so they now
  interpolate, but only your eyes can judge them.
- **Ships on other cameras** (replays, spectator) would need the same
  `get_global_transform_interpolated()` treatment. There are none today.
