@tool
extends Node3D
class_name UtopiaRailScatter
## Scatters one mesh along a Path3D rail as chunked MultiMeshes (no collision).
##
## Editor workflow: tweak the exports, press "Rebuild" in the inspector. The
## result is baked into child MultiMeshInstance3D nodes and saved with the
## scene, so nothing runs at game time.
##
## Instance frame (from Curve3D.sample_baked_with_rotation, tilt applied):
##   -Z = along the rail (direction of travel)   +Y = rail up (surface normal)
##   +X = rail right
## `offset` is applied in that frame. For left/right pairs use `face_inward`:
## the mesh is authored with +X pointing TOWARD the track centre; on the
## right-hand side it is turned 180 deg about Y so +X still faces inward.
##
## To swap in a detailed model: point `mesh` at your mesh (keep the same pivot
## and axis convention) and press Rebuild -- or simply overwrite the greybox
## .tres the mesh export points to, and every scatter using it updates.

@export var rail: NodePath
@export var mesh: Mesh:
	set(v):
		mesh = v
		for c in get_children():
			if c is MultiMeshInstance3D and c.multimesh:
				c.multimesh.mesh = v
@export_group("Distribution")
@export var spacing := 20.0
@export var phase := 0.0                 ## first instance at this distance
@export var spacing_jitter := 0.0        ## +/- metres
@export_range(0.0, 1.0) var probability := 1.0
@export var seed := 1
## Only place inside these [from, to] distance ranges (empty = whole rail).
@export var include_ranges: PackedVector2Array = PackedVector2Array()
## Never place inside these [from, to] ranges (tunnels, start line...).
@export var skip_ranges: PackedVector2Array = PackedVector2Array()
@export_group("Placement")
@export var offset := Vector3.ZERO      ## in the rail frame
@export var offset_jitter := Vector3.ZERO
@export var rotation_deg := Vector3.ZERO
@export var scale_min := 1.0
@export var scale_max := 1.0
## Right-hand rail: turn 180 deg about the local up so +X faces the track.
@export var face_inward_right := false
## Ignore the rail tilt and stand the instance upright in world space.
@export var world_up := false
@export_group("Rendering")
@export var chunk_length := 400.0
@export var cast_shadows := true
@export var visibility_end := 0.0        ## 0 = always drawn

@export_tool_button("Rebuild", "Reload") var rebuild_action := rebuild

func rebuild() -> void:
	for c in get_children():
		if c is MultiMeshInstance3D:
			remove_child(c)
			c.queue_free()
	var p := get_node_or_null(rail) as Path3D
	if p == null or p.curve == null or mesh == null:
		push_warning("UtopiaRailScatter %s: rail or mesh missing" % name)
		return
	var cv := p.curve
	var L := cv.get_baked_length()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var to_local := global_transform.affine_inverse() * p.global_transform
	var chunks := {}
	var extra := Basis.from_euler(rotation_deg * (PI / 180.0))
	var d := phase
	while d < L:
		var here := d
		d += spacing + rng.randf_range(-spacing_jitter, spacing_jitter)
		if rng.randf() > probability or not _allowed(here):
			continue
		var xf := cv.sample_baked_with_rotation(here, true, true)
		# rebuild a clean frame: -Z along travel, +Y rail up, +X rail right
		var fwd := (cv.sample_baked(fposmod(here + 0.5, L), true) - cv.sample_baked(fposmod(here - 0.5, L), true)).normalized()
		var up := xf.basis.y
		if world_up:
			fwd.y = 0.0
			fwd = fwd.normalized()
			up = Vector3.UP
		up = (up - fwd * up.dot(fwd)).normalized()
		var right := fwd.cross(up).normalized()
		xf.basis = Basis(right, up, -fwd)
		var off := offset + Vector3(rng.randf_range(-1, 1) * offset_jitter.x, rng.randf_range(-1, 1) * offset_jitter.y, rng.randf_range(-1, 1) * offset_jitter.z)
		var b := xf.basis * extra
		if face_inward_right:
			b = b * Basis(Vector3.UP, PI)
		var s := rng.randf_range(scale_min, scale_max)
		var t := Transform3D(b.scaled_local(Vector3.ONE * s), xf.origin + xf.basis * off)
		var key := int(here / chunk_length)
		if not chunks.has(key):
			chunks[key] = []
		chunks[key].append(to_local * t)
	var owner_node := owner if owner else self
	if Engine.is_editor_hint() and get_tree() and get_tree().edited_scene_root:
		owner_node = get_tree().edited_scene_root
	for key in chunks.keys():
		var arr: Array = chunks[key]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		mm.instance_count = arr.size()
		for i in range(arr.size()):
			mm.set_instance_transform(i, arr[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Chunk%02d" % key
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cast_shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.visibility_range_end = visibility_end
		add_child(mmi)
		mmi.owner = owner_node

func instance_count() -> int:
	var n := 0
	for c in get_children():
		if c is MultiMeshInstance3D and c.multimesh:
			n += c.multimesh.instance_count
	return n

func _allowed(d: float) -> bool:
	for r in skip_ranges:
		if d >= r.x and d <= r.y:
			return false
	if include_ranges.is_empty():
		return true
	for r in include_ranges:
		if d >= r.x and d <= r.y:
			return true
	return false
