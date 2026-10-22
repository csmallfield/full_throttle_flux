# FTF v34: the Track Builder (in progress)

A way to make new tracks without the road/spline offset, with loops, barrel
rolls, jumps and split tracks to come. Chris draws the base curve and the
banks by hand in Godot and sees the result within a fraction of a second;
one **Build** writes the track the game runs on, one **Validate** checks it.
The brief is `full_throttle_flux/docs/TRACK_BUILDER_HANDOFF.md`.

Done so far:

- **Step 1: live preview, bank keys, width keys.** A `TrackBuilder` node, a
  hand-drawn `BaseSpline`, and `BankKey` / `WidthKey` / `StartKey` nodes
  dropped anywhere near it. A coloured ribbon follows every edit.
- **Step 2: Build and the validator core.** Build writes the MainSpline (tilts
  solved), the road and walls with the width profile, the start line and the
  grid. Validate checks the offset rule, the road surface against the spline,
  the bank the game will use against the bank keyed, roll rate, width taper,
  minimum width and key placement. Both run in the editor and headless.
- **Builder Lab** (`scenes/tracks/builder_lab.tscn`, in the manifest): a
  5.9 km test lap made with the tools. It races: 7 AI ships, 0 respawns, 0
  airborne time, best lap 50.9 s on the untrained shared bake.

Coming: roll, loop, jump and branch features (step 3), the rest of the
validator (step 4), AI training and the full acceptance run on Builder Lab
(step 5), `docs/TRACK_AUTHORING.md` (step 6).

## Decisions taken with Chris (step 1)

| Question | Decision |
|---|---|
| Hand-set handles make a curvature step (a lateral-g jolt) at every control point | **Fair it**, with `fairing_m` = 0 to keep the drawn curve exactly |
| Bank key dragging | **Drop anywhere; the marker snaps** to the nearest track point. No EditorPlugin |
| Feature footprints | **The builder fits the ends** (no hand-drawn straight-and-level stretches). Step 3 |
| Track width (asked during step 1) | **WidthKeys**, left and right half widths, linked by default. Walls move with the edge and keep their shape |

## How it works

### The base curve is resampled, never used directly

The circuits' splines have 22-44 control points, 180-300 m apart. Godot's
frame twists on its own between control points, so a bank solved only there
drifts in between. `TrackSampler` samples the base every 1 m, applies the
bank and width profiles per sample, and the build emits a **dense**
MainSpline: a new control point whenever the tangent or the up vector has
turned 1° (or every 12 m on straights, at least 2 m apart). Builder Lab: 755
control points for 5.9 km, a 116 KB scene file.

### Fairing is local

A cubic Bézier's curvature is smooth inside each segment and only jumps at
control points. So fairing rewrites a window around each control point
(`fairing_m` wide, at most 45% of the gap to the neighbours) with a quintic
Hermite blend that matches position, direction and curvature at both window
ends. Everything outside the windows is exactly what was drawn.

| Builder Lab | fairing 0 | fairing 40 m |
|---|---|---|
| worst lateral-g step (g per metre at 110 u/s) | 1.86 | 0.37 |
| furthest the curve moved | 0 | 0.10 m |

(A first version smoothed curvature along the whole lap and spread the
closure error; it moved the curve up to 5.8 m. Rejected.)

### Tilts are solved, never typed

The build hands the dense samples (position, tangent, desired up) to
`fork_lab_turtle.gd`'s `build_curve()`, unchanged: tilt 0, read Godot's baked
up vectors, measure the angle to the desired up, unwrap, write back, verify.
Builder Lab: 0.001° max error at the control points. The lap is an **open
curve with coincident ends**, as on the labs, so a closing span can never
unwind accumulated tilt.

### Keys are world-placed

A key's distance along the track is derived by projecting it onto the
(faired) base each time, with the last distance as a hint so it can't jump
to another stretch where the track passes near itself. Editing the curve
upstream leaves keys where they are. A key more than 30 m from the track is a
validator error.

### Width

`TrackRoadSegment` has an optional `width_profile` (distance, left, right).
Polygon points within `width_stretch_limit` of the centre are scaled (the road
stretches); points beyond it move sideways by the width change (lips and
walls keep their shape). Walls use a stretch limit of 0. **An empty profile
runs the exact pre-v34 code path**, so Fork Lab is untouched. The build only
emits profile entries where the width is changing (Builder Lab: 184).

Limits the validator uses for now: taper over 0.1 m of half width per metre
warns; a half width under 10 m warns. Both to be tuned once Chris has driven
them. Junctions (step 3) will hold the standard 21.5 m.

### Build output is stable

