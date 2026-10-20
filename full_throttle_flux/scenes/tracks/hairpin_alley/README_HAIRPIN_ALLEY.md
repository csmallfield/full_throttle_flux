# Hairpin Alley: night city greybox

The environment for **Hairpin Alley** (`test_circuit_6_live`). It's built with the same toolkit as Utopia, so read `scenes/tracks/utopia/README_UTOPIA_GREYBOX.md` for the shared systems: track space, clearance guards, zone dressing, the sky controller and detail swaps.

The racing parts are untouched: MainSpline, groundGeo, the walls, the start line and the grid.

## Install

Unzip at the project root. **The zip also contains the current Utopia v6 files, because Hairpin Alley shares that toolkit, its greebles and its sky.**

Changes to `scenes/tracks/test_circuit_6_live.tscn`:

| Removed | Added |
|---|---|
| `WorldEnvironment` and `DirectionalLight3D` | `HairpinLighting` (`hairpin_alley/hairpin_lighting.tscn`) and `HairpinCity` (`hairpin_alley/hairpin_city.tscn`) |

## The idea

The raceway is an elevated deck threading a dense grid of towers at night.

* **Canyon frontage:** buildings stand right at the walls, with facades 38 m from the centreline (the walls' outer face is at 28.6 m). They line both sides for the whole lap.
  * Lots are office-scale: 60–120 m along the track and 50–90 m deep, with 8–22 m service alleys and the odd 30–45 m plaza. Each lot is a podium over the whole footprint, usually with a tower on part of it (flush with the facade or set back), or one big mid-rise slab. For reference, the ship is about 3.8 m wide and the road is 34 m.
  * Lots are cut at zone edges rather than dropped. Lots on the inside of gentle curves are shortened and pushed out so the straight box clears the bow. Deep lots that would reach another pass of the track fall back to a shallower, then shorter footprint.
  * On the *inside* of tight corners the blocks are small (22×24 m), so they don't fan into each other.
  * On the *outside* of corners the frontage drops to low shop podiums, so the corner billboard reads above it. The board's own pad (corner start to apex, ±15 m) stays empty.
* **Oversailing floors and sky-bridges:** upper blocks cantilever over the walls and bridges span the track. Everything is at least 22 m above the road, so the city weaves over you.
* **Seven fully enclosed tunnels,** about 1.9 km of the 7 km lap, each bored through a megablock:

  | Tunnel | Track distance | Neon |
  |---|---|---|
  | GateTunnel | 380–640 | cyan |
  | MarketBore | 1080–1320 | amber |
  | TowerBore | 1900–2200 | magenta |
  | LongBore | 2700–3000 | cyan |
  | NorthBore | 3950–4200 | amber |
  | RampBore | 5080–5380 | magenta |
  | HomeBore | 6560–6800 | white |

  Each tunnel has ribbed walls, ceiling light strips and continuous neon edge lines in its colour. Every portal has a lit frame and a sign over the mouth. The ceiling height is solved from the tunnel's own maximum banking.
* **Corner signage,** for all 14 corners over 45°:
  * an **animated arrow billboard** on the outside of the corner, turned to face the ship on approach. It is 60×20 m for corners over 90° and 46×16 m otherwise, and its chevrons scroll in the turn direction;
  * an **overhead arrow gantry** 120 m before every corner over 90°;
  * **chevron boards** on the outside wall through the corner, from the dressing.

  Colours cycle magenta, cyan and amber, and a matching coloured light spills onto the road.
* **Landmarks:** a tower with neon rings stands in the eye of each big hairpin, and a 620 m core spire with cyan bands is visible from much of the lap.
* **The background city:** about 600 office-scale blocks drawn as chunked MultiMeshes with no shadows, so it's cheap. The dense core uses 100 m cells with 60–80 m footprints, and the outer skyline, which runs about 2 km out, uses 180 m cells with 105–140 m footprints. Where a full block won't fit between passes of the track, it shrinks to 70% or 50% instead of leaving a hole.

## Night look

| Piece | Where | What |
|---|---|---|
| Windows | `materials/night_windows.gdshader` | Procedural lit windows in world space on any box, so they work on scaled cubes and MultiMeshes. Each building is hashed into *office* (cool, denser, whole lit floors) or *residential* (warm, sparse). Street level gets a coloured shop band, and roofs stay dark. Past about 0.5–1.6 km each facade fades to its average glow, which avoids moiré. `night_windows_tower.tres` is the denser variant used on tall buildings. |
| Screens | `materials/night_screen.gdshader` | Unshaded, HDR, and feeds the glow. Per-node *Instance Shader Parameters*: `screen_color`, `arrow_dir` (-1 left, +1 right, 0 = ad pattern) and `pattern_seed`. |
| Neon | `neon_*.tres` | Emissive StandardMaterials for blades, crowns, tunnel lines and beacons. `beacon_red` is the aviation lights. |
| Sky | `SkyController` preset `night` (added to the shared controller) | Moon as the key light (cool, low energy), deep navy sky, **stars**, and **city glow**: a warm light-pollution band on the horizon that also lights the cloud bases from below. God rays are off. Stronger glow/bloom is set in `lighting_params()`. |
| Lights | `districts/hairpin_lights.tscn` | About 240 OmniLights with no shadows and distance fade: warm deck lights every 34 m alternating sides, tunnel lights every 28 m tinted to each tunnel's neon, and a coloured spill light at every corner billboard. Forward+ handles this count comfortably. |

The track's own road and wall materials aren't emissive; they're the original racing materials and I didn't touch them. At night they read through the deck lights, which make the cyan grid glow.

## Files

```
scenes/tracks/hairpin_alley/
  hairpin_city.tscn               instances every district + the dressing
  hairpin_lighting.tscn           WorldEnvironment + Moon + SkyFill + SkyController (preset: night)
  hairpin_track_dressing.tscn     Rails + TrackDresser (Utopia zone system)
  hairpin_road_rails.tscn         surveyed rails for this track
  districts/hairpin_*.tscn        ground, frontage, infill, tunnels, signs, landmarks, lights
  greebles/style_neon_alley.tres  the night straight style
  materials/                      night shaders + materials
tools/hairpin/
  hairpin_layout.gd               the layout (extends UtopiaLayout)
  build_hairpin.gd                regenerates the districts, city and lighting
  build_hairpin_dressing.gd       zone map: corners -> hairpin, tunnels -> service, rest -> neon_alley
  make_night_materials.gd         writes the night materials
```

## Regenerating

```
godot --headless --path . -s res://tools/utopia/survey_road.gd -- res://scenes/tracks/test_circuit_6_live.tscn res://scenes/tracks/hairpin_alley/hairpin_road_rails.tscn
godot --path . -s res://tools/hairpin/build_hairpin_dressing.gd      # NOT --headless
godot --path . -s res://tools/hairpin/build_hairpin.gd               # writes the city + lighting; NOT --headless
godot --headless --path . -s res://tools/utopia/check_clearance.gd -- res://scenes/tracks/test_circuit_6_live.tscn HairpinCity
```

Don't run `build_hairpin.gd` headless. The dummy renderer drops MultiMesh instance transforms, so the infill gets saved as zero-size boxes and the background city disappears. Pass district ids to rebuild only some, for example `-- frontage infill`. The window materials' `ground_y` matches `HairpinLayout.GROUND_Y`, and `make_night_materials.gd` writes it from there.

The clearance check reports **0 intrusions**. It checks MeshInstances only. The MultiMesh background city stays at least 82 m from every pass and goes through the same placement guard.

Detail swaps work the same way as in Utopia: put a scene at `scenes/tracks/hairpin_alley/replacements/<district>.tscn` whose top-level children are named after greybox groups (`TowerBore`, `Corner03_L140`, `Pin02`, `CoreSpire` and so on).

## Notes

* **Track geometry:** the road has the same ~1° node-transform pitch as Utopia's, so everything is placed through `UtopiaKit.road_xf`.
* **Wall rails:** on the tightest hairpins the surveyed wall rails are rougher (up to about 10° tilt error at p99, against 2–5° on Utopia). That's fine for greebles, but worth knowing if you hang anything precise off them.
* **Lights and lamp greebles:** the deck lights aren't tied to the `lamp_pole` greeble positions; they run on their own 34 m rhythm.
* **Greeble colour:** the greebles use Utopia's light-grey greybox materials, so at night they read as pale silhouettes. Swapping in detailed meshes with night-appropriate materials fixes that.
* **Optional extras:** turning on `volumetric_shafts` on the SkyController gives the street lights and neon visible light cones in the haze. It looks great in replays and photo mode, but it's heavier.
