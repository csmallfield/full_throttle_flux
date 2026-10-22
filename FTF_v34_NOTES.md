# FTF v34: the Track Builder

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
- **Step 4: the race checks.** An estimated racing speed along the lap (the
  AI's own performance model) and limits measured on the four gameworthy
  circuits: cornering, kinks, grade, crests, jump speeds, clearance overhead,
  start and grid, junction width, branch ends, respawn coverage. A
  self-test breaks Builder Lab on purpose eleven ways and checks each fault
  is caught (11/11; 16/16 with the boost pad cases added later).
- **Builder Lab** (`scenes/tracks/builder_lab.tscn`, in the manifest): an
  8.9 km test lap made with the tools: a jump, a loop, a roll, and a
  corner-cut shortcut over a bigger jump. All validator checks pass.

- **Step 5: AI lines and acceptance.** Builder Lab's main route and shortcut
  lines are trained on default_racer. Full 3-lap races at Easy, Medium and
  Hard, a pushed run and the rig probe all pass (below).
- **Step 6: the authoring guide**, `full_throttle_flux/docs/TRACK_AUTHORING.md`:
  the rules, the workflow, each feature with its limits and why, what every
  validator message means, adding a track to the game, training its AI.
- **Follow-up (after Chris's review): boost pads, AI jumps without a fork, a
  faster preview.** `BoostPadKey` puts the game's boost pads on the road
  (centre / left / right, offset, several across); the validator checks
  where they are and what the boost does next. The AI's jump handling no
  longer needs a fork. The preview of Builder Lab went from ~1.7 s to
  ~0.5 s. Details below.

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

### Builder Lab numbers (step 2: the first, 5.9 km version)

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

## Step 4: the race checks

### Limits measured on the circuits

`tools/track_builder/measure_circuits.gd` samples each circuit's MainSpline
(the offset is a rigid rotation, so curvature is unaffected) and an
estimated racing speed (below):

| | Utopia | Swoopy | Hairpin Alley | The Drop | Builder Lab |
|---|---|---|---|---|---|
| Cornering at 110 u/s, p99 / max | 11.7 / 18.2 g | 12.3 / 19.8 g | 14.2 / 34.7 g | 12.2 / 21.6 g | 2.1 / 2.9 g |
| Curvature step ("kink"), p99 / max | 0.75 / 3.6 g/m | 0.75 / 3.1 | 0.75 / 5.8 | 0.46 / 2.9 | 0.06 / 0.1 |
| Grade, p99 / max | 37 / 45% | 43 / 48% | 16 / 33% | 111 / 113% | 5 / 6% |
| Crest demand at racing speed, max | 34 u/s² | 101 | 85 | 82 | 5 |

The raw maxima are spline kinks: the circuits' sparse control points give
radii down to 14 m and grades to 113%, which no ship feels. So the limits use
the percentiles, and kinks get their own check. The Drop really is steep.

Swoopy's organic exits (v33: ~6,350 m at 90–110 u/s, ~7,645 m climbing at
33–65 u/s) are **not** crest launches: the worst crest near 6,350 needs ~7 u/s²
beyond gravity at the estimated speed, and ~108 u/s² at 100 u/s, well inside
gravity + the hover spring's pull (~225 u/s², "the crest glue" in v31). v33's
own description (ships go over the outside wall) is a lateral problem. The
crest check catches real launches; it won't explain Swoopy.

### The checks

| Check | Rule | Why |
|---|---|---|
| Cornering | over 15 g at 110 u/s (radius ~32 m) warns | tighter than 99% of the circuits' corners |
| Kinks | curvature stepping over 1.0 g/m warns | circuits' p99 is 0.75; a faired builder track ~0.1 |
| Grade | over 50% warns | only The Drop goes steeper |
| Crests | demand over 110 u/s² warns, over 200 errors | beyond any circuit / close to gravity + hover pull (a launch) |
| Jumps | racing speed at the lip under clean_speed + 5: main route error, branch warning | a must-make jump vs a choice (the AI judges a branch jump itself) |
| Jump run-up | respawn_runup under 250 m warns; the AI model's standing start under clean_speed errors | Fork Lab measured 150–220 m; the AI's acceleration model says ~60 m (it leaves out the respawn settle and throttle response), so the measured rule leads |
| Clearance | anything of this track within 10 m above its road (centre, ±60%) errors | loop exits, over/unders, overhangs |
| Start and grid | grid area over 3% grade or 1 g at 110 (radius ~480 m) warns; a slot with no road under it errors | the handoff's "straight, level stretch" |
| Junctions | main road not standard width inside one errors; a feature within 60 m of one warns | TrackJunction is fixed at 21.5 m; the junction levels the road |
| Branch ends | more than 0.05 m / 0.5° off the main spline errors | the handoff's numbers |
| Respawns (headless) | a point with no road under it errors; a gap over 2 × spacing not explained by a zone or a jump warns | uses the real TrackRespawnManager (not a tool script, so not in the editor) |

The speed estimate (`TrackSpeedProfile`): each sample's limit is
`ShipPerformanceModel.corner_speed()` of the curvature the ship must steer in
the road's own plane, then a forward pass (full throttle) and a backward pass
(braking), twice round the lap. Zones and jumps are left at top speed. Builder
Lab: 74.5 s estimated vs 76.3–80.6 s raced by the untrained AI.

### What the self-test found

`tools/track_builder/validator_selftest.gd` loads Builder Lab, breaks it one
way at a time (kink, grid on a bend, short respawn run-up, narrow junction,
geometry overhead, feature in a junction, branch drawn off the road, roll
too short, sharp crest, moved geometry), rebuilds in memory and checks the
validator says so. 11/11 after these fixes:

- **A step at a feature's end inside a junction's levelling ramp.** The
  fork's levelling reached back over the roll's exit, but only base samples
  were levelled, not the feature's mapped samples: a 5.7 cm step, read as a
  103 u/s² "crest". Features are now levelled with the road under them
  (crest on the clean track: 5 u/s²).
- **Cap faces at the lap seam.** With the road in pieces (jumps), the two
  pieces meeting at the seam each had an end cap: vertical faces flush with
  the road, which a ray landing exactly on the seam hit (a 90° "normal"). A
  ship's hover ray could too. Welded seam ends now get no cap.
- **The roll's bank between control points** came within 0.01° of the 0.5°
  limit on some rebuilds. Inside features a point now goes in every 0.5° of
  turn (was 1°): max 0.26°.
- **Test harness:** `load()` returns the cached PackedScene, whose curves the
  build writes into, so one case's damage carried into the next. The
  self-test loads uncached. (The editor isn't affected: the open scene owns
  its resources.)

The route lap is now sparser (2° / 20 m; it's logic only): Builder Lab's
scene is 460 KB (was 618).

## Step 5: AI lines and acceptance

`train_ai_lines.gd` now lists Builder Lab, with both route laps
(`ROUTES["builder_lab"] = [-1, 0]`). Trained from a fresh bake on
default_racer:

| Line | Lap | Mean target speed |
|---|---|---|
| `builder_lab` (main route) | 74.15 s | 120 u/s |
| `builder_lab__route0` (via the shortcut) | 73.22 s | 120 u/s |

Both converged after one iteration: Builder Lab is flat out everywhere (its
corners top out at 2.9 g at 110 u/s), so there's nothing for the trainer
(or the style search, which has no route support anyway) to find. Builder
Lab tests the features, not race craft. The shortcut is worth ~0.9 s a lap.

### Acceptance runs (seed 1234; 7 AI + the parked player ship)

The race probe fills the 8-ship grid with 7 AI and the player's ship
(parked). Full 3-lap races at each difficulty:

| Difficulty | Laps (best / mean flying) | Respawns | Wall contacts | Shortcut taken | Jumps (main / branch), falls |
|---|---|---|---|---|---|
| Easy | 78.9 / 81.1 s | 0 | 9 | 9/21 (43%) | 28 / 9, 0 |
| Medium | 76.3 / 77.7 s | 0 | 0 | 13/21 (62%) | 28 / 13, 0 |
| Hard | 73.2 / 74.5 s | 0 | 0 | 15/21 (71%) | 28 / 15, 0 |

Fork Lab's v32 take rates were 21% / 46–60% / 76%. Longest flight 1.17 s
(the main jump) in every race; takeoff speeds 116–120 u/s against clean
speeds of 72 and 86.

A pushed run (`PROBE_PUSH`, 70 u/s sideways + 35 up at ~140 u/s) at 1,300 m,
the loop's exit (3,000 m), the roll's end (5,200 m) and the main route
inside the fork (6,000 m): eight ships pushed, **none left the track**, 0
respawns.

The rig probe (90 s): no NaNs on any camera. The probe now labels magnetic
zones before fork/jump sections (labels only; the checksum is over the
camera transforms and every rig checksum is unchanged), so Builder Lab's
camera flips show up where they belong, in the loop and the roll (113 / 141
per camera, as on Loop Lab), and nowhere else except the `kamikaze` camera
(17, as on the other tracks).

## Follow-up: boost pads, AI jumps without a fork, a faster preview

Chris's review of steps 5 and 6: keep the junction levelling; leave the AI's
respawn acceleration model alone (the validator's measured 250 m rule
stands); the AI's jump handling shouldn't depend on a fork; and add boost
pads to the builder.

### Boost pads (`BoostPadKey`)

A key like the others: drop it near the road and the pads go on the road
surface at the nearest point of the finished track (features included, so
on a loop or in a roll too), facing the direction of travel. Under a
BranchFeature they go on the branch. Settings: `anchor` (centre / left edge /
right edge of the flat road, so an edge pad follows WidthKeys), `offset`
(+ = right), `count` side by side, `spacing` centre to centre, `strength`.
The preview draws each pad's outline with a chevron; Build instances the
game's `scenes/boost_pad.tscn` under a generated `BoostPads` node, on the
built road's frame (the MainSpline's, or the branch's), updated in place
(rebuilds stay byte-identical).

The pad scene's chevrons point down its +Z, as the hand-placed pads on the
old circuits face (checked on test_circuit_3b / 4: +Z along the direction of
travel), so the builder turns each pad that way. The trigger box is
symmetric, so which way a pad faces doesn't change what it does.

**What a pad does, measured** (`measure_boost`: the real default_racer over
a pad on a straight lane, speed every 10 m after it), against the model the
validator uses (`TrackSpeedProfile.boosted`: speed + strength, then full
throttle with the limit at max_speed + an extra that decays at the profile's
`overspeed_damping`, 2.5/s):

| Arrive / strength | At the pad | 40 m | 80 m | 160 m | 240 m | Model, worst difference |
|---|---|---|---|---|---|---|
| 116 / 150 | 266 | 215 | 178 | 136 | 123 | 4 u/s |
| 87 / 150 | 237 | 215 | 175 | 135 | 123 | 6 u/s |
| 58 / 150 | 208 | 196 | 173 | 133 | 123 | 6 u/s |
| 116 / 80 | 196 | 165 | 143 | 125 | 121 | 0 |
| 116 / 250 | 366 | 299 | 243 | 165 | 132 | 0 |

(The worst differences are where the speed changes fastest: 10 m samples at
~4.4 m per frame.) So +150 is gone in about 300 m; a pad wants ~250 m clear
before anything tight.

**Validator checks.** Before Build: each pad on the flat road at both ends
and the middle (error), no overlaps (error), not over a jump's gap (error),
not on a kicker (warning: `clean_speed` is measured without a pad), not on
the grid (warning). After Build: a ray at each corner and the centre of every
built pad: road under all of them (error), and the pad within 0.2 m of it (a
flat 12 m pad on a tight crest or in a dip; warning). Then the boost: from
each key, the boosted speed (from the racing-speed estimate at the pad, no
braking) against

- the bends ahead: over what default_racer can hold there warns. The AI's
  `corner_speed()` caps at top speed, so this uses the same yaw-rate and grip
  model without the cap (`_corner_speed_uncapped`). Above 120 u/s that model
  is an extrapolation: nothing measured it there. In the three races below
  (63 laps, each with a boost), boosted ships made 1 wall contact;
- crests ahead (the crest thresholds, 110 / 200 u/s², at the boosted speed);
- jump lips ahead: over 120 u/s warns, because `measure_jumps` only flies
  40-120 u/s.

The self-test gained five cases (16/16 pass): a pad over the road edge,
over the main jump's gap, two overlapping, +300 thirty metres before the
tightest bend, and a pad 200 m before the main jump (~127 u/s at its lip).

**Builder Lab's pads:** `BoostRow`, three across the centre of the bottom
straight (6,999 m); `BoostNE`, one against the right edge after the
north-east corner (1,499 m); `BoostShortcut`, one against the left edge of
the shortcut after its jump's outrun. Validate 0 / 0.

**Races** (270 s, seed 1234, the trained lines; the pads don't change the
road, so the lines stay valid):

| Difficulty | Best / mean flying lap | Respawns | Wall contacts (while boosted) | Shortcut | Jump falls | Top speed |
|---|---|---|---|---|---|---|
| Easy | 78.6 / 80.7 s (78.9 without pads) | 0 | 8 (0) | 43% | 0 | 257-261 |
| Medium | 75.6 / 77.4 s (76.3) | 0 | 0 (0) | 57% | 0 | 262-266 |
| Hard | 72.9 / 74.2 s (73.2) | 0 | 1 (1) | 71% | 0 | 267-270 |

Every AI ship hit 3 pads in 3 laps: the centre row, every lap. None ever hit
the edge pads. **The AI doesn't aim for pads;** it only gets the ones on its
racing line. Teaching it to would be AI work of its own (the line baker and
trainer don't know pads exist).

The rig probe (90 s): no NaNs; camera flips only in the loop and the roll
(and `kamikaze`'s usual 17), as before.

`scripts/boost_pad.gd` printed five lines per trigger; they're now behind a
`debug_log` export (off). Nothing else in it changed. The race probe prints a
`BOOST` line per ship (pad hits, wall contacts that began while boosted) on
tracks where any ship hit a pad.

### AI jump handling without a fork

The jump handling (full throttle from 60 m before a kicker to the lip, no
avoidance swerves there, holding the nose on the velocity in flight, and the
jump spans the line baker and trainer skip) was written in v32 as part of
the route-lap code for Fork Lab, so it only switched on when the track had a
fork. There was no reason for that beyond history. Now:

- `TrackSplineHelper` keeps a TrackGraph that has jumps but no branches as
  `jump_graph` (still no branch mapping: `graph` stays null) and sets the
  main lap's jump spans;
- `AIShipController` fills `route_jumps[-1]` from it, and the jump controls
  and the no-swerve rule run whenever there are route jumps, on the main lap
  (route -1) when there's no route follower.

Fork Lab and Builder Lab (forks) take the same code paths as before; the
circuits and Loop Lab have no TrackGraph. So no existing track changes (all
checksums below are unchanged; Builder Lab's Medium race gave the same
checksum before and after the change). Tested on Builder Lab with its shortcut
disabled (a lone jump), Medium and Hard, 270 s:

| | Takeoff speed, Medium | Takeoff speed, Hard | Falls |
|---|---|---|---|
| Before | 112-113 | 116-118 | 0 |
| After | 120 every time | 120 every time | 0 |

Before, the AI eased off up the kicker; now it holds full throttle as it
does on Fork Lab. This jump clears from 72, so it didn't matter here; on a
jump nearer the AI's speed it would. A short training run on the same
variant (no ROUTES entry, the generic path) trained normally (the result
was thrown away; Builder Lab's real lines are unchanged).

### The preview is faster

Builder Lab's preview took ~1.7 s headless: the fork's junction walks
projected each branch point onto the whole 8.9 km lap (about 1,400
whole-lap projections per preview). They now search ±60 m around the previous answer
(`TrackSampler.project_near`). Evaluate went from ~1.4 s to ~0.33 s, the
whole preview to ~0.5 s. Build output is byte-identical.

## Regressions

Before any change, all 11 handoff baselines matched exactly. After steps 2,
3 and 4, all 11 are unchanged (the only runtime change is the opt-in width
profile and seam weld in `TrackRoadSegment`):

| Track | AI race checksum | Rig checksum |
|---|---|---|
| test_circuit_3_live | 3929678988 ✓ | 3621838145 ✓ |
| test_circuit_5_live | 3790437673 ✓ | 2900775167 ✓ |
| test_circuit_6_live | 2668530540 ✓ | 110340458 ✓ |
| test_circuit_7_live | 133359682 ✓ | 2300779685 ✓ |
| loop_lab | 3860760227 ✓ (140 s) | 3358873327 ✓ (75 s) |
| fork_lab | 3551594432 ✓ (150 s) | — |
| builder_lab (new) | 3416591037 (270 s, Medium) | 2816354120 (90 s) |

After the follow-up (boost pads, AI jumps without a fork, the faster
preview) all 11 are unchanged again. The Builder Lab numbers are for the
final build with its boost pads and trained lines (Easy 3036415311, Hard
1987363982, both 270 s; before the pads: Medium 3382735449, Easy
3682742997, Hard 435312279, rig 3940470676). Earlier builds' numbers are in the
step sections; the race results were the same throughout. Its
race, 240 s, seed 1234, 7 AI on the untrained shared bake: 2–3 laps each,
76.3–80.6 s, **0 respawns, 0 wall contacts**, longest flight 1.17 s; the
shortcut taken on 13 of 21 passes (62%); 38 jump attempts (25 main, 13
branch), no falls; race order through the fork matched the exit order 100%
(same route) / 97% (mixed). The rig probe ran 90 s with the branch, both
jumps and the main route as their own segments, no NaNs.

## Open items

- `TrackBuilder` has no undo for Build (Ctrl+Z won't revert it); rebuilding
  from the inputs is the recovery.
- `fork_lab_turtle.gd` is still in `tools/fork_lab/`; the builder preloads it
  from there (unchanged, so Fork Lab's build output can't move).
- **The AI doesn't aim for boost pads**: it gets the ones on its racing line
  (see the follow-up).
- The boosted-corner check extrapolates the AI's cornering model above
  120 u/s, where nothing has measured it.
- The AI's acceleration model says a respawned ship reaches jump speed in
  ~60 m; Fork Lab measured 150-220 m. Chris: leave the model; the
  validator's 250 m rule covers it.
- The Report field shows the last Build/Validate until the next one, even
  after inputs change; Validate's "out of date" warning is the reliable signal.
- Respawn coverage is only checked headless (the respawn manager isn't a
  tool script, so it can't run inside the editor).
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
# what a boost pad does to default_racer, against the validator's model
godot --headless --fixed-fps 60 --path full_throttle_flux -s res://tools/track_builder/measure_boost_boot.gd
# validator self-test (breaks Builder Lab 16 ways, checks each is caught)
godot --headless --path full_throttle_flux -s res://tools/track_builder/validator_selftest_boot.gd
# the circuits' measured limits (cornering, kinks, grade, crests)
godot --headless --path full_throttle_flux -s res://tools/track_builder/measure_circuits_boot.gd
# train its AI lines (both routes)
godot --headless --path full_throttle_flux res://tools/train_ai_lines.tscn -- --track=builder_lab --fresh
# race it
PROBE_TRACK=builder_lab PROBE_SECONDS=270 PROBE_SEED=1234 godot --headless --fixed-fps 60 --path full_throttle_flux -s res://tools/dev/ai_race_probe_boot.gd
```