Godot 4.7 gives every saved node a random `unique_id`, with no API to set it,
so a build that deleted and recreated its nodes would rewrite the whole
`.tscn` every time. The build **updates its nodes in place by name** (tagged
with the `track_builder_generated` group) and copies the solved curve into the
existing `Curve3D` sub-resource. **Building twice gives a byte-identical
scene file** (checked). Nodes outside the group (environment, set dressing)
are never touched; generated nodes the build no longer makes are removed.

The MainSpline stays a direct child of the track root: `MagneticTrack`,
`TrackGraph`, the AI's spline helper and the probes all look for it there.

### Validator findings that changed the build

- **Lap seam crack.** The first and last rings of a whole-lap road segment
  were 0.003° apart, enough for a ray exactly on the seam to slip through.
  `TrackRoadSegment.weld_lap_seam` (off by default) makes the last ring reuse
  the first ring's frame.
- **Banking twists the road surface.** While the bank changes, the road is a
  helicoid: off the centre line it tilts fore and aft by about
  lateral × roll rate (1.2° at 12 m and 0.1°/m). That's real geometry, not a
  build error, so the surface check compares the hit normal against the ideal
  extruded surface at that lateral position, not the centre-line up vector.

### Builder Lab numbers

| Check | Result |
|---|---|
| Surface (3,558 rays: centre and 60% out each side, every 5 m) | max height error 0.001 m, max normal error 0.25°, 0 misses |
| Bank delivered vs keyed | max 0.047° |
| Max roll rate | 0.10 °/m |
| Build time | ~0.75 s headless |
| Preview rebuild | ~0.1 s |
| AI race, 150 s, seed 1234, 7 AI (untrained shared bake) | 0 respawns, 0 airborne, 2 wall touches; laps 50.9-52.7 s; checksum 3775227380 |
| Cinematic rig, 60 s | no NaNs, no flips; `pan` 51% and `kamikaze` 29% occluded (no tuning yet) |

## Regressions

Before any change, all 11 handoff baselines matched exactly. After step 2,
all 11 are unchanged (the only runtime change is the opt-in width profile and
seam weld in `TrackRoadSegment`):

| Track | AI race checksum | Rig checksum |
|---|---|---|
| test_circuit_3_live | 3929678988 ✓ | 3621838145 ✓ |
| test_circuit_5_live | 3790437673 ✓ | 2900775167 ✓ |
| test_circuit_6_live | 2668530540 ✓ | 110340458 ✓ |
| test_circuit_7_live | 133359682 ✓ | 2300779685 ✓ |
| loop_lab | 3860760227 ✓ (140 s) | 3358873327 ✓ (75 s) |
| fork_lab | 3551594432 ✓ (150 s) | — |
| builder_lab (new) | 3775227380 (150 s) | 3489370936 (60 s) |

## Open items

- `TrackBuilder` has no undo for Build (Ctrl+Z won't revert it); rebuilding
  from the inputs is the recovery.
- Lateral-g and grade limits for the validator: to be measured from the four
  circuits (step 4).
- `fork_lab_turtle.gd` is still in `tools/fork_lab/`; the builder preloads it
  from there. Move it to a shared place in step 3 if the features need it too.
- The Report field shows the last Build/Validate until the next one, even
  after inputs change; Validate's "out of date" warning is the reliable signal.

## Running it

In the editor: open `scenes/tracks/builder_lab.tscn`, select `TrackBuilder`.
Edit `BaseSpline` and the keys; press **Build**, then **Validate**.

```
# headless build (saves the scene), then validate
godot --headless --path full_throttle_flux -s res://tools/track_builder/build_boot.gd -- --scene=res://scenes/tracks/builder_lab.tscn
# validate only
godot --headless --path full_throttle_flux -s res://tools/track_builder/validate_boot.gd -- --scene=res://scenes/tracks/builder_lab.tscn
# preview numbers (fairing on/off, key placement)
TB_SCENE=res://scenes/tracks/builder_lab.tscn godot --headless --path full_throttle_flux -s res://tools/track_builder/preview_check_boot.gd
# screenshots of the overlays and the built road (software GL)
TB_OUT=/tmp/shots xvfb-run -a -s "-screen 0 1600x1000x24" godot --rendering-driver opengl3 --path full_throttle_flux -s res://tools/track_builder/preview_shots_boot.gd
# the editor code path, headless (Build + Validate inside a running editor, no save)
TB_EDITOR_SELFTEST=1 godot --headless -e --path full_throttle_flux res://scenes/tracks/builder_lab.tscn
# race it
PROBE_TRACK=builder_lab PROBE_SECONDS=150 PROBE_SEED=1234 godot --headless --fixed-fps 60 --path full_throttle_flux -s res://tools/dev/ai_race_probe_boot.gd
```
