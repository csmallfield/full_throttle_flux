@tool
extends Node3D
class_name UtopiaZoneDresser
## Zoned track dressing. Each UtopiaGreebleZone covers a stretch of the lap and
## dresses it with a UtopiaGreebleStyle; each style holds rules for five layers
## (ground / wall_face / wall_top / outside / overhead).
##
## Every rule in a zone sits on the SAME BAY GRID, measured along the Road rail
## from the zone start and projected onto the wall rails. So a rib on the wall
## face, a lamp pole on the wall top and a seam in the road line up across the
## track, instead of each layer scattering on its own spacing.
##
## Edit zones/styles/rules in the inspector, press Rebuild. Results are baked
## into MultiMeshInstance3D children (one per rule, chunked) and saved with the
## scene; nothing runs in game. Nothing collides.
##
## Instance frame for every mesh: -Z = direction of travel, +Y = road normal,
## +X = toward the track centre (right-hand pieces are turned 180 deg about Y).

@export var rails_root: NodePath
@export var zones: Array[UtopiaGreebleZone] = []
## Road-rail distance ranges [from, to] treated as tunnels.
@export var tunnels: PackedVector2Array = PackedVector2Array()
@export var chunk_length := 400.0
@export_tool_button("Rebuild", "Reload") var rebuild_action := rebuild

const RAILS := ["Road", "WallFaceL", "WallFaceR", "WallTopL", "WallTopR", "WallOuterL", "WallOuterR"]
const LAYER_RAIL := {"wall_face": "WallFace", "wall_top": "WallTop", "outside": "WallOuter"}
const MAP_STEP := 2.0

var _curves := {}
var _maps := {}       # rail -> PackedFloat32Array of rail distance per road MAP_STEP
var _road_len := 0.0
var _stats := {}

func rebuild() -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()
	_stats = {}
	var root := get_node_or_null(rails_root)
	if root == null:
		push_warning("UtopiaZoneDresser: rails_root not set")
		return
	for r in RAILS:
		var p := root.get_node_or_null(r) as Path3D
		if p == null:
			push_warning("UtopiaZoneDresser: missing rail " + r)
			return
		_curves[r] = p.curve
	_road_len = _curves["Road"].get_baked_length()
	_build_maps()
	var to_local := global_transform.affine_inverse() * (root as Node3D).global_transform
	var owner_node := owner if owner else self
	if Engine.is_editor_hint() and is_inside_tree() and get_tree().edited_scene_root:
		owner_node = get_tree().edited_scene_root
	for zi in range(zones.size()):
		var z := zones[zi]
		if z == null or z.style == null:
			continue
		var zn := Node3D.new()
		zn.name = "Z%02d_%s" % [zi, z.label.to_pascal_case()]
		add_child(zn)
		zn.owner = owner_node
		var span := fposmod(z.to_d - z.from_d, _road_len)
		var bay := maxf(z.style.bay_length, 1.0)
		for ri in range(z.style.rules.size()):
			var rule := z.style.rules[ri]
			if rule == null or not rule.enabled or rule.mesh == null:
				continue
			var rng := RandomNumberGenerator.new()
			rng.seed = hash([z.seed, zi, ri])
			var chunks := {}
			var chunks_r := {}
			var split_r := rule.mesh_right != null
			var slot_len := bay / float(rule.slots_per_bay)
			var n_slots := int(span / slot_len)
			for s in range(n_slots):
				var ch := rule.pattern[s % rule.pattern.length()] if rule.pattern.length() > 0 else "x"
				if ch != "x":
					continue
				var local_d := (float(s) + rule.slot_phase) * slot_len
				var road_d := fposmod(z.from_d + local_d, _road_len)
				if rng.randf() > rule.probability * z.density:
					continue
				if rule.avoid_tunnels and _in_tunnel(road_d):
					continue
				for side in _sides(rule, z):
					var xfv: Variant = _place(rule, side, road_d, slot_len, rng)
					if xfv == null:
						continue    # past the rule's upright limit
					var xf: Transform3D = xfv
					var key := int(road_d / chunk_length)
					var target: Dictionary = chunks_r if (split_r and side == "R") else chunks
					if not target.has(key):
						target[key] = []
					target[key].append(to_local * xf)
			_emit(zn, "%02d_%s" % [ri, _rule_name(rule)], rule.mesh, chunks, rule.cast_shadows, owner_node)
			if split_r:
				_emit(zn, "%02d_%s_R" % [ri, _rule_name(rule)], rule.mesh_right, chunks_r, rule.cast_shadows, owner_node)
		# threshold portal at the zone entrance
		if z.style.threshold_mesh and not _in_tunnel(z.from_d + 4.0):
			var tx := _frame("Road", fposmod(z.from_d + 4.0, _road_len))
			_emit(zn, "Threshold", z.style.threshold_mesh, {0: [to_local * tx]}, true, owner_node)

func instance_count() -> int:
	var n := 0
	for z in get_children():
		for c in z.get_children():
			if c is MultiMeshInstance3D and c.multimesh:
				n += c.multimesh.instance_count
	return n

# ---------------------------------------------------------------------------

