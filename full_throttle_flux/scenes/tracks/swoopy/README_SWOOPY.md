# Swoopy: sky-high greybox

The environment for **Swoopy** (`test_circuit_5_live`). It's built with the Utopia toolkit, so `scenes/tracks/utopia/README_UTOPIA_GREYBOX.md` covers the shared systems: track space, clearance guards, zone dressing, the sky controller and detail swaps.

The racing parts are untouched: MainSpline, groundGeo, the walls, the start line and the grid.

## Install

Unzip at the project root, **on top of the Hairpin Alley drop-in** (it builds on that commit).

Changes to `scenes/tracks/test_circuit_5_live.tscn`:

| Removed | Added |
|---|---|
| `WorldEnvironment` and `DirectionalLight3D` | `SwoopyLighting` (`swoopy/swoopy_lighting.tscn`) and `SwoopyCity` (`swoopy/swoopy_city.tscn`) |

Two shared files change. Both are backwards compatible.

| File | Change |
|---|---|
| `tools/utopia/sky_controller.gd` | New `high_altitude` preset. New `ground_darken` export, which sets how much darker than the fog the sky is below the horizon; the default 0.5 is the old behaviour. |
| `tools/utopia/survey_road.gd` | Also frees `SwoopyCity` and `SwoopyLighting` before it surveys. |

## The idea

The lap is flung across the sky 500–700 m above a city. The deck sits between y -27 and 178 m, and the streets are at y -520. The whole thing hangs on a structure you race **through**, not just on top of:

* **Box girder:** a continuous girder runs under the road for the whole lap, so the deck reads as a bridge rather than a ribbon. Diaphragm ribs every 16 m give it a rhythm from below.
* **Supports:** 75 of them, each one merged mesh and one draw call:
  * `Monolith`: a tapered concrete pier with a stepped plinth and collars, on the low sweeps.
  * `Split`: a shaft that forks into two raking legs, every third low pier.
  * `Trestle`: a battered four-leg lattice tower with steel ring beams, X braces and a working floor every third level. These carry the high section (2050–4780).

  Each support top is cut to the banked bearing plane, so the supports sit flush under banked road.
* **Webs:** 81 truss bridges and girders link supports on different parts of the lap, 55–250 m below the deck. 34 hung work platforms (hangars, tanks, landing pads, beacon masts) sit on them. This is what you look across at from the track.
* **Overhead:** scaffolding that straddles the deck and rises above it. It comes in 16 clusters, one about every 500 m. Their outboard legs stand at ±46 m and run all the way down to the city.

  | Kind | What you fly through |
  |---|---|
  | `Gallery` | 7 portal frames, 34 m apart, with cross trusses and a lattice overhead. |
  | `Upperdeck` | A working platform over the road, with a hangar, tanks and a crane swung out over the void. It throws real shade on the road. |
  | `Catwalks` | 3 light trusses with pipe bundles between slim masts. |
  | `Towers` | Two 150–200 m scaffold towers either side of the road, with floors, sky-bridges overhead and a low gate frame. |

  Every overhead member is at least 8 m above the solved clearance height (`clear_y`, which accounts for banking).
* **Service decks and start stands:** decks cantilevered off the supports just below the wall line, and grandstands either side of the start.
* **City:** about 11,900 blocks in 118 MultiMesh tiles, with no shadows. It's a rotated street grid with avenues, a 190 m wide river, a denser core, and clear plazas around every support foot.
* **Cloud sea:** two patchy cloud decks at y -235 and -320, so the city comes and goes. It's a cheap shader on two planes (`materials/cloud_sea.gdshader`):
  * two scrolling noise layers;
  * soft contact where supports punch through (from scene depth);
  * a fade before the far plane.

  Tune `coverage`, `opacity` and `wind` in `cloud_sea.tres` (upper deck) and `cloud_sea_low.tres` (lower deck), or delete the `Swoopy_Clouds` district to drop it.
* **Needles:** 11 slender towers rising from the city to around deck height, for mid-ground parallax. They come in four forms: `discs`, `stack`, `fork` and `blade`.
* **Megastructures:** 8 impossible spires, 2–3 km out, between 1.5 and 1.8 km tall.

  | Spire | What defies physics |
  |---|---|
  | `Halo` | A needle with two rings floating free around it. |
  | `Orb` | A 420 m sphere skewered on a thin needle. |
  | `Inverted` | A 540 m wide stepped crown balanced on a slender stem. |
  | `Cantilever` | Slabs cantilevered off a thin core, twisting as they climb. |
  | `Twin` | A huge mass slung between two needles. |
  | `Balanced` | A leaning monolith with a cube standing on one vertex. |
  | `Levitate` | A needle that stops short, with an ovoid hovering above it and its little moons. |
  | `Cluster` | Slender needles bound by floating rings. |

  Their heights are solved so every top stays inside the race camera's 4 km far plane.

