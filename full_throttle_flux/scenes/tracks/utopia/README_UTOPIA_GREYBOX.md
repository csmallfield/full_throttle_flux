# Utopia: greybox city

The non-racing environment for **Utopia** (`test_circuit_3_live`). The racing parts are unchanged: MainSpline, groundGeo, the walls, the start line and the grid are byte-identical.

## Install

Unzip at the project root (`res://`). This overwrites one file, `scenes/tracks/test_circuit_3_live.tscn`. Everything else is new.

### What changed in `test_circuit_3_live.tscn`

| Removed | Why |
|---|---|
| `WorldEnvironment`, `DirectionalLight3D` | Replaced by `utopia/utopia_lighting.tscn`. RaceLauncher still finds them because its search is recursive. |
| `GroundMesh` (sandy terrain obj) | Replaced by the water datum and the city. |
| `CSGTorus3D` ×4 | The four start rings now live in `Utopia_Concourse/Rings` with the same transforms (they are torus meshes now, not CSG). |
| `CSGBox3D` ×2 | Placeholder slabs, superseded by the loop-core and canyon architecture. |

| Added |
|---|
| `UtopiaLighting` (instance of `utopia/utopia_lighting.tscn`) |
| `UtopiaCity` (instance of `utopia/utopia_city.tscn`) |

## Layout

```
scenes/tracks/utopia/
  utopia_city.tscn            instances every district
  utopia_lighting.tscn        WorldEnvironment + Sun + SkyFill
  districts/utopia_<id>.tscn  one scene per section of the lap
  materials/greybox_*.tres    7 shared materials, retint the whole city here
  meshes/unit_*.tres          unit primitives, scaled per node
  meshes/gen_*.res            generated arches, ribbons and tunnel shells
tools/utopia/
  utopia_kit.gd               track-space placement helpers (d, lat, h)
  utopia_layout.gd            the authored layout, one function per district
  build_utopia.gd             regenerates every scene above
  check_clearance.gd          sweeps the race envelope and reports intrusions
  utopia_lighting_builder.gd
```

| District | d range | Idea |
|---|---|---|
| concourse | 5650 → 300 | Waterfront boulevard: the start rings, a Gate hall over the grid, civic slabs on pilotis, the Spire on the vanishing point |
| terraces | 300 → 700 | A stepped terrace hill on the outside of the bend, water arches over the dip |
| skyway | 700 → 1300 | Climb on pylons, two tall parabolic sky arches, a sky-bridge framing the crest |
| canyon | 1300 → 1900 | Slot canyon with stacked sky-bridges; the chicane runs through the ribbed *Atrium* tunnel |
| corner | 1900 → 2300 | Civic dome inside the corner, a stoa colonnade wrapping the outside |
| arcade | 2300 → 2900 | A march of arches, then a slab hall on pilotis straddling the bend |
| hairpin | 2900 → 3150 | Pivot tower with a 92 m cantilevered canopy over the hairpin |
| northloop | 3150 → 3850 | Tower core in the loop, a horizontal *Halo* ring overhead, a loop-top bridge |
| spirerun | 3850 → 4150 | Telescoping portals, with the Spire ahead and to the right |
| viaduct | 4150 → 4700 | Elevated climb that runs through a tall slab building |
| spiral | 4650 → 5100 | A drum tower in the eye of the spiral, beacons dead ahead of the crest, a portal at the bottom of the plunge |
| eastsweep | 5100 → 5750 | The Crescent on the inside, a sea colonnade, the great sea ring, a lighthouse in the U-turn |
| base | the whole map | Water, the Spire, the radial city (8 avenues, concentric bands), and distant islands |
| mega | horizon, 2–3.7 km out | The megastructures: the Continuous Monument (a 2.8 km slab on legs, to the south), a stepped arcology (west), twin megatowers 1.5 km and 1.7 km tall with a sky-bridge (north), a 1.2 km sea arch (east) and a needle cluster (north-east) |

## Track dressing (greebles)

