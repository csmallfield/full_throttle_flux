# FTF v34 — Central ship-to-ship contact resolver

Background and measurements: `FTF_v34_COLLISION_ANALYSIS.md`. This note is
what was built and what it measured.

## Files

| | |
|---|---|
| `scripts/ships/ship_contact_rules.gd` | **new** — `ShipContactRules.resolve(a, b, n, point, depth, dt, fresh)`: the contact response as pure rules on two ships |
| `scripts/ships/ship_contact_resolver.gd` | **new** — `ShipContactResolver`: self-installing node, runs after every ship each physics tick (`process_physics_priority 100`), capsule–capsule test per pair, calls the rules, one feedback event per contact episode |
| `scripts/ships/ship_controller.gd` | joins the `ship_contacts` group and calls `ShipContactResolver.ensure()`; drops layer 2 from its mask and the hover ray's; `contact_yaw_rate` integrated in `_apply_contact_yaw()`; `notify_ship_contact()`, `set_boost_overspeed()`, `get_thrust_power()` |
| `scripts/resources/ship_profile.gd` | `mass` and the `ship_collision_*` rule parameters (all **excluded from the handling hash** — they cannot touch a solo lap, so trained lines and recordings stay valid) |
| `tools/dev/ship_collision_sim.gd` | reads contact state from the resolver when present; prints `CS mode=` |
| `tools/dev/ai_race_probe.gd` | prints `PROBECONTACT episodes= hits= max_hit=` |

`FTF_CONTACT=legacy` in the environment keeps the v7 per-ship path (ships
collide inside `move_and_slide` again, pass 1 of `_handle_collisions` live)
for A/B runs. In resolver mode that pass is inert: ships never produce ship
slide collisions. It can be deleted once the resolver is accepted.

## The rules (per touching pair, per tick)

1. **Position**: the planar penetration is removed (80 %/tick) and shared by
   inverse mass. Both ships move; the heavier one less.
2. **Normal impulse** (closing > 1 u/s): `J = (1+e)·closing·exchange / (1/mA+1/mB)`,
   exchange 0.35, restitution ramping from 0 at 8 u/s closing to the profile
   value at 30, capped by `ship_collision_max_impulse`. A ship pushed over
   max_speed hands the excess to the soft limiter's overspeed allowance so it
   bleeds at `overspeed_damping` instead of being clamped next tick.
3. **Yaw kick, impact tick only**: lever arm from each ship's centre to the
   contact point, `I = m·r²` (r 2.5 m), gain 0.3, capped at 1.2 rad/s, decays
   at 4/s. Re-kicking every touching tick was tried first: a ship pressing
   into another keeps closing a little each tick through grip, and it spun
   itself into the wall. Once per episode reads as a hit; the roll spring and
   the driver catch it.
4. **Tangential damping while touching** (6/s): side-by-side ships lean on
   each other instead of chattering apart.
5. **Lean push while touching**: the ship on the throttle whose nose points
   into the other hands 12 % of its thrust (× mass ratio) to it and pays
   4 u/s² of drag. A faster ship can nudge a leader along; it costs more than
   it gives.
6. Normals are projected into the shared track plane; nothing vertical ever
   comes out of a contact.

Mass is relative; only ratios matter. `default_racer` is 1.0. The classes can
be given heft here (a Kestrel at ~1.4 displaces a Sparrow and takes less of
the exchange) without touching any handling number.

## Rig results (`ship_collision_sim`, default_racer, 60 Hz)

| Scenario | | v33 legacy | v34 resolver |
|---|---|---|---|
| rear-end, 52 closing | single-tick Δv, both ships | **35.3** | **12.4** |
| | victim speed 70 → | 102.8 (max 120) | 86.5 |
| | contact episodes / feedback events | 4 / 3 | 1 / 1 |
| push (lean on a leader at 100) | | locked at leader's speed, thrust cancelled | leader +1.6 u/s, follower −1.8 vs solo, 1 episode |
| side-swipe, 8.5 closing | contact episodes in 0.6 s | **28** | **2** |
| | feedback events | 8 | 1 |
| | victim yaw | 0 | 0.33 rad/s (twitch, recovers) |
| merge 8° into a neighbour | | 7 episodes | 1 episode, 1.5 s lean, 0.24 rad/s |
| any | vertical velocity from contact | 0 | 0 |
| solo (control) | | identical | identical |

## Race probe (`ai_race_probe`, 8 ships, 2 laps)

| Track | | legacy | resolver |
|---|---|---|---|
| test_circuit_6 (untrained lines, chaotic pack) | top speed spike | **145** (AI_Ship_7, from a shunt) | 117 |
| | lap-1 spread at the line | 4.15 s | 2.98 s |
| | lap-1 mid-pack (ships 3, 5) | 57.25 / 58.23 | 55.38 / 56.25 |
| | wall contacts (field) | 20 | 19 |
| | flying lap, best / mean | 52.33 / 53.45 | 52.33 / 53.48 |
| | contact episodes / hits / max | n/a | 3 / 3 / 16.5 |
| test_circuit_6_live (trained) | episodes | n/a | 1 (max hit 3.7) |
| test_circuit_5_live (trained) | episodes | n/a | 0 |

Flying laps are unchanged: the resolver does nothing when ships aren't
touching. Trained-line AI races barely touch at all (the field runs in a
train), which is the AI point from the analysis: contact strategy has to be
written, it won't emerge. Checksums differ even on the contact-free c5 run
because legacy `move_and_slide` was silently stopping ships short of each
other on the grid (positional contact below the 0.01 u/s impulse threshold);
that hard stop is gone.

Not measured here: the player in the pack (hand test), banked road and bob
(normals are planar so the hover spring is safe, but the capsule test uses a
shared up averaged from both ships), classes with mass ≠ 1.

## Running

```
# rig
CS_CSV=/tmp/cs.csv godot --headless --fixed-fps 60 --path . -s res://tools/dev/ship_collision_sim_boot.gd
FTF_CONTACT=legacy CS_SCENARIO=rearend ... (the old path)
# race A/B
PROBE_TRACK=test_circuit_6 PROBE_SECONDS=120 godot --headless --fixed-fps 60 --path . -s res://tools/dev/ai_race_probe_boot.gd
FTF_CONTACT=legacy PROBE_TRACK=test_circuit_6 ...
```
