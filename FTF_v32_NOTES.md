# Full Throttle Flux — v32: AI and cinematic rig on Fork Lab

v31 built Fork Lab, a fork plus two jumps, for the player. v32 makes the AI
race it and makes the cinematic rig shoot it:

- The AI chooses a route per lap, before the fork. It drives a trained line
  and speed profile on either route, and blends between them at both
  junctions.
- The AI follows the road it is on if contact puts it on the other one.
- The AI holds full throttle into the kickers and holds still in the air.
- An AI that falls short respawns on the branch and keeps racing.
- Fork Lab now supports races.
- The rig places its cameras along the route the followed ship is on.
- The rig treats each jump as a zone, with a witness spot chosen by
  measurement.

Everything here is inert on tracks without route laps. The AI-race and rig
checksums on circuits 3, 5, 6 and 7 and on Loop Lab are identical to the
baselines (see Regression).

## Files

| File | What |
|---|---|
| `scripts/ai/ai_route_follower.gd` (new) | `AIRouteFollower`: one `AILineFollower` per route lap. It switches between them with a 120 m blend of the steering target, speed target and line curvature. |
| `scripts/ai/ai_ship_controller.gd` | Route decision and commit, forced switch, jump controls, respawn hook (section "ROUTES: FORKS AND JUMPS"). |
| `scripts/ai/ai_control_decider.gd` | `hold()` / `hold_throttle()`: pin the smoothed controls and clear the stuck and recovery timers. |
| `scripts/ai/track_spline_helper.gd` | `for_path()` (a helper on any Path3D) and jump spans. |
| `scripts/ai/ai_racing_line_baker.gd`, `ai_line_trainer.gd` | Jump spans: the curvature is not a corner there, and the trainer records nothing in the air. |
| `scripts/tracks/track_graph.gd` | Route laps API (`route_path`, `route_to_path`, `path_to_route`, `route_jumps`). `TrackGraph.Tracker` is a per-ship path tracker. |
| `scripts/tracks/track_branch.gd`, `track_jump.gd` | `route_path` / `route_fork` / `route_rejoin`; `clean_speed`. |
| `tools/fork_lab/build_fork_lab.gd` | Adds `RouteSpline_Branch` (the full lap through the shortcut). Scene regenerated. |
| `tools/train_ai_lines.gd` | Trains Fork Lab once per route lap. Also fixes the trainer's ship profile (see "Found along the way"). |
| `resources/ai_data/fork_lab[__route0]_default_racer_trained_line.tres` (new) | Trained lines for the main route and the shortcut route. |
| `scripts/modes/race_mode.gd` | Tracks with a TrackGraph get a respawn manager in races. |
| `scripts/ships/ship_controller.gd` | On TrackGraph tracks, respawn looks up the point from `last_safe_position`. |
| `scripts/recording/lap_recorder.gd` | Rejects laps that took a branch. |
| `resources/tracks/fork_lab.tres` | `supports_race = true` |
| `scripts/debug/cinematic_camera_rig.gd` | Route-aware spline, jump zones, gap-safe plants, crest handling (section "FORKS AND JUMPS"). |
| `tools/dev/ai_race_probe.gd`, `tools/dev/cine_rig_probe.gd` | Fork and jump telemetry, shove and sabotage tests, per-route rig stats, jump-spot grid search. |

## Design

### Route laps: the AI follows one closed lap at a time

Fork Lab now has two lap splines:

- `MainSpline`: the main route, unchanged.
- `RouteSpline_Branch`: main up to the fork, then the branch, then main from
  the rejoin. It is 3,322 m against 3,559 m, with the fork at 1,180.5 m and
  the rejoin at 2,181.9 m on the route lap.

Each route lap is a normal closed spline, so the baker, the trainer, the
line follower's look-ahead and the speed profile all work across the
junctions unchanged. Each route lap has its own racing line, stored under
`fork_lab` and `fork_lab__route0`. `TrackGraph` converts between route
distance and (path, distance).

