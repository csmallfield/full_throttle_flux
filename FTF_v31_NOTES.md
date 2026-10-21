# Full Throttle Flux — v31: forks, jumps + Fork Lab

A new greybox test track with a **fork** (two routes that split and rejoin)
and two **jumps**: one on a shared section that everyone takes, and a bigger
one on the shortcut branch. The branch is shorter, but you have to clear its
jump. Player first: time trial and endless work. The AI and the cinematic rig
don't crash there and run the main route, but they don't use the branch yet
(see "Not done yet / next").

## Files

| File | What |
|---|---|
| `scripts/tracks/track_graph.gd` | `TrackGraph` node: branches + jumps, `locate()` (which path a position is on), branch → main distance map, respawn exclusions |
| `scripts/tracks/track_branch.gd` | `TrackBranch` resource: a branch Path3D, fork/rejoin distances on the MainSpline, junction lengths |
| `scripts/tracks/track_jump.gd` | `TrackJump` resource: kicker/lip/landing/landing-end on a path, respawn run-up, flight and landing physics knobs |
| `scripts/tracks/track_road_segment.gd` | `TrackRoadSegment`: extrudes a cross-section along a **distance range** of a Path3D at load (mesh + trimesh collision), with edge-lip fades |
| `scripts/tracks/track_junction.gd` | `TrackJunction`: a Y junction's flat union road and its splitter wedge, built at load |
| `tools/fork_lab/build_fork_lab.gd` | Generator for `scenes/tracks/fork_lab.tscn` |
| `tools/fork_lab/fork_lab_turtle.gd` | The Loop Lab turtle and tilt solver, plus pitch (kickers, landings) |
| `tools/fork_lab/check_fork_lab.gd` | Raycast verification: road, gaps, seams, junctions, grid, branch map |
| `tools/fork_lab/jump_sim.gd` + `_boot` | Flies the real ShipController off kicker ramps at a range of speeds; what the jumps were sized from |
| `tools/fork_lab/fork_lab_driver.gd` + `fork_lab_drive_boot.gd` | Headless autopilot that takes a chosen route at the fork: per-section, per-jump, progress, respawn, camera and rig stats, stills |
| `scenes/tracks/fork_lab.tscn` | The track (generated; re-run the builder rather than hand-editing) |
| `resources/tracks/fork_lab.tres` | Track profile "Fork Lab", in the manifest; `supports_race = false` |

Also changed (all inert on tracks without a `TrackGraph`, proven below):

- `ship_controller.gd`: jump flight (below).
- `track_spline_helper.gd`: `world_to_spline_offset()` is branch-aware when the track has branches. The old search moved into `_main_closest()` unchanged.
- `track_respawn_manager.gd`: branch- and jump-aware respawn points when the track has a `TrackGraph`.

## Fork Lab

Same 42 m road / 57 m wall-to-wall section and grid material as the test
circuits. 3,559 m via the main route.

```
start -> 3 deg climb -> SHARED JUMP -> banked 180 right -> FORK
   main route: 45 left, straight, banked 90 right, straight, 45 left  (1,238 m, no jump)
   branch:     straight on, 3 deg climb, BRANCH JUMP                  (1,001 m)
-> REJOIN -> banked 180 right -> closing straight (grid) -> start
```

The main route bulges out symmetrically, so it comes back exactly onto the
branch's line (closure error 7 mm, snapped). The shortcut is **237 m shorter**.
Both jumps are height-neutral (a gentle 3° climb before each, solved), so the
junctions are flat and level at y = 0, which the junction geometry needs.

```
godot --headless --path . -s res://tools/fork_lab/build_fork_lab.gd
godot --headless --path . -s res://tools/fork_lab/check_fork_lab.gd
```

### Architecture (as chosen): MainSpline = canonical lap, branch = second Path3D

- `MainSpline` runs the **main (long, safe) route**. That way the AI, the rig and anything else that only knows the MainSpline follow the route without a jump.
- `BranchSpline` runs from the fork to the rejoin. A `TrackBranch` on the `TrackGraph` holds its fork and rejoin distances on the MainSpline.
- **Branch distance → main distance** (`TrackGraph.branch_to_main`): piecewise. In the middle it's linear, as suggested (each shortcut metre counts 1.38 main metres). In the two junctions, where the roads overlap, it's a correspondence table, because a linear map made progress jump there (below).
- **Which path a position is on** (`TrackGraph.locate`) is stateless: the nearest centre line of the MainSpline and each branch. Every consumer keeps its one-call API, which is why this works with the position tracker, respawn manager, spectator, rig and recorder without touching them. Tradeoff: this assumes a branch never passes close to another part of the track. A branch crossing over the main road (a bridge) would need a per-ship stateful tracker. Fork Lab doesn't need one.

