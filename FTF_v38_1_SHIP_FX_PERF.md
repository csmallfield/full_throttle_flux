# FTF v38.1: ship FX performance

On a CPU with modest per-core speed, a full race was CPU-bound at about
40 fps; the GPU sat mostly idle. Measured on a Xeon W-2265 + RTX 3080.
`tools/dev/race_bench.gd` showed that the v35 ship FX were most of the
problem: without them the same race held 59 fps. Below 60 fps the engine
runs 1.3–1.6 physics ticks per frame, which makes each frame longer still.
This was also the judder on main on this machine before v37.1.

Branch `perf/ship-fx`, off main (v38 + v37.1 + race_bench).

## What changed
### Trail ribbons on the GPU (`TrailRibbon`, `trail_common.gdshaderinc`)
**Before:** every frame, each of the 32 ribbons (4 per ship) did this in
GDScript:
- ran a centripetal Catmull-Rom through its samples;
- built about 100 vertices with a `pow` each;
- rebuilt its `ArrayMesh`.

**Now:**
- **Each ribbon keeps its samples in a ring buffer** (48 samples). Samples
  past the visible length are dropped; the CPU version also kept those, but
  they were invisible.
- **Each ribbon writes its row of one shared float texture:** a 5-texel
  header (head, tint × intensity, time, 1/life, 1/length, scales, count,
  ring slot, subdivisions, head odometer, widths, fade) and 2 texels per
  sample (position + time, odometer). The odometer gives each point's
  distance from the head without walking the chain.
- **All ribbons draw one shared static strip.** `UV.x` is the point index;
  the vertex shader does the spline, tangent, widths, fades and head fade,
  with the same maths as before.
- **One texture upload per frame** for all ribbons
  (`RenderingServer.frame_pre_draw`). Each ribbon owns its row as a member
  array, because packed arrays are copy-on-write.
- **The head and samples follow the socket where it's drawn**
  (`get_global_transform_interpolated`). Since v37.1 the ships are
  interpolated, so the raw physics pose ran up to a tick (about 1.6 m) ahead
  of the drawn nozzle.
- **`trail_points()`** is a CPU reference of the same curve, for the tests
  and the debug overlay (`point_count()`, `head_position()`).

### Env probe (`ShipEnvProbe`, `SplineTracker`)
- **`SplineTracker`** first refines from last tick's distance (3
  Newton-style steps of up to 6 m). It falls back to the ±40 m window scan
  only if that doesn't settle. This uses about 9 curve samples instead of
  about 47, and stays as local as the scan, so loops and crossovers are
  unchanged.
- **The probe samples walls, track and surface by the ship's FX LOD:**
  - FULL (the camera's ship): every tick;
  - NEAR: every 2nd tick;
  - FAR: every 4th tick;
  - OFF: every 8th tick.

  It's staggered across ships. Everything it feeds is visual. With no
  camera (tests, sims) it samples every tick.

### Dust (`ShipFx`)
No dust from ships the camera can't see (a 6 m margin either side). In a
chase view that's half the pack. The ribbons keep sampling, so trails are
there when a ship comes into view.

## Measured
`race_bench`, Utopia, 7 AI, 1080p, vsync on. Runs vary by a few fps as the
pack moves through the city.

| | fps | ribbons | ShipFx (dust) | physics scripts per tick |
|---|---|---|---|---|
| Main (v38) | 38–43 | 3.28 ms | 0.78 (0.40) ms | ~7.0 ms |
| GPU ribbons | 50–51 | 0.41 ms | 0.75 (0.39) ms | ~7.1 ms |
| + probe + dust | **51–55** | 0.39 ms | 0.52–0.63 (0.10–0.21) ms | ~6.6 ms |
| No ship FX at all | 59–60 | | | ~6.3 ms |

- **Other tracks with everything in:** Builder Lab 59.8 fps, Hairpin
  Alley 50 fps.
- **The GPU frame time is unchanged** (5.6 ms).
- **The env self-test's full-grid FX budget:** 4.71 ms on main (failing),
  now 1.31–1.35 ms against its 3 ms budget.

## Look
`tools/env/render_trails` before and after (straight, weave, boost, rain,
side): the same trails. The only difference is at the nozzle: the trail now
starts at the drawn nozzle and fades in over its 0.5 m `head_fade`, as in
v35. Since v37.1 the head had sat a tick ahead, hidden under the hull.

## Checks
- **`env_selftest`: PASS, 0 failed, three runs in a row.** It failed 2
  checks on main.
  - **"Head pinned to the nozzle"** now compares the head with the drawn
    socket just before drawing (0.0000 m). It used to compare with the raw
    physics pose, which since v37.1 runs up to a tick ahead (that was the
    old 0.048 m failure).
  - **"All ship FX under 3 ms"** passes.
- **`ship_collision_sim`:** output identical to main's.
- **`judder_probe`:** 0.15 px (Builder Lab), 0.18 px (Utopia).

## What's left: the rest of the frame
Without any FX, this race takes about 16.4 ms per frame on this CPU, right
at the 60 fps edge. The rest of the game is now the lever. Per frame on
Utopia:
- **Draw submission (CPU): about 6–7 ms.** About 2,000 draw calls and
  1,300 mesh instances (the city).
- **Physics scripts: about 6.3 ms per tick.**
  - AI controllers, 2.3–3.2 ms;
  - ship controllers and the contact resolver, the rest.
- **`_process`, about 2 ms:**
  - the race HUD, 1.5–2.2 ms;
  - the results screen, 0.8–1.5 ms while hidden;
  - the chase camera's track search, about 1.4 ms;
  - ship audio, about 0.7 ms.

These came from `race_bench`'s `RB_PROFILE` switch-off test, which is
noisy; treat them as rough sizes.
