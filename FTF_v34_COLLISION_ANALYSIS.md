# FTF v34 — Ship-to-ship collision analysis and AI contact strategy

Measured on `main` @ 258e2e5 with Godot 4.7-stable headless, `--fixed-fps 60`,
default_racer, using the new two-ship rig `tools/dev/ship_collision_sim.gd`.
Nothing in the game was changed for this; the rig only scripts inputs on two
real ShipControllers on a flat straight road and logs every tick.

```
# all scenarios, per-tick CSV
CS_CSV=/tmp/cs.csv godot --headless --fixed-fps 60 --path . -s res://tools/dev/ship_collision_sim_boot.gd
# one scenario, print every contact tick
CS_SCENARIO=sideswipe CS_TRACE=1 godot --headless --fixed-fps 60 --path . -s res://tools/dev/ship_collision_sim_boot.gd
# A/B a profile (a .tres copy with overrides appended; keys absent from the file are defaults)
CS_PROFILE=res://resources/ships/my_variant.tres ...
```

Scenarios: `rearend` (B holds 70, A flat out from 40 m back), `push` (B holds
100, A flat out, then leans on it), `pushsteer` (push, then A steers hard out),
`sideswipe` (both 110, lanes 4 m apart, A steers into B for 0.6 s), `merge`
(hulls overlapping lengthwise, A heads 8° into B), `solo` (control: no contact).
Metrics per ship: contact ticks, contact **episodes** (rising edges — the
chatter count), `ship_collision` events, largest single-tick velocity change
(**dv/tick** — the shunt), max speed, max |vy|, yaw rate / yaw accel, hover ray
hitting a ship, min centre distance.

## What the numbers say

| Scenario | Closing | Hitter dv/tick | Victim dv/tick | Victim speed jump | Contact ticks / episodes (hitter) | Yaw on victim |
|---|---|---|---|---|---|---|
| rearend | 52.3 | **35.3 in one tick** (120→85) | **35.3** (70→**102.8**) | +47% instantly | 429 / 4 | 0.00 |
| push | 23.6 | 15.9 | 15.9 (100→112) | +12% | 428 / 4, then locked at B's speed | 0.00 |
| sideswipe | 8.5 | 5.7 | 5.7 | — | **38 / 28** | 0.00 |
| merge | 14.1 | 9.5 | 9.5 | — | 128 / 7 | 0.00 |

Full-race corroboration: the stock `ai_race_probe` on circuit 6 (60 s, 8 ships)
had AI_Ship_7 peak at **145 u/s** against a 120 max, from contact.

Knob sensitivity (same rig): restitution 0.35→0.05 cuts sideswipe episodes only
28→22 and still gives the rear-end victim +25 u/s in one tick; max_impulse
40→12 turns the one 35 u/s shunt into 7 capped hits over the next frames —
the victim still ends at 92. **The current knobs cannot fix this; the model
has to change.**

## Why it feels like that — four mechanisms

### 1. The "shunt" is a full equal-mass elastic exchange in a single tick
`_resolve_ship_contact` applies `J = (1+e)·closing/2` to both ships at once.
A 52 u/s closing rear-end (quite ordinary: 120 into a ship braking for a
corner) is a 35 u/s step on both. The victim gets +33 u/s *forward*, well over
max_speed, and the soft limiter then bleeds it off over the next second. Two
feel consequences: the victim is launched (you see the ship ahead "teleport"
away), and the hitter stops like it hit a wall. Real WipEout transfers a much
smaller fraction of closing speed and spends most of it as yaw/roll on the
victim plus a short speed loss on the hitter.

### 2. Sustained contact is a hard stop with thrust cancelled
`_pre_collision_velocity` is captured at the **top** of `_physics_process`,
before thrust, drag, grip and airbrakes integrate this tick. When any ship
contact exists, `velocity = _pre_collision_velocity` discards all of that
integration. Combined with `move_and_slide` treating the other
CharacterBody3D as a static obstacle and the `closing >= -0.01` no-op, the
`push` case locks both ships at the leader's exact speed indefinitely (428 of
480 ticks "in contact", dv 0.00): the follower cannot push, the leader is never
nudged, and the follower's throttle does nothing until it steers out of the
wake. That's the "no weight / nothing transfers" feeling in pack racing, and it
is the opposite failure to the rear-end shunt: too much in one tick, then
nothing at all.

### 3. Side contact chatters at tick rate
Side-swipe: 28 contact episodes inside 38 contact ticks. Each tick the mover
is stopped at the hull by `move_and_slide`, gets a small lateral impulse out,
the steering input pushes it back in next tick, repeat. Restitution is not the
cause (see sensitivity). It is the combination of (a) no positional
separation being shared with the other ship, (b) restitution applied even at
tiny closing speeds, and (c) nothing damping relative *tangential* velocity, so
the ships never "settle" against each other. The audio hears it: 8
`ship_collision` events in 0.6 s (the cooldown is per ship, and both ships
fire).

