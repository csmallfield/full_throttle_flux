# FTF: Sky Lab, phase 1

A dev scene for tuning a track's sky, its post and fog, the weather presets and
how rain, snow and grit look, live on the real track, and saving the result to
the files the game loads. Built on Surface Lab's model (`FTF_SURFACE_LAB.md`):
one flat dictionary for undo, compare, snapshots and "what's unsaved".

Open `tools/sky_lab/sky_lab.tscn` and run it (F6), or:

```
godot --path full_throttle_flux res://tools/sky_lab/sky_lab.tscn
```

`LAB_TRACK=<scene name>` picks the track. The default is `test_circuit_3_live`
(Utopia). Swoopy (`test_circuit_5_live`) and Hairpin Alley
(`test_circuit_6_live`) also have a sky rig. Tutorial: `docs/sky-lab/`.

## Keys
| Key | What |
|---|---|
| Hold C | Show the saved look, in the same weather |
| [ / ] | Previous / next weather |
| H | Hide the UI |
| Ctrl+Z / Ctrl+Y | Undo / redo |
| Ctrl+S | Save (asks first, listing the files) |
| Space | Pause the glide camera |
| Right mouse + WASD, Q/E | Fly camera; Shift for fast, the wheel for speed |

## What's on screen
- **Top bar:** camera (Fly, Glide, Chase lap), Look (road, toward the sun,
  away from it, up), the weather, Play change, compare, snapshots A and B, GPU
  time, what's unsaved.
- **Tabs:** Sky (the track's `UtopiaSkyController`), Weather (the previewed
  `WeatherPreset`), Falling (the `PrecipLook` of its kind), Post (the track's
  Environment), Track (its `TrackEnvironment` dust, where it has one). Rows come
  from the scripts' exported properties, so new ones appear by themselves.
- **Sun dial:** the sun from above; drag it. The wedge is the camera's view.
- **Exposure:** a luma histogram of the 3D view after tonemapping, with the
  average, the sky's average (top quarter), crushed (< 2%) and clipped (> 98%).
- **Readout:** what EnvironmentState is publishing (wetness, frost, dust,
  falling, wind), the distance fog's 90% distance, the height fog's top
  against the road's height, the sun's actual light.
- **Checks:** sky presets that don't exist, `sky_mood` with no sky preset,
  precipitation that does nothing (or nothing falling), distance fog that hides
  the road within 400 m, a look whose max length is under its min, volumetric
  shafts and ultra clouds (cost). Double-click one to see that weather.

## How far an edit reaches

| Edit | Saved to | Reaches |
|---|---|---|
| Sky | the track's lighting scene (`scenes/tracks/utopia/utopia_lighting.tscn`), its `SkyController` node | This track |
| Post | the same scene, its Environment | This track |
| Track | `resources/track_fx/<track>_environment.tres` | This track |
| Weather | `resources/weather/<preset>.tres` | Every track using that weather |
| Falling | `resources/weather/precip/precip_<kind>.tres` | Every weather of that kind, every track |

Every save changes only the lines of the values edited (or adds a line for a
value the file left at its default). No `ResourceSaver`: the files keep their
uids, ordering and everything else byte for byte.

## How it works
- **The weather never reaches a save.** EnvironmentState changes the sky
  controller and three Environment fog values at runtime (coverage, cloud
  density, fog...). So `sky_doc.gd` keeps the authored values itself.
  `apply()` writes them to the nodes, lets EnvironmentState snapshot them, and
  applies the previewed weather on top: the same order as a race start.
  Switching through every weather and back to clear leaves the controller and
  Environment exactly as authored (self test).
- **Badges.** A Sky or Post row the current weather changes says so ("weather
  sets it", "weather blends 60%", "weather x 0.60"), using the same rules as
  `EnvironmentState._apply_sky`. An edit there still saves, but you'll only see
  it in a weather that leaves the value alone.
- **Start from** sets every value a `UtopiaSkyController.PRESETS` entry has,
  as one undo step, and records the preset's name.
- **Play change** starts clear and changes to the selected weather with
  `instant = false`, so you see the mid-race transition at its real times.

## Game code it needed
- **`PrecipLook`** (`scripts/resources/precip_look.gd`): the per-kind look
  `WeatherFx._configure` used to hard-code (fall speed, wind carry, streak size,
  far layer, tint), now in `resources/weather/precip/precip_{rain,snow,dust_storm}.tres`.
  The files hold v35's numbers exactly, and `PrecipLook.builtin()` returns them
  if a file is missing. The self test checks both against the old values.
- **`WeatherFx.reconfigure()`**, for a live edit.
- **`LabCamera.road_xf`**: the circuits' road sits off their spline (the old
  ~1° offset), so the glide camera follows `road_xf * spline` there. Identity on
  builder tracks, so Surface Lab is unchanged.

## Checks
`LAB_SELFTEST=1` runs `sky_lab_selftest.gd`, which drives the lab on Utopia
and writes only to `user://sky_lab`. It checks: the looks match v35, every
weather on and off leaves the authored values alone, edits reach the
controller, Environment, road and rain, undo / redo / compare / Start from,
that a redirected save loads back with the edits and changes only the
edited lines, and that Play change goes from clear to the full weather.
39 checks, all passing headless.

The existing `tools/env/env_selftest_boot.gd` covers WeatherFx in a race
(snow falls in the open, cut out under cover) on the PrecipLook version.

`LAB_TOUR=<folder>` retakes the tutorial's screenshots (`sky_lab_tour.gd`);
`LAB_TOUR_ONLY=a,b` retakes the shots starting with those prefixes, and
`LAB_TOUR_ONLY=probe` shoots 16 spots round the lap to choose its view. The
mid-race change is timed on game time: under a slow renderer a frame's delta
is clamped, so wall-clock timing shows almost no change.

Not covered, so it needs a person:
- **GPU cost on real hardware.** This branch was built in a cloud sandbox with
  software rendering only, so no timings. Run Utopia on the 1080 Ti with the
  exposure readout off (it reads the frame back twice a second) and compare
  the GPU figure with and without the lab's changes.
- Dragging the sun with a real mouse, and whether the panels feel right.

## Worth knowing from the tutorial shots
- **Utopia's height fog does nothing in clear weather.** Its `fog_height` is
  -12 and the road averages y 13, so the layer sits under the road. The fog
  weathers move it (`road_mean_y + height_fog_top`), which is why they work.
  If the clear-weather look should have ground haze, raise `fog_height` on
  the Post tab.
- **Four weathers fog the road within 400 m** (fog medium / heavy, dust storm
  medium / heavy: 90% at 288 to 384 m). Probably intended, but at racing
  speed that's a second or two of sight; worth a drive.

## Limits
- **Circuits with a sky rig only.** Builder tracks (Builder Lab, Fork Lab,
  Loop Lab) use a plain `ProceduralSkyMaterial` with no `UtopiaSkyController`,
  so there's no sky to edit and weather can't change their sky (only the road,
  fog and falling weather). Giving builder tracks the sky rig would fix both.
- **Named sky presets are read-only.** `UtopiaSkyController.PRESETS` is a
  dictionary in code; the lab starts from one but saves to the track. Making
  presets resources would let weathers and tracks share edited ones.
- **No new weathers.** Phase 1 edits the 13 existing presets. Which weathers a
  track allows, and its default, stay in its `TrackEnvironment`.
- **One look per kind.** Light and heavy rain share `precip_rain`; the preset's
  `precipitation` sets the amount.
- **Saving needs an editor build of Godot**, as in Surface Lab.
