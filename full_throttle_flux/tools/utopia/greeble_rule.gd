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
@export_group("Rendering")
@export var cast_shadows := true
## Leave out inside tunnels (tall or overhead pieces).
@export var avoid_tunnels := false
