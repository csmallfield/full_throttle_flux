# FTF v33: respawns on every track and in every mode

v32 found two respawn bugs on the real circuits (Utopia, Swoopy, Hairpin
Alley, The Drop) and left them alone to keep those tracks bit-identical.
v33 fixes them and a few more found along the way.

- Races now get a respawn manager on every track, as time trial and endless
  already had. That covers the player and the AI ships.
- Respawn points sit on the road surface. Each one is found by raycast, aligned
  to the road and placed at hover height. Before, they were 20 m above the
  spline.
- A ship that leaves the track respawns about 1 s after it goes over the wall,
  on every circuit. Before, the only trigger was y < -100: 2–7 s, and much
  longer from high sections.
- The respawn goes to the last point behind where the ship last had road
  under it. It never puts a ship on the other side of the start/finish line,
  and never onto a spot another ship occupies.
- On every run without a respawn, every checksum is bit-identical to before,
  including Loop Lab and Fork Lab.

## What was wrong

1. **Races had no respawn manager on the circuits** (v32 only added one for
   TrackGraph tracks). A fallen ship came back at its `last_safe_position`.
   That spot is on the road, but the ship kept whatever orientation it had
   there: up to 16° off the road on banked sections, often at the edge
   (15.8 m off centre) and pointing at the wall.
2. **The road is not where the spline is.** I found this on the way to the
   respawn-height bug, and it is the root cause of that bug. On each circuit
   the `groundGeo` (and wall) CSG node has its own transform: about 1.04° of
   tilt about X plus a small translation, pivoting on the MainSpline origin.
   2 km from the origin that moves the road a long way. Measured, road surface
   minus spline: Utopia −2..+19 m, Swoopy −9..+14, Hairpin Alley +0.5..+16,
   The Drop −21..+4. A model of road = spline × node transform × polygon
   matches the raycast surface to within 0.9 m. So "20 m above the spline"
   was really 0–41 m above the road.
3. **Respawn points were tilted up to 50° off the road** on banked sections
   (Swoopy 45°, The Drop 50°). Off Loop Lab they used the spline's *untilted*
   up vector.
4. **The time-trial/endless lookup used the fall position.** It took the
   respawn point nearest to where the ship was when it got to y = −100. After
   a long fall that is some unrelated part of the lap. Measured: respawns
   3,669 m *ahead* and 1,738 m behind the spot where the ship fell, and 50–250
   m ahead in most cases.
5. **Falls were slow to trigger:** y < −100 is 120–550 m below these roads,
   which took 2.1–6.8 s.
6. **The respawn drop** (the v31 finding): in time trial the ship fell from
   the high point, hit the road at 35–52 u/s, and 5 of 10 forced falls sank
   into the one-sided road collision (up to 131 of the next 180 ticks with the
   hull below the surface). The camera itself was fine: it snapped on the
   respawn tick and then followed the drop.
7. `settle_on_surface()` didn't set `ground_distance`. When a respawn happens
   mid-tick (from `_check_respawn_needed()`), the hover spring then read a
   stale airborne value in the same tick.

Also found (not respawn bugs, not fixed; see Open issues):

- **Swoopy loses AI ships over the outside wall** at about 6,350 m (at
  90–110 u/s) and 7,645 m (at 33–65 u/s, climbing). It happens in an ordinary
  race with no forced falls: 4 respawns in the 75 s seed-1234 baseline, about
  10 in 230 s. So that baseline already included respawns.
- The walls are about 6.0–6.5 m above the road everywhere I measured,
  including at those two spots. There are no wall gaps on any circuit. I did
  not find the cause.

## What changed