**Junction mapping, measured.** The largest step *back* in lap progress per tick (what `RacePositionTracker` sees), autopilot through the fork:

| Junction map | Main route | Branch |
|---|---|---|
| Linear, slope 1 in the junctions | −8.5 m (fork junction) | 0 |
| Same cross-section (plane through the branch point) | −6.8 m | 0 |
| **Medial line** (the point equidistant from both centre lines gets the same answer from each) | **0.00** | **0.00** |

The nearest-path choice flips between the two centre lines somewhere in the
junction. With the medial map, both answers agree exactly where it flips. The
largest step *forward* is 2.8 m per tick: 120 u/s × 1/60 s × 1.38 on the
shortcut's middle section, so it's never a jump. The map is monotonic (slope
0.91–1.38 per branch metre; `check_fork_lab`). Also tested over three laps
alternating main and branch, and at ±15 m lateral offsets: no backward steps.

`TrackSplineHelper` on branch tracks refines its coarse main search (which
steps ~7 m on a 3.5 km lap) before comparing distances (`TrackGraph.refine_main`).
Cost per `world_to_spline_offset` call: 0.088 ms against 0.031 ms without
branches. The junction tables take 225 ms to build on first use.

**Race positions** are `laps + offset`, so they inherit the same continuity:
ranking can't flip spuriously at the fork or the rejoin. In the middle of the
fork, ranking a branch ship against a main-route ship is an estimate (the
linear map assumes even progress along the branch). It's exact at both
junction ends.

### Geometry: why not CSG

A CSGPolygon3D runs a whole path, so it can't have gaps (jumps) or open its
walls at a junction. Two overlapping CSG roads don't work either: each road's
0.9 m edge lip stands up in the middle of the other one. Per-piece Path3Ds
with copied sub-curves would need exact cut points. Saved ArrayMesh resources
would put about 20 MB of mesh and collision data in git.

So geometry is **built at load** from the splines (like CSG, so the scene file
stays at 96 KB and always matches its curves):

- `TrackRoadSegment`: the test circuits' road and wall sections extruded along a distance range, 0.5 m rings for road and 1 m for walls, the same 3 m road strips as Loop Lab, end caps (the front of a landing ramp is solid), and one-sided trimesh collision like CSG. **Lip fades**: the road's edge lips fade to flat over 30 m into and out of each junction, so there's no step anywhere.
- `TrackJunction`: the 2D union of the two road strips (`Geometry2D.merge_polygons`), triangulated as one flat surface on layer 1. The **splitter** is a wedge between the two roads' inner wall faces, from a sharp nose where they meet out to where the junction ends and the ordinary inner walls take over (layer 4). Junctions must be flat and level. The junction ends where the centre lines are 62 m apart, so the inner walls clear each other.
- Main walls: the main route's right wall is the inner one, the branch's left wall is the inner one, and the outer walls run straight through both junctions.
- Building it all takes 1.2 s at load in GDScript. Fine for a test track. A dressed track might want it baked.

`check_fork_lab` (raycasts):

| Check | Result |
|---|---|
| Road every 5 m at 5 laterals, both splines | 0 misses, height error ≤ 2 mm. Normal ≤ 3.2° from the centre frame, the banked turns' true twist at 18 m off centre. |
| Straight down through both gaps | 0 / 385 rays hit anything |
| Seams (shared road → junction, junction ends, lap seam), 0.25 m steps out to ±21 m | 0 misses (the hover ray never drops through). Max step 0.008 m per 0.25 m, the lip fade itself. |
| Junction road grid, 2 m | 0 / 7,480 misses, 0 off the plane |
| Wall rays along each route through each junction at hover height, ±17 m | 0 / 3,164 blocked: neither route is blocked by the splitter or the other route's walls |

### Jumps

Sized with `jump_sim` (the real ShipController and kicker geometry), then
measured on the track with the driver. The sim also showed why the physics
had to change.

**What stock ShipController does in the air** (sim, 8° kicker, 120 u/s):

- `air_drag` 0.161/s against thrust settles at 35.6 u/s: **113 u/s at the lip is down to 54 u/s by touchdown.** All approach speeds landed at ~55 u/s.
- The hover ray reaches 3× hover height (8.25 m). A descending ship counts as "grounded" from ~8 m up, gravity stops, and the spring **pulls** it down at hover_force_max (200 u/s²): the crest glue. Touchdown at 25–31 u/s into the road, min hover 0.08–0.89 (hull on the road), rebound up to 15 u/s.
- On Fork Lab with stock physics (`FL_STOCK=1`): the shared jump lands at 63 u/s (−54) with the hull on the road (hover 0.03, rebound 26 u/s). **The branch jump can't be cleared at all**: 25 falls in a row at full speed.

**Jump flight** (`ShipController`, inert unless a flight takes off from a `TrackJump`):

