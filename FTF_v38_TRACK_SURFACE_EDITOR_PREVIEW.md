# FTF v38: the circuits' surface in the editor

The four CSG circuits (Utopia, Swoopy, Hairpin Alley, The Drop) now show the
v38 track surface in the Godot editor, not the old grid. Editing a zone,
decal or variation in the `TrackSurface` inspector updates it live. Nothing
is saved into the scenes. This closes "Editor preview on the circuits" from
`FTF_v38_TRACK_SURFACE_P5B.md`.

## How it works
- **Render-only override** (your pick of the three options):
  - in the editor, `TrackSurface` builds the same road and wall materials
    as at runtime (`_apply_csg(..., preview = true)`);
  - it sets them on each CSG's render instance through the
    `RenderingServer` (`instance_geometry_set_material_override` and the
    `path_length` instance parameter on `get_instance()`).
  - The nodes' `material_override` and `instance_shader_parameters` stay
    empty, so a save has nothing to write.
  - `TrackSurface` keeps the materials alive (the server only holds RIDs);
    it puts each CSG's own override back when the node leaves the tree, and
    rebuilds the preview when it comes back.
- **Live refresh** (also your pick): in the editor, `_process` hashes
  `preview_signature()` every 0.25 s and calls `refresh_preview()` when the
  hash changes. The hash covers:
  - every stored property of the zones and decals;
  - the variation, and the profiles and bands under them;
  - the path length, and each CSG's polygon and `path_u_distance`.

  It catches edits inside nested sub-resources too, with no plugin and no
  setters on the resource scripts. Processing is off at runtime.
- **Runtime path unchanged:** `apply()` still sets `material_override` only
  outside the editor. The builder tracks' `signature()` (used by the
  validator) and `notes` are untouched.

**Catch:** if you set a CSG's own Material Override in the inspector, it
takes over until the next preview rebuild, which then covers it again.
Remove the `TrackSurface` node to see the grid.

## Checks
- **Editor self-test**, new: `tools/track_surface/editor_preview_selftest.gd`.
  - Run it with `TS_EDITOR_SELFTEST=1` and
    `Godot --editor --path . res://scenes/tracks/test_circuit_N_live.tscn`
    (add `TS_SHOT=<dir>` for viewport shots without `--headless`).
  - It checks the preview is built and that zone and decal edits rebuild it.
  - It puts the edits back, saves through the editor, and confirms the
    packed scene has no `material_override` or instance parameter.
  - All four circuits: 0 failures.
  - The real saved files have no override lines either. Their `git diff`
    shows only Godot's known re-save churn (uids, `unique_id`s, ext_resource
    order), which was reverted.
  - Under `--headless` only, the editor prints `Parameter "t" is null` once
    around the save. It doesn't happen in a windowed editor and looks like
    the headless thumbnail path, not this code.
- **Shots:** the editor viewport on Utopia's start shows the surface with
  the "UTOPIA" word. After the decal text was changed to "PREVIEW", the road
  showed "PREVIEW".
- **`env_selftest`:** ENVTEST PASS (0 failed).
- **`race_bench`**, Utopia, an A/B in this worktree with main's
  `track_surface.gd` and then this one (RTX 3080, 1080p, vsync on):

  | | fps | p95 ms | GPU ms | objects / nodes |
  |---|---|---|---|---|
  | main | 59.6 | 22.2 | 5.31 | 5328 / 2357 |
  | this | 60.0 | 20.9 | 5.28 | 5328 / 2357 |

  The same within run noise.

## Files
- `full_throttle_flux/scripts/tracks/track_surface.gd`: editor preview,
  live refresh, self-test hook
- `full_throttle_flux/tools/track_surface/editor_preview_selftest.gd`: new
- `full_throttle_flux/docs/TRACK_AUTHORING.md` §7: the editor now shows the
  surface

No scenes or surface data (zones, variations, decals) were changed.