| File | Change |
|---|---|
| `scripts/modes/race_mode.gd` | `_setup_respawn_manager()` on every track. Player and AI both get it. The unused `_track_graph_node()` is removed. |
| `scripts/tracks/track_respawn_manager.gd` | Road-surface table, surface respawn points, behind-the-ship lookup with a start/finish-line guard, free-spot check, and `off_track_reason()`. |
| `scripts/ships/ship_controller.gd` | `_check_respawn_needed()` asks the manager. `respawn()` looks up from `last_safe_position` on every track. `settle_on_surface()` sets `ground_distance`. The respawn log prints the reason. |
| `tools/dev/fall_monitor.gd` (new) | Forced-fall measurement shared by the race probe and the time-trial driver. |
| `tools/dev/ai_race_probe.gd` | `PROBE_PUSH` (any track), AIRMAX, and an ORGANIC line for every unforced respawn. |
| `tools/dev/loop_lab_driver.gd` | `LL_PUSH`, airmax, and a `DRIVE checksum` for A/B. After a respawn the autopilot re-acquires the spline. |

Nothing in `scripts/ai/*` changed.

### Respawn points (tracks without a TrackGraph)

At load, a ray is cast along the tilted road normal through the spline every
5 m, ±45 m. Of the upward-facing road hits (layer 1), it keeps the one nearest
the previous sample's height.

- That continuity is what keeps Utopia's bridge from being taken for the road
  underneath it. The bridge at 4,530 m is 29 m above the road at 5,040 m, with
  centre lines 37–43 m apart.
- The road was found at every sample on all six tracks.

The points themselves:

- One every 50 m, `surface_clearance` (2.75 m, the default ship's hover
  height) above the surface along its normal. They face along the road in its
  plane.
- None inside a magnetic zone (the v30 rule is kept).
- None within 15 m of the start/finish line. A ship that appears inside the
  line's trigger at a standstill counts as a wrong-way crossing, and its next
  lap would only clear that penalty.
- `settle_on_surface()` then snaps the ship onto its own hover height. The
  hover ray reaches `hover_height * 3`, so any profile with hover ≥ 0.92 m
  settles.

Tunnels and buildings: there is no scenery collision on any circuit (only the
road and the walls), so a point on the road is always clear, wherever it is.
Utopia's tunnels are visual only.

### Which point

- **The query position is `last_safe_position` on every track**, which v32
  used on graph tracks only. A ship that has fallen 500 m is nearest to some
  unrelated part of the lap.
- The nearest road sample is found by distance to the *road*, not to the
  spline, so a ship on the bridge maps to the bridge.
- **It respawns at the last point behind that position** (Loop Lab always
  did). A respawn never gains ground; it costs 0–52 m, 45 m typical.
- **Start/finish guard:** laps are counted by line crossings. A ship sent
  back behind the line would score the lap twice; one sent ahead of it would
  lose a lap. If the point behind is across the line, the first point past the
  line is used instead.
- **Free spot:** two ships that leave at the same corner a moment apart get
  the same point. If another ship is within 6 m of it, the spot moves 7 m to
  the right, then 7 m to the left. This applies on Fork Lab's graph points too.
- **Fork Lab is unchanged:** route- and jump-aware points at 4 m, the
  last-safe lookup, and the RespawnTriggers.

### When to respawn: `TrackRespawnManager.off_track_reason()`

This applies to a ship that is airborne, outside a magnetic zone (v30 keeps
its own rules there) and not flying a designed jump (the v31 RespawnTriggers
catch those). Either condition sends it back:

- **more than `fall_depth` (12 m) below the road surface it left**, or
- **airborne for more than `max_air_time` (4 s)**: stranded on a wall top,
  or anything else that never falls below the road.

How the road is measured:

- The road reference starts from the ship's last grounded spot and is
  tracked locally (±40 m per tick). A ship falling past another part of the
  lap is still measured against the road it came off.
- On Utopia's bridge the 12 m rule fires before the ship reaches the road
  29 m below, so landing on a later part of the lap can't happen there.
- On graph tracks the reference is `TrackGraph.locate()` and that path's road
  frame.
- Grounded ships cost nothing. An airborne ship costs one 17-sample scan per
  tick.

`y < respawn_y_threshold` (−100) stays as a backstop.

Measured airtime with no forced falls:

| Run | Longest airborne spell |
|---|---|
| Races on Utopia, Hairpin Alley, The Drop, Loop Lab | 0.00–0.23 s |
| Fork Lab, outside jumps | 1.1 s |
| Time-trial autopilot, outside falls | ≤ 1.9 s |

