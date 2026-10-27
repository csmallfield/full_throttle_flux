# FTF v38: circuit surface identities (first pass)

Each of the four circuits now has a surface of its own: its own variation,
zone layout and decals, authored in its `TrackSurface` node
(`docs/TRACK_AUTHORING.md` §7). There's no new code, profile or shader: only
the presets (industrial, service, grate_run) and the variation levers from
phases 3–5.

Earlier notes: `FTF_v38_TRACK_SURFACE_P5B.md` (the port),
`_P3.md` to `_P5.md`.

**You picked the directions** (lived-in boulevard, sky bridge, neon
wet-black, warning!). These are first passes for your sign-off on looks; every
value lives in the variation `.tres` or the scene's sub-resources.

## The four
Corner distances come from each circuit's trained line: the speed minima of
`default_racer`. Chevrons run 6 × 14 m and end about 60 m before the apex.

### Utopia (`test_circuit_3_live`): lived-in boulevard
Sunny waterfront city, warm sun, warm grey haze.

| | |
|---|---|
| Variation | Warm greige plates (0.235, 0.225, 0.21), edges to match. Lights neutral white: blue → cool white, red → warm white. Panel tint 0.10, wear 0.45, warmer grime |
| Zones | industrial 0 m (concourse) · service 700 m (skyway, 200 m blend) · grate_run 2,300 m (arcade, hard seam) · industrial 3,150 m (north loop, 60 m blend) |
| Decals | District names from the README in Audiowide, left side: TERRACES, SKYWAY, CANYON, CORNER, ARCADE, NORTH LOOP, VIADUCT, SPIRAL, EAST SWEEP. Yellow chevrons into the hairpin (apex 3,127 m) and north loop (3,860 m). Serials `*UT-0n*` along the concourse |

### Swoopy (`test_circuit_5_live`): sky bridge
Deck 500–700 m above a city, cold blue haze, steel trestles.

| | |
|---|---|
| Variation | Cool blue-grey plates. White and ice-blue lights. **Red/white hazard** (aviation): `hazard_yellow` (0.66, 0.04, 0.05), `hazard_black` (0.66, 0.67, 0.68). Ice-blue grate glow 0.5, wear 0.35 |
| Zones | industrial 0 m (start stands) · service 400 m (low sweeps) · grate_run 2,050 m (the trestle section) · service 4,780 m (descent) · industrial 8,100 m |
| Decals | Structure names (TRESTLE, UPPERDECK, GALLERY) at their overhead clusters. Altitude above the streets (`ALT 578` … `ALT 684`, from the spline's height + 520 m). White chevrons into the 3,600 m and 7,611 m hairpins (the slowest on the lap, 30 u/s) |

### Hairpin Alley (`test_circuit_6_live`): neon wet-black
Night canyon city, cyan/magenta/amber neon, seven tunnels.

| | |
|---|---|
| Variation | Near-black plates (0.13, 0.135, 0.15). Cyan lights, magenta instead of red. **Magenta/black hazard.** Cyan grate glow 0.8, wear 0.75, dark grime |
| Zones | 15 zones: grate_run inside each of the seven tunnels, hard seams at both portals. Service on the two long straights (2,200–2,700 m, 5,380–6,560 m), industrial elsewhere |
| Decals | Tunnel names in Alien Block, 30 m before each portal (GATE TUNNEL … HOME BORE), faintly lit. Glowing blue chevrons into the three big hairpins (978, 1,479, 3,724/3,838 m) |

### The Drop (`test_circuit_7_live`): warning!
Dusk violet sky; starts at 320 m, plunges 146 m in 200 m from about 1,000 m,
climbs to a 28 u/s hairpin at the 437 m summit.

| | |
|---|---|
| Variation | Strong lemon hazard (1.0, 0.8, 0.0). Blue lights → violet, red stays. Violet grate glow 0.5, stronger violet scorch, wear 0.6 |
| Zones | industrial 0 m · grate_run 1,000 m (the plunge, hard seam) · service 2,100 m (the climb) · industrial 5,450 m (summit, wear ×1.5) |
| Decals | Red BRACE (Alien Block) and yellow DROP (Bartle) before the crest, four big red chevrons over it. ALT 133 / 285 / 362 / 420 on the climb. Yellow chevrons into the 525 m corner, red into the summit hairpin |

## Changed after the first render
- **Hairpin Alley's hazard was yellow** at first. Under the warm deck lights
  it read amber, too close to the boost pads' orange. It's magenta now (pink
  under the deck lights, violet under the cyan tunnel lights), and the
  chevrons are glowing blue instead of yellow.
- **Swoopy's chevrons were red.** In full sun they drifted toward
  orange-red, so they're white now, and the hazard red is deeper (0.78 →
  0.66) with a slightly darker white stripe.
