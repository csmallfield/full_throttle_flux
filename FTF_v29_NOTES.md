# Full Throttle Flux — v29: velocity-buffer motion blur

Camera and per-object motion blur from Forward+'s velocity buffer, as a
`CompositorEffect`. This is option 1 from the plan. The radial speed blur
(option 3) is still to come, as a boost effect and a low-spec fallback.

## Files

| File | What |
|---|---|
| `scripts/rendering/motion_blur_effect.gd` | `MotionBlurEffect`: the CompositorEffect |
| `shaders/motion_blur/mb_prep.glsl` | Pass 1: colour + linear distance, blur radius per pixel |
| `shaders/motion_blur/mb_tile_max.glsl` | Pass 2: largest radius per tile |
| `shaders/motion_blur/mb_neighbor_max.glsl` | Pass 3: largest radius in the 3×3 tile neighbourhood |
| `shaders/motion_blur/mb_gather.glsl` | Pass 4: depth-aware reconstruction gather |
| `scripts/rendering/motion_blur_profiler.gd` | `MotionBlurProfiler`: GPU timing hook (real hardware) |
| `tools/dev/mb_profile.gd` | Automated on/off A/B GPU profile of a live AI race |
| `tools/dev/render_motion_shots.gd` | Moving-camera shot harness, also renders frame sequences |
| `tools/dev/mb_metrics.py` | Measures "ship sharp, world streaks" from harness renders |

Also changed:

- The three lighting scenes (Utopia, Hairpin, Swoopy) and `utopia_lighting_builder.gd`: motion blur is first in the compositor, god rays second.
- `ag_camera_2097.gd`: drives the speed fade and flags camera cuts.
- `render_shots.gd`: finds the god rays by type instead of `compositor_effects[0]`.

## How it works

`needs_motion_vectors = true` makes Forward+ render its velocity buffer. The effect runs at `POST_TRANSPARENT`, so it works in HDR after transparents and before glow, tonemap and SMAA. In the compositor it comes before the god rays, so the rays stay crisp.

The filter is McGuire et al. 2012 ("A Reconstruction Filter for Plausible Motion Blur"). It adds the tile jitter and the second sampling direction along the centre pixel's own motion from Guertin/McGuire 2014. Each tap counts if:

- the tap is in front and its own blur reaches the pixel, or
- the tap is behind and the pixel's blur reaches the tap, or
- both are blurry and overlap.

A sharp foreground therefore neither smears nor gets smeared. That is why the ship stays crisp while the world streaks past it.

### Engine facts, checked against the 4.7.1 source and measured

- **Velocity convention:** `prev_uv - cur_uv`, where `uv = clip.xy * 0.5`. One unit is the full screen per axis, in texture space with y down, and TAA jitter is removed. In the harness, a diagonal camera strafe measured (0.00137, −0.00122) against an expected (0.00136, −0.00121), so the sign, scale and y-orientation are confirmed.
- **Linear distance from `get_view_projection()`:** `p32 / (d + p22)` (reverse-Z). At the screen centre it read 46.8 m against a physics raycast of 47.1 m.
- **MSAA:** with `needs_motion_vectors`, Forward+ resolves the MSAA velocity with `texture_resolve_multisample`, which averages the samples. The depth resolve (`resolve.glsl`, `MODE_RESOLVE_DEPTH`) also averages. A silhouette pixel therefore gets about half the background's velocity at an in-between depth, and without a fix it would smear the ship's edge colour into the streaks. With MSAA on, `msaa_edge_fix` makes depth-edge pixels take the velocity and depth of their closest 3×3 neighbour, so the anti-aliased edge stays with the foreground.
- **Temporal upscaler (FSR2):** Forward+ switches to a separate motion pass. Static geometry is then cleared to a (−1, −1) sentinel, and only moving objects write velocity. The prep pass catches the sentinel and reprojects camera motion from depth, using last frame's view-projection.
- **Sky:** Forward+ never writes velocity for the sky. Sky pixels (far plane and zero velocity) are reprojected at the far plane, so they streak with camera rotation but not translation (`sky_velocity`).
- **Transparents** (cloud sea, neon) write no velocity. They blur with whatever opaque surface is behind them, which is acceptable as briefed.
- **Disabled effects** are skipped when the engine decides whether it needs motion vectors. Turning the blur off therefore also drops the velocity pass.