`AIRouteFollower` holds one follower per route lap and mirrors the active
one, so the decider, style gains and debug views see a normal follower.
Switching blends the world-space steering target, the suggested speed, the
lateral offset and the signed line curvature from the old route lap to the
new one over 120 m of travel, using smoothstep. The two route laps share
geometry until the fork, so a switch made before the fork is invisible. A
switch made inside the junction, after a shove, eases in.

### Which road am I on: `TrackGraph.Tracker`

Each AI has a tracker that does a local search around its last answer:
±30 m window, 2 m steps, re-locate if more than 40 m out. It never confuses
another stretch of road that runs nearby. In the junctions it compares the
ship's distance to both centre lines. It reports `ambiguous` until one is
12 m clearer than the other, and only then does it commit to the main or
the branch route.

If the tracker unambiguously says the ship is on the other road from the one
it chose, the AI switches to that road's route lap (a forced switch). A ship
shoved across the splitter follows the road it is on and does not steer back
through the wall.

### Route choice

The AI decides once per lap, 300 m before the fork, and can still change
its mind until 60 m before the fork. At 60 m the choice is committed.

- **Decision.** The shortcut needs a predicted lip speed at least as high as
  the jump's measured clean-landing speed (`clean_speed` 93 u/s for the
  branch jump) plus a skill margin: 20 u/s at skill 0, 6 u/s at skill 1.
  - The prediction is the speed the ship's profile asks for at the lip,
    scaled by its skill speed margin. It is capped by what full throttle
    reaches from the ship's current speed over the distance to the lip
    (`perf_model.speed_after_full_throttle`).
  - If the ship clears that, it takes the shortcut with probability
    `lerp(0.25, 0.8, skill)` plus a per-ship bias in ±0.15, fixed at spawn.
- **Commit point.** The ship goes back to the main route if it is now too
  slow for the jump. It switches routes if a slower ship is within 45 m ahead
  and 10 m to the side, as long as the other route is also feasible.
- **Difficulty.** The skill margin and take-rate are exports
  (`jump_margin_novice/expert`, `shortcut_take_min/max`). They can serve as
  difficulty handicaps.

**What the data says about the speed gate.** I tested your suggestion, "shortcut
only if lip speed clears ~93 with margin", against the data. Every clean AI
actually reaches the lip at 120 u/s, the ship's top speed: the branch's
run-up is 540 m of straight from the fork.

The prediction is deliberately conservative. It scales the profile's lip
speed by the skill speed margin (0.85 at skill 0), so it predicts 106–110 u/s
for low-skill ships. Those ships need 107–110 (93 + 20..6).

- **Easy.** The gate cuts in at skill ≈ 0.34. Ships below that never take
  the shortcut (12 of 32 Easy decisions). This is a clean difficulty knob:
  raise `jump_margin_novice` and more of the field stays on the main route.
- **Medium and Hard.** The gate never binds; variety comes from the take
  probability and the per-ship bias.
- **Contact.** For a ship slowed by contact at the commit point, the
  full-throttle reach cap is what the gate checks.

### Jumps

- **Kicker run-up** (60 m before the kicker to the lip): full throttle, no
  airbrakes, no avoidance. An avoidance swerve at the lip measured 17° of
  heading error, and that ship flew over the landing's wall. With avoidance
  suppressed, takeoff heading errors are −1.6..+0.5°.
- **In the air:** full throttle (it acts horizontally), airbrakes 0, and
  steering only to keep the nose on the velocity, so the ship lands straight.
  The decider's smoothing and its stuck/recovery/saturation timers are pinned
  to those values (`hold()`). Nothing fires mid-flight, and control resumes
  from the held values on landing without a lurch.
- **Baker and trainer:** jump spans (kicker − 10 m to landing end + 10 m)
  use road-plane curvature, so a kicker's vertical bend is not braked for as
  a corner. The trainer records nothing inside them.

### Respawn

Races never had a respawn manager, on any track. Every ship respawned at its
last grounded spot, which on Fork Lab is the kicker ramp at zero speed. In a
first sabotage run one ship fell 124 times. Races on tracks with a
TrackGraph now get the branch- and jump-aware manager from v31. On those
tracks the lookup uses `last_safe_position`. Without that, a ship knocked off
beside the branch's landing came back on the main route, ahead of where it
left.

