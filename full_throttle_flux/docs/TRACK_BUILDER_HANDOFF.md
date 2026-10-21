# Handoff: track authoring guide and Track Builder tools (v34)

This brief is for a new Claude session. It has what the previous session
(v30–v33: Loop Lab, magnetic zones, Fork Lab, jumps, AI lines on
default_racer, respawns) learned, so the next one can start building
without having to rediscover it.

**Owner:** Chris (csmallfield). Repo: `github.com/csmallfield/full_throttle_flux`.
The Godot project is in the `full_throttle_flux/` subfolder, and run notes
(`FTF_vNN_*.md`) are at the repo root.

---

## 0. Before anything else: which branch has the code

Earlier PRs were stacked. PRs #5 to #8 merged into feature branches instead of
`main`, so `main` stops at v30 (PR #4). All the work through v33 is on
**`feature/fork-jump-lab`**.

This handoff ships in a PR (`release/v33-to-main` → `main`) that also brings v31–v33 to
`main`. It merges cleanly: 67 files, +7.3k lines, no conflicts.

- **If that PR is merged:** branch from `main`.
- **If not:** branch from `release/v33-to-main`. Don't open stacked PRs again:
  target `main` directly.

Check with `ls full_throttle_flux/scripts/tracks/track_graph.gd`. It must exist.

---

## 1. What Chris asked for

In his words: *"What will be helpful for future courses is a method of
working that will avoid the offset. Allow me to make loops and barrel rolls,
jumps and split tracks."* He asked whether this should be a best-practices
doc or tools, and decided on both.

His decisions:

| Question | Decision |
|---|---|
| Where are base curves drawn? | **In Godot**: "I don't want to introduce more round trips" (no Maya/Blender step). |
| How is banking authored? | **A distance-keyed bank profile**, "as long as I can get visual feedback quickly". |
| What to deliver | (1) a best-practices doc, (2) tools: a **validator**, plus a **feature/build system** for loops, barrel rolls, jumps and split tracks, built on hand-drawn base curves and banks. |
| The four existing circuits (test_circuit_3/5/6/7_live) | **Leave them alone.** Their road/spline offset stays: "Adjusting them would change the flavor of the course." The tools must not require changing them, and their regression checksums must not move. |
| Loop Lab / Fork Lab | Very low priority. They are test tracks, not real levels. |
| Standing priority | Correct racing with `default_racer` for every racer. |

How Chris likes to work (stored preference): offer alternatives, flag issues
and explain tradeoffs, be direct rather than agreeable, and challenge his
assumptions when they look wrong. He tests in the editor and tells you what
he sees. Keep that loop short: give him something he can open and drag
around early.

---

## 2. The offset: cause and the rules that prevent it

### Cause (verified in all four circuit `.tscn` files)

`groundGeo`, `wallLeftGeo` and `wallRightGeo` (CSGPolygon3D, `MODE_PATH`,
`PATH_FOLLOW`, `path_local = false`) each carry a node transform:

```
Transform3D(1, 0, 0,  0, 0.999836, -0.0181155,  0, 0.0181155, 0.999836,  …)
```

This is a ~1.04° rotation about X. groundGeo has a small origin too
(−0.2258, 3.8e-6, −0.164); the walls' origin is 0. `MainSpline` itself has
no transform.

Because `path_local = false`, the extrusion follows the spline in world
space, but the node's own transform then rotates the whole result about
the **scene origin**. That 1° pivot moves the road **21 m below to 19 m above** its
spline, depending on how far that part of the track is from the origin. Any
system that trusts the spline is then wrong by that much:
- AI lines
- respawn points
- magnetic frames
- the cinematic rig
- set dressing

v33 worked around it with ray-cast road surfaces, and `UtopiaKit.road_xf`
works around it the same way.

### Rules (the authoring doc must state these clearly)

1. **Identity transforms** on every node between the track root and the
   road geometry. That covers the track root, the spline, and the geometry nodes. Never rotate
   or move geometry to "fix" a look. Edit the curve or the bank profile
   instead.
2. **The road surface is at polygon y = 0.** Cross-section polygons put the
   driving surface on y = 0, with x across (+x = right of travel). Lips and
   walls go above it, skirts below.
3. **Banking comes from the bank profile only**, which the builder turns into
   curve tilts. Never type tilts by hand (see §4.3 for why the numbers you'd
   type are wrong).
4. **One source of truth.** Geometry, magnetic zones, the jump/branch graph,
   respawn data and AI lines all come from the spline plus the bank
   profile. The validator checks this by ray-casting the built road against
   the spline frame (target: under 0.05 m vertical, under 0.5° normal).

---

## 3. What already exists (reuse it, don't rewrite it)

All paths are relative to `full_throttle_flux/`.

### Runtime (used by every track)

| File | What it is |
|---|---|
| `scripts/tracks/magnetic_track.gd`, `magnetic_zone.gd` | Zones keyed by distance along MainSpline, with ramps. `frame_at(d)` (−Z forward, basis.y = road up). Each ship keeps a Tracker that searches locally. |
| `scripts/tracks/track_graph.gd`, `track_branch.gd`, `track_jump.gd` | Forks and jumps. Branch distance maps to main distance (equidistant medial mapping at junctions). Route-lap paths for the AI. Jump extents and `clean_speed`. |
| `scripts/tracks/track_road_segment.gd` | Load-time extrusion of a cross-section along a **distance range** of a Path3D. Handles gaps, lip fades and end caps. Uses the tilted baked frame. **Use this, not CSG, for builder tracks** (CSG can't leave gaps or open walls). |
| `scripts/tracks/track_junction.gd` | Y-junction road union and splitter wedge. **The junction must be flat and level** on both paths. |
| `scripts/tracks/track_respawn_manager.gd` | Respawn points from road ray-casts every 5 m. Skips jump extents. Off-track rules: 12 m below the road, or 4 s in the air. |
| `scripts/tracks/starting_grid.gd` | Grid slots. |
| `scripts/ships/ship_controller.gd` | Zone gravity, jump flight (ground drag in the air, landing pull capped at 2 g), `slerp_safe()`. |
| `scripts/ai/*` | `track_spline_helper.gd` (in zones it steers in the road plane), `ai_route_follower.gd` (picks a branch 300 m ahead and commits 60 m ahead), the baker (geodesic curvature in zones). |
| `scripts/debug/cinematic_camera_rig.gd` | Per-camera zone handling: mounted, riding (road frame), track-fixed, and witness cameras outside the zone envelope. |

### Generators: today's "build step", one script per track

| File | Notes |
|---|---|
| `tools/fork_lab/fork_lab_turtle.gd` | **The core to reuse.** A turtle integrator: `straight`, `turn(length, dpsi, bank_deg)`, `pitch_change`, `mark()`, and `build_curve()`, which **solves tilts against Godot's baked up vectors** and unwraps them. |
| `tools/loop_lab/build_loop_lab.gd` | The teardrop loop (`_loop`) and the 360° roll, built on CSG. The shape maths is the reference. |
| `tools/fork_lab/build_fork_lab.gd` | Main and branch curves, route-lap curve, TrackRoadSegments, junctions, TrackGraph, grid and environment. |
| `tools/fork_lab/jump_sim.gd` (+ `_boot`) | Flies the **real ShipController** (default_racer) off a kicker shape to find the clean landing speed. Size jumps with this, not ballistics. |
| `tools/loop_lab/check_loop_lab.gd`, `tools/fork_lab/check_fork_lab.gd` | Ray-cast verification. These are the seed of the validator. |
| `tools/utopia/utopia_kit.gd`, `check_clearance.gd` | Set dressing placed in track space (d, lat, h) with a clearance envelope. A builder track should work with these, and with `road_xf = IDENTITY` it should just work. |

### Probes (headless; use them for regression and for measuring)

| Probe | Settings |
|---|---|
| `tools/dev/ai_race_probe_boot.gd` | `PROBE_TRACK`, `PROBE_SECONDS`, `PROBE_SEED`, `PROBE_DIFFICULTY`, `MAGNET`… Prints `PROBE … checksum=N`. |
| `tools/dev/cine_rig_probe_boot.gd` | `CR_TRACK`, `CR_SECONDS`, `CR_ROUTE`, `CR_SNAP_EVERY`, `CR_ANALYZE`, `CR_SHOTS`… |
| `tools/dev/ai_lap_probe_boot.gd` | One AI on one line file: lap time, speeds, wall contacts. |
| `tools/dev/loop_lab_drive_boot.gd`, `tools/fork_lab/fork_lab_drive_boot.gd` | Player autopilots, with shots and traces. |
| `tools/train_ai_lines.tscn` | `-- --track=<id> [--fresh]`. Refuses mismatched handling stamps. |
| `tools/style_search.tscn` | `-- --track=<id>`. |

Run notes with the full detail: `FTF_v30_NOTES.md` (zones, loop, roll),
`FTF_v31_NOTES.md` (forks, jumps), `FTF_v32_NOTES.md` (AI and rig on
forks and jumps), `FTF_v33_AI_LINES.md`, `FTF_v33_RESPAWN.md`.

---

## 4. Measured design numbers: these become the doc's limits and the validator's thresholds

### 4.1 Loops

- **Shape:** teardrop, made from a sin² curvature profile. Arc length
  L = 820 m gives a top radius of about 65 m (`L / 4π`).
- **Lateral step:** 90 m across the loop, so the exit clears the entry.
- **Zone settings:** `magnet_strength` 1 (forgiving) to 0 (needs speed).
  Default `hover_force_scale` 2. `normal_smoothing` 30. `contact_recovery`
  on.
- **Cross-section:** road subdivided every **3 m** across (`ROAD_STRIP`).
  Otherwise the normals on twisted sections washboard.
- **Lighting:** inversions need light from below (Loop Lab's `GroundFill`).

### 4.2 Barrel rolls

- **Length:** 800 m, smoothstep roll profile, peak about **0.68°/m**.
  - 460 m was too fast: tested and rejected.
  - Treat **0.7°/m** as the upper limit.
- **Closure:** a net 360° roll needs an **open curve with coincident ends**.
  On a closed curve the closing segment unwinds the tilt.
- **CSG only:** `path_simplify_angle = 0`, or CSG merges the twist away.
  This doesn't apply to TrackRoadSegment.

### 4.3 Tilt and up vectors (the core reason banks must be generated)

Godot's `Curve3D` (with `up_vector_enabled`) bakes a **rotation-minimizing
frame**. Point tilt is added *on top of* that frame, and the frame twists
on its own through 3D curves (holonomy).

So the tilt you'd type to get "18° bank" isn't 18°. The turtle's
`build_curve()` solves it:

1. Set tilt = 0.
2. Read the baked up vector at each control point.
3. Measure the angle to the desired up vector.
4. Unwrap that angle and write it back as the tilt.
5. Verify: the maximum error is printed (the tilt solve aims for under 0.2°).

The builder must do the same, starting from the bank profile.

### 4.4 Jumps

Use `TrackJump`. The road has a real gap and no collision under it.

| Jump | Gap | Kicker | Drop | Lands cleanly from | Falls at or below |
|---|---|---|---|---|---|
| Fork Lab shared jump | 55 m | 6° kicker, 70 m | 4 m | 66 u/s | 49 u/s |
| Fork Lab branch jump | 100 m | 8° kicker, 70 m | 6 m | 93 u/s | 83 u/s |

- **Approach:** jump approaches climb first, so the jump is height-neutral.
- **Respawn run-up:** 250 m with no respawn points before the kicker.
- **`clean_speed`** is measured with `jump_sim` and stored on the
  TrackJump. The AI uses it to decide whether to take a route.

### 4.5 Forks

- **Splines:** the branch is a second Path3D from the fork to the rejoin on
  the main spline.
- **Junction length:** junctions span `fork_blend` / `rejoin_blend` (150 m)
  and must be **flat and level**.
  - Junction ends are where the two centre lines are 62 m apart.
  - Walls are offset 21.1 m and the road half width is 21.5 m.
- **Route lap:** a route-lap Path3D (main → branch → main) is needed so the
  AI, its trainer and the rig can treat each route as a closed lap.
- **AI route take rates** (v32): Easy 21%, Medium 46–60%, Hard 76%.

### 4.6 Road and walls (the circuits' sections, reused by both labs)

- **Road:** half width 19.5 m, edge lips out to 21.5 m.
- **Walls:**
  ```
  right (+x): (28.5,8.5) (23.5,8.4) (21.1,6.5) (21.1,-2.0) (28.6,-2.0)
  left:       the mirror image
  ```
- **Collision layers:** ground 1, walls value 4, ships 2.

### 4.7 Cameras and respawn

**Witness cameras** (track-fixed cameras outside the zone envelope; measured
by visibility):

| Feature | Where | Share of the feature visible |
|---|---|---|
| Loop | about 25 m outside, at hub height +20 | 87% |
| Loop | the hub | 100% |
| Roll | 80% of the way along, 12 m up | ~58% |

**Respawn:**
- Respawns use the last point **behind** the ship, never across the lap line.
- If that spot is occupied, the ship side-steps 7 m.

---

## 5. Proposed design (a starting point: challenge it)

The aim: Chris draws the base curve and the banks by hand in the editor
and gets feedback within about a second. Features that can't be drawn by
hand (loops, rolls, jump profiles, junctions) come from parameters. One
**Build** produces everything the game needs, and one **Validate** reports
problems in the editor.

### 5.1 Scene layout

```
MyTrack (Node3D, identity)
├─ TrackBuilder (Node3D, @tool)            ← authoring; buttons: Preview / Build / Validate
│  ├─ BaseSpline (Path3D)                  ← hand-drawn in the editor (control points + handles)
│  ├─ BankKeys (Node3D)
│  │   └─ BankKey × n (Node3D, @tool)      ← placed in the world, snapped to the spline, bank_deg, ease
│  ├─ Features (Node3D)
│  │   ├─ LoopFeature / RollFeature / JumpFeature (Node3D, @tool)  ← placed + params
│  │   └─ BranchFeature (Node3D) └─ BranchBase (Path3D, hand-drawn)
│  └─ Preview (generated, editor-only ribbon + labels; not saved)
└─ Generated (Node3D)                      ← written by Build; never hand-edited
   ├─ MainSpline (Path3D: base + spliced features + solved tilts)
   ├─ Road / Walls (TrackRoadSegments), Junctions, Floor/Env
   ├─ MagneticTrack, TrackGraph (+ BranchSpline, route laps)
   ├─ StartingPoint / StartFinishLine / StartingGrid
   └─ (respawn manager settings, AI hooks as the runtime expects)
```

Existing runtime code looks up `MainSpline` by name (in `TrackSplineHelper`
and elsewhere), and looks up `MagneticTrack` / `TrackGraph` by group.
**Check how a track scene is loaded and how `MainSpline` is found** before
nesting it under `Generated`. If anything expects it as a direct child of
the root, either keep it there or fix the lookup. Don't do both.

### 5.2 Fast visual feedback (the key requirement)

- **Live updates:** `TrackBuilder` listens to `BaseSpline.curve.changed` and
  to each BankKey's property and transform changes. It debounces them
  (about 0.2 s) and rebuilds a **lightweight preview**: a road-width ribbon
  every 2–4 m, using the solved bank. No walls, no collision. A full
  build is too slow for every drag on a 5 km track; measure it.
- **Preview overlays,** each one toggleable:
  - colour by bank angle, or by roll rate in °/m (red above 0.7);
  - curvature and lateral g at a reference speed;
  - grade;
  - distance ticks and `Label3D`s every 100 m;
  - feature footprints;
  - validator problems drawn at their location.
- **BankKeys:** each key draws a small tilted plank showing its bank. Dragging
  it moves it along the track: on each change it re-projects onto the spline
  (with a local search seeded from its last distance, so it can't jump to a
  crossing section of track).
- **Buttons:** use `@export_tool_button` (Godot 4.4+) for Preview, Build,
  Validate and Clear. The project is on Godot 4.7.

### 5.3 Distance keys vs edits upstream (decide this early and tell Chris)

If keys are stored as **plain distance**, every edit upstream slides every
key and feature downstream. That will feel broken.

**Recommendation:** keys and features are **world-placed nodes**; their
distance is *derived* by projecting onto the spline. Edit the curve
upstream, and the key stays where it is in the world.

Two costs:
- Projection is ambiguous where the track crosses itself. A local search
  from the last-known distance handles this; store that distance.
- A key that ends up too far from the spline (over 30 m) is a validator
  error.

### 5.4 Splicing features into a hand-drawn base

This is the hardest design problem.

**A loop isn't pose-neutral:** it exits 90 m to the side. Options:

- **(a) Footprint replacement.** Recommended.
  - The feature claims a stretch of the base, from d0 to d1.
  - The validator requires that stretch to be straight and level within
    tolerances.
  - The feature generates a sub-curve that starts at the base pose at d0
    and **ends exactly at the base pose at d1**. The loop's lateral step is
    absorbed by S-jogs before and after it: −shift/2 before, +shift through
    the loop, −shift/2 after. The builder solves the jog lengths so the
    stretch from d0 to d1 matches.
  - The rest of the base never moves.
- **(b) Offset everything downstream.** Simple, but it breaks the lap
  closure and moves what Chris drew. Avoid it.

**Rolls** are pose-neutral, so a straight footprint is enough. Allow a gentle
curve later if he asks.

**Jumps:**
- A climb, then the kicker, the gap, the landing and the outrun.
- Height-neutral, like Fork Lab's.
- The footprint must be straight and close to level.
- The builder runs `jump_sim` (or an in-editor shortcut of it) to fill in
  `clean_speed`, and **warns if that speed is above what the course lets a
  ship carry there**. Estimate that speed roughly or measure it with the
  lap probe.

**Branches:**
- Chris draws `BranchBase` by hand.
- The builder snaps its ends onto the main spline: positions and tangents
  over the junction length.
- It forces both paths flat and level over `fork_blend` / `rejoin_blend`.
- It emits the TrackBranch, the junctions, the route lap, and the
  TrackRoadSegments with lip fades.
- Jumps on a branch use `JumpFeature.branch`.

**Magnetic zones** come from features: a loop or roll emits its own zone,
with ramps. A manual `MagnetZone` feature lets Chris add zones anywhere
else, such as a steep bank.

**The bank profile and features:** inside a feature's footprint the
feature owns the frame (roll and loop tilts). Bank keys inside a footprint
are a validator warning. The profile blends in and out at the footprint
ends.

### 5.5 Build output

The build output should be deterministic: the same input gives a
byte-identical `.tscn`. A small output file is fine, because the road
segments build their meshes at load time (as in Fork Lab).

### 5.6 Validator (in the editor and headless)

**Checks** (each with a location, severity and message, drawn in the
preview and printed headless):

- Non-identity transforms on the root, the splines or the geometry
  (**the offset rule**).
- The road surface vs the spline frame: ray-cast every 5 m, check
  height and normal error.
- Roll rate above 0.7°/m outside a roll feature, and above 0.75°/m anywhere.
- Lateral g at a reference speed, and minimum radius, against a threshold.
  Pick the threshold from what the circuits already contain, measured.
- Grade or pitch-rate spikes. Crests that would launch a ship where no
  jump is designed: estimate from curvature times speed squared against
  the hover hold. v33 found these as "organic" exits on Swoopy.
- Feature footprints: straight and level within tolerance; no overlaps;
  not crossing the start line.
- Junctions flat and level; branch ends on the main spline within
  0.05 m and 0.5°.
- Clearance: no geometry of this track (or another section of it) within
  the ship envelope above the road. This is the self-intersection check:
  the loop exit vs the entry, over and under crossings.
- Start line and grid: on a straight, level stretch; all slots on the road.
- Respawn coverage: the largest gap between respawn points outside jumps.
- Jumps: `clean_speed` is set, and the run-up is at least 250 m.
- Bank keys farther than 30 m from the spline; bank keys inside a footprint.

**Headless entry point:** `godot --headless --path . -s
res://tools/track_builder/validate_boot.gd -- --scene=res://…`. Use the boot
pattern (see §7) so autoload-dependent code works.

### 5.7 The authoring doc (`docs/TRACK_AUTHORING.md`)

Written for Chris, not for code:

- The §2 rules, with a picture of what the offset does.
- The workflow: draw the base → place bank keys → place features → Preview
  → Build → Validate → drive it → train the AI → probes.
- One section per feature, with the §4 numbers as limits and why each one
  exists.
- A "what the validator is telling you" table.
- How to add the new track to `resources/tracks/track_manifest.tres` with a
  TrackProfile `.tres`.
- How to train AI lines:
  `train_ai_lines.tscn -- --track=<id> --fresh`, on **default_racer**.
- A short section on why the four existing circuits keep their offset, and
  that the runtime copes with it through ray-casts.

---

## 6. Deliverables and acceptance

1. **`docs/TRACK_AUTHORING.md`**: the best-practices guide (§5.7).
2. **`tools/track_builder/`** (or `addons/track_builder/`; an EditorPlugin
   is only worth it if a dock or custom gizmos clearly help):
   - `TrackBuilder`, `BankKey`, and the feature nodes, with live preview.
   - Build: splice, solve tilts, and emit the generated nodes.
   - The validator: in the editor and headless.
   - Reuse `fork_lab_turtle.gd`. Move it to a shared place if needed, and
     keep the Fork Lab build output identical.
3. **A demo track, "Builder Lab"** (`scenes/tracks/builder_lab.tscn`), made
   *with* the tools the way Chris would make it:
   - a hand-drawn base with banks, one loop, one roll, one jump, one fork
     (with a jump on the branch);
   - added to the manifest;
   - trained AI lines (default_racer);
   - all validator checks pass;
   - a full race with 8 AI racers and 0 respawns from organic exits;
   - the cinematic rig works around it.
4. **No regressions.** The six AI race checksums and the five rig checksums
   in §8 are unchanged, unless a change was intended and is explained in
   the notes.
5. **`FTF_v34_NOTES.md`** at the repo root: what was built, the measurements,
   open items, and how to run it.
6. One PR to **`main`**.

**Suggested order** (get Chris something to try early):

1. Preview and bank keys on a hand-drawn spline. Push this and ask Chris to
   try dragging.
2. Build the plain road with solved banks, plus the validator core (the
   offset and surface checks).
3. Roll, then loop, then jump, then branch.
4. The rest of the validator.
5. Builder Lab, AI training, probes.
6. The doc.

---

## 7. Environment and gotchas

- **Godot:** 4.7.1 at `/usr/local/bin/godot`. If it's missing, download
  `Godot_v4.7.1-stable_linux.x86_64.zip` from
  `github.com/godotengine/godot-builds` releases.
- **First import:** `godot --headless --path full_throttle_flux --import`.
- **CPU:** the machine has **2 cores**. Run 2, at most 4, Godot processes
  at once.
- **GitHub:** use `gh api` (REST). GraphQL is blocked here.
- **Import noise:** `shipTest.glb.import` changes on reimport. Revert it
  before committing.
- **Shared user data:** `user://` is shared between git worktrees.

### GDScript and Godot gotchas

- **`-s` scripts and autoloads:** `-s` SceneTree scripts compile *before*
  autoloads exist. Use a tiny boot script that loads a Node script (as
  every `*_boot.gd` does).
- **PackedArrays are value types:** an element you take out and change
  isn't written back.
- **Typed loops:** typed `for` loops need `for x: float in [...]`.
- **`:=` inference:** `:=` can't infer a type from an untyped value. Write
  the type out.
- **`Vector3.slerp`:** fails on parallel vectors. Use
  `ShipController.slerp_safe`, which keeps tracks bit-identical.
- **Headless errors:** a headless run prints `SCRIPT ERROR` and *keeps
  running*. Grep probe output for it.
- **Repeatable races:** seed the global RNG.
- **Timing:** time laps in simulated time under `--fixed-fps 60`.
- **`@tool` scripts:** these run in the editor, so guard runtime-only code
  with `Engine.is_editor_hint()`. Don't save generated preview children
  into the scene: leave their `owner` unset.
- **Whitespace:** blank lines inside GDScript functions in this repo keep
  their indentation tabs. Keep diffs clean.

---

## 8. Regression baselines (after PR #8; `feature/fork-jump-lab` @ adea814)

```
# AI race probe, seed 1234, 75 s unless noted
PROBE_TRACK=<id> PROBE_SECONDS=75 PROBE_SEED=1234 \
  godot --headless --fixed-fps 60 --path . -s res://tools/dev/ai_race_probe_boot.gd
# cinematic rig probe, 45 s unless noted
CR_TRACK=<id> CR_SECONDS=45 godot --headless --fixed-fps 60 --path . -s res://tools/dev/cine_rig_probe_boot.gd
```

| Track | AI race checksum | Rig checksum |
|---|---|---|
| test_circuit_3_live | 3929678988 | 3621838145 |
| test_circuit_5_live | 3790437673 | 2900775167 |
| test_circuit_6_live | 2668530540 | 110340458 |
| test_circuit_7_live | 133359682 | 2300779685 |
| loop_lab | 3860760227 (140 s) | 3358873327 (75 s) |
| fork_lab | 3551594432 (150 s) | — |

Before changing anything, run these once and confirm they match. If one
doesn't, check the seed, `PROBE_DIFFICULTY` and the probe defaults against
`FTF_v33_*.md` before assuming something is broken.

---

## 9. Conventions

- **Branches:** branch from `main` (see §0). Use one feature branch and one
  PR to `main`. No stacking.
- **Commit trailers:**
  ```
  Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
  Claude-Session: <this session's URL>
  ```
- **PR bodies:** end with `🤖 Generated with [Claude Code](https://claude.com/claude-code)`.
- **Files to commit:** commit the `.uid` files for new scripts. Add
  `.claude/` to `.git/info/exclude` if agent worktrees are used.
- **Notes files:** match the existing `FTF_vNN_*.md` style:
  - what changed and why;
  - the measurements;
  - open items;
  - a "Running it" section with the exact commands.

---

## 10. Open items carried over (not part of this task unless they block it)

- **Respawn feedback:** no ghosting or time penalty yet (v33).
- **The Drop:** it keeps its older, cleaner AI line rather than the new one.
  The new line is 0.3 s faster per lap but has more wall contacts.
- **Stale doc:** `docs/AI_TRAINING_REGIMEN.md` still has the v15 results
  table.
- **Camera occlusion:**
  - the kamikaze camera is blocked on kickers;
  - trackside cameras are blocked on Fork Lab;
  - witness shots of the loop sometimes frame dark ground.
- **Utopia:** `UtopiaKit.road_xf` exists only because of the offset.
  Builder tracks shouldn't need it.
