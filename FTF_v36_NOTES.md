# FTF v36: the Track Builder greebler

Track dressing for Track Builder tracks: zones you place as keys, presets
from a library, and greebles that come straight from the built road. The
how-to is in `docs/TRACK_AUTHORING.md` §3.6. These notes cover the design and
the measurements.

## Choices (agreed before building)
- **Zones are start keys**, like BankKeys with HOLD. Each `GreebleZoneKey`
  runs to the next one. The lap is always covered, and a "None" key leaves a
  stretch bare.
- **Scattered at load**, like TrackRoadSegment. The scene saves only the
  zones; the instances live in internal MultiMesh children.
- **Edited in the inspector, with keys.** There's no custom dock.
- **Builder tracks only.** The four circuits keep their survey-based
  UtopiaZoneDresser.

## Pieces
| File | What |
|---|---|
| `tools/track_builder/greeble_zone_key.gd` | `GreebleZoneKey`: preset dropdown, style, mirror, density, seed, skip_layers; Make local copy / Save as preset |
| `tools/track_builder/track_greebler.gd` | `TrackGreebler`: projects the keys onto the built splines and works out the zones, with branch inheritance, no-overhead spans and ground exclusions. Used by Build, live refresh and the validator |
| `scripts/tracks/track_greebles.gd` | `TrackGreebles` (generated node): rails from the spline frame and width profile, coverage from the Road/WallL/WallR segments, the scatter, `placements()` and `intrusions()` |
| `scripts/tracks/track_greeble_zone.gd` | `TrackGreebleZone` (extends `UtopiaGreebleZone`): path index, skipped layers, key name |
| `resources/greeble_presets/style_*.tres` | Copies of the 7 existing styles, as the starter library |
| `tools/track_builder/greeble_shots.gd` | Chase-camera renders at each zone, plus stats and the intrusion check |

The data model is the existing `UtopiaGreebleStyle` and `UtopiaGreebleRule`,
so every existing style and greybox mesh works unchanged. Rails sit where
`survey_road.gd` put them (face 3 m up, top at 62% across, outer 3 m up),
taken from TrackBuild's wall polygon. The rule offsets in the presets
therefore mean the same thing here.

## Behaviour worth knowing
- **Random draws are fixed per slot.** Every slot draws the same numbers
  whether or not a piece fits, and zones are seeded by key name, not by
  index. So a new gap or key doesn't reshuffle the rest.
- **The drivable track is unaffected.** Greeble keys are excluded from
  `input_hash`, so moving them never makes the Build out of date or
  invalidates AI lines. Adding the Builder Lab keys left MainSpline's hash
  and curves identical.
- **Builds stay byte-identical.** Building twice gives identical scene files,
  because zone sub-resources are reused in place.
- **Headless runs** (probes, validator) skip the scatter unless
  `FTF_GREEBLES=1`. The validator calls `placements()` directly.

## Measured on Builder Lab (8.9 km, 15 zones: 13 main, branch inherited and own)
- 9,298 instances; scatter 160–190 ms (editor refresh and load).
- Intrusion check 180 ms: 0 hits. The validator self-test proves it does
  fire: lamp poles pushed 8 m in are caught; studs scaled ×8 are caught.
- Validator self-test: 21/21 passing (5 new greeble cases). In-editor
  self-test: key moved, preset swapped and local copy made, live refresh
  OK, scene untouched.
- Under xvfb/llvmpipe the rendered smoke frame rate matches Fork Lab (no
  greebles): 23 vs 25 frames in 20 s. That's software rendering, so it's no
  GPU measurement.

## Known limits / possible next steps
- **Live refresh re-scatters the whole track** (~0.2 s after you stop
  editing). Per-zone caching would make it instant.
- **Outside-layer pieces in rolls**: fixed by `upright` (below).
- **Junction areas on the main road get no ground pieces**, because the
  junction road isn't a Road segment. The walls on the far side are still
  dressed.
- **Stretched overhead pieces** get slightly thicker or thinner legs where
  the width changes.
- **No builder-specific presets yet.** Save-as-preset makes adding them
  quick, e.g. a cheap "speed lines" set for long straights.

## Upright and surface offset (added after the first push)
Six new fields on `UtopiaGreebleRule`, applied by `GreebleUpright`
(`tools/utopia/greeble_upright.gd`). Both TrackGreebles and
UtopiaZoneDresser use it, so a rule means the same in both:
- `upright` (0..1): turns the piece from the road's up toward world up, about
  its attachment point.
- `upright_axes`: bank and slope, bank only, or slope only.
- `upright_limit_deg`: past this the piece is left out (Chris's call: off
  where world up stops making sense), and always when upside down.
- `surface_offset`: along the layer's surface normal (road, wall top, inner
  face, outer face); + = away, − = in.
- `auto_embed`: sinks a tilted standing piece just enough that no base
  corner floats.
- Overhead pieces ignore upright.

The defaults are off. Builder Lab with the old presets produced the same
9,298 instances, and the Utopia dresser draws its random numbers in the same
order, so the circuits' dressings rebuild unchanged.

Presets now stand lamp poles and antennas upright. Masts and tall pylons
outside the wall are upright too, with a 30° limit and a 1.5 m surface
offset: at 45° on a 35° test bank, two pylons near the roll entry swung into
the track and the validator caught them. On Builder Lab, 60 pieces are left
out, all in the loop and the roll; that replaces the fan-out. Checked
headless with `greeble_stats_boot.gd` (counts, left-out pieces, intrusions,
and a checksum to compare code versions).