### 4. Zero rotational response
`max_yaw` on the victim is 0.00 in every scenario. An off-centre hit changes
velocity only; the hull never pivots, the roll spring (driven by measured
yaw rate) never fires on the victim. Most of what reads as "weight" in a
racer is angular: the hit ship twitching, over-rotating, and the driver
catching it. There is no lever arm anywhere in the current code even though
`KinematicCollision3D.get_position()` provides one.

Smaller things seen in the code, not measured as problems:
- Only the ship that moves into the contact reports a slide collision (victim
  `contact_ticks = 0` in every rear-end). Detection is asymmetric, so the
  victim's own `_handle_collisions` never sees ship contact and the resolver's
  behaviour depends on which ship happens to move first.
- `hover_ray.collision_mask = 3` includes ships; never triggered in the rig
  (capsule is narrow), but on banked road with bob it can fire the hover spring
  at `hover_force_max` into a vertical kick.
- Capsule normals carry a Y component when the two hulls sit at different
  heights (bob, banking); any vertical impulse fights the hover spring.
- `ship_collision_feedback_min_speed = 5` with the cooldown per ship: pack
  racing spams the collision sound.

## Fix design — two options

### Option A: keep the per-ship impulse model, repair it (small, incremental)
1. Capture `_pre_collision_velocity` **immediately before** `move_and_slide`
   (after all integration), not at the top of the tick. One line; fixes the
   thrust cancel in sustained contact.
2. Exchange a *fraction* of closing speed, not all of it: `J = k·(1+e)·closing/2`
   with k ≈ 0.4–0.5, and route the victim's overspeed through
   `_boost_overspeed` so the limiter owns it.
3. Restitution ramp: `e = 0` below ~8 u/s closing, rising to the profile value
   by ~30. Kills most chatter without touching big hits.
4. Yaw kick from the lever arm: `r = contact_point − ship_centre`,
   `yaw += k_yaw · (r × J·n)·up`, applied to both ships with opposite sign.
   This is the single biggest "weight" lever.
5. Sustained contact push: when in contact with `|closing| < 1`, transfer
   `f·throttle_input·thrust` from follower to leader (f ≈ 0.3) and apply
   `(1−f)` as a drag on the follower, so leaning on a leader nudges it and
   costs you more than it gains them.
6. Tangential damping while touching: damp relative velocity along the
   contact tangent (in the track plane) so side-by-side ships lean rather
   than bounce.

Tradeoffs: minimal code motion, stays bit-identical for anything not in
contact. But the structural problems stay: `move_and_slide` still stops the
mover dead at the hull (positional response is one-sided), detection stays
asymmetric and order-dependent, and the victim is never displaced — a
side-by-side push can't move the other ship over, only change its velocity.

### Option B (recommended): central pair resolver, ships stop colliding with each other in move_and_slide
- Remove layer 2 from the ships' `collision_mask` (and from the hover ray).
  Ships then slide only against road and walls; `move_and_slide` never sees
  another ship.
