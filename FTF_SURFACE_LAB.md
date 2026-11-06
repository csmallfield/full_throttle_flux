# FTF: Surface Lab, phase 1

A dev scene for tuning the road surface and the greebles together, live on a
real track, and saving the result to the files the game loads. There's no bake
step: the surface and greebles are already built from those files when a track
loads.

Open `tools/surface_lab/surface_lab.tscn` and run it (F6), or:

```
godot --path full_throttle_flux res://tools/surface_lab/surface_lab.tscn
```

`LAB_TRACK=<scene name>` picks another builder track (default `builder_lab`).

## Keys
| Key | What |
|---|---|
| Hold C | Show the saved look of both layers |
| H | Hide the UI |
| Ctrl+Z / Ctrl+Y | Undo / redo |
| Ctrl+S | Save (asks first, listing the files) |
| Space | Pause the glide camera |
| Right mouse + WASD, Q/E | Fly camera; Shift for fast, the wheel for speed |

The debug keys in `DEBUG_KEYS.md` still work (shadows, AA, tier, and so on),
except while a text field has focus.

## What's on screen
- **Top bar:** camera (Fly, Glide, Chase lap with a real AI ship), weather,
  surface debug view, Road and Greebles switches, one switch per greeble layer,
  compare, snapshots A and B, GPU time, what's unsaved.
- **Section (bottom left):** the cross-section at the camera, both layers to one
  across-the-road scale. Height has its own scale. Click a band or a pin to
  select it, drag the inner edge of a fixed band to resize it, drag a ground pin
  to change its `lateral`.
- **Rhythm (bottom right):** 120 m around the camera: road seams of the selected
  band, wall panels, and each rule of the zone's style. Ticks show the rule's
  pattern; `probability` thins them in the game, not here.
- **Timeline:** the lap with road and greeble zones on one axis. Click to go there.
- **Tabs:** Bands, Road, Walls, Greebles, Materials, Cost. The rows come from the
  shaders' uniforms and the rule's exported properties, so new ones appear by
  themselves.
- **Checks:** profile problems, orange too close to the boost pads, greebles
  reaching into the track, pieces dropped by upright limits, ground pieces on
  road decals. Double-click one with a place to go there.

## How far an edit reaches
Each row says so.

| Edit | Saved to | Reaches |
|---|---|---|
| Road, Walls | `shaders/track/track_surface_material.tres`, `track_wall_material.tres` | Every track |
| Road, ticked "track" | `resources/track_surface/variations/variation_<id>.tres` | That track |
| Bands | `resources/track_surface/profiles/profile_<name>.tres` | Every zone using the profile |
| Greebles | `resources/greeble_presets/style_<name>.tres` | Every zone using the style on builder tracks; not the circuits' baked dressings |
| Materials | `scenes/tracks/utopia/materials/greybox_<name>.tres` | Every greeble mesh using it, circuits' dressings included |

Saving `profile_industrial` also updates slot 0 of the base road material, as
`sync_surface_presets` does.

## Surface mask
One or two tiling textures combined into one value that moves roughness, metallic
and specular, so two images give many looks. Off unless a track's variation names
a recipe, so no track changes until you assign one.

- **Recipes** (`TrackSurfaceMask`, `resources/track_surface/masks/mask_<name>.tres`):
  mode (A only, A x B, B masks A), each layer's texture, channel, tile (across,
  along) and offset, then contrast, bias, and the roughness, metallic and specular
  amounts. The Mask tab edits them; **New** makes one.
- **Textures** (`resources/track_surface/mask_textures`): any tiling greyscale PNG
  there appears in the pickers, as does `wear_detail` with its four channels. The
  five there are placeholders from `tools/track_surface/make_mask_noises.gd`. Import
  with mipmaps on and no VRAM compression: copy an existing `.import`.
- **Per band:** `mask_amount` in the Bands tab. Channels and painted lines are left out.
- **Using one in a race:** choose a variation in the Road tab, pick the recipe in the
  Mask tab, save, and give the track that variation. With no variation it's a preview.
- **Debug view:** Mask (key 9), where mid grey means no change.

How it behaves:
- It's computed once per pixel, outside the zones, so a blend doesn't sample it twice.
- The result is centred on the texture's measured average, so mipmaps can't shift the
  far road and the low tier, which skips the textures, keeps the same overall look.
  `bias` is the one deliberate overall shift, and applies on both tiers.
