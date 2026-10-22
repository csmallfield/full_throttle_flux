# FTF v34 — AI contact strategy

Follows `FTF_v34_NOTES.md` (the resolver) and the design in
`FTF_v34_COLLISION_ANALYSIS.md`. The AI now treats traffic as a set of
choices instead of a repulsion field.

## Files

| | |
|---|---|
| `scripts/ai/ai_contact_strategy.gd` | **new** — `AIContactStrategy`: perception in spline space, the intent machine, outputs a lateral bias and a speed cap |
| `scripts/ai/ai_field_sense.gd` | **new** — `AIFieldSense`: every ship's spline offset / lateral / speed-along-track computed once per tick and shared (the helper's closest-point search is a 1000-point scan; 8 AIs × 7 others would have been too heavy) |
| `scripts/ai/track_corridor.gd` | **new** — `TrackCorridor`: usable [min, max] lateral per spline bucket, measured lazily with the baker's wall raycasts and cached per track (baked lines don't persist widths) |
| `scripts/ai/ai_line_follower.gd` | `lateral_bias` added to the aimed lateral (baked and geometric targets, and the crosstrack term); `speed_cap` bounds the suggested speed |
| `scripts/ai/ai_ship_controller.gd` | creates the strategy instead of `AIShipAvoidance` (unless `FTF_AI_CONTACT=legacy`); `update()` runs **before** the decider so the decider stays the only steering law; forwards race ships / position / skill |
| `scripts/ships/ship_contact_resolver.gd` | episode hysteresis (12 ticks) and a 0.25 m contact skin, so a lean is one episode; `in_episode()`; hit stats count closing ≥ 3; `FTF_LOG_HITS=1` prints every hit, big hits (≥ 25) always print with context |
| `scripts/resources/ship_profile.gd` | yaw kick gain 0.3 → 0.25, cap 1.2 → 0.9 rad/s (the AI's steering couldn't catch a 1.2 rad/s twitch before the next hit) |
| `tools/dev/ai_race_probe.gd` | `PROBESTRAT` per AI: personality, overtakes done/attempted, defends, shoves, yields, recovers, seconds per intent, hits taken per intent; big hits print both ships' recent intents |

`AIShipAvoidance` is untouched and still used under `FTF_AI_CONTACT=legacy`.

## How it works

**Plumbing.** The strategy never touches the steer. Each tick, before
`decide_controls()`, it writes `follower.lateral_bias` (metres, relative to the
baked line, clamped so the aimed lateral stays inside the measured corridor,
rate-limited to 7 m/s — 5 m/s into a shove) and `follower.speed_cap`. The
decider then drives toward the biased target as it always has. One controller
per axis; the two-controllers-fighting wobble of the old avoidance is gone.

**Perception.** For every other ship: distance along the track `ds` (signed,
wrap-aware), lateral gap `dlat`, closing rate along the track and a
time-to-collision. Three ships matter: the nearest **lead** ahead within
`speed × 1.5 s` and 6 m laterally; the fastest-arriving **threat** behind; and
whoever is **beside** (|ds| < 7 m). Corner context comes from the follower's
own look-ahead (signed curvature, distance to the corner).

**Intents** (committed, with cooldowns, so they read as decisions):

