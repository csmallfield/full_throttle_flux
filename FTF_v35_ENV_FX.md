# FTF v35 — Environmental FX & weather (design)

Full proposal with diagrams: https://claude.ai/artifact/PfjYVBzDQZzC9phvmU5qrV
This file is the condensed version that lives with the code. Build notes per
phase: `FTF_v35_NOTES.md`.

Branch: `experiment/v35-env-fx` off `main` @ `232e2f6`.

## The idea

Build one shared environment layer, then hang every effect off it. Dust,
spray, air streams, rain occlusion and the wet / frozen / dusty road all ask
the same three questions: what is the surface condition here, how close is
this ship to the ground and walls, and where on the spline is it.

| Building block | What it is |
| --- | --- |
| `EnvironmentState` | One per race. Wetness, frost, dust, precipitation, wind, dust colour as global shader uniforms; drives the weather part of `UtopiaSkyController` |
| `ShipEnvProbe` | One per ship. Ground distance/point, wall distances, spline distance, zone values, local surface, wall hits |
| `TrailRibbon` | One component for the thrust trail and the wingtip air streams |
| Ship particles | Dust, spray, snow powder, sparks: presets of one emitter, swapped by surface state |
| Weather | Camera-local rain/snow (near + far layers), fog, dust storm, `env_surface.gdshaderinc` for the road and walls |

Visual only: weather never changes handling, so trained AI lines and
recordings stay valid.

## Phases

| Phase | Content | Gate |
| --- | --- | --- |
| 0 Foundation | EnvironmentState + globals, TrackEnvironment, TrackFxZones on SplineSpan, ShipEnvProbe, wall_hit/scrape signals, FxSettings, debug overlay | Probe and zone values correct on Utopia in the overlay |
| 1 Trails | FX_* sockets in variant scenes, ShipFxProfile, TrailRibbon (CPU), thrust + air-stream presets | 8-ship race smooth at 30 and 144 fps, clean on respawn |
| 2 Dust | Belly emitter on the ground point; ground, wall, airbrake terms; dust_scale zones; spray / powder presets | Dust never hides the racing line in a pack |
| 3 Wall hits | Pooled sparks, scrape stream, dust puff; decal marks if time allows | Hits read well from crawl to boost |
| 4 Weather | WeatherPreset → sky/fog/surface; shared wall shader on the circuits; env_surface include; rain/snow; fog; dust storm; SSR in wet | Every weather at 3 intensities within 2 ms GPU; merge candidate |
| 5 Polish | Heightfield occlusion, city material converter, shader ribbons, builder FxKey, mid-race transitions | Each item on its merit |

## Decisions still open

- Who picks the weather: per track, race-setup menu, random from `allowed_weather`, mid-race changes?
- Which track is the dusty one?
- Per-distance surface mask texture for the road shader, or global values + world noise?
- FX sockets placed by hand, or a first pass derived from mesh bounds?
- Trail colour identity: per class, team or visual variant?
- Which city materials react to wetness?
