# Full Throttle Flux — v28: random ship models (TEMPORARY)

Extract at the **repository root**. Two files replaced, two scripts added, one scene and one resource added. Requires v27.

Every ship on the grid — **player included** — now draws its model from a pool. Handling is untouched: same profile, same collider, same `handling_hash()`, so trained lines and recordings stay valid.

---

## Files

| File | Status |
|---|---|
| `scripts/ships/ship_visual_pool.gd` | new — `ShipVisualPool` resource |
| `scripts/ships/ship_visuals.gd` | new — `ShipVisuals.swap_mesh()` |
| `scripts/modes/mode_base.gd` | replaced — pool loading, shuffle bag, call in `_spawn_ship()` |
| `scripts/modes/race_mode.gd` | replaced — calls in player + AI spawn; quiet hull tint |
| `scenes/ships/variants/variant_red_yellow.tscn` | new — current model as a variant |
| `resources/ships/visual_pools/default_racer_visuals.tres` | new — the pool for `default_racer` |

## How it works

1. A spawner instantiates `default_racer.tscn` as before.
2. **Before `add_child()`**, `_apply_visual_variant()` looks for `resources/ships/visual_pools/<ship_id>_visuals.tres`. Missing or disabled → nothing happens.
3. It takes the next index from a shuffle bag, so a grid of 8 with 4 models shows each twice. A refill never hands out the model that was just used.
4. `ShipVisuals.swap_mesh()` deletes the old `ShipMesh` and puts a fresh identity `Node3D` called `ShipMesh` in the same child slot, with the variant underneath.
5. `ShipController._ready()` then finds the new `ShipMesh` as usual. No controller changes.

Covers Race (player + AI), Time Trial and Endless. The tools (`train_ai_lines`, `analyze_laps`, `style_search`) don't spawn through the modes, so they are unaffected.

## Why the pool is not on ShipProfile

`handling_hash()` includes every bool/int/float on the profile unless it is listed in `NON_HANDLING_PROPERTIES`. An `enabled` flag there would have changed default_racer's hash and orphaned all four trained lines and your lap history.

## Something the old scene was hiding

In `default_racer.tscn`, `ShipMesh` has position **(0, 0.709, 0.265)**. That offset **never rendered**: `_update_visuals()` overwrites `ship_mesh.position` every frame with the hover bob. Only the 1.808 scale survived.

`variant_red_yellow.tscn` reproduces what you actually see in game today (scale 1.808, no offset), so nothing visibly changes. If the 0.709 lift was what you meant, add it to the `Model` child in that wrapper — it will now render.

The rule for all variants: **ShipMesh is a pivot the controller owns. Everything about a model's placement goes on a child below it.**

---

## Adding a model — in Godot

### 1. Import
- Put the `.glb` in `res://assets/ships/variants/` (create the folder).
- Select it → **Import** dock. If it faces the wrong way or is at the wrong scale, you can fix it here (**Root Scale**, or Advanced → root node transform), but the wrapper below is easier to iterate on.

### 2. Make the wrapper scene
- **Scene → New Scene → Other Node → `Node3D`**. Rename the root, e.g. `VariantBlue`. Leave its transform at identity.
- Drag the `.glb` from the FileSystem dock onto the root. Rename that child `Model`.
- Save as `res://scenes/ships/variants/variant_blue.tscn`.

### 3. Line it up against the collider
The collider is a capsule about **6.3 m long and 1.26 m wide**, lying along Z. Nose is **−Z** (ShipController uses `-basis.z` as forward).

- Open `scenes/ships/default_racer.tscn`.
- Drag `variant_blue.tscn` in as a child of the root, next to `ShipMesh`. Hide `ShipMesh` (eye icon).
- Turn on **Perspective menu → Display Collision** or just select `CollisionShape3D` to see the capsule.
- Now **go back to `variant_blue.tscn`** and adjust the `Model` child's scale, rotation and position until it fills the capsule in the ship scene. (Adjust inside the wrapper, not on the instance in the ship scene — that instance is just a preview.)
- Tips: match the length first, then drop it so the underside sits roughly where the red/yellow model's does. Compare with `ShipMesh` by toggling visibility.
- When done, **delete the preview instance** from `default_racer.tscn`, unhide `ShipMesh`, and save. Don't leave it there — it's an extra mesh riding along on every ship.

### 4. Add it to the pool
- Open `resources/ships/visual_pools/default_racer_visuals.tres` in the Inspector.
- **Variants → Add Element** → drag `variant_blue.tscn` into the slot.
- Save.

### 5. Test
- Run a race. The Output panel prints one line per ship: `ModeBase: AI_Ship_3 -> variant_blue.tscn`.
- Check a Time Trial too (that path goes through `ModeBase._spawn_ship`).
- Pack racing: bump into other ships and look for visible gaps or clipping. That means the model doesn't match the capsule — go back to step 3.

## Pool settings

| Field | What it does |
|---|---|
| `enabled` | Off = every ship uses the mesh baked into its scene, exactly as before v28. |
| `variants` | Wrapper scenes. List one twice to double its share of the grid. |
| `fixed_seed` | 0 = new shuffle each race. Anything else = same model order every race, useful for comparing captures. |

## Hull tint

AI hull tinting only ever worked on meshes named `hull`. The red/yellow model has none, so it has been failing silently (well, loudly — a warning per AI ship) all along. The warning is gone; tinting still applies to any variant that contains a `MeshInstance3D` named `hull`, and textured models keep their textures. If you want a model tintable, name its body mesh `hull` in Blender/Maya before export.

## Retiring it

- **Quick:** untick `enabled` on the pool.
- **Full:** delete `resources/ships/visual_pools/`, `scenes/ships/variants/`, the two `scripts/ships/ship_visual*.gd` files, the `TEMPORARY: RANDOM VISUAL VARIANTS` section at the bottom of `mode_base.gd`, and the three `_apply_visual_variant(...)` calls. Each is marked `TEMPORARY`.

When you go back to one model per profile, `ShipProfile.ship_scene` is the permanent home. It already exists, it's already excluded from the handling hash, and nothing reads it yet.

## Verified

Headless Godot 4.5: pool loads and reports usable; swap keeps `ShipMesh` in its original child slot; `ShipController.ship_mesh` points at the new pivot after `_ready()`; `_apply_visual_variant` tags the ship with `visual_variant` meta.

**Not verified:** how it looks, or a full race with several variants — there's only one model in the pool until you add yours.
