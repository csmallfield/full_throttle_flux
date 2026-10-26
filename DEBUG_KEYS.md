# Debug keys and test switches

Every debug hotkey goes through `scripts/debug/debug_keys.gd` (autoload
`DebugKeys`). Press **F1** in game for the same list with each setting's
current value. Debug builds only: an exported release build has none of these.

Binding a key that's already taken prints an error and keeps the original, so
two features can't share a key by accident. **F5–F8 are off limits**: they're
the editor's run / run scene / pause / stop shortcuts and still reach the
editor while the game has focus (F8 ends the game). The rendering switches use
the number row instead, with the same numbers.

## Keys

| Key | What | Saved? | Owner |
|---|---|---|---|
| F1 | This list, with current values | – | `DebugKeys` |
| F2 | Debug HUD (ship telemetry); also in the pause menu | no | `debug_hud.gd` |
| F3 | Environment readout + probe lines | no | `env_debug_overlay.gd` |
| F4 | Next weather, blended as mid-race | no | `env_debug_overlay.gd` |
| Shift+F4 | Next weather, instantly | no | 〃 |
| Ctrl+F4 | Previous weather, instantly | no | 〃 |
| 5 | FX quality Low / Medium / High | `user://fx_settings.tres` | `graphics_settings.gd` |
| 6 | Motion blur on / off | no | 〃 |
| Shift+6 | Motion blur debug view: off / velocity / neighbour max / distance | no | 〃 |
| 7 | Anti-aliasing: MSAA 2x+SMAA (v36) / **MSAA 4x+SMAA** / TAA / FSR 2 native | `user://graphics.cfg` | 〃 |
| Shift+7 | Road grid: **filtered (v37)** / v36 fixed-pixel lines | no | 〃 |
| 8 | Shadows: Low (v36) / **High** / Ultra | `user://graphics.cfg` | 〃 |
| 9 | Track surface debug view (v38): off / s,t / band ids / panel ids / filter level / zones / wear | no | 〃 |
| Shift+9 | Track surface quality tier: Low / **High** (same look in v38 phase 1) | `user://graphics.cfg` | 〃 |
| F9 | AI spectator on / off | no | `ai_spectator.gd` |
| F10 | Spectator overlay detail: off / basic / full | no | 〃 |
| F11 | Freeze the spectator readout | no | 〃 |

Bold = default. Each press shows the new value at the top of the screen and
prints it to the log.

Weather keys cycle the track's `allowed_weather`, or every stock preset in
`resources/weather/` if the track doesn't list any.

FX quality (5) changes ship detail, dust and SSR right away, but particle counts are
fixed when the race loads. Restart the race to see all of it.

### While spectating (F9 on)

These keys do nothing in normal play, so they're free for the results screen's
initials entry.

| Key | Gamepad | What |
|---|---|---|
| `[` / `]` (or `,` / `.`) | LB / RB | Previous / next ship |
| `\` | | Back to your ship (ends spectating) |
| Y (or Z, C); Shift goes back | Y / X | Cycle cinematic cameras |
| H | | Clean view: hide every HUD and overlay |

Letters match by layout and by position, so a German QWERTZ keyboard works too.

## Environment variables

Set these before launching to pin a setting for a test or benchmark run. They
override the saved files but don't change them.

| Variable | Values | Effect |
|---|---|---|
| `FTF_AA` | 0–3 | AA mode, in key 7 order |
| `FTF_SHADOWS` | 0–2 | Shadow quality, in key 8 order |
| `FTF_FX` | 0–2 | FX quality, in key 5 order |
| `FTF_BLUR` | 0 / 1 | Motion blur off / on |
| `FTF_SURFACE_TIER` | 0 / 1 | Track surface quality tier, in Shift+9 order |
| `FTF_WEATHER` | preset file name, e.g. `rain_heavy` | Starting weather (`resources/weather/<name>.tres`) |
| `FTF_CONTACT` | `legacy` | Old per-ship contact path instead of `ShipContactResolver` |
| `FTF_AI_CONTACT` | `legacy` | Old `AIShipAvoidance` for AI ships |
| `FTF_LOG_HITS` | 1 | Log each ship contact |
| `FTF_GREEBLES` | 1 | Build track greebles in headless runs too |

The dev tools have their own prefixes (`PROBE_*`, `CP_*`, `CR_*`, `AL_*`,
`MB_*`, `SMOKE_TRACK`), documented at the top of each script in
`full_throttle_flux/tools/dev/`.

## Saved settings

Found in `%APPDATA%\Godot\app_userdata\full_throttle_flux\`. Delete a file to
go back to the defaults.

| File | Holds |
|---|---|
| `graphics.cfg` | AA mode, shadow quality |
| `fx_settings.tres` | FX quality and LOD distances |

## Adding a key

```gdscript
DebugKeys.bind(KEY_F12, "My thing", _toggle_thing,
	func(): return "on" if _thing else "off",   # optional: shown on F1 and on press
	self)                                         # optional: unbind when this node leaves
DebugKeys.bind(KEY_F12, "My other thing", _other, Callable(), self, DebugKeys.SHIFT)
```

Then add it to the table above.