- A `ShipContactResolver` node runs once per physics tick **after** every ship
  has moved (`process_physics_priority` above the ships, owned by ModeBase).
  For each pair (8 ships = 28 pairs, trivial): capsule–capsule test
  (segment–segment closest points; the capsule is already axis-aligned with
  the ship's forward axis), penetration depth and normal **projected into the
  track plane** (drop the component along the shared up, so the hover spring
  is never fought).
- Resolution per pair, symmetric and order-independent:
  - **Position**: split the penetration by inverse mass (`profile.mass`, new;
    classes get real heft: a Kestrel displaces a Sparrow, not the other way).
  - **Normal impulse**: fraction-scaled, restitution ramp, overspeed through
    the limiter — as in A.2/A.3.
  - **Angular**: yaw kick from the lever arm, inverse-inertia weighted — A.4.
  - **Tangential**: relative-tangent damping while in contact — A.6.
  - **Sustained push**: thrust transfer while resting — A.5.
  - Feedback: one `ship_collision` emit per pair per episode with the impact
    speed, so audio/shake fire once per actual hit.
- Delete pass 1 of `_handle_collisions` and `_resolve_ship_contact`.

Tradeoffs: more new code (~200 lines) and it touches every mode that spawns
ships (one `add_child(resolver)` + registering ships, where `set_race_ships`
already happens). But it gives the properties the feel needs — symmetric,
order-independent, both ships displaced, real mass — and it gives the AI a
model it can *reason about* (below), because the resolver's rules are
explicit numbers rather than emergent from Godot's slide response. A also
remains a cheap first step inside B's parameters; the rig distinguishes them.

Both options keep CharacterBody3D. Switching ships to RigidBody3D was
considered and rejected: the hover, grip-rotates-velocity and wall logic are
all written against a kinematic body, and rigid contact would add bounce you
would then spend weeks fighting.

**Targets for the rig** (acceptance numbers for either option): rear-end at
52 closing → victim ≤ +12 u/s and ≤ max_speed within 0.3 s, hitter −15 to
−20, victim yaw spike 0.4–0.8 rad/s; sideswipe → ≤ 3 episodes per 0.6 s of
steering into the other ship, ≤ 2 feedback events; push → follower loses
~3 u/s/s while leaning, leader gains ~1 u/s/s; no vy from any contact.

## AI: contact as strategy

What exists (`ai_ship_avoidance.gd`): Euclidean zones (25 m forward cone, 8 m
side, 12 m rear), urgency from distance only, a steer term added **after**
the control decider (clamped ±0.5), throttle lift to 75% only inside 5 m. At
120 u/s, 25 m is 0.2 s and 5 m is 40 ms of look-ahead. "Aggression" only ever
*reduces* avoidance; `allow_blocking` is read nowhere; `relative_speed` is a
difference of speed magnitudes, not closing speed; the side zone is a
`|forward_dot| ≤ 0.3` cone, which at 2 m lateral means ±0.6 m of overlap.
Adding steer after the decider also means the line follower corrects it back
next tick (two controllers on one axis), which is some of the AI wobble in
traffic.

Proposed structure (works in spline space, which the AI already has:
`world_to_spline_offset`, `calculate_lateral_offset`, the baked line's
lateral):

**Perception**: for each other ship, `(Δs, lat, Δs_dot)` along the spline, a
0.5–1.5 s prediction of its lateral (its current lateral drift + its baked
line's lateral ahead, which every AI can read for every other AI and estimate
for the player), and time-to-collision from `Δs / Δs_dot`. Replaces the
zones; makes awareness speed-scaled for free.

**Intent state machine** (per AI, decisions committed for 1–3 s so they read
as choices, not jitter):
- `FOLLOW` — hold the baked line, keep a TTC-based gap behind a slower ship,
  lift only when TTC < ~0.6 s.
- `OVERTAKE` — pick the side with the most predicted room at the next apex
  (inside if the target is on the baked line, outside if it's hugging the
  inside), set a lateral *target offset* and commit; abort if the gap closes.
- `DEFEND` — a faster ship behind with TTC < ~1.5 s: move once toward its
  predicted side / toward the inside of the next corner, hold until the
  corner. One move per straight (no weaving), which is both fair and what
  `allow_blocking` meant.
- `SHOVE` — alongside, in or entering a corner, target on the **outside**:
  lean in with a controlled lateral closing speed (~6–10 u/s, below the
  shunt range) so the resolver's lateral push plus the corner pushes them
  wide. Cost model: the pusher's own line and scrub, so it is worth it only
  when ahead of the apex. This is the WipEout move and it needs the symmetric
  resolver to work at all.
- `YIELD` — being lapped, or a much faster class approaching: give the line.
- `RECOVER` — after being hit (yaw spike > threshold): full line-holding,
  no strategy for ~1 s.

**Plumbing change**: instead of adding steer, the strategy layer biases the
**lateral target** the line follower aims at (`cached_target_lateral_offset`
± bias, clamped to the usable half width) and sets a throttle cap; the
existing decider and steering do the rest, so there's one controller per
axis. Avoidance becomes a special case: an overtake that isn't attempted.

**Parameterisation**: per-ship *personality* (aggression, patience, risk)
layered under the existing skill scalar, so the field has characters;
difficulty handicaps the AI per the existing plan (worse decisions, later
commits, misjudged TTC) rather than different tuning. Optional: short memory
of who hit me, raising aggression toward that ship for a lap.

**Verification**: `ai_race_probe` already counts walls and laps; add per-ship
counts of contact episodes, shunt magnitudes, places gained/lost within 2 s
of a contact, and the intent state at each contact. Acceptance: contacts per
lap stays in a band (not zero, not every corner), no measurable lap-time cost
from strategy on a clean lap, and no respawns caused by AI contact.

## Suggested order
1. Option A steps 1–3 (an afternoon) and re-run the rig: it removes the two
   worst behaviours and tells us how much of the feel is the exchange model.
2. Option B resolver behind a flag, A/B with the rig and the race probe
   checksum (expected to change only when ships touch).
3. Perception + FOLLOW/OVERTAKE/DEFEND on the lateral-target plumbing;
   SHOVE last, once the resolver's push is tuned.

## Files
| | |
|---|---|
| `tools/dev/ship_collision_sim.gd` + `_boot.gd` | the two-ship rig (new) |
| `scripts/ships/ship_controller.gd` `_handle_collisions`, `_resolve_ship_contact` | the code analysed |
| `scripts/ai/ai_ship_avoidance.gd` | the AI layer to replace |