```
scenes/tracks/utopia/
  utopia_road_rails.tscn        surveyed utility rails (Path3D), NOT tied to MainSpline
  utopia_track_dressing.tscn    Rails + TrackDresser (UtopiaZoneDresser)
  greebles/gb_*.tres            greybox greeble meshes: swap these for detail
  greebles/styles/style_*.tres  dressing styles (rules per layer)
tools/utopia/
  survey_road.gd                raycasts the rendered road and builds the rails
  zone_dresser.gd               @tool UtopiaZoneDresser
  greeble_zone.gd / greeble_style.gd / greeble_rule.gd   the data model
  make_greebles.gd              builds the greybox gb_*.tres meshes
  build_dressing.gd             initial setup: writes the styles and the zone map
  rail_scatter.gd               UtopiaRailScatter: one-off single-rule scatter (still usable)
```

### The rails

`survey_road.gd` raycasts the real `groundGeo` (layer 1) and walls (layer 4) every 4 m, then writes 7 closed `Curve3D` rails:

| Rail | Where it sits |
|---|---|
| `Road` | Centre of the driving surface |
| `WallFaceL`, `WallFaceR` | Inner wall face, 3 m above the road |
| `WallTopL`, `WallTopR` | Middle of the flat wall top |
| `WallOuterL`, `WallOuterR` | Outer wall face, 3 m above the road |

The tilt on each rail is solved so the up vector matches the surveyed road normal, banking included: 99% of samples are within 2–5°. One short spot near d≈2390 is off by about 13°.

The rails work with any Path3D tool: PathFollow3D, CSGPolygon3D, your own scatters. Re-run the survey only if the road geometry changes; nothing on the racing side was touched.

### Zones, styles and rules

The dressing is data-driven and has three levels:

| Level | Resource | What it holds |
|---|---|---|
| **Zone** | `UtopiaGreebleZone` | A stretch of the lap (`from_d`, `to_d` in Road-rail distance; it can wrap past the start), one style, `mirror` (swaps left/right rules) and `density` |
| **Style** | `UtopiaGreebleStyle`, saved as a .tres | `bay_length`, a list of rules, and an optional `threshold_mesh` placed overhead at the start of every zone that uses the style |
| **Rule** | `UtopiaGreebleRule` | Layer, mesh (plus an optional right-hand mesh), rhythm, side, offsets, jitter, scale, stretch, shadows, and (v36) upright and surface offset: see `docs/TRACK_AUTHORING.md` §3.6. They default to off, so the existing dressings rebuild unchanged |

**Layers.** Each rule sits on one of five layers, and each layer uses its own rail:

| Layer | Rail | Notes |
|---|---|---|
| `ground` | Road | `lateral` sets the distance from the centre |
| `wall_face` | WallFaceL/R | Rail point is 3 m above the road |
| `wall_top` | WallTopL/R | |
| `outside` | WallOuterL/R | −X points away from the track |
| `overhead` | Road, centred | Spanning pieces such as trusses and gantries |

**The bay grid keeps the structure readable.** Every rule in a zone sits on the same grid of bays.
- **Slots and patterns:** a rule splits each bay into `slots_per_bay` slots, and a `pattern` over those slots decides where it places: `x` places, `-` skips. For example, `"x-"` with one slot per bay means every other bay. `"-x--"` with two slots means mid-bay, every second bay.
- **Shared grid across layers:** bay positions are measured along the Road rail from the zone start, then projected onto the wall rails. So the seam in the road, the rib on the wall face, the lamp on the wall top and the pylon outside all land on the same bay line, even through banked curves where the walls are longer or shorter than the road.
- **Continuous pieces:** `mesh_length` stretches a mesh to fill its slot exactly, for pipes and railings.

**Directional pieces.** Right-hand instances are turned 180° so +X faces the track, which also reverses travel direction. Give directional meshes (chevrons, arrows) a `mesh_right` authored to point +Z. `gb_chevron_sign_r` is the example.

**The styles and where they're used:**