The 12 m depth is about 0.8 s of fall after the wall.

False-positive check: kicks of 80 u/s sideways and 60 u/s up, 3 ships at each
of 12 spots.

- 30 of the 36 kicked ships stayed on the road or came back down on it, and
  none of those was respawned.
- The 6 that went over the wall (Swoopy 2200 and 4800, Hairpin 4900)
  respawned 1.6–4.0 s after the kick.

### Alternatives rejected

- **A fixed 4 m above the spline (the Fork Lab approach):** the circuits'
  road is −21..+19 m from the spline, so the point would be inside the road or
  20 m up. Raycasting works whatever the geometry.
- **Fixing the CSG transforms** so the road matches the spline: it changes
  the road under every trained line and every checksum, and it's a track
  edit, not a respawn fix. It is recommended separately (see Open issues).
- **Keeping `last_safe_position` as the respawn spot** (the old race
  behaviour): it lands on the road, but tilted and at the edge. It also gives
  no line guard, no zone or jump exclusion, and can come back on a kicker
  (Fork Lab, v32).
- **The nearest point instead of the one behind:** from the fall position it
  is the 3.7 km bug above. From the last-safe position it gains up to 25 m.
- **A per-track kill plane** (lowest road − margin): still 500 m of fall from
  The Drop's summit. The depth below the road is the same rule everywhere and
  needs no tuning per track.
- **An airtime rule only:** it would need a margin over legitimate air (up to
  1.9 s measured) and would still take 2+ s. Depth is the direct signal, and
  airtime catches what depth can't.
- **A "landed on another part of the lap" rule** for stacked sections: not
  needed, because the depth rule fires first (bridge 29 m, depth 12 m).

## Forced falls: before → after

Ships are put over the wall: `T…` sides, 14 m past the wall's inner face,
same height, same velocity plus 20 u/s outward. I used this because kicks
almost never get a ship off these circuits: the hover spring (an 8.25 m ray)
and the 6 m walls hold it. The spots are corners, high sections, the
descent, and both sides of Utopia's bridge.

- **Race:** 2 AI ships per spot on lap 2, seed 1234, 230 s.
- **Time trial:** the player on the autopilot, lap 1.

Respawn time is from going over the wall to the respawn. *on road* = the
ray under the respawned ship hits the road within 0.5 m of hover height.
*settle* = the largest height error / largest speed along the road normal in
the first 0.5 s.

**Race (AI)**

| Circuit (spots) | Respawn time | On road | Back from spot | Tilt at respawn | Settle |
|---|---|---|---|---|---|
| Utopia (1100, 2200, 4560 L, 4580 R) | 2.78–3.35 s → **0.82–1.12 s** | 8/8 → 8/8 | 2–36 m → 22–71 m | ≤ 4.7° → **0.0°** | 0.78 m / 10.3 → **0.04 m / 1.1** |
| Swoopy (2200, 3500, 4800) | 3.10–4.65 s → **0.55–1.27 s** | 6/6 → 6/6 | 3–32 → 36–46 m | ≤ 15.4° → **0.0°** | 0.29 / 5.9 → 0.38 / 8.3 (traffic contact) |
| Hairpin Alley (900, 1400, 4900) | 2.48–3.10 s → **0.75–1.00 s** | 6/6 → 6/6 | 7–27 → 31–47 m | ≤ 2.3° → ≤ 0.7° | 0.34 / 7.1 → 0.98 / 17.4 (a ship hit 0.3 s after its respawn) |
| The Drop (1500 descent, 3900, 5700 summit) | 2.15–**6.48** s → **0.67–1.02 s** | 6/6 → 6/6 | 4–34 → 0–52 m | ≤ 16.3° → **0.0°** | 0.62 / 6.8 → **0.07 / 1.3** |

**Time trial (player)**