- The state is set at **takeoff** (the hover ray stops hitting within a jump's kicker-to-landing range, via `TrackGraph.jump_at`), not by position. A ship leaving a crest anywhere else keeps the profile's air physics.
- In the air: `TrackJump.air_drag` (−1 = the profile's ground drag). Gravity, its 1→2× ramp and the vertical decay are untouched.
- While landing, until the ship has been settled at hover height for 0.5 s:
  - the spring's downward pull is capped at 2 g (`landing_pull_limit_g`), so the ship keeps falling as it was instead of being yanked down;
  - damping ×3 (`landing_damping_scale`; the profile's damping ratio is ~0.2, which bounces);
  - hover_force_max ×2 (`landing_force_scale`).
- Also tried: scaling the pull to 0. Rejected: "grounded" means no gravity, so the ship floated at constant height over the outrun.
- Safe positions aren't recorded on jumps; `respawn()` clears the state.

**The jumps:**

| | Shared jump (main 330–575 m) | Branch jump (branch 470–760 m) |
|---|---|---|
| Kicker | 6°, 70 m (sin² vertical curvature) | 8°, 70 m |
| Gap (horizontal, no road, no collision) | 55 m | 100 m |
| Landing lip | 4 m below the kicker lip | 6 m below |
| Landing ramp | 6° down for 40 m, then an 80 m outrun to level | same |
| **Clean landing from** (hover ≥ 2.1, rebound ≤ 3.6) | **66 u/s at the lip** (68 approach) | **93 u/s at the lip** (96 approach) |
| Survives with a hull strike on the landing lip (hover 0.3–1.5, rebound 8–18 u/s) | 54–64 | 85–91 |
| Falls | ≤ 49 | ≤ 83 |

Racing speed is 120, so the shared jump is forgiving and the branch jump
needs you to arrive within ~22% of top speed: a wall touch or a lift in the
run-up costs the jump. Note that around the threshold the outcome isn't
monotonic in speed. The hover spring is still oscillating from the kicker
when the ship leaves the lip, so takeoff vertical speed varies ±2–3 u/s with
spring phase. 95 u/s held fell once and clipped through once.

**Landing at full speed** (autopilot flat out):

| | Flight | First ray contact | Into the road at contact / at hover height | Min hover (2.75) | Rebound | Speed |
|---|---|---|---|---|---|---|
| Shared | 1.00 s, apex +5.8 m | 66 m down the landing ramp | −17.6 / −9.4 u/s | 2.32 | 3.5 u/s | 120 → 118 |
| Branch | 1.10 s, apex +7.8 m | 33 m down | −15.5 / −5.0 u/s | 2.36 | 3.4 u/s | 120 → 119 |

There's no mid-flight grounding at any speed: the hover ray never catches the
far side or the walls (layer 4 isn't in its mask) before the landing ramp. At
low speed the ray grounds at the landing lip, which is the landing.

**Risk and reward** (autopilot, flat out): flying lap **32.00 s main route,
30.07 s shortcut (−1.93 s)**. A failed branch jump costs ~6.2 s (fall, respawn
on the branch, standing start, second attempt), so the shortcut pays off unless
you fail more than about one attempt in four.

### Respawns (branch- and jump-aware)

- Points on the MainSpline and on each branch. A ship respawns at the last point **behind it on the path it's on**. Before a branch's first point, it gets the last main point before the fork.
- No points from `respawn_runup` before a kicker to the end of its landing: 150 m for the shared jump, 220 m for the branch jump (both measured to give a standing start enough speed).
- A `RespawnTrigger` box under each gap, 10 m below the landing lip, respawns a ship that fell short a moment after it drops.

| Test | Result |
|---|---|
| Shared jump, approach held at 45 | Fell. Back on **main at 150 m** (180 m before the kicker), up and heading error 0.0°, settled at hover height. Second attempt took off at 110 u/s and landed. |
| Branch jump at 85 / 80 / 60 | Fell. Back on the **branch at 226 m** (244 m before the kicker), 0.0° / 0.0°. Second attempt took off at 116 u/s and landed. |

Graph-track points are 4 m above the road instead of `respawn_height_offset`
(20 m), so `settle_on_surface()` reaches the road. **Found on the way:** from
20 m the ship free-falls, and the stock spring pulls it down harder once in
range. Measured on test circuits 3 and 6 with the current code: it hits at
~48 u/s, ends at hover 0.05 and is still not grounded 3 s later (the hull has
gone into the one-sided road collision). On Fork Lab the first version did
the same, then slid along at the 35 u/s airborne terminal speed. **This is an
existing bug on the gameworthy circuits.** It's left alone there to keep them
bit-identical. The same 4 m fix would apply.

### Chase camera through the jumps

Measured every tick at full speed, both jumps:

- No snaps: 0 ticks where the camera moved > 2 m more than the ship.
- Never occluded: a ray ship → camera on layers 1|4 never hit anything.
- Turns ≤ 1.0° per tick in landings.
- The ship stays within 13.6° of view centre, and distance holds at 10.9.

The ship keeps its kicker pitch in the air (`_align_to_track` only runs
grounded), so the camera holds a 6–8° nose-up attitude through the flight and
re-aligns on landing. Whether the ship should pitch to follow its arc is a
feel question for a hand test.

## AI and the cinematic rig (no crashes; main route only)

- **AI** (8-ship race, 140 s, untrained fallback line): every AI ship did 3 laps with 0 respawns on the main route, over the shared jump, v max 113–116. Checksum 2275443594.
- **Rig** on an AI ship (75 s, and 90 s with `CR_SNAP_EVERY=37`, 145 snaps and cycles): no errors.
- **Rig on the player ship on the branch** (`FL_RIG`, 100–250 snaps and cycles over branch, main and alternating laps): no errors, no stack overflows. But cameras placed along the MainSpline lose a ship on the branch: handheld, kamikaze, roadkill, whip and crossing are 82–100% occluded there.

## Running the harness

```
# flat out, main route / shortcut / alternating
FL_LAPS=2 godot --headless --fixed-fps 60 --path . -s res://tools/fork_lab/fork_lab_drive_boot.gd
FL_ROUTE=branch FL_LAPS=2 godot --headless --fixed-fps 60 --path . -s res://tools/fork_lab/fork_lab_drive_boot.gd
# fall short of the branch jump, then see where it respawns
FL_ROUTE=branch FL_JUMP_SPEED=branch:85 FL_LAPS=1 godot --headless --fixed-fps 60 --path . -s res://tools/fork_lab/fork_lab_drive_boot.gd
# A/B against stock air and hover physics
FL_STOCK=1 FL_ROUTE=branch godot --headless --fixed-fps 60 --path . -s res://tools/fork_lab/fork_lab_drive_boot.gd
# jump sizing
JS_ANGLES=8 JS_SPEEDS=90,95,100,120 JS_LAND=100,6,6,40,80 godot --headless --fixed-fps 60 --path . -s res://tools/fork_lab/jump_sim_boot.gd
```

Driver env: `FL_TRACK`, `FL_ROUTE` (main|branch|alt), `FL_SPEED`,
`FL_JUMP_SPEED`, `FL_LAT`, `FL_LAPS`, `FL_MAX_T`, `FL_TRACE` (1/2/3),
`FL_SHOTS`, `FL_SHOT_DIR`, `FL_OVERVIEW`, `FL_RIG`, `FL_STOCK` (see the
script header). Lap times are in simulated seconds.

## Regression

Every change takes its new path only on a track with a `TrackGraph` (or for a
flight from a `TrackJump`). Same seeds, same checksums as before the change:

| Probe | 3_live | 5_live | 6_live | 7_live | Loop Lab |
|---|---|---|---|---|---|
| `ai_race_probe` 75 s | 3929678988 | 2744688434 | 2544408098 | 133359682 | 675169125 (140 s, A/B against the base branch) |
| `cine_rig_probe` 45 s (Loop Lab 75 s) | 3621838145 | 1427140778 | 1324755775 | 2300779685 | 1087435003 |

Loop Lab player autopilot (2 laps): 35.65 / 33.85 s, identical to the base branch.

## Not done yet / next

- **AI branch choice** needs:
  1. a per-ship stateful path tracker (which path it's on; the stateless `locate` is fine for scoring, not for steering);
  2. a racing line per path: bake or train the branch as its own line and blend at the junctions (the trainer drives the real ShipController, so it would train jumps correctly given a route);
  3. a decision rule: take the shortcut only if it will reach ~93 u/s at the lip with margin, which also makes a natural difficulty handicap.
  
  Until then, an AI pushed onto the branch gets a main-mapped offset and steers for the main route's line.
- **AI over jumps:** works on the shared jump. For bigger ones the speed model should know there's no steering in the air (arrive aligned) and never brake before a kicker.
- **Rig:** place cameras with `TrackGraph.locate` and `frame_at(path, d)` instead of the MainSpline. Add jump witness shots (side-on at the gap, low under the landing lip).
- **Lap recorder:** records main-mapped offsets and laterals against the MainSpline, so branch laps are junk as training data. Tag or skip them.
- **Respawn drop on the existing circuits** (above).
- **Feel by hand:** landing softness (damping ×3 may read as floaty), the fixed nose-up attitude in flight, whether 1.9 s is the right reward, and the ~22% speed margin on the branch jump.
- **Driver note:** at `FL_LAT=15` on the main route the autopilot drifts into the branch lane in the junction and grinds along the branch's inner wall. That's the autopilot, not the geometry (a player would just be on the branch), but it marks where the commitment point is.
