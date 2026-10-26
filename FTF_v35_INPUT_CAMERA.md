# FTF v35 — menu pad input, chase camera look-ahead, boost lag

## 1. Joypad navigation in menus / pause menu
`ui_left/right/up/down` had their joypad d-pad and left-stick events bound to
**device 0 only**, while every racing action (and `ui_accept`/`ui_cancel`)
uses device -1 (all devices). Racing worked, menu navigation didn't, as soon as
the pad stopped enumerating as device 0 (a second/virtual controller, a
reconnect, Steam Input, an engine update). No menu code changed. Fix: those
events now use device -1 (project.godot). Keyboard binds are unchanged in
behaviour.

## 2/3. Chase camera (scripts/ag_camera_2097.gd)
Root cause of both "looks down at the ground in tight turns" and "whips down
on boost": the aim point had no velocity feedforward (the v2 rewrite added it
to the position only). Its lag is speed / `aim_follow_rate` = 10 m at 120 u/s,
against `look_distance` 9 m, so at speed the camera aimed at the ship itself;
on a +150 boost the lag jumped to ~22 m and the view pitched down ~24°.

- `aim_feedforward` (1.0; 0 = old behaviour)
- Track Look-Ahead group: aim bends toward the track `track_look_time` (0.35 s,
  15–55 m) ahead at the ship's current lateral/vertical offset (cancels the
  older circuits' road-vs-spline offset). Follows fork branches and carries on
  along the main line past a rejoin. Fades out > 40 m off the centre line.
  `track_look_weight` 0.55. ModeBase calls `set_track(track_instance)`.
- Boost Lag group: chase distance += `boost_lag_distance` (7 m) per
  `boost_lag_ref_speed` (120 u/s) above max_speed; attack 12/s, release 1.5/s.
  Measured on a 150 pad: ~4.4 m pull-out at ~0.45 s, back in ~2 s.

Framing note: with the aim fixed, the steady-state view at top speed is ~6°
higher than before (the ship sits lower in frame, nearer the lower third).
Lower `look_distance` (~3–4) if you want the old top-speed framing back
without the lag.

### Measured (tools/dev/camera_probe.gd, AI driving the trained line, 75 s)
| track | view ray hits road < 25 m (before → after) | worst pitch below road ahead |
|---|---|---|
| Swoopy | 55.4% → 3.6% | -48.9° → -25.5° |
| Utopia | 35.0% → 0.9% | -14.6° → -5.9° |
| Hairpin Alley | 27.3% → 1.9% | -25.1° → -9.3° |
| The Drop | 32.0% → 1.8% | -58.8° → -42.2° |
| Builder Lab | 15.3% → 3.1% | boost: -31.0° → -2.0° |

`CP_CAMLEGACY=1` runs the pre-v35 camera; `CP_SET="track_look_weight=0.8"`
overrides exports for A/B.

## 4. Speed wobble on Builder Lab — not reproduced yet
tools/dev/wobble_probe.gd flies default_racer at constant throttle (centre
line, ±12/±17 m offsets, the trained racing line, the shortcut route) and the
full AI field was run with ai_race_probe. No sustained speed oscillation found;
only a small hover bounce on the pad row and hover compression on the loop
exit. Needs the spot (or a recorded lap) to pin down.
