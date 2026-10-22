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
- **Step 3: features.** `RollFeature`, `LoopFeature`, `JumpFeature` and
  `BranchFeature` (a split track, with its own hand-drawn `BranchBase`).
  Features are placed like keys and the builder fits them onto the curve you
  drew. A **Clear build** button removes everything the builder generated.
  `measure_jumps` flies the real ship off each jump to set its `clean_speed`.
- **Builder Lab** (`scenes/tracks/builder_lab.tscn`, in the manifest): an
  8.9 km test lap made with the tools: a jump, a loop, a roll, and a
  corner-cut shortcut over a bigger jump. All validator checks pass.

Coming: the rest of the validator (step 4), AI training and the full
acceptance run on Builder Lab (step 5), `docs/TRACK_AUTHORING.md` (step 6).

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

## Step 3: features

### Fitting features onto a hand-drawn curve

Chris chose "the builder fits the ends" over "draw a straight, level
stretch": a feature can sit on whatever the base does under it. Each feature
defines its shape in a canonical frame (a straight, level road heading
forward: forward x, lateral y, height h, and the road's up), starting and
ending on the centre line with zero offset, slope and curvature.
`TrackComposer` maps that shape onto the base along the footprint, like a
path deformer:

```
position = base(u) + right(u) * y + level_up(u) * h,   u = footprint start + x
up       = right(u) * up.x + level_up(u) * up.y + tangent(u) * up.z
```

So the feature joins the drawn curve exactly at both ends, and a gently
curving or climbing footprint bends the feature with it. The validator warns
when the base turns or climbs too much under a feature (loop 15° / 3%, jump
10° / 3%, roll 60° / 8%). Nothing outside a footprint moves.

The composer walks the lap from the lap origin (start line − start_lead),
splices the shapes in and resamples the whole lap every metre: that composite
is what the preview draws, the build emits and the validator checks. Its
distances are the MainSpline's to within a metre or two.

| Feature | Shape | Footprint (defaults) |
|---|---|---|
| Roll | Loop Lab's: the up turns 360° about the travel direction, smoothstep. Centre line unchanged (pose-neutral). Keyed bank still applies on top | `length` (800 m) |
| Loop | Loop Lab's teardrop (sin² pitch curvature, 820 m of arc, 65 m top radius), stepping `shift` (90 m) sideways. An S-jog before (−shift/2) and after (−shift/2) brings the exit back onto the drawn curve | 2 × `jog_length` + the loop's forward travel = 961 m |
| Jump | Fork Lab's: climb (so the whole jump is height-neutral), run-up, kicker, a real gap, landing ramp, outrun | 554 m |
| Branch | A second, hand-drawn route; ends snapped onto the main track (below) | — |

Rolls and loops emit their own magnetic zone (Loop Lab's settings); jumps
become `TrackJump`s in a `TrackGraph`, with the road cut at the gap and a
respawn trigger under it, as on Fork Lab.

Keyed bank inside a footprint: a roll adds its turn on top of it; a loop and
a jump fade it out (over the first jog, the climb) and back in. A bank key
inside a loop or jump footprint is a validator warning.

### Jumps: clean_speed is measured, not guessed

`tools/track_builder/measure_jumps_boot.gd` builds a straight test lane for
each JumpFeature (400 m run-up + the feature's exact shape), flies the real
ShipController (default_racer, TrackJump flight physics) off it at lip
speeds 40–120 u/s in 2 u/s steps, and writes the result into the feature,
then rebuilds. A landing is clean if the ship lands on the landing ramp with
the hull at least 2.1 above the road and rebounds at most 3.6 u/s (Fork Lab's
criteria, FTF_v31). Near the threshold the outcome isn't monotonic, so
`clean_speed` is the lowest speed from which **every** faster speed is clean.
A changed shape makes it stale (hash), and the validator warns.

| Jump | Shape | clean_speed (lip) | Lowest survivable |
|---|---|---|---|
| Builder Lab main jump | Fork Lab shared jump: 6°/70 m kicker, 55 m gap, 4 m drop | 72 u/s | ~57 (hull strike) |
| Builder Lab branch jump | 8° kicker, 80 m gap, 5 m drop | 86 u/s | ~75 (hull strike) |

The main jump is Fork Lab's shared-jump shape, which v31 measured clean from
66. The difference is the rebound criterion: here it's measured along the
road's normal for 2.5 s after touchdown, and at 64–70 u/s the spring rebounds
8–14 u/s. v31's own note applies: takeoff varies ±2–3 u/s with the spring's
phase off the kicker.

### Split tracks

A `BranchFeature` holds a hand-drawn, OPEN `BranchBase` from a point on the
main road to a later one; its own BankKeys, WidthKeys and JumpFeatures go
under it. The builder:

- snaps the ends: over the first and last `junction_blend` (150 m) the
  branch eases from the main centre line (at the same progress) into the
  drawn curve, positions and ups;
- finds the junctions: each ends where the centre lines are 62 m apart
  (Fork Lab's rule; inner walls clear of each other);
- **levels both roads across each junction**, height and bank (TrackJunction
  builds the union road flat at one height). Inside, the road is brought to
  the fork's (or rejoin's) height; outside, it eases back to the drawn
  heights over a ramp sized for at most ~3% grade (60 m per metre of change,
  80–500 m). The Report says how far it moved the road. On Builder Lab the
  fork reaches into a climbing corner: levelled to within 0.00 m / 0.01°;
- emits BranchSpline, the route lap (main → branch → main, for the AI and the
  rig), the TrackBranch, Fork/RejoinJunction, and road and wall pieces: the
  main road and the branch fade their lips into each junction; the main wall
  on the branch's side and the branch's inner wall stop at the junctions.

Validator: the junctions are flat (height within 0.15 m of the junction
level) and level (within 1°) on both paths; the branch's road gets the same
surface and bank checks as the main one.

### Validator findings in step 3

- **A frame interpolation bug.** `TrackSampler.frame_at` skipped
  interpolating tangents less than 0.81° apart (`dot < 0.9999`). In a loop
  neighbouring samples differ by 0.8°, so the check compared against the
  wrong sample's tangent: "0.77° bank error" that wasn't there (the built
  curve matched the composite to 0.05° at every sample).
- **Facets on a twisting road.** The 3 m strips and 1 m rings make a slight
  washboard wherever the road twists: ~0.5° on the centre line and isolated
  spikes up to ~4.5 m × the roll rate at strip edges (2.6° in the roll). The
  surface tolerance is 0.5° + 4.5 m × roll rate (Loop Lab's roll, ~2°,
  drives fine; finer strips would double the road's triangles everywhere).
- **Loops need denser control points.** At 2 m spacing Godot's interpolated
  frame drifted off the loop's helix; inside features the build places a
  point every metre when the road turns (1° rule).
- **Duplicate point at the jump lip** (end of the kicker + the lip). The
  composer drops near-duplicates; the jump test lane didn't, and its tilt
  solve failed. Fixed in the shape.

### Builder Lab (step 3)

Redrawn as an 8.5 km base (roughly a rectangle) with a straight per feature:
north straight with the start and the jump, east straight with the loop,
south straight (gently downhill) with the roll, a corner-cut fork with a
bigger jump to the bottom straight, and a narrowing into the last corner.
The scene is written by `make_builder_lab_start.gd` (a record of the starting
point), then built with the tools.

| | |
|---|---|
| Lap | 8,942 m; MainSpline 1,622 control points |
| Shortcut | 1,338 m vs 1,454 m of main route (saves 116 m) |
| Validate | 0 errors, 0 warnings |
| Surface | 4,923 rays main + 333 branch, max height error 0.014 m |
| Bank delivered | max 0.38° main, 0.05° branch |

## Regressions

Before any change, all 11 handoff baselines matched exactly. After steps 2
and 3, all 11 are unchanged (the only runtime change is the opt-in width
profile and seam weld in `TrackRoadSegment`):

| Track | AI race checksum | Rig checksum |
|---|---|---|
| test_circuit_3_live | 3929678988 ✓ | 3621838145 ✓ |
| test_circuit_5_live | 3790437673 ✓ | 2900775167 ✓ |
| test_circuit_6_live | 2668530540 ✓ | 110340458 ✓ |
| test_circuit_7_live | 133359682 ✓ | 2300779685 ✓ |
| loop_lab | 3860760227 ✓ (140 s) | 3358873327 ✓ (75 s) |
| fork_lab | 3551594432 ✓ (150 s) | — |
| builder_lab (new) | 3536941873 (240 s) | 4274104507 (90 s) |

The Builder Lab numbers are for the step 3 track (features and fork). Its
race, 240 s, seed 1234, 7 AI on the untrained shared bake: 2–3 laps each,
76.3–80.6 s, **0 respawns, 0 wall contacts**, longest flight 1.17 s; the
shortcut taken on 13 of 21 passes (62%); 38 jump attempts (25 main, 13
branch), no falls; race order through the fork matched the exit order 100%
(same route) / 97% (mixed). The rig probe ran 90 s with the branch, both
jumps and the main route as their own segments, no NaNs.

## Open items

- `TrackBuilder` has no undo for Build (Ctrl+Z won't revert it); rebuilding
  from the inputs is the recovery.
- Lateral-g and grade limits for the validator: to be measured from the four
  circuits (step 4).
- `fork_lab_turtle.gd` is still in `tools/fork_lab/`; the builder preloads it
  from there (unchanged, so Fork Lab's build output can't move).
- **AI jump control needs a fork.** The AI's run-up speed control and its
  "no swerving on a kicker" rule only switch on when the track has a route
  (`has_routes()`), and `TrackSplineHelper` drops a TrackGraph without
  branches. A jump on a track with no fork gets no special AI handling. On
  Builder Lab before the fork went in, 7 AI cleared the main jump at racing
  speed with no respawns, so it matters only for jumps near the AI's
  limits. Widening it touches AI code paths; left for a decision.
- Width under a junction: TrackJunction is fixed at the standard 21.5 m; the
  snap blends a branch's width to standard at its ends, but WidthKeys on the
  main track inside a junction aren't checked yet (step 4).
- The Report field shows the last Build/Validate until the next one, even
  after inputs change; Validate's "out of date" warning is the reliable signal.
- Builder Lab's scene is 478 KB, about half of it the route-lap curve (a
  whole second lap of control points, logic only). It could be emitted
  sparser. Rebuilds are still byte-identical, so it doesn't churn.
- The race and rig probes run in parallel share `user://baked_lines/`; when
  both bake the same new line at once, one reads a half-written cache file
  (a parse error, then it re-bakes). Harmless, but run one probe first on a
  track whose lines aren't cached yet.

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
# measure every jump's clean_speed (flies the real ship), then rebuild and save
godot --headless --fixed-fps 60 --path full_throttle_flux -s res://tools/track_builder/measure_jumps_boot.gd -- --scene=res://scenes/tracks/builder_lab.tscn
# race it
PROBE_TRACK=builder_lab PROBE_SECONDS=240 PROBE_SEED=1234 godot --headless --fixed-fps 60 --path full_throttle_flux -s res://tools/dev/ai_race_probe_boot.gd
```