func _rule_name(r: UtopiaGreebleRule) -> String:
	var mn := r.mesh.resource_path.get_file().get_basename() if r.mesh.resource_path != "" else "mesh"
	return "%s_%s" % [r.layer, mn.trim_prefix("gb_")]

func _sides(rule: UtopiaGreebleRule, z: UtopiaGreebleZone) -> Array:
	var s := rule.side
	if z.mirror:
		s = {"left": "right", "right": "left"}.get(s, s)
	if rule.layer == "overhead":
		return ["C"]
	match s:
		"left":
			return ["L"]
		"right":
			return ["R"]
		"center":
			return ["C"] if rule.layer == "ground" else []
	return ["L", "R"]

## Instance transform for a rule at a road distance.
## Instance transform for a rule at a road distance, or null where the road
## tilts past the rule's upright limit (GreebleUpright).
func _place(rule: UtopiaGreebleRule, side: String, road_d: float, slot_len: float, rng: RandomNumberGenerator) -> Variant:
	var rail := "Road"
	if LAYER_RAIL.has(rule.layer):
		rail = LAYER_RAIL[rule.layer] + side
	var f := _frame(rail, _rail_d(rail, road_d))
	# inward frame: +X toward the track centre
	if side == "R":
		f.basis = f.basis * Basis(Vector3.UP, PI)
	var o := rule.offset + Vector3(rng.randf_range(-1, 1) * rule.jitter.x, rng.randf_range(-1, 1) * rule.jitter.y, rng.randf_range(-1, 1) * rule.jitter.z)
	if side != "C" and rule.layer == "ground":
		o.x -= rule.lateral
	var s := rng.randf_range(rule.scale_min, rule.scale_max)
	var ori := GreebleUpright.orient(rule, f.basis)
	if not ori[0]:
		return null
	var b := (ori[1] as Basis) * Basis.from_euler(rule.rotation_deg * (PI / 180.0))
	var sc := Vector3.ONE * s
	if rule.mesh_length > 0.0:
		sc.z = slot_len / rule.mesh_length
	var bs := b.scaled_local(sc)
	var origin := f.origin + f.basis * o + GreebleUpright.surface_normal(rule.layer, f.basis) * rule.surface_offset
	if rule.auto_embed and ori[1] != f.basis and rule.layer in ["ground", "wall_top"]:
		origin -= bs.y.normalized() * GreebleUpright.embed_depth(bs, rule.mesh.get_aabb(), f.basis.y.normalized())
	return Transform3D(bs, origin)

## Clean rail frame at rail distance d: -Z travel, +Y road normal, +X right.
func _frame(rail: String, d: float) -> Transform3D:
	var cv: Curve3D = _curves[rail]
	var L := cv.get_baked_length()
	d = fposmod(d, L)
	var xf := cv.sample_baked_with_rotation(d, true, true)
	var fwd := (cv.sample_baked(fposmod(d + 0.5, L), true) - cv.sample_baked(fposmod(d - 0.5, L), true)).normalized()
	var up := xf.basis.y
	up = (up - fwd * up.dot(fwd)).normalized()
	var right := fwd.cross(up).normalized()
	return Transform3D(Basis(right, up, -fwd), xf.origin)

## Road distance -> distance along another rail (perpendicular foot), from the
## lookup table built per rebuild.
func _rail_d(rail: String, road_d: float) -> float:
	if rail == "Road":
		return road_d
	var m: PackedFloat32Array = _maps[rail]
	var fi := fposmod(road_d, _road_len) / MAP_STEP
	var i := int(fi)
	var a := m[i % m.size()]
	var b := m[(i + 1) % m.size()]
	var L: float = _curves[rail].get_baked_length()
	if b < a - L * 0.5:
		b += L   # wrapped past the rail's start
	return fposmod(lerpf(a, b, fi - i), L)

func _build_maps() -> void:
	var road: Curve3D = _curves["Road"]
	var n := int(ceil(_road_len / MAP_STEP))
	for rail in RAILS:
		if rail == "Road":
			continue
		var cv: Curve3D = _curves[rail]
		var L := cv.get_baked_length()
		var k := L / _road_len
		var m := PackedFloat32Array()
		m.resize(n)
		var prev := 0.0
		for i in range(n):
			var p := road.sample_baked(i * MAP_STEP, true)
			var est := i * MAP_STEP * k if i == 0 else prev + MAP_STEP * k
			var win := 40.0 if i == 0 else 8.0
			var best := est
			var bd := INF
			var o := est - win
			while o <= est + win:
				var dd := cv.sample_baked(fposmod(o, L)).distance_squared_to(p)
				if dd < bd:
					bd = dd
					best = o
				o += 0.25
			m[i] = fposmod(best, L)
			prev = best
		_maps[rail] = m

func _in_tunnel(d: float) -> bool:
	for t in tunnels:
		if d >= t.x and d <= t.y:
			return true
	return false

func _emit(parent: Node, base: String, mesh: Mesh, chunks: Dictionary, shadows: bool, owner_node: Node) -> void:
	for key in chunks.keys():
		var arr: Array = chunks[key]
		if arr.is_empty():
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		mm.instance_count = arr.size()
		for i in range(arr.size()):
			mm.set_instance_transform(i, arr[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "%s_c%02d" % [base, key]
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(mmi)
		mmi.owner = owner_node