| Style | Bay | Character | Zones |
|---|---|---|---|
| civic | 24 m | Seams, ribs, fins and lamp poles on bay lines; lit panels mid-bay on alternate bays; a continuous railing on the wall tops; a portal at each zone entry | concourse, corner, arcade, spire run |
| garden | 20 m | Planters on the wall tops, light walls, nothing outside so the views stay open; gantry at entry | terraces, north loop |
| skyway | 30 m | A tall pylon frame on every bay line, light dashes every 5 m, antennas | skyway, viaduct |
| service | 16 m | Gutter grates, hazard strips, continuous pipe runs, louvres, sensors, dense fins, a truss every 96 m | canyon (incl. the Atrium) |
| maritime | 28 m | Masts with pennants, bollards, cool light dashes; portal at entry | east sweep |
| hairpin | 12 m | Chevron boards on the outside wall, hazard edges, sensors | hairpin; spiral; U-turn (mirrored) |

**Editing.** Open `utopia_track_dressing.tscn`, select **TrackDresser**, edit the zones array, or open a style .tres and edit its rules, then press **Rebuild**. Baking takes a few seconds and writes one MultiMeshInstance3D per rule per 400 m chunk, under a node per zone. There are about 5,500 instances, nothing runs at game time, and nothing collides.

**Ideas for more variation that the system already supports:**
- **Same style, different density:** the corner zone uses civic at 0.8 density.
- **A style variant:** duplicate a style .tres, change two rules, and assign it to one zone.
- **A short accent zone inside a longer one:** split the zone. Its threshold mesh then marks the change.

### Swapping in your detailed models

* **Everywhere at once:** overwrite `greebles/gb_<name>.tres` with your mesh. For example, in the .glb import settings, save the mesh to that path. Every rule and chunk references that resource, so nothing needs rebuilding.
* **Per style:** point a rule's `mesh` at your model and press Rebuild. For example, civic railings can get a detailed balustrade while service keeps the plain one.
* Keep the pivot and axes of the greybox piece (see the convention above), with units in metres. Materials can live on your mesh's surfaces.
* Changing spacing, offsets or ranges needs **Rebuild**. Swapping the mesh doesn't.

### Detail models for the city greybox

`build_utopia.gd` looks for `scenes/tracks/utopia/replacements/<district>.tscn`. If that file exists, it is instanced into the district as `Detail`. Every greybox node whose **name matches a direct child of that scene's root** is then removed. For example, a child named `Pivot` replaces the hairpin tower and canopy, and `Gate` replaces the start Gate.

The district groups have identity transforms, so the greybox is in world space. One workflow:
1. Export a district to glTF (Scene → Export As → glTF 2.0) and model on top of it in Maya.
2. Export your pieces back in world space, named after the groups they replace.
3. Save them as `replacements/<district>.tscn` and rebuild.

Your pieces survive every rebuild, and anything you haven't replaced stays greybox.

## Regenerating

```
godot --headless --path . -s res://tools/utopia/survey_road.gd             # rails (only if the road changes)
godot --path . -s res://tools/utopia/build_dressing.gd                     # NOT --headless: see note
godot --headless --path . -s res://tools/utopia/build_utopia.gd            # all districts
godot --headless --path . -s res://tools/utopia/build_utopia.gd -- arcade  # one district
godot --headless --path . -s res://tools/utopia/check_clearance.gd         # must report 0 intrusions
```

`build_dressing.gd` needs a real renderer. The headless dummy renderer doesn't keep MultiMesh buffers, so a headless run saves empty scatters. Pressing Rebuild in the editor is always fine. Re-running `build_dressing.gd` overwrites the style .tres files and the zone list. Once you start tuning in the editor, use Rebuild instead.

**The build overwrites the district scenes.** To hand-edit a district in the editor and keep the edit, remove its id from `district_ids()` in `utopia_layout.gd` first, or save your version under a new name.

### Clearance envelope

Nothing may sit inside |lat| < 31 and −2 … +19 m above the road centreline, measured in the *banked* track frame. The layout guards every solid as it places it, and `check_clearance.gd` sweeps the whole lap every 2 m against the real meshes. The current build reports 0 intrusions.

## ⚠ The road is offset from MainSpline