- **The sector labels** went from 2.2 m / 0.8 opacity to 2.6 m / 0.9: they
  were faint from the chase camera.

## Checks
### Clean in motion
`track_surface_shots`, RTX 3080, 1080p, lights frozen: chase and top at
every circuit's decals, seams and zones (CSV in each `cN\` folder). Far road
against the averaged reference:

- **Top poses (all four circuits): brightness within about 1%** of the
  reference, far flicker within noise of it.
- **Chase poses** look across the cities, which animate (clouds, screens,
  the sky). As 5b found, the measure there is unreliable:
  - The first Swoopy run showed the far road 8–14% above its reference at
    2,050 and 3,460 m.
  - An A/B settled it: with the full look again it measured within 0.1–0.5%,
    and the same with the hazard overrides removed. So it was run-to-run
    noise.
  - Main's own Utopia chase poses vary 1–5% the same way.
- **The Drop** (no animated city) reads clean at every pose.
- Some chase poses at the tightest corners (Utopia 2,290 and 3,140 m,
  Swoopy 5,290 m) put the camera under or beside the deck. The tool frames
  them from the spline, and the circuit roads are offset from it (§7). Their
  top poses are fine.

### Load
Every zone and decal resolves with no `TrackSurface` notes: glyphs all in
the atlas, no metre over the 24-record limit. Per circuit: 4 / 5 / 15 / 4
zones; 13 / 12 / 11 / 10 decals.

### Performance
**Not compared yet.** The baseline on main was taken: `race_bench`, Utopia,
7 AI, 1080p, vsync off, 20 s, two runs:

| Run | fps | frame p50 | GPU |
|---|---|---|---|
| main a | 101.0 | 9.39 ms | 3.76 ms |
| main b | 118.1 | 8.22 ms | 3.86 ms |

The run after the change was skipped (your call: you'll play it instead).
Runs vary by about 15% even on main, so compare GPU time over several runs.

What to expect: nothing here adds per-pixel work. Decals were already on
(the start word) and the strip fetch is the same one fetch; more zones and
decals only fill textures that already exist, built once at load. Only
pixels inside a decal's metres loop over its records, as on Builder Lab.

### Env self-test
**Not completed.** On Utopia (the default track) it passes every check up
to its "trails" stage:
- the span and zone maths;
- EnvironmentState with 3 surface materials, 0 conflicts and the mask on;
- grounding, the walls and the covered zone.

Then it **hangs**: the AI ships it spawns around the test ship respawn
forever at about (94, 25, −547), around d ≈ 545 m, and it never prints a
result.
- These are ship and physics problems. This change only sets rendering
  materials, so it's most likely pre-existing.
- I started the same run on main to confirm it but stopped it unfinished,
  at your request.
- The other three circuits weren't run.

## Screenshots
In `%APPDATA%\Godot\app_userdata\full_throttle_flux\circuit_identities\`:
- `cN\`: every pose as grid, surface and average, with the chase debug views
  (bands, zones, wear…);
- `sheet_cN.png`: a contact sheet per circuit, one row per distance, chase
  left, top right;
- `main_cN\`, `ab_*\`: the brightness A/Bs above.

## Open
- **Your look sign-off**, and gate 2 (at speed) on the circuits.
- **The env self-test hangs on Utopia** (AI ships respawning at d ≈ 545 m):
  confirm on main, then fix or exclude that stage.
- **The race_bench comparison** against the baseline above.
- **Swoopy's wall hazard band is large.** The walls are tall, so the
  red/white band dominates the chase view. If it's too loud, a darker red
  or keeping yellow (the alternative you were offered) are one-line changes.
- **Decal colours aren't per-track.** `decal_red/yellow/blue/white` are style
  uniforms, not in `TrackSurfaceVariation.PARAMS`. Adding them would let,
  say, Hairpin Alley's chevrons go magenta. A small code change; not done.
- **Shot tool on circuits:** chase poses ignore the CSG offset. Placing the
  camera from the road (a ray down, as the respawns do) would fix the
  under-deck frames.
- **No new profile.** All the identity comes from the variation, zone mix
  and decals. A circuit-specific profile (e.g. a tunnel profile for
  Hairpin Alley) would be the next lever.

## Files
- `full_throttle_flux/scenes/tracks/test_circuit_{3,5,6,7}_live.tscn`:
  plain-text edits only (two profile ext_resources, zone and decal
  sub-resources, the `TrackSurface` arrays). No uid or node-id churn.
- `full_throttle_flux/resources/track_surface/variations/variation_test_circuit_{3,5,6,7}_live.tres`