## Parameters (`MotionBlurEffect`)

| Param | Default | Notes |
|---|---|---|
| `blur_enabled` | on | Authoring switch. The built-in `enabled` is derived from this and the user settings. |
| `intensity` | 1.0 | Multiplies streak length. |
| `shutter_angle` | 180° | Fraction of the frame exposed. |
| `timing` | NORMALISED | NORMALISED = as if every frame lasted 1/`reference_fps`. PHYSICAL = real exposure of the actual frame time, so blur shrinks as fps rises. |
| `reference_fps` | 60 | |
| `max_blur_px` | 40 | Full streak length at 1080p; scales with render height. |
| `tile_size` | 20 | Automatically raised to at least the max blur radius, which the 3×3 neighbourhood requires. |
| `samples` | 12 | Gather taps per pixel, only where something blurs. |
| `fade_start` / `fade_full` | 0.2 / 0.6 | Speed-ratio fade-in, driven by `MotionBlurEffect.speed_ratio`. |
| `cut_distance` / `cut_angle_deg` | 30 / 40° | A bigger camera jump in one frame counts as a cut and that frame isn't blurred. |
| `sky_velocity`, `depth_softness`, `msaa_edge_fix`, `animate_noise`, `editor_preview` | | See the tooltips. |
| `debug_view` | OFF | VELOCITY / NEIGHBOUR_MAX / DISTANCE. |
| `debug_stats` | off | Async read-back into `MotionBlurEffect.last_stats`. |

### Game hooks (statics, no reference to the effect needed)

```gdscript
MotionBlurEffect.set_user_settings(enabled, intensity_0_to_1)  # settings slider; off = no velocity pass
MotionBlurEffect.speed_ratio = ship.get_speed_ratio()           # AGCamera2097 does this every frame
MotionBlurEffect.notify_camera_cut()                            # respawn / teleport / hard cut
```

`AGCamera2097` sets `speed_ratio` before its intro branch, so there is no blur while the ship sits on the grid. It calls `notify_camera_cut()` from `_snap_to_ship()` and resets the fade on `_exit_tree`. No settings UI is wired yet: there is no video settings menu, only the volume sliders in the pause menu.

## Testing

GPU timing can't be measured in the container (lavapipe). Everything below is correctness and look.

### Harness

```
SHOTS_NO_MSAA=1 xvfb-run -a -s "-screen 0 1920x1080x24" \
  godot --path . -s res://tools/dev/render_motion_shots.gd -- shots.json out/ res://scenes/tracks/test_circuit_6_live.tscn
python3 tools/dev/mb_metrics.py out/
```

The harness flies the camera and ship (and optional AI ships) along the trained racing line for a few frames before capturing. `debug_frame_dt` pins the effect's frame time to the authored 1/60 s, because lavapipe renders far slower than real time.

Shot options:

- `render_hz` / `physics_hz`: simulate the ship moving only on physics ticks.
- `strafe`: velocity calibration.
- `sequence`: save every frame, for video.
- `mask`: flat white ship silhouettes, used by the metric.

### Results

`mb_metrics.py`: mean |on − off| inside the ships' exact silhouettes (eroded 2 px) against everywhere else (8 px away from the ships). 0–255 scale; ship ≈ 0 means untouched.

| Shot | Ship diff | World diff | Ship / world |
|---|---|---|---|
| Hairpin city straight | 0.00 | 8.84 | 0.00 |
| Hairpin + 2 AI ships (same speed, +4 %) | 0.00 | 8.79 | 0.00 |
| Hairpin corner (chevrons) | 0.01 | 6.66 | 0.00 |
| Utopia light strips | 0.00 | 5.66 | 0.00 |
| Utopia + 2 AI ships (same, +5 %) | 0.25 | 5.51 | 0.04 |
| Hairpin, MSAA 2× (lavapipe, empty depth) | 0.20 | 8.89 | 0.02 |
| **Hairpin, 144 Hz render / 60 Hz physics, NORMALISED** | **15.56** | 9.00 | **1.73** |
| **Same, PHYSICAL** | **10.61** | 4.95 | **2.14** |

The +5 % AI ship is meant to blur slightly; it moves relative to the camera. The 144 Hz rows are the problem described below.

A 5-second Hairpin flythrough (tunnel, gantry, corner, 3 AI ships) was rendered frame by frame with the `sequence` option and encoded with ffmpeg, both blur-on and stacked off/on.

