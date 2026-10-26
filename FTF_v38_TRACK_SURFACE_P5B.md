# FTF v38: track surface, phase 5b (the circuit port)

The last step of v38's rollout: **Utopia, Swoopy, Hairpin Alley and The
Drop** (circuits 3, 5, 6, 7) now have the track surface and its walls. Each
has an industrial zone, wear from its own trained racing line, its name as
a start word, and an empty per-circuit variation ready for tuning.

Earlier phases are in `FTF_v38_TRACK_SURFACE.md` and `_P2.md` to `_P5.md`.
Same branch, `feature/v38-track-surface`.

**Sign-off.** I took your "let's proceed" after 5a as the go-ahead the doc
asks for before the port (gate 3).

**Budgets are guides, not gates** (your call after 5a): the cost is
measured and reported below, and nothing was cut to meet a number.

## How it works
The circuits are `CSGPolygon3D` extrusions along MainSpline: road
(`groundGeo`), `wallLeftGeo` and `wallRightGeo`. They have UVs only, with
no UV2, CUSTOM0 or tangents. All four share the same three polygons.

### No geometry changes: CSG mode
- **A `TrackSurface` node in the circuit scene** turns the port on.
  - At runtime it gives the road and walls a `material_override`: a v38
    road or wall material in **CSG mode**.
  - It never does this in the editor, so nothing is saved, and the editor
    still shows the grid.
  - `material_override` is a rendering property: **the CSG meshes and their
    collision aren't rebuilt.**
  - The shared `grid_material.tres` underneath isn't touched, so nothing
    leaks into other tracks in the same session.
  - Remove the node and the circuit is back on the grid.
- **The edge table** (`TrackSurface.csg_edge_table()`) describes each CSG
  polygon edge: its UV.y range, its ends (x, y) and its class.
  - It uses CSG's outline convention (a counter-clockwise polygon reversed,
    vertex i at UV.y = i/2n).
  - The road's driving edge is the widest one facing up above the centre.
  - Lips, faces and the rest are classed by their normals, as on builder
    tracks.
- **The shaders** (`modules/csg.gdshaderinc`) find the pixel's edge from
  UV.y and interpolate along it: t, height and class, exactly. s = UV.x ×
  `path_u_distance` (100 for the road, 50 for the walls).
- **The high tier's frame:** CSG has no tangents, so the road builds its
  along/across frame from screen derivatives (a cotangent frame). It only
  steers the subtle rib normals.
- **`EnvSurfaces`** adopts a CSG on a v38 override like a builder segment:
  `along_main` per node, the zone mask on.
- **Authoring** goes in the `TrackSurface` inspector, since there's no
  Track Builder here (see `docs/TRACK_AUTHORING.md` §7):
  - `zones`: a zone's `to_d` may stay 0 and run to the next zone;
  - `decals`: `TrackSurfaceDecal`s by distance;
  - `variation`.

### Found on the way
- **CSG +x is right of travel, the same as `TrackRoadSegment`.** A builder
  comment ("Loop Lab's CSG calls the same polygon wallLeftGeo") led me to
  assume the opposite first.
  - The band view showed the cross-section mirrored and the wall faces
    classed as tops, so I flipped it.
  - `CSG_X_SIGN` / the `csg_x_sign` uniform keep the CPU table and the
    shader in step.
  - The wall names are only names.
