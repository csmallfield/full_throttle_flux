# Full Throttle Flux — v24: long-range shadows

Extract at the **repository root**. Four track scenes replaced. No code changes.

```
full_throttle_flux/scenes/tracks/test_circuit_3_live.tscn
full_throttle_flux/scenes/tracks/test_circuit_5_live.tscn
full_throttle_flux/scenes/tracks/test_circuit_6_live.tscn
full_throttle_flux/scenes/tracks/test_circuit_7_live.tscn
```

Each `DirectionalLight3D` gains four lines:

```
directional_shadow_max_distance = 500.0
directional_shadow_split_1 = 0.04
directional_shadow_split_2 = 0.12
directional_shadow_split_3 = 0.35
```

Nothing else in the scenes is touched — same transform, colour, `shadow_enabled` and `shadow_blur`.

**Verified:** all four scenes load and report `max_distance=500, splits 0.04/0.12/0.35`, shadow mode 2 (4 splits, the default and the right one here).

## What the numbers do

**500** covers everything the cinematic cameras see. Trackside sits ~192 units from the ship on average and cuts at 470; crane and pan are similar. Chase and cockpit views would be fine at 300, but the planted cameras are exactly where missing shadows are most obvious.

**The splits** are fractions of max distance, and Godot's defaults (0.1 / 0.2 / 0.5) are tuned for the default 100 units. Left alone at 500 they'd put the sharpest cascade boundary at 50 units — wasting your best shadow detail on empty track around the ship. At 0.04 / 0.12 / 0.35 the near cascade covers ~20 units, which is about the ship plus its immediate surroundings.

## Two follow-ups you may want

**Shadow map size.** Still 4096. A directional shadow map is a fixed texture budget stretched across max distance, so 100 → 500 is five times less texel density everywhere. Contact shadows under the ship will be softer and may shimmer slightly as it moves. If that bothers you, add to `project.godot` under `[rendering]`:

```
lights_and_shadows/directional_shadow/size=8192
```

That's a project setting rather than a per-scene one, so it applies everywhere at once. Costs VRAM and some fill rate.

**`shadow_blur = 2.0`** is unchanged, deliberately — I didn't want to alter the look you already have in one go. But blur is applied in texel space, so as texel size grows with max distance the same value reads as a much softer shadow. If the ship's shadow now looks mushy up close, try 1.0. That one is per-light, so it's the same four scenes.

I'd look at it through the trackside and pan cameras first, since long-range shadows are exactly what those show.