- Contrast relaxes to 1 as features drop below a pixel.
- Tiling along the path is snapped per path, so there's no jump at the start line.

Measured on the 1080 Ti at 1080p, on Builder Lab at 850 m, with the UI hidden:

| Mode | GPU vs off | Near road brightness | Far road brightness |
|---|---|---|---|
| A only | +0.07 ms | +0.6% | +0.3% |
| A x B | +0.09 ms | +3.4% | +0.3% |
| B masks A | +0.10 ms | +0.5% | +0.1% |

Earlier runs gave GPU differences from about -0.02 to +0.11 ms, so treat the cost as
roughly 0.1 ms or less on this view, where road fills much of the screen. The near
road's shift is real: highlights don't respond to roughness in a straight line, and
A x B is the most contrasty case. Worth knowing when comparing with off.

Limits:
- **Road only:** the walls don't use it.
- **One recipe per track:** not per zone. Per-zone textures would need a texture array.
- **Specular** only affects non-metals, so roughness does most of the visible work.
- **No per-panel offset:** panels depend on the band, and the mask is computed before
  bands are known so that blends stay cheap.

## How it works
- `lab_doc.gd` holds everything editable as one flat "key -> value" dictionary.
  Undo, compare, snapshots and "what's unsaved" are the same operation: capture
  it, restore an older one, and only the keys that differ touch the track.
- `apply_param()` draws a parameter as the variation's override if it has one,
  else the style. The walls use the lab's own copy of the wall material, so a
  previewed variation can't reach the base.
- Materials are saved by changing only the edited lines. The saver would write
  out every shader default, which then stops following the shader.
- Other files go through `ResourceSaver`, then their uids are put back: outside
  the editor the saver drops them.

Game code it needed, none of which changes how a track draws:
- `TrackSurface`: `live_materials()`, `refresh_bands()`.
- `TrackGreebles`: `rebuild_rule()`, `set_display()`, `group_info()`, and filters
  on `placements()`.
- `DebugKeys`: `suspended`, so typing a digit isn't a hotkey.

## Checks
`LAB_SELFTEST=1` runs the self test (`surface_lab_selftest.gd`), which drives the
lab on the real GPU and writes only to `user://surface_lab`.

GTX 1080 Ti, 1080p window, vsync off, Builder Lab, UI showing:

| Measured | p50 | p95 | max |
|---|---|---|---|
| Idle, gliding | 4.5 ms | 4.9 ms | 5.3 ms |
| Dragging a road colour | 4.6 ms | 5.1 ms | 14.0 ms |
| Dragging a band width | 4.8 ms | 5.2 ms | 13.7 ms |
| Dragging the biggest rule | 4.8 ms | 22.0 ms | 27.4 ms |

The biggest rule on Builder Lab is `service`'s `pipe_run`, 294 instances: about
20 ms to re-scatter, at most ten times a second while dragging. A full re-scatter
(9,238 instances) takes about 250 ms, so it waits for 0.25 s with no new edit. Running all the checks takes about 400 ms, once at load; after that
only for the styles that changed.

`greeble_stats_boot.gd` gives the same instance checksum (1738486986) on this
branch and with main's scripts, so placement hasn't moved.

Not covered by the self test, so it needs a person:
- Dragging with a real mouse (rows are driven through their signals, and clicks
  through synthetic events). Fly's WASD isn't exercised at all.
- Whether the panels and drags feel right.
- An RTX 3080 run.

## Limits
- **Builder tracks only.** Zones and decals show on the timeline but can't be
  edited (phase 2), and nothing saves to a track's scene (phase 3).
- **Walls preview variations, builder walls don't get them in a race.**
  `TrackSurface` applies variations to circuit walls but only to the road on
  builder tracks. All four existing variations belong to circuits, so the preview
  matches where they're used.
- **Variations are previewed, not assigned.** The lab doesn't set a track's
  `surface_variation`; do that on the TrackBuilder or the circuit's `TrackSurface`.
- **No new profiles or styles.** Phase 1 edits the existing ones. Recipes and
  variations can be made new.
- **An open editor** may ask to reload a file the lab saved.
- **Saving needs an editor build of Godot.** An exported build can't write `res://`.
- **The decal check is approximate:** it uses each piece's unrotated bounds, so a
  flat `seam` across the road counts as an overlap.