- **The edge table matches the real mesh.**
  - Road classes: [other, other, lip, **surface**, lip, other].
  - Half-widths: 16.6 m left, 17.2 m right (the design doc's −16.6 to +17.2).
  - Driving surface UV range: 0.250–0.333 (= 3/12–4/12, as measured in v35).
  - The env self-test's mesh check confirms the rows: 2.0 m up, 16.9 m out.
- **Re-saving a circuit scene through Godot churns it:** the header uid,
  and node ids added to every node.
  - So the `TrackSurface` nodes were added as plain text: 26 added lines per
    scene, nothing else touched.
  - The variations are new files in `resources/track_surface/variations/`.

### What each circuit got
| Circuit | Start word (25 m past the line) | Zone | Variation |
|---|---|---|---|
| test_circuit_3_live (Utopia) | UTOPIA, 3.5 m | industrial, whole lap | `variation_test_circuit_3_live.tres` (empty) |
| test_circuit_5_live (Swoopy) | SWOOPY, 3.5 m | industrial | `variation_test_circuit_5_live.tres` |
| test_circuit_6_live (Hairpin Alley) | HAIRPIN ALLEY, 1.7 m | industrial | `variation_test_circuit_6_live.tres` |
| test_circuit_7_live (The Drop) | THE DROP, 2.7 m | industrial | `variation_test_circuit_7_live.tres` |

## Gate
### Look
- Chase and top views of all four are in `track_surface_circuits\`:
  - lanes, grates, lights and hazard lips the right way round;
  - the new walls;
  - start words (behind the start gantries in the top views).
- The band and class debug views agree with the edge tables.

**Flicker on the circuits isn't measurable this way.** On Utopia at 800 m
the averaged reference flickered anywhere from 0.6× to 3× the surface
between runs. The cities have their own animation, and moving scenery
crossing the far rows swamps the measure. The circuits run the same shader
code as Builder Lab, which measures clean (the 5a numbers, unchanged after
this phase: within 1.00–1.06× of the averaged reference).

### Cost (RTX 3080; budgets as guides)
`gfx_bench`, default tracks (the four circuits), `GB_CONFIGS=v38`, 15 s
each. `grid_v37` = the circuit as before: the CSG's own grid with the
weather wrapper. GPU frame time median, ms:

| Circuit | 1080p grid | low | high | 1440p grid | low | high |
|---|---|---|---|---|---|---|
| Utopia | 3.67 | 3.62 | 3.68 | 6.06 | 6.02 | 6.07 |
| Swoopy | 3.98 | 4.01 | 4.01 | 6.08 | 6.19 | 6.13 |
| Hairpin Alley | 3.43 | 3.32 | 3.49 | 5.48 | 5.34 | 5.57 |
| The Drop | 1.01 | 1.00 | 1.01 | 1.63 | 1.59 | 1.64 |

- **The surface costs about the same as the grid on every circuit:** within
  ±0.1 ms at both resolutions, the low tier sometimes slightly below.
- These frames are dominated by the cities (1–6 ms). Builder Lab, an
  almost empty scene, shows the shader's own cost better: +0.2 ms low /
  +0.38 ms high.
- **The 1080 Ti is still unmeasured.**

## Checks
- `env_selftest` now follows the route the track uses. With a
  `TrackSurface`, it checks the road is on the v38 surface in CSG mode
  (u 100 m, `along_main`) and that the edge table's driving edge matches
  the mesh. Only the two known failures remain (CPU timing; the
  intermittent nozzle test).
- Validator self-test 26/26.
- Editor self-test: 0 errors, 0 warnings, scene untouched.
- `track_uv2_check`: both labs ok.
- Builder Lab's shots: identical to 5a.

## Open after v38
- **Tuning the circuits' identities:** profiles, zones, decals and the four
  empty variations.
- **Editor preview on the circuits:** the editor shows the grid. A preview
  would need a non-saving editor path; `material_override` is saved if set
  in the editor.
- **Hand tests:** gate 2 (at speed, against refs 2, 5, 9) on the circuits
  too.
- **The 1080 Ti run**, and the placeholder wear texture.
- **Junctions** on builder tracks still use the grid.
- **CSG roads with width changes:** the circuits have a constant section;
  CSG mode assumes one.

## Files
- New:
  - `full_throttle_flux/shaders/track/modules/csg.gdshaderinc`
  - `full_throttle_flux/resources/track_surface/variations/variation_test_circuit_{3,5,6,7}_live.tres`
- Changed:
  - `full_throttle_flux/scripts/tracks/track_surface.gd`: CSG apply, edge
    table, hand-authored zone ends
  - `full_throttle_flux/shaders/track/track_surface.gdshader`,
    `track_wall.gdshader`: CSG mode
  - `full_throttle_flux/scripts/env/env_surfaces.gd`: CSG overrides
  - `full_throttle_flux/scenes/tracks/test_circuit_{3,5,6,7}_live.tscn`: the
    TrackSurface node
  - `full_throttle_flux/tools/env/env_selftest.gd`
  - `full_throttle_flux/tools/dev/gfx_bench.gd`, `track_surface_shots.gd`:
    CSG
  - `full_throttle_flux/docs/TRACK_AUTHORING.md` §7
