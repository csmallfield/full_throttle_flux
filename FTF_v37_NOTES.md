# FTF v37: shadows and anti-aliasing

Shadows forming 50–70 m ahead (worst on Utopia), low shadow resolution,
coarse anti-aliasing. The dynamic FOV is unchanged. Nothing here changes
physics or the AI: a headless race probe runs as before.

## Try it in game
| Key | What | Options (default in bold) |
|---|---|---|
| F7 | Anti-aliasing | MSAA 2x + SMAA (v36) · **MSAA 4x + SMAA** · TAA · FSR 2 native |
| F8 | Shadows | Low = v36 (4096, soft low) · **High (8192, soft medium)** · Ultra (8192, soft high) |
| F9 | Road grid, for A/B only | **filtered (v37)** · v36 fixed-pixel lines |

F7 and F8 are saved to `user://graphics.cfg`; F9 isn't. A label shows the new
setting for two seconds. These are a testing aid, not the settings menu.
The `GraphicsSettings` autoload is what a menu would call later.

## What was wrong and what changed

### Shadows forming 50–70 m ahead
Utopia's sun ended its first shadow cascade at 0.03 × 1400 m = **42 m**.
Godot scales shadow bias with each cascade's texel size. In cascade 2
(42–140 m, ~15 cm texels on a 4096 atlas) the bias is large enough to push
the shadows of thin casters (lamp poles, railings, greebles, trusses) off
entirely. They then grow in as they cross into cascade 1, with split
blending making that a fade. That's the band you were seeing.

- **`ShadowProfile`** (`scripts/rendering/shadow_profile.gd`): one set of
  directional shadow settings for every track, applied to its lights when
  it loads (ModeBase → `GraphicsSettings.apply_track`). Splits are in
  metres, so overrides only change what they need to.
  - **Default** (`resources/rendering/shadow_profile_default.tres`):
    1300 m; cascades end at 80 / 230 / 560 m; fade from 65% (a long fade,
    not a band); split blending on; bias 0.04 and normal bias 1.2 (the
    circuits' tested values). Each light's own PCSS angular size is kept.
  - **Swoopy** (`shadow_profile_swoopy.tres`): 1600 m, as before.
  - **Any track** can name its own profile in its `TrackProfile.shadow_profile`.
- **8192 atlas, soft medium filter** (project settings and the High setting).
  The first cascade now reaches 80 m at about the texel density it had over
  42 m, and every cascade beyond it is 1.5–2× finer. Thin casters keep their
  shadows much further out, and edges are smoother.

| Before (v36) | Max distance | First cascade ends |
|---|---|---|
| Utopia, Hairpin | 1400 m | 42 m |
| Swoopy | 1600 m | 48 m |
| The Drop | 500 m | 20 m |
| Labs | 600 m (blending off) | 60 m |
| Old test circuits | 100 m (engine default) | 10 m |

All of them now use the profile.

### Coarse anti-aliasing
- **The road and wall grid shader** was the main cause. Its lines were a
  fixed 1–2 pixels wide at any distance, so far away they crowd several
  lines into each pixel: moiré, crawling lines, a road that brightens toward
  the horizon. MSAA can't fix lines drawn inside a surface.
  `shaders/grid_shader.gdshader` is now a filtered grid (Ben Golus's
  technique):
  - Lines have a width in metres (`line_width_m` 0.015, major 0.06: minor lines stay as faint as in v36).
  - A line thinner than a pixel is dimmed to its real coverage.
  - The grid fades to its average colour where cells get smaller than a few
    pixels; `far_glow` (0.3) keeps a little of the old distant brightness.
  - It costs nothing measurable.
  - `grid_material.tres` now uses the shader file instead of an embedded
    copy. The v36 shader is kept as `grid_shader_v36.gdshader` for F9 only.
- **MSAA 4x** (was 2x), still with SMAA: smoother geometry edges on
  railings, walls and greebles.
- **TAA / FSR 2 native** are options, not defaults. They're best at
  shimmer, but can smear at 120+ u/s; judge them with your own eyes. They
  turn MSAA and SMAA off, which would only cost on top.

## Performance: measure on your GPU
This environment renders in software, so it can't time anything. Run:

```
godot --path full_throttle_flux -s res://tools/dev/gfx_bench_boot.gd
```

For each of the four circuits it runs these configs:

| Config | AA | Shadows | Profile | Grid |
|---|---|---|---|---|
| v36 | MSAA 2x + SMAA | Low | the track's own | v36 |
| profile | MSAA 2x + SMAA | Low | v37 | filtered |
| shadows_high | MSAA 2x + SMAA | High | v37 | filtered |
| msaa4 | MSAA 4x + SMAA | Low | v37 | filtered |
| v37 | MSAA 4x + SMAA | High | v37 | filtered |
| shadows_ultra | MSAA 4x + SMAA | Ultra | v37 | filtered |
| taa | TAA | High | v37 | filtered |
| fsr2 | FSR 2 native | High | v37 | filtered |

Each config is a fresh track, an AI lap on the trained line from the grid,
and the real chase camera with motion blur. It takes 4 s of warm-up, then
20 s measured, with vsync off. It prints GPU median and p99, CPU median and
fps per row, and writes `gfx_bench.csv` (location printed at the end).

**Budget:** about +0.5 ms GPU over `v36` on the same track. If `v37` goes
over, drop back in this order: Ultra → High filter → 4x MSAA. The profile
and the grid are free. One thing to watch: The Drop went from 500 m to
1300 m of shadows. If it's the expensive one, give it its own profile.

## Files
- `scripts/rendering/graphics_settings.gd` (autoload), `shadow_profile.gd`
- `resources/rendering/shadow_profile_default.tres`, `shadow_profile_swoopy.tres`
- `shaders/grid_shader.gdshader` (new filtered grid), `grid_shader_v36.gdshader` (A/B)
- `shaders/resources/grid_material.tres`
- `tools/dev/gfx_bench.gd`, `gfx_bench_boot.gd`
- `project.godot`: autoload, MSAA 4x, 8192 atlas, soft medium filter
- `scripts/modes/mode_base.gd`: applies the profile on load
- `scripts/resources/track_profile.gd`: `shadow_profile`
- `resources/tracks/test_circuit_5_live.tres`: Swoopy's profile