`groundGeo`, `wallLeftGeo` and `wallRightGeo` carry a node transform with a pitch of about 1°, and `groundGeo` also has a small offset. CSGPolygon3D applies that transform to the extruded path, so the road surface sits up to **~16–19 m above the raw spline** in the north of the map (roughly −0.018 × z). Probe results:

| d | spline y | road surface y |
|---|---|---|
| 0 | −0.2 | 1.8 |
| 2400 | 12.1 | 30.4 |
| 3500 | −0.2 | 19.0 |

`TrackSplineHelper.spline_offset_to_world()` does not include this offset. The AI baker raycasts, so it is unaffected. Anything that places things from the spline alone will be wrong in the north, though: debug cameras, spectator rigs, future set dressing. `UtopiaKit.road_xf` applies the groundGeo transform. The cleaner fix is to zero those three node transforms and re-bake, but that changes the racing surface, so it is your call.

## Lighting, sky and weather

Everything about the light and the weather is driven by one node: **`UtopiaLighting/SkyController`** (`tools/utopia/sky_controller.gd`).

The controller controls these:
* the sun's direction, colour and energy
* the sky fill light
* the sky shader uniforms
* fog colour and density, ambient energy, exposure
* both god-ray paths

Every export applies live in the editor. At game time you can blend weather with:

```gdscript
$UtopiaLighting/SkyController.transition_to("storm_light", 8.0)
```

### Presets

`PRESETS` in `sky_controller.gd` are plain dictionaries: copy one, tweak it, add it to the enum. Picking a preset in the inspector overwrites the individual exports. You can then fine-tune those exports for this scene, and they're saved with it.

| Preset | Sun | Clouds | God rays |
|---|---|---|---|
| golden_afternoon *(default)* | SSW, 23° | Scattered cumulus, light cirrus | Subtle |
| clear_noon | 62° | Sparse | Faint |
| fair_cumulus | 42° | Big fair-weather cumulus | Light |
| storm_light | Low, 14° | 80% heavy cover, dark bases, strong wind | Strong shafts through gaps |
| overcast | Diffuse | Full cover; the sun is dimmed and ambient takes over | Off |
| dusk | 4° | Orange horizon, cirrus | Warm |

Snapping between presets is instant for the sun and the sky. The ambient/reflection cubemap updates incrementally, so it catches up over roughly a second. `transition_to()` hides this.

### Where to adjust the sky

| What | Where |
|---|---|
| Everyday controls: sun, colours, coverage, wind, quality, billow size, detail, edge softness, dither | `UtopiaLighting/SkyController` in the inspector |
| Weather presets | `PRESETS` in `tools/utopia/sky_controller.gd` |
| Every shader uniform, including advanced ones (cloud heights and scales, phase, horizon fade, cirrus, sun disk) | `sky/utopia_sky_material.tres`. The controller overwrites the ones it drives. |
| Cloud shapes themselves | Regenerate the noise volumes: `python3 tools/utopia/gen_cloud_noise.py`, then `godot --path . -s res://tools/utopia/bake_cloud_noise.gd`. The bake must run **without** `--headless`. |

### Cloud quality

`cloud_quality` on the controller swaps the shader variant and the step counts:

| Tier | Cloud resolution | March steps | Light taps | Use |
|---|---|---|---|---|
| low | ¼ | 20 | 2 | Weak GPUs |
| medium | ½ | 32 | 3 | What v4/v5 shipped with |
| **high** (default) | full | 40 | 4 | Racing |
| ultra | full | 64 | 6 | Screenshots and replays |

Grazing rays near the horizon automatically get up to 1.75× more steps.

**Cost:** I couldn't measure it here (I only have a software renderer). Full-res clouds cost roughly 2–4× what half-res does. On an RTX 3080 at 1440p I'd expect *high* to land around 1.5–3 ms. Check the GPU profiler (Debugger → Visual Profiler → Sky). If it's too heavy, *medium* is still much better than before because of the new noise.

### The sky shader: `sky/utopia_sky_common.gdshaderinc`

Three thin variants include it: `utopia_sky_full`, `utopia_sky_half` and `utopia_sky_quarter.gdshader`.

