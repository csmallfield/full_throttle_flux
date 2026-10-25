@tool
extends Resource
class_name UtopiaGreebleRule
## One scatter rule inside a UtopiaGreebleStyle. Rules are placed on the
## zone's shared BAY GRID, so rules on different layers line up (a lamp pole
## on the wall top sits over the wall rib below it and the seam in the road).

## Which surveyed rail the rule lives on.
##   ground    -> Road (lateral offset across the road)
##   wall_face -> WallFaceL/R  (3 m above the road, +X faces the track)
##   wall_top  -> WallTopL/R
##   outside   -> WallOuterL/R (+X faces the track, so -X is outward)
##   overhead  -> Road, centred (spanning pieces: gantries, trusses)
@export_enum("ground", "wall_face", "wall_top", "outside", "overhead") var layer := "ground"
@export var enabled := true
@export var mesh: Mesh
## Optional right-hand variant. Right-hand instances are turned 180 deg about
## Y (so +X faces the track), which also reverses -Z. Directional pieces
## (chevrons, arrows, signs) need a variant authored for that: same +X-inward
## convention, but pointing +Z for "down-track".
@export var mesh_right: Mesh
@export_group("Rhythm")
## Slots per bay. Each slot is bay_length / slots_per_bay long.
@export_range(1, 32) var slots_per_bay := 1
## Pattern over SLOTS: 'x' = place, '-' = skip. "x---" with 4 slots = once per bay.
## Patterns repeat from the start of each zone, so they stay aligned with other rules.
@export var pattern := "x"
## Where in the slot the piece sits, 0..1 (0.5 = slot centre).
@export_range(0.0, 1.0) var slot_phase := 0.0
@export_range(0.0, 1.0) var probability := 1.0
@export_group("Placement")
@export_enum("both", "left", "right", "center") var side := "both"
## Ground: distance from the road centre (mirrored for the right side).
@export var lateral := 0.0
## Extra offset in the rail frame (x = toward the track for side layers).
@export var offset := Vector3.ZERO
@export var jitter := Vector3.ZERO
@export var rotation_deg := Vector3.ZERO
@export var scale_min := 1.0
@export var scale_max := 1.0
## > 0: the mesh is authored this long along Z and gets stretched to fill
## its slot exactly (pipes, railings, continuous trims). 0 = never stretch.
@export var mesh_length := 0.0
@export_group("Upright and surface")
## How far the piece turns from the road's up toward world up, 0..1
## (GreebleUpright). 0 = leans with the bank and slope like the road (walls,
## panels, anything fixed to a surface); 1 = stands vertical (light poles,
## masts, antennas: nobody builds a leaning pole). Turns about the piece's
## attachment point. Overhead pieces ignore it: their legs stand on both walls.
@export_range(0.0, 1.0, 0.05) var upright := 0.0
## What upright straightens: bank and slope, the bank only (still leans
## along hills), or the slope only (still leans with the bank).
@export_enum("bank_and_slope", "bank", "slope") var upright_axes := "bank_and_slope"
## Where the road tilts further than this from what upright aims for, the
## piece is left out (an upright pole makes no sense on a loop's wall or
## upside down). Only applies when upright > 0.
@export_range(0.0, 90.0, 1.0, "suffix:°") var upright_limit_deg := 45.0
## Metres along the surface's normal: + = away from the surface, - = into it
## (to hide edges). The surface is the road for ground pieces, the wall top,
## the inner wall face (+ = toward the track) or the outer face (+ = outward).
@export var surface_offset := 0.0
## When upright tilts a piece standing on a surface (ground, wall top), sink
## it just enough that no corner of its base floats above that surface.
@export var auto_embed := true
@export_group("Rendering")
@export var cast_shadows := true
## Leave out inside tunnels (tall or overhead pieces).
@export var avoid_tunnels := false