After a respawn the AI snaps its route to the road its tracker finds and
keeps racing. It decides again on the next lap.

### Race mode and positions

Fork Lab has `supports_race = true`, with the grid on the shared start
straight. Positions use the v31 branch → main mapping, so race positions
inside the fork are an estimate. A shortcut ship is credited with linear
progress along the branch, while it is really gaining time. See Results for
how often that estimate agrees with the exit order.

### Lap recorder

The lap recorder now tracks each lap with a `TrackGraph.Tracker` and rejects
any lap that took a branch. Recordings are against the MainSpline, so branch
laps never reach training data.

### Cinematic rig

- **Route-aware spline.** The rig follows the followed ship's route lap: the
  AI's chosen route (known 300 m before the fork), or a tracker for the
  player. Kamikaze, roadkill, whip, handheld's track clamp, crossing and the
  zone frames all use that route lap. When the route changes, those cameras
  replant on the new route lap.
- **Jumps are zones** (non-loop), so every existing witness rule applies.
  Witnesses stay outside the swept envelope and take their shot from a
  measured spot near a jump.
  - The spot was found with `CR_ANALYZE=1`, which raycasts the racer's
    recorded path through each jump from a grid of spots.
  - 100% visible: from 3/4 of the way across the gap to the landing lip,
    20–35 m above the lower lip, 8–20 m beyond the envelope.
  - Defaults: `jump_witness_gap_frac` 0.85, `jump_witness_height` 25,
    `jump_witness_standoff` 14 (+6 envelope margin).
  - The obvious "low and side-on at the gap" spot measured worse, and so did
    the first defaults (0.5, 0 m, 25 m): handheld 59%, pan 67% and crane 41%
    occluded at the jumps. The ramps' own bulk hides the racer from low
    spots.
- **Track-fixed cameras never plant in a gap.** Plants that land between a
  lip and its landing move 15 m past the landing, and the zone envelope
  keeps witnesses out of the flight space.
- **Crests.** A camera on the road beyond a kicker can't see a ship that is
  still on the run-up.
  - Roadkill lies on the kicker ramp 6 m before the lip instead. The ramp is
    concave, so it sees all the way down.
  - Kamikaze rises over the crest, up to 24 m, while it is past the kicker
    and the ship is short of the lip.
  - Trackside (route tracks only) takes the other side if its alternate side
    has no line of sight to the ship.
- **Riding cameras: no change.** Their frame is world-up outside magnetic
  zones. Their ground clearance only lifts them over road that is actually
  there, so in flight they carry on beside the ship. Measured through both
  jumps: drone 12.1–12.7 m, side 9.7–11.0, lowchase 10.8, orbit 14.3–15.4,
  heli 42.1, with 0 jumps, 0 flips and 0 NaNs. Switching them to world-up in
  flight would change nothing.

## Results

All measurements are headless at `--fixed-fps 60`, with logs in the
scratchpad. In the race probes, 7 AI race and the player ship sits on the
grid, as in every earlier probe.

### AI races (Medium, 150 s, 3 laps)

| Seed | AI laps | Respawns | Shortcut taken | Branch-jump falls | Takeoff speed (both jumps) |
|---|---|---|---|---|---|
| default | 7 × 3 | 0 | 17/35 (49%) | 0 | 120 |
| 1 | 7 × 3 | 0 | 21/35 (60%) | 0 | 120 |
| 2 | 7 × 3 | 0 | 16/35 (46%) | 0 | 120 |
| 3 | 7 × 3 | 0 | 18/35 (51%) | 0 | 120 |

- 0 progress steps back. The largest step forward was 2.8 m per tick.
- Decision reasons, default seed and seeds 1 and 2: 56 shortcut rolls, 49
  main rolls and 6 traffic switches at the commit point. The speed gate
  never fired at Medium.

Take rate by skill, with no falls at any skill:

| Difficulty | Skill range | Shortcut taken |
|---|---|---|
| Easy | 0.25–0.45 | 6/28 (21%). Skills ≤0.32 are ruled out by the speed gate (12 decisions) |
| Medium | 0.50–0.72 | 72/140 (51%) over 4 seeds |
| Hard | 0.78–1.00 | 26/34 (76%), 2/4 to 5/5 per ship |