| Circuit | Respawn time | On road | Back from spot | Settle | Hull under the road (ticks) |
|---|---|---|---|---|---|
| Utopia | 2.75–3.75 s → **0.78–1.15 s** | 1/3 → **3/3** | −152..−100 (ahead!) → 46–52 m | 8.1 m / 43 u/s → **0.04 / 1.1** | 9 → **0** |
| Swoopy | 3.57 s → **0.78–1.32 s** | 0/1 → **3/3** | −3,669 (ahead!) → 37–45 m | 5.6 / 35 → **0.10 / 2.4** | 0 → 0 |
| Hairpin Alley | 2.63–3.17 s → **0.80–0.95 s** | 0/3 → **3/3** | −55..+1,738 → 31–46 m | 9.1 / 42 → **0.01 / 0.3** | 197 → **0** |
| The Drop | 2.12–**6.82** s → **0.63–1.58 s** | 0/3 → **3/3** | −249..+1 → 51 m | (fell 20+ m) → **0.05 / 1.2** | 2 → **0** |

- **Old time trial, Swoopy:** it has only one sample because the first
  respawn put the ship 3.7 km ahead, past the other two spots.
- **Grounded:** after the respawn, 180/180 ticks for every time-trial fall,
  and for AI falls except those hit by traffic (≥ 155/180).
- **Camera:** the chase camera is at its normal offset on the first tick
  (7.5 m, 14.7° aim). After that, its largest per-tick move beyond the ship's
  own is 0.11 m. It snapped cleanly before too, but then followed a 20–40 m
  drop.
- **Speed:** the ship comes back at 0 u/s and reaches 80 u/s in 1.7–1.9 s on
  the flat. It takes more than 3 s at a few spots on long climbs (Swoopy 3500,
  Hairpin 4900, The Drop 5700) because of slope gravity.
- **AI:** every pushed ship picked its line back up and finished the race (3
  laps) on Utopia, Hairpin Alley and The Drop. On Swoopy 5 of 7 finished in
  230 s (before: 1 of 7). The stragglers fell repeatedly at the organic spots.
- **Lap counts:** no ship scored more than 3.
- **Contacts:** a respawned ship standing on the centre line gets 0–6 ship
  contacts in its first 3 s in a race (before: 0–6 too).
- **Fork Lab, main route** (900 L, 2900 R, 3300 L): respawn 0.87–1.10 s,
  on the road at 2.75 m, tilt ≤ 0.2°. The second ship at a spot was moved
  7 m aside.

**Organic falls (Swoopy, 75 s race, no pushes).** The ship leaves the road
at 6,350 m or 7,645 m. It now respawns 1.1–1.2 s later at the first spot and
1.6–3.2 s later at the second, where the ships climb before they fall. Before
it took 2.6–4.9 s. In both cases it lands 20–30 m behind.

## Regression: runs with no respawn are bit-identical

Same branch, same seeds; before = `e2aa20b`.

| Run | Before | After | Respawns in the run |
|---|---|---|---|
| ai_race_probe c3 Utopia 75 s | 3929678988 | 3929678988 | 0 |
| ai_race_probe c6 Hairpin 75 s | 2544408098 | 2544408098 | 0 |
| ai_race_probe c7 The Drop 75 s | 133359682 | 133359682 | 0 |
| ai_race_probe Loop Lab 140 s | 675169125 | 675169125 | 0 |
| ai_race_probe Fork Lab 150 s | 3551594432 | 3551594432 | 0 |
| cine_rig_probe c3 / c5 / c6 / c7 45 s | 3621838145 / 1427140778 / 1324755775 / 2300779685 | same | 0 |
| cine_rig_probe Loop Lab 75 s | 1087435003 | 1087435003 | 0 |
| time trial autopilot c6 / c7 (DRIVE checksum) | 687560683 / 3729254047 | same | 0 |
| time trial Loop Lab, Fork Lab | 973562491, 3101412798 | same | 0 |
| time trial Loop Lab, magnet 0 on the loop, 34 u/s (peels off, lands on the loop, carries on) | 1644886184 | 1644886184 | 0 |

**Changed: every one of these runs includes respawns**