| | enters when | does | leaves when |
|---|---|---|---|
| FOLLOW | default | holds the line; gives room to a ship alongside (so the line doesn't lead back into it); lifts to 98→90 % of the lead's speed as TTC drops under 1.1 s; after ~3 s side by side with no progress, **tucks in** behind for 1.5 s | — |
| OVERTAKE | lead TTC < 1.6 s, closing > 3 u/s, no braking zone inside 0.8 s (or closing > 8), cooldown clear, aggression roll | aims for the lead's lateral ± 4.6 m on the side with more corridor room (inside of the next corner preferred, stickiness to the side already taken); caps speed to the lead's while still in its lane | past it by 8 m (counted as done), stalled 3 s × patience, or it pulls away |
| DEFEND | faster ship behind, TTC < 1.6 s, straight ahead (> 60 m to the corner), nobody alongside, position worth defending, aggression roll | moves to cover the threat's lateral (≤ 4 m), once per 6 s | 2 s, threat gone, or the corner is 25 m away |
| SHOVE | a ship alongside running at our speed (closing < 6), corner 30–120 m ahead with the other on the **outside**, aggression × risk roll | leans 1.6 m into it at 5 m/s, speed capped to the other's + 2 (lean, never ram); the resolver's push and the corner do the rest | 1.2 s, the other leaves, or speeds diverge |
| YIELD | something closing > 25 u/s and faster than our class max | 3 m aside for ≤ 2 s | — |
| RECOVER | hit ≥ 6 u/s, or a contact yaw twitch > 0.3 rad/s | line only, but keeps giving room to the ship alongside | twitch settled, ≥ 0.3 s |

**Personality** per ship, deterministic from its name: aggression 0.25–0.85,
patience 0.2–0.8, risk 0.2–0.8, scaled down at low skill. The field has
characters: in every run AI_Ship_2 (aggression 0.60) and AI_Ship_4 (0.23 but
patient) are the two who defend and shove most; AI_Ship_7 (risk 0.16) never
shoves.

## What the probe showed on the way (each a rule above)

| Symptom | Cause | Rule |
|---|---|---|
| 310 episodes / 43 hits / one **60 u/s** crash in 2 min on c6 | a SHOVE on a ship that then braked for the corner (97 vs 71) | shove needs matched speed and caps the shover's speed |
| most hits taken in FOLLOW | rear-ends: the lift came at 0.8 s TTC | lift from 1.1 s, deeper as TTC falls |
| hundreds of micro-leans | a ship in FOLLOW returns to the line straight into the car passing it | FOLLOW gives room to whoever is alongside |
| pairs of **54 u/s** hits at equal speeds, headings crossed 20–30° | after a touch both ships RECOVER to the *same* trained line at once | RECOVER keeps giving room; yaw kick softened |
| c5: 158 episodes / 113 "hits", one pair glued for 45 s | two leaning ships re-closing at 1–2 u/s every 6 ticks as the separation pushes them apart; counted as hits | resolver episode hysteresis + contact skin; hits counted from 3 u/s; FOLLOW tucks in after a stalemate |
| one ship 18 s in OVERTAKE, 1 of 9 completed | passes launched into braking zones where the leader brakes first | no overtake into a corner < 0.8 s away unless clearly faster; patience scales stall and cooldown |

## Results (`ai_race_probe`, 8 ships, 120 s, 60 Hz)

| Track | AI | episodes / hits / max closing | respawns | flying lap best / mean | notes |
|---|---|---|---|---|---|
| test_circuit_6 (untrained, chaotic) | legacy avoidance + resolver | 3 / 1 / 16.9 | 0 | 52.33 / 53.45 | |
| | **strategy** | 1 / 1 / 19.8 | 0 | 52.87 / 53.78 | every AI attempts passes (2–7 each) |
| test_circuit_5_live (trained) | legacy | 0 / 0 / – | 0 | – | the field runs in a train |
| | **strategy** | 23 / 18 / 24.6 | 0 | – | 1–3 passes done per AI, defends and shoves happen |
| test_circuit_6_live (trained, 40 wall hits/2 min anyway) | legacy | 1 / 1 / 3.7 | 0 | – | |
| | **strategy** | 3 / 3 / 40.3 | 0 | – | one real crash in 2 min, in a slow corner |
| loop_lab | strategy | 0 / 0 | 0 | 33.48 / 34.05 | identical to v33 |
| fork_lab | strategy | 5 / 3 / 26.1 | 0 | 28.85 / 30.40 | jumps unaffected; one side hit at the fork |

The strategy costs about 0.3–0.5 s per lap in traffic on the chaotic track
(lifting behind a lead at 1.1 s TTC, giving room): that is the price of not
rear-ending, and `follow_ttc` is the dial. A clean lap costs nothing.

Not measured: the player in the pack. Everything above is AI vs AI; what a
DEFEND or SHOVE feels like from the cockpit is the hand test. Difficulty
handicaps (worse TTC judgement, later commits) are parameters that exist but
have not been tuned per level.

## Running

```
PROBE_TRACK=test_circuit_6 PROBE_SECONDS=120 godot --headless --fixed-fps 60 --path . -s res://tools/dev/ai_race_probe_boot.gd
FTF_AI_CONTACT=legacy ...        # old avoidance, new resolver
FTF_LOG_HITS=1 ...               # every hit with frame, ships, closing speed
```