Within a skill level, per-ship bias and per-lap rolls spread the field. Over
the four Medium seeds, ships at the same skill took the shortcut 0/5 to 5/5
times.

**Positions across the fork.** Pairs of ships in the fork together:

- Same-route pairs keep the exit order 98–100% of the time.
- Mixed-route pairs keep the exit order 78–87% of the time (85–88% for pairs
  that exit more than 0.5 s apart).
- Flicker: mixed pairs whose order changed more than once in the fork
  numbered 0, 1, 0 and 2 per race. The last in-fork order equalled the exit
  order for 100% of pairs.

The mixed-route misses are the shortcut ship being credited "behind" until
it catches up in the estimate, then passing once. It is not noise.

**Contact.**

- **`PROBE_SHOVE=1`**: a 40 u/s sideways shove toward the other road, once
  per lap, 110 m into the fork junction. 7 × 3 laps, 0 respawns, 0 wall
  ticks. No ship crossed onto the other road.
- **`PROBE_SHOVE=2`**: each ship is put straight onto the other road past
  the splitter nose, every lap. 5 forced switches per ship. Each ship
  followed the road it was on, with 7 × 3 laps, 0 respawns and 0 wall
  ticks. (The −17 m progress step is the teleport itself.)

**Falling short (`PROBE_SABOTAGE=1`).** Each AI is held at ~55 u/s to the
branch lip once.

- 7 falls, one per ship, all taking off at 53 u/s.
- Each ship respawned at branch 226 m, on the run-up 400 m before the
  kicker. From there it launched at 116 u/s and landed cleanly. All finished
  3 laps.
- Later laps were decided afresh: 22 of 35 passes took the shortcut, with no
  further falls.
- Takeoff heading errors over all 29 branch takeoffs were −1.6..+0.5°.
- An earlier run, before avoidance was suppressed on the run-up, had one
  extra fall: a 16.7° swerve at the lip.

### Cinematic rig: occlusion % per camera, before → after

The "before" columns have route awareness off (`CR_NO_ROUTES=1`), which is
the v31 behaviour. The probe follows one AI for 90 s. Branch columns come
from runs with every AI on the shortcut (`CR_ROUTE=0`). Main-route and
shared-jump columns come from runs with every AI on the main route
(`CR_ROUTE=-1`).

| Camera | Main route | Open track | Branch | Branch jump | Shared jump |
|---|---|---|---|---|---|
| kamikaze | 42 → 42 | 35 → 34 | **77 → 2** | **97 → 15** | 22 → 14 |
| roadkill | 0 → 0 | 14 → 13 | **51 → 0** | **98 → 10** | 4 → 3 |
| whip | 1 → 1 | 25 → 25 | **61 → 0** | 31 → 6 | 7 → 7 |
| handheld | 20 → 16 | 42 → 42 | 25 → 0 | 51 → 0 | 0 → 0 |
| crossing | 12 → 20 | 29 → 28 | 32 → 28 | 4 → 0 | 0 → 0 |
| trackside | 38 → 58 | 45 → 39 | 29 → 0 | 35 → 0 | 0 → 0 |
| crane | 36 → 26 | 27 → 11 | 0 → 0 | 0 → 0 | 0 → 0 |
| pan | 59 → 67 | 68 → 77 | 42 → 34 | 22 → 3 | 8 → 0 |
| Mean, 25 cameras | 10.9 → 11.8 | 14.1 → 13.5 | 13.3 → 3.2 | 14.1 → 2.0 | 2.5 → 1.9 |

The other cameras are unchanged. At the jumps they are 0% occluded, except
overtake (7%), orbit (2%) and vertigo (9–21%, as on any road).

**Main route.** Trackside, pan and crossing got worse there, and crane got
better. This is not caused by the jump logic.

- The extra jump-zone shot shifts the timing of replants. Trackside
  alternates sides on each replant, so the side it plants on along the
  bypassed stretch flips.
- Flipping the starting side shows this. v31 trackside on that stretch
  measured 38% or 73% depending on its starting side. v32 measured 85% or
  58% before the line-of-sight side check, and 58% after it.