| Run | Before | After | Respawns |
|---|---|---|---|
| **ai_race_probe c5 Swoopy 75 s** | 2744688434 | **2814012173** | 4 → 3 (the organic falls) |
| ai_race_probe Fork Lab 150 s, PROBE_SABOTAGE=1 | 2680360294 | 1044753590 | 7 → 7. Same falls and points (branch 226). Only the free-spot offset differs. Without it (an interim build) it was still 2680360294. |
| time trial c3 / c5 autopilot | 3775433328 / 4104008484 | 2345208784 / 1471406625 | 2 / 1 → 2 / 1 (the simple autopilot falls off) |
| time trial Loop Lab, magnet 0, 28 u/s | 627383074 | 2426234624 | 3 → 3. The same point behind the loop, now on the road (y 2.75) instead of 20 m up |

**New baselines on the current lines**, for when the retrained lines land:

| Probe | Utopia (c3) | Swoopy (c5) | Hairpin Alley (c6) | The Drop (c7) | Loop Lab |
|---|---|---|---|---|---|
| ai_race_probe | 3929678988 | 2814012173 | 2544408098 | 133359682 | 675169125 |
| cine_rig_probe | unchanged | unchanged | unchanged | unchanged | unchanged |

- **Respawns in these runs:** only Swoopy's race probe has any (3, all
  organic).
- **Run lengths:** ai_race_probe uses PROBE_SECONDS=75 (140 on Loop Lab).
  cine_rig_probe uses CR_SECONDS=45 (75 on Loop Lab).
- **Retrained lines:** the race checksums will move again when the other
  session's lines land. Re-check that the circuits' race probes still show 0
  respawns (or only the Swoopy organic ones), using the AIRMAX and ORGANIC
  lines.

Also unchanged: the race setup now awaits the manager's one setup frame on
every track. That changed nothing (bit-identical above).

## Running it

```
# AI: knock ships over the wall (T*) or kick them (O/I/L/R) at spline distances
PROBE_TRACK=test_circuit_6_live PROBE_SECONDS=230 PROBE_PUSH=900:TO,1400:TO,4900:TO \
  godot --headless --fixed-fps 60 --path . -s res://tools/dev/ai_race_probe_boot.gd
#   PROBE_PUSH_SHIPS (per spot, default 2), PROBE_PUSH_PASS (default 2 = lap 2),
#   PROBE_PUSH_LAT / PROBE_PUSH_UP (kick, default 70 / 35), FALL_TRACE=1
# Player in time trial on the autopilot
LL_TRACK=test_circuit_7_live LL_LAPS=2 LL_PUSH=1500:TL,3900:TO,5700:TO \
  godot --headless --fixed-fps 60 --path . -s res://tools/dev/loop_lab_drive_boot.gd
```

Each push prints a FALL line; the FallMonitor header explains every field.

## Open issues

1. **Swoopy's organic falls** at about 6,350 m and 7,645 m, which happen
   without forced falls. Respawns now catch them in about 1 s, but the AI
   shouldn't be leaving the track there. Worth checking with the retrained
   lines; the ORGANIC log lines give where, how fast and how long.
2. **Road vs spline.** The circuits' road CSG nodes are tilted about 1° about
   the MainSpline origin. Anything that assumes the road is at the spline is
   off by up to 21 m. The respawn code no longer is. Fixing the tracks means
   re-baking/retraining lines and new checksums.
3. **Loop Lab falls inside a zone** still wait for y < −100. A ship that
   drops out of the loop takes about 5 s, the same as before. The new rules
   are skipped in zones on purpose, to keep v30's rules. A depth rule against
   the zone's surface frame would make this prompt; untested.
4. **No respawn penalty or ghosting.** The ship comes back stationary on the
   centre line, and traffic can hit it (0–6 contacts in the first 3 s, the
   same as before). A short no-collision window or a time penalty are design
   choices, left for Chris.
5. **Climbs.** Some points sit on long climbs (The Drop before the summit,
   Swoopy 3500), where a standing start is slow. Points could be moved off
   steep grades if that feels bad.
6. **The free-spot check moves sideways only** (±7 m). With three or more
   ships at once, the third one goes on the point as before.
7. **The lap guard assumes the start/finish line is the only lap counter.**
   It is today (`StartFinishLine`). A ship that crosses the line in the air
   and then falls would still be put back behind it. I didn't see this happen.