Readability (side-by-side stills on all three tracks):

- **Hairpin Alley:** the gantry arrows and the corner billboards stay fully readable; they are far away and move slowly on screen. The wall chevrons smear only where they are closest to the camera, and still read as arrows. Ground markings right in front of the camera smear into bands, which is the strongest blur on screen and physically right.
- **Swoopy:** gallery and catwalk scaffolding overhead streaks smoothly instead of strobing frame to frame. The structure still reads. The sky barely moves (rotation only).
- **Utopia:** the ceiling light strips stay readable; they mostly streak along their own length. Near wall panels smear.

### Ship sharpness above 60 Hz (needs a decision)

At 60 Hz render with one physics tick per frame, player and AI ships at similar speed stay sharp. AI ships being passed or passing blur by their relative motion, which is correct.

At 144 Hz render with 60 Hz physics, the player ship smears badly. The cause:

- `AGCamera2097` runs in `_process`.
- The ship (and its `ShipMesh` bob) only moves in `_physics_process`.
- Physics interpolation is off.

So on frames without a physics tick the camera moves and the ship doesn't, and on tick frames the ship jumps. That jump is real screen-space motion of the ship relative to the camera, and the velocity buffer records it. The blur doesn't cause the problem; it makes an existing above-60 Hz ship judder very visible. NORMALISED timing amplifies it (×2.4 at 144 Hz); PHYSICAL is milder but the same in kind.

Recommended fix, as its own PR, because it touches gameplay-wide transforms:

1. Set `physics/common/physics_interpolation = true`.
2. In `AGCamera2097`, read `ship.get_global_transform_interpolated()` and set its own `physics_interpolation_mode` to OFF (it is driven in `_process`).
3. Call `reset_physics_interpolation()` on respawn and teleport.

This should also cure the existing ship judder on high-refresh displays without blur. The cinematic camera rig (`_physics_process`) would then interpolate for free.

At exactly 60 Hz there can still be an occasional frame with 0 or 2 physics ticks, which gives a one-frame ship smear. Interpolation fixes that too.

### Known limitations

- **Shadows and other screen-space-stationary lighting on moving surfaces** blur with the surface. Example: the ship's own shadow on the track, which barely moves on screen but sits on fast-moving ground. This is inherent to velocity-buffer blur.
- **Velocity is per frame (one sample).** Curved motion within a frame becomes a straight streak.
- **Noise:** 12 taps give a fine hatched grain in the longest streaks. Raising `samples` smooths it; `animate_noise` trades the fixed pattern for grain.
- **MSAA on lavapipe:** depth reads back empty, as it already did for the god rays, so the depth half of the MSAA path can't be judged in the container. The velocity resolve does work there: the MSAA probe velocity matches the non-MSAA one exactly. The prep pass trusts any written velocity over the sky reprojection, so even an empty depth buffer leaves the blur and a sharp ship intact (see the table). Please check MSAA 2× on real hardware with `debug_view = VELOCITY`, and look at the ship's silhouette with `msaa_edge_fix` on and off.
- **Circuit 7** has its own WorldEnvironment without a compositor, so it gets no blur yet.

## Profiling on real hardware

```
MB_TRACK=test_circuit_6_live godot --path . -s res://tools/dev/mb_profile.gd
```

The script:

1. Starts an AI race and spectates an AI ship, so the camera is at race speed.
2. Alternates the blur on and off in 4-second blocks.
3. Prints `MB_PROFILE ON {...}` and `MB_PROFILE OFF {...}`:
   - per-pass GPU milliseconds (prep / tile_max / neighbour / gather / total) from RD timestamps;
   - the viewport's whole-frame GPU milliseconds.
4. Prints the on−off frame delta, which includes Forward+ writing the velocity buffer.

Environment options: `MB_SECONDS`, `MB_BLOCK`, `MB_MSAA=0|2|4`, `MB_SAMPLES`.

For hands-on checks, add a `MotionBlurProfiler` node to any running scene. It prints `MBPROF` lines every 2 s; F7 toggles the blur and F6 cycles the debug views. The `MB …` timestamps also show in the editor's Visual Profiler.

Expected cost is about 4 full-screen-ish passes plus the velocity attachment. The gather dominates and scales with `samples`. Almost every tile is active at race speed (about 5000 of 5184 at 1080p).