- Pan and crossing move the same way with replant phase. Trackside is
  40–60% occluded on Fork Lab either way; see Open issues.

**Player autopilot with the rig** (`FL_RIG=37`: snap and cycle every 37
ticks, 100 times, on the branch). Mean occlusion before → after:

| Section | Before | After | Worst after |
|---|---|---|---|
| Branch | 16.9% | 4.4% | kamikaze 53% |
| Branch jump kicker | 18.6% | 8.3% | kamikaze 78%, roadkill 65%, whip 49% |
| Branch jump gap | 5.8% | 0.0% | — |
| Branch jump landing | 5.1% | 0.0% | — |

Kickers are still the weak spot; see Open issues.

**Snap and cycle (F9 + Y).** Two runs, with 0 script errors, 0 stack
overflows and 0 NaNs:

- `CR_SNAP_EVERY=37` for 150 s, with mixed routes: 243 snaps and camera
  cycles.
- `CR_SNAP_EVERY=23` for 120 s, with every AI on the shortcut: 313 snaps and
  cycles over the branch and both jumps.

One pan reposition was flagged as a position jump on the branch jump, out of
556 snaps. The player driver with `FL_RIG` did 100–107 snaps and cycles on
the branch and the main route, also with 0 errors.

### Fork Lab health after the rebuild

- `check_fork_lab.gd` passes everything as in v31. No road misses, gaps are
  clear, no seam steps above 8 mm, no walls in either junction, and the
  branch → main map is monotonic.
- The player autopilot gives the same results:
  - Alternating routes: 33.78 s on the main route, 29.93 s on the branch.
  - Falling short at 60 u/s: one respawn, then 29.93 s.
  - Largest progress step back: 0.

### Trained lines

`train_ai_lines.tscn -- --track=fork_lab` trains both route laps: main route
29.83 s and shortcut 28.42 s. No other track was retrained. Their `.tres`
files are untouched in git.

### Stills

Rendered with `CR_SHOTS` under xvfb (gl_compatibility, 960×540). They are
not in the repo.

- **The field splitting at the fork.** `CR_SHOTS=overview@1460` is a new
  free camera high over the fork junction. Two ships take the main route to
  the left, and four take the branch toward its kicker.
- **An AI mid-air over the branch jump.** Orbit and side cameras.
- **Witness jump shots.** Trackside and crane at the branch jump (one ship
  launching, one in the air), and helilost over the shared jump's landing.
  The measured witness spot is high, so these frames look down onto the dark
  ground plane under the gap. A low, side-on spot would look more dramatic,
  but it measured 41–67% occluded.

## Found along the way (not fixed beyond Fork Lab)

1. **The trainer drove the wrong ship.** `train_ai_lines.gd` never set the
   ship's profile, so every line was trained with the scene's speed_demon
   physics (max 160, different grip, steering and hover) under a
   `default_racer` label. It's fixed now: the trainer sets `ship.profile`.
   The existing trained lines for circuits 3/5/6/7 and Loop Lab were **not**
   retrained, as the brief required. Retrain them when convenient; the race
   checksums will change.
2. **Races have no respawn manager** on any track without a TrackGraph.
   Ships respawn at their last grounded spot. That is harmless on a flat
   circuit and was fatal at a kicker. I enabled the manager only on
   TrackGraph tracks to keep the circuits bit-identical. Turning it on
   everywhere is a one-line change, but the circuit checksums will change.
3. **Speed spikes on ship-ship landings.** For a single tick, contact
   impulses give 210–232 u/s. The circuits show 145 for the same reason
   (symmetric impulse system). It is harmless here: no falls or wall hits
   followed.

## Running it