* **Atmosphere:** an art-directed gradient (zenith, horizon, ground), plus a forward-scattering sun glow, a halo and a sun disk. It reads the Sun via `LIGHT0_*`, so moving the light moves the sky.
* **Cumulus:** raymarched on a curved shell (planet radius 60 km), so the clouds sink to the horizon and dissolve into the haze.
  * **Shape** comes from a **128³ tileable Perlin-Worley volume**, which gives billowy cauliflower tops.
  * **Erosion** comes from a **64³ Worley FBM volume**: wispy at the cloud base, billowy toward the top. It fades out past `detail_fade_distance`, where it would only alias.
  * **Coverage** is set by the 512² weather map.
  * **Lighting:** Beer and powder terms, a forward/back phase (silver linings), and a jittered light march toward the sun.
  * **Dither:** the march start is dithered per pixel (`cloud_dither`), so thick clouds don't show step "slices".
* **Why it looked blocky before:** there were three causes:
  1. a half-res pass that was upscaled;
  2. a low-detail 64³ single-octave cellular noise, which gave faceted shapes;
  3. 28 fixed, undithered steps, which made banding visible.

  All three are fixed.
* **Cirrus:** a streaky 2D layer at 7 km.
* **Wind** drifts the clouds with `TIME`. **Parallax** slides the deck past as the camera travels.
* **Cubemap pass:** the ambient/reflection pass skips the raymarch (it uses a coverage veil) and most of the sun glow.

### God rays

| Path | What it is | Cost and behaviour | Default |
|---|---|---|---|
| **Screen-space** | `UtopiaGodRays` CompositorEffect on the WorldEnvironment's `compositor` (`tools/utopia/godrays_*.glsl`). Pass 1 makes a half-res mask of bright **sky** pixels around the sun; clouds and architecture occlude by not being bright sky, so shafts come through cloud gaps, portals and arches. Pass 2 radially blurs that mask toward the sun and adds it to the HDR buffer before tonemapping. | Cheap (one half-res and one full-res compute pass) and stable at race speed. Only appears when the sun is in or near frame. | On |
| **Volumetric** | `volumetric_shafts` turns on Forward+ volumetric fog and gives the Sun a volumetric energy. These are real shafts through the city, visible even with the sun behind you. | Heavier, and the fog's temporal reprojection smears at race speed. | Off; best for menus, replays and photo mode |

Screen-space tuning lives on the effect resource: `threshold` (default 0.6), `decay`, `ray_length`, `samples`, `sun_radius`, `weight` and `horizon_cutoff`. Intensity and tint come from the controller.

**Only the sky emits rays.** A pixel can cast rays only if all three of these hold:
1. its depth is the far plane, meaning it really is sky;
2. its view ray points above the world horizon (`horizon_cutoff`);
3. it is brighter than `threshold`.

So lane studs, wall strips, sign panels and lamp heads never cast rays, but bright sky and cloud showing through gaps do. To check what's emitting on your machine, tick **`debug_mask`** on the effect (WorldEnvironment → Compositor → UtopiaGodRays): the screen then shows only the emission mask.

The depth test relies on Godot resolving the MSAA depth before post-transparent effects, which it does on Vulkan GPUs. The horizon gate is a second line of defence that doesn't need depth at all.

### Other lighting

* AgX tonemapping
* SSAO and SSIL
* Directional shadows with 4 splits out to 1400 m
* Height fog that sinks the lower city levels into haze

**Performance knobs, in order:**
1. SSIL off.
2. `march_steps` down.
3. Shadow distance down.
4. Volumetric shafts off (they already are by default).

The city has about 1,230 MeshInstance3D nodes and 5,500 greeble instances, with no collision and no CSG.

## ⚠ Camera far plane

`AGCamera2097` doesn't set `far`, so it uses Godot's default of 4000 m. Every megastructure is placed so its farthest point is less than 3.9 km from any point on the track, which means nothing gets clipped. If you add more distant geometry, raise `far` (for example `far = 8000.0` in `_ready()`). Depth precision at that range is still fine with Forward+ reverse-Z.