## Look

| Setting | Value |
|---|---|
| Sky preset | `high_altitude`: deep zenith, pale horizon, cumulus up high, crisp sun at 33° from the SSW. God rays are on at low strength. |
| Fog | Height fog from y -60 down (`fog_height_density` 0.0022) plus aerial perspective. Everything below the deck dissolves into blue haze, so the city reads as *far*. |
| Below the horizon | `ground_darken` 0.04, so looking down past the city edge you see haze, not a dark band. |

Materials are in `materials/`: `concrete`, `concrete_dk`, `steel`, `pale`, `glass`, the `city_*` set, `river`, `beacon` (emissive aviation red) and `halo`. Every generated mesh references these files, so swapping a material file restyles everything that uses it.

## Files

```
scenes/tracks/swoopy/
  swoopy_city.tscn             instances every district + the dressing
  swoopy_lighting.tscn         WorldEnvironment + Sun + SkyFill + SkyController (preset: high_altitude)
  swoopy_track_dressing.tscn   Rails + TrackDresser (Utopia zone system)
  swoopy_road_rails.tscn       surveyed rails for this track
  districts/swoopy_*.tscn      deck, piers, webs, platforms, overhead, city, needles, spires, clouds
  greebles/style_sky_deck.tres the new straight style
  materials/                   greybox materials + cloud sea shader
  meshes/                      generated merged meshes (one per support / link / cluster)
tools/swoopy/
  swoopy_layout.gd             the layout (extends UtopiaLayout)
  swoopy_mesher.gd             merges boxes/beams/prisms/trusses into one mesh per structure
  build_swoopy.gd              regenerates districts, city and lighting
  build_swoopy_dressing.gd     zones: corners -> hairpin, overhead clusters + high section -> skyway, rest -> sky_deck
  make_swoopy_materials.gd     writes the materials
```

## Regenerating

```
godot --headless --path . -s res://tools/swoopy/make_swoopy_materials.gd   # only if you want to reset the materials
godot --headless --path . -s res://tools/utopia/survey_road.gd -- res://scenes/tracks/test_circuit_5_live.tscn res://scenes/tracks/swoopy/swoopy_road_rails.tscn
godot --path . -s res://tools/swoopy/build_swoopy_dressing.gd     # NOT --headless (MultiMesh)
godot --path . -s res://tools/swoopy/build_swoopy.gd              # NOT --headless; or: -- overhead city   (just those districts)
godot --headless --path . -s res://tools/utopia/check_clearance.gd -- res://scenes/tracks/test_circuit_5_live.tscn SwoopyCity
```

The clearance check reports **0 intrusions**.

Detail swaps work as in Utopia: put a scene at `scenes/tracks/swoopy/replacements/<district>.tscn` whose top-level children are named like the greybox nodes, for example:

| Group | Named like |
|---|---|
| Supports | `Trestle_2124`, `Monolith_0040` |
| Overhead clusters | `Gallery_0295` |
| Spires | `Spire_Orb` |
| Webs | `Link_…` |

Every support, link and cluster is a single mesh, so a swap replaces exactly one structure.

## Cost

| District | Draw items | Triangles |
|---|---|---|
| Structure (deck, piers, webs, platforms, overhead) | ~630 | ~150k |
| City (MultiMesh, no shadows) | 120 | 143k |
| Spires, needles, clouds | ~90 | 37k |
| Track dressing (MultiMesh greebles) | 1,368 | 320k |

That's about 650k triangles before culling. I couldn't measure GPU frame time here (software renderer), so profile it on your machine.

The main lever is the sun's `directional_shadow_max_distance` (1600 m), because the scaffolding casts a lot of shadow. Dropping it to about 900 m keeps the shadows you see near the deck.

## Notes

* **Wall rails:** Swoopy's walls are tall, and the surveyed wall rails are rougher than Utopia's (9–16° tilt error at p99). That's fine for greebles, but don't hang anything precise off `WallOuter`.
* **Overhead placement is automatic.** A cluster is rejected if any other pass of the lap is within about 58 m of a leg, or if the curve or bank is too tight. That's why the very twisty high middle gets catwalks and towers rather than upper decks. To force or move a cluster, edit `_plan_clusters()` (or `SwoopyLayout.clusters`), then rebuild `overhead` **and** the dressing, since the dressing zones follow the clusters.
* **The far plane is the limit on scale.** The race camera's far plane is 4 km, which is why the spires are about 2.5 km out rather than 6 km. If you raise the camera's `far`, you can push them further and taller: change `SPIRE_FAR` in the layout.