```
# 8-ship race, fork telemetry (+ PROBE_SEED, PROBE_DIFFICULTY=easy|hard)
PROBE_TRACK=fork_lab PROBE_SECONDS=150 godot --headless --fixed-fps 60 --path . -s res://tools/dev/ai_race_probe_boot.gd
#   PROBE_SHOVE=1|2  contact at the fork      PROBE_SABOTAGE=1  fall short once
#   PROBE_TAKEOFFS=1 per-takeoff lines         PROBE_SPIKES=1    speed spikes
# rig: CR_ROUTE=0|-1 forces every AI's route, CR_NO_ROUTES=1 = v31 behaviour,
#      CR_ANALYZE=1 grid-searches witness spots (jumps included)
CR_TRACK=fork_lab CR_SECONDS=90 CR_ROUTE=0 godot --headless --fixed-fps 60 --path . -s res://tools/dev/cine_rig_probe_boot.gd
# retrain Fork Lab's two route lines
godot --headless --path . res://tools/train_ai_lines.tscn -- --track=fork_lab
```

## Regression

The AI race probe (8 ships; checksum of every ship's final transform) and the
cine rig probe (checksum of every camera's transform and FOV every tick) are
identical to the baselines:

| Track | AI | Rig |
|---|---|---|
| circuit 3 (75 s / 45 s) | 3929678988 | 3621838145 |
| circuit 5 | 2744688434 | 1427140778 |
| circuit 6 | 2544408098 | 1324755775 |
| circuit 7 | 133359682 | 2300779685 |
| Loop Lab (140 s / 75 s) | 675169125 | 1087435003 |

Fork Lab races are deterministic: the default seed gives checksum 3551594432
on repeat runs.

## Decisions and rejected alternatives

- **Route laps, not a branch-only follower handed over at the junctions.**
  With a branch-only spline, the look-ahead, the speed profile and the baker
  would all see an open path ending at the rejoin. Every junction would need
  a handover in three systems. A full lap per route needs none, and it costs
  one extra Path3D generated by the builder.
- **Positions: kept the v31 branch → main map.** The alternative was race
  distance along each ship's route lap. That would make a shortcut ship jump
  ahead at the fork instead of catching up through it. The map flips each
  mixed pair at most once, as measured, which reads as an overtake.
- **Route choice: probability by skill plus per-ship bias, gated by
  predicted lip speed.** A pure speed threshold on actual speed would send
  every ship the same way, because they all arrive at 120. The skill-scaled
  prediction makes the gate a difficulty knob, keeping the weakest ships off
  the shortcut.
- **Decide 300 m before the fork, commit at 60 m.** Deciding at the fork
  leaves no room for the 120 m blend or for the traffic check. Re-deciding
  freely makes ships weave at the nose.
- **Riding cameras unchanged in flight.** Measured: no dive, no stall, no
  flips. Switching to world-up would have changed nothing.
- **Witness jump spot by measurement.** The suggested "low, side-on at the
  gap" spot loses the racer behind the ramps. The grid search put it high,
  near the landing.

## Open issues

- **Kickers are hard to shoot from the road.** Kamikaze is still 71–87%
  occluded while the ship is on a kicker. That is about 1.2 s of each jump;
  it is 14–16% over a whole jump. The lift needed exceeds 24 m when the
  camera is far beyond the landing. Options:
  - Cut kamikaze away near kickers.
  - Plant it on the landing deck so it is shorter.
  - Accept it: the shot does find the ship as it launches.
- **Trackside on Fork Lab** is 40–60% occluded on open road, in v31 too. It
  plants blindly 11 m left or right of the ship's line, and Fork Lab's walls
  and banks often hide it. The new side check helps only at plant time. A
  check along the ship's coming path would do better and could apply on all
  tracks, but that changes the circuit rig checksums.
- **The speed gate's contact path is untested.** It works at Easy through
  the skill-scaled prediction. Its full-throttle reach cap, which catches a
  ship slowed by contact at the commit point, never fired, because nothing
  on Fork Lab slows an AI enough there. Sabotage happens after the commit,
  by design, so ships fall. A track with a slow corner before a shortcut
  jump would exercise it.
- **One fork per lap is assumed** by the decision logic (it reads
  `branches[0]`). Route laps and the tracker handle several branches, but
  the decision would need a per-fork loop.
- **Still open from v31:** a respawn on the circuits drops the ship 20 m and
  it sinks into the road. Not touched, to keep the circuits bit-identical.
- **Fork Lab only has the default_racer line.** Other ship profiles fall
  back to baking per route at race start, which works but is slower to load.
