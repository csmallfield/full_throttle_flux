@tool
extends Node3D
class_name TrackGreebles
## Track greebles for a Track Builder track (v36).
##
## Written by the Track Builder (Build, or live as you move GreebleZoneKeys):
## a list of resolved zones, each a stretch of one spline dressed with a
## UtopiaGreebleStyle (the same styles, rules and greybox meshes the Utopia,
## Swoopy and Hairpin dressings use). Like TrackRoadSegment, the instances are
## scattered when the scene loads, into internal MultiMesh children that are
## never saved: the track file holds only the zones, and the greebles always
## match the road.
##
## The rails come straight from the built road, no survey: the spline frame
## (TrackRoadSegment.frame_at, banked, through loops and rolls) plus the width
## profile of the spline's Road segment. Each layer sits where the Utopia
## survey put its rail:
##   ground     road surface; `lateral` scales with the flat road's half width
##   wall_face  inner face of the wall, 3 m up (moves with the road edge)
##   wall_top   middle of the wall's flat top
##   outside    outer face of the wall, 3 m up
##   overhead   centred between the wall tops
## Wide pieces (wider than SPAN_FIT: seams, gantries, trusses, portals) are
## stretched across so they keep spanning the road where WidthKeys change it.
##
## A piece only goes where its surface exists: ground on the road, wall layers
## on their wall, overhead where both walls stand. So jump gaps, junction
## openings and the inner side of a fork are left bare by themselves. Overhead
## pieces, and any rule with avoid_tunnels, are also left out over the
## `no_overhead` spans (loops, rolls, jumps, the start line); ground pieces
## stay off the boost pads and the start line (`ground_exclusions`).
##
## Instance frame (as every Utopia greeble): -Z = direction of travel,
## +Y = road normal, +X = toward the track centre (right-hand pieces are
## turned 180° about Y). Nothing collides.
##
## Headless runs (probes, the validator) skip the scatter unless FTF_GREEBLES=1;
## placements() works either way.

const LAYER_BITS := {"ground": 1, "wall_face": 2, "wall_top": 4, "outside": 8, "overhead": 16}
## Half width of the standard road (centre line to the lip's outer edge) and
## the lip; the flat road ends LIP inside the edge.
const ROAD_EDGE := 21.5
const LIP := 2.0
## Centred pieces wider than this are stretched to the road's width.
const SPAN_FIT := 20.0
const CHUNK := 400.0
## Validation: the corridor a ship drives through (flat road, this high) and
## the tallest a ground piece may be.
const CLEARANCE := 10.0
const GROUND_MAX := 0.3

## Splines the zones run along, relative to this node. 0 = MainSpline.
@export var paths: Array[NodePath] = []
@export var zones: Array[TrackGreebleZone] = []
## (path index, from, to): no overhead or avoid_tunnels pieces here.
@export var no_overhead: PackedVector3Array = PackedVector3Array()
## Flattened (path index, distance, lateral, half width, half length)
## rectangles that ground pieces keep off.
@export var ground_exclusions: PackedFloat32Array = PackedFloat32Array()
## Rail positions in the road cross-section (x out from the centre line on
## the standard road, y up), from the builder's wall polygon.
@export var rail_face := Vector2(21.1, 3.0)
@export var rail_top := Vector2(25.72, 8.44)
@export var rail_outer := Vector2(28.55, 3.0)

@export_group("Display")
## Scatter in the editor too (off: only in game).
@export var editor_preview := true:
	set(v):
		editor_preview = v
		if Engine.is_editor_hint() and is_inside_tree():
			if v:
				rebuild()
			else:
				clear()
## Master switch for greeble shadows (each rule has its own as well).
@export var shadows := true:
	set(v):
		shadows = v
		if Engine.is_editor_hint() and is_inside_tree():
			rebuild()
@export_tool_button("Rebuild", "Reload") var _btn_rebuild := rebuild

## Set by rebuild().
var instance_total := 0
var last_ms := 0.0

var _made: Array[Node] = []
var _style_hash := 0
var _poll := 0.0
var _infos: Array = []


func _ready() -> void:
	if Engine.is_editor_hint():
		set_process(true)
		if editor_preview:
			rebuild()
		return
	set_process(false)
	if DisplayServer.get_name() == "headless" and OS.get_environment("FTF_GREEBLES") != "1":
		return
	rebuild()


## Editor: rebuild when a style or rule changes (presets are edited in the
## inspector, and custom resources don't announce their own changes).
func _process(delta: float) -> void:
	if not Engine.is_editor_hint() or not editor_preview:
		return
	_poll += delta
	if _poll < 0.5:
		return
	_poll = 0.0
	if _styles_hash() != _style_hash:
		rebuild()


func clear() -> void:
	for n in _made:
		if is_instance_valid(n):
			remove_child(n)
			n.queue_free()
	_made.clear()
	instance_total = 0


func rebuild() -> void:
	var t0 := Time.get_ticks_usec()
	clear()
	_style_hash = _styles_hash()
	if not is_inside_tree():
		return
	var groups := {}    # "zi:ri:variant:chunk" -> [mesh, shadows, transforms]
	for p in placements():
		var zi: int = p.zi
		var ri: int = p.ri
		var mesh: Mesh = p.mesh
		var key := "%d:%d:%d:%d" % [zi, ri, int(p.variant), int(float(p.d) / CHUNK)]
		if not groups.has(key):
			groups[key] = [mesh, p.shadows, []]
		(groups[key][2] as Array).append(p.xf)
	var keys := groups.keys()
	keys.sort()
	for key: String in keys:
		var g: Array = groups[key]
		var arr: Array = g[2]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = g[0]
		mm.instance_count = arr.size()
		for i in arr.size():
			mm.set_instance_transform(i, arr[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "G_" + key.replace(":", "_")
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if (g[1] and shadows) \
				else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mmi, false, Node.INTERNAL_MODE_BACK)
		_made.append(mmi)
		instance_total += arr.size()
	last_ms = (Time.get_ticks_usec() - t0) / 1000.0


# =============================================================================
# PLACEMENT (pure: no renderer needed)
# =============================================================================

## Every greeble instance: {zi, ri (-1 = the style's threshold mesh), variant
## (1 = the rule's right-hand mesh), mesh, shadows, xf (in this node's space),
## pi, d, layer, side}.
func placements() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	_infos = _path_infos()
	for zi in zones.size():
		var z := zones[zi]
		if z == null or z.style == null or z.path_index < 0 or z.path_index >= _infos.size():
			continue
		var info: Dictionary = _infos[z.path_index]
		if info.is_empty():
			continue
		var L: float = info.length
		var span: float = z.to_d - z.from_d
		if info.closed and span <= 0.0:
			span += L
		if span <= 0.0:
			continue
		var bay := maxf(z.style.bay_length, 1.0)
		for ri in z.style.rules.size():
			var rule := z.style.rules[ri]
			if rule == null or not rule.enabled or rule.mesh == null:
				continue
			if z.skip_layers & int(LAYER_BITS.get(rule.layer, 0)):
				continue
			var rng := RandomNumberGenerator.new()
			rng.seed = hash([z.seed, ri])
			var slots := maxi(rule.slots_per_bay, 1)
			var slot_len := bay / float(slots)
			var n_slots := int(span / slot_len)
			var aabb := rule.mesh.get_aabb()
			var sides := _sides(rule, z)
			for s in n_slots:
				var ch := rule.pattern[s % rule.pattern.length()] if rule.pattern.length() > 0 else "x"
				if ch != "x":
					continue
				# Every slot draws the same numbers whether or not a piece fits
				# there, so a gap or a width change never reshuffles the rest.
				var roll := rng.randf()
				var rnd := PackedFloat32Array()
				for k in 8:
					rnd.append(rng.randf())
				if roll > rule.probability * z.density:
					continue
				var d := z.from_d + (float(s) + rule.slot_phase) * slot_len
				if info.closed:
					d = fposmod(d, L)
				elif d > L:
					break
				if rule.avoid_tunnels and _in_no_overhead(z.path_index, d):
					continue
				for si in sides.size():
					var side: String = sides[si]
					var hl := _half_length(aabb, rule, slot_len)
					if not _available(info, z.path_index, rule.layer, side, d, hl):
						continue
					var xf := _place(info, rule, side, d, slot_len, aabb, rnd, si * 4)
					if rule.layer == "ground" and _excluded(info, z.path_index, d, xf, aabb):
						continue
					var right := side == "R" and rule.mesh_right != null
					out.append({zi = zi, ri = ri, variant = 1 if right else 0,
							mesh = rule.mesh_right if right else rule.mesh, shadows = rule.cast_shadows,
							xf = xf, pi = z.path_index, d = d, layer = rule.layer, side = side})
		# The style's threshold piece, overhead at the zone entrance.
		var tm := z.style.threshold_mesh
		if tm:
			var d0: float = fposmod(z.from_d + 4.0, L) if info.closed else z.from_d + 4.0
			if d0 <= L and _available(info, z.path_index, "overhead", "C", d0, 3.0):
				var tr := UtopiaGreebleRule.new()
				tr.layer = "overhead"
				tr.mesh = tm
				var xf := _place(info, tr, "C", d0, 1.0, tm.get_aabb(), PackedFloat32Array([0.5, 0.5, 0.5, 0.5]), 0)
				out.append({zi = zi, ri = -1, variant = 0, mesh = tm, shadows = true,
						xf = xf, pi = z.path_index, d = d0, layer = "overhead", side = "C"})
	return out


## Pieces of non-ground layers that reach into the driving corridor (the flat
## road, CLEARANCE high), and ground pieces taller than GROUND_MAX.
## [{zi, ri, count, pos (global), d, pi, what}], one per zone and rule.
func intrusions(pl: Array[Dictionary] = []) -> Array[Dictionary]:
	if pl.is_empty():
		pl = placements()
	var faces := {}
	var found := {}
	for p in pl:
		var info: Dictionary = _infos[p.pi]
		var F := _frame(info, p.d)
		var w := _width(info, p.d)
		var local := F.affine_inverse() * (p.xf as Transform3D)
		var mesh: Mesh = p.mesh
		var box: AABB = local * mesh.get_aabb()
		var what := ""
		if p.layer == "ground":
			if box.end.y > GROUND_MAX:
				what = "%.2f m tall on the road (ground pieces: under %.1f m)" % [box.end.y, GROUND_MAX]
		else:
			var lo := Vector3(-(w.x - LIP) + 0.2, 0.3, -INF)
			var hi := Vector3((w.y - LIP) - 0.2, CLEARANCE, INF)
			if _overlaps(box, lo, hi):
				# Box test passed: check the triangles (a gantry's AABB spans
				# the corridor, its legs and beam don't).
				if not faces.has(mesh):
					faces[mesh] = mesh.get_faces()
				var tris: PackedVector3Array = faces[mesh]
				var k := 0
				while k + 2 < tris.size():
					var a := local * tris[k]
					var tb := AABB(a, Vector3.ZERO).expand(local * tris[k + 1]).expand(local * tris[k + 2])
					if _overlaps(tb, lo, hi):
						what = "reaches into the track (%.1f m up, %.1f m in from the edge)" % [
								maxf(tb.position.y, 0.3), minf(hi.x - tb.position.x, tb.end.x - lo.x)]
						break
					k += 3
		if what.is_empty():
			continue
		var key := "%d:%d" % [p.zi, p.ri]
		if found.has(key):
			found[key].count += 1
		else:
			found[key] = {zi = p.zi, ri = p.ri, count = 1, pos = global_transform * (p.xf as Transform3D).origin,
					d = p.d, pi = p.pi, what = what}
	var out: Array[Dictionary] = []
	for k in found:
		out.append(found[k])
	return out


# =============================================================================
# INTERNALS
# =============================================================================

## One dictionary per path: {curve, xf, length, closed, road, wall_l, wall_r,
## width_seg}, or {} when the path is missing.
func _path_infos() -> Array:
	var out := []
	for i in paths.size():
		var p := get_node_or_null(paths[i]) as Path3D
		if p == null or p.curve == null:
			out.append({})
			continue
		var L := p.curve.get_baked_length()
		var info := {curve = p.curve, xf = global_transform.affine_inverse() * p.global_transform,
				length = L, closed = i == 0, road = [], wall_l = [], wall_r = [], width_seg = null}
		for c in p.get_children():
			if not c is TrackRoadSegment:
				continue
			var seg := c as TrackRoadSegment
			var r := Vector2(seg.start_distance, L if seg.end_distance < 0.0 else seg.end_distance)
			var nm := String(seg.name)
			if nm.begins_with("Road"):
				info.road.append(r)
				if info.width_seg == null:
					info.width_seg = seg
			elif nm.begins_with("WallL"):
				info.wall_l.append(r)
			elif nm.begins_with("WallR"):
				info.wall_r.append(r)
		out.append(info)
	return out


func _frame(info: Dictionary, d: float) -> Transform3D:
	return (info.xf as Transform3D) * TrackRoadSegment.frame_at(info.curve, d)


## (left, right) half widths, centre line to the lip's outer edge.
func _width(info: Dictionary, d: float) -> Vector2:
	var seg: TrackRoadSegment = info.width_seg
	return seg.width_at(d) if seg else Vector2(ROAD_EDGE, ROAD_EDGE)


static func _covered(ranges: Array, d: float, hl: float, L: float, closed: bool) -> bool:
	for e: float in [-hl, 0.0, hl]:
		var x := d + e
		if closed:
			x = fposmod(x, L)
		var ok := false
		for r: Vector2 in ranges:
			if x >= r.x - 0.01 and x <= r.y + 0.01:
				ok = true
				break
		if not ok:
			return false
	return true


func _available(info: Dictionary, pi: int, layer: String, side: String, d: float, hl: float) -> bool:
	var L: float = info.length
	var closed: bool = info.closed
	match layer:
		"ground":
			return _covered(info.road, d, hl, L, closed)
		"overhead":
			return _covered(info.wall_l, d, hl, L, closed) and _covered(info.wall_r, d, hl, L, closed) \
					and not _in_no_overhead(pi, d)
	if side == "L":
		return _covered(info.wall_l, d, hl, L, closed)
	if side == "R":
		return _covered(info.wall_r, d, hl, L, closed)
	return false


func _in_no_overhead(pi: int, d: float) -> bool:
	for s in no_overhead:
		if int(s.x) == pi and d >= s.y and d <= s.z:
			return true
	return false


## Ground pieces: off the boost pads and the start line.
func _excluded(info: Dictionary, pi: int, d: float, xf: Transform3D, aabb: AABB) -> bool:
	if ground_exclusions.is_empty():
		return false
	var F := _frame(info, d)
	var x := (xf.origin - F.origin).dot(F.basis.x)
	var half := Vector2(aabb.size.x, aabb.size.z) * 0.5 * xf.basis.get_scale().x
	var L: float = info.length
	var i := 0
	while i + 4 < ground_exclusions.size():
		if int(ground_exclusions[i]) == pi:
			var dd := d - ground_exclusions[i + 1]
			if info.closed:
				dd = wrapf(dd, -L * 0.5, L * 0.5)
			if absf(dd) < ground_exclusions[i + 4] + half.y \
					and absf(x - ground_exclusions[i + 2]) < ground_exclusions[i + 3] + half.x:
				return true
		i += 5
	return false


## How far along the track a piece reaches from its slot point (for the
## coverage test): the slot for stretched pieces, else the mesh's own extent.
static func _half_length(aabb: AABB, rule: UtopiaGreebleRule, slot_len: float) -> float:
	if rule.mesh_length > 0.0:
		return slot_len * 0.5
	return minf(maxf(absf(aabb.position.z), absf(aabb.end.z)) * rule.scale_max, 12.0)


func _sides(rule: UtopiaGreebleRule, z: UtopiaGreebleZone) -> Array:
	if rule.layer == "overhead":
		return ["C"]
	var s := rule.side
	if z.mirror:
		s = {"left": "right", "right": "left"}.get(s, s)
	match s:
		"left":
			return ["L"]
		"right":
			return ["R"]
		"center":
			return ["C"] if rule.layer == "ground" else []
	return ["L", "R"]


## The rail point in the road frame (x right, y up) for a layer and side,
## with the road's width at d. Ground side rails include the rule's lateral.
func _rail(info: Dictionary, layer: String, side: String, d: float, lateral: float, aabb: AABB) -> Array:
	var w := _width(info, d)
	var dl := w.x - ROAD_EDGE
	var dr := w.y - ROAD_EDGE
	var sgn := -1.0 if side == "L" else 1.0
	var grow := dl if side == "L" else dr
	var p := Vector3.ZERO
	var sx := 1.0
	match layer:
		"ground":
			if side == "C":
				p.x = (w.y - w.x) * 0.5
				if aabb.size.x > SPAN_FIT:
					sx = ((w.x - LIP) + (w.y - LIP)) / (2.0 * (ROAD_EDGE - LIP))
			else:
				var flat := (w.x if side == "L" else w.y) - LIP
				p.x = sgn * lateral * flat / (ROAD_EDGE - LIP)
		"wall_face":
			p = Vector3(sgn * (rail_face.x + grow), rail_face.y, 0.0)
		"wall_top":
			p = Vector3(sgn * (rail_top.x + grow), rail_top.y, 0.0)
		"outside":
			p = Vector3(sgn * (rail_outer.x + grow), rail_outer.y, 0.0)
		"overhead":
			p.x = (dr - dl) * 0.5
			if aabb.size.x > SPAN_FIT:
				sx = (rail_top.x + (dl + dr) * 0.5) / rail_top.x
	return [p, sx]


## Instance transform for a rule at distance d. rnd[o..o+3] = jitter x/y/z
## and scale, in 0..1.
func _place(info: Dictionary, rule: UtopiaGreebleRule, side: String, d: float, slot_len: float,
		aabb: AABB, rnd: PackedFloat32Array, o: int) -> Transform3D:
	var F := _frame(info, d)
	var r := _rail(info, rule.layer, side, d, rule.lateral, aabb)
	var p: Vector3 = r[0]
	var inward := F.basis
	if side == "R":
		inward = F.basis * Basis(Vector3.UP, PI)
	var j := rule.jitter
	var off := rule.offset + Vector3((rnd[o] * 2.0 - 1.0) * j.x, (rnd[o + 1] * 2.0 - 1.0) * j.y,
			(rnd[o + 2] * 2.0 - 1.0) * j.z)
	var b := inward * Basis.from_euler(rule.rotation_deg * (PI / 180.0))
	var s := lerpf(rule.scale_min, rule.scale_max, rnd[o + 3])
	var sc := Vector3(s * float(r[1]), s, s)
	if rule.mesh_length > 0.0:
		# Fill the slot as measured along this rail (longer on the outside
		# of a bend, shorter on the inside).
		var L: float = info.length
		var da := d - slot_len * 0.5
		var db := d + slot_len * 0.5
		if info.closed:
			da = fposmod(da, L)
			db = fposmod(db, L)
		var Fa := _frame(info, clampf(da, 0.0, L))
		var Fb := _frame(info, clampf(db, 0.0, L))
		var pa: Vector3 = Fa.origin + Fa.basis * (_rail(info, rule.layer, side, da, rule.lateral, aabb)[0] as Vector3)
		var pb: Vector3 = Fb.origin + Fb.basis * (_rail(info, rule.layer, side, db, rule.lateral, aabb)[0] as Vector3)
		sc.z = pa.distance_to(pb) / rule.mesh_length
	return Transform3D(b.scaled_local(sc), F.origin + F.basis * p + inward * off)


static func _overlaps(b: AABB, lo: Vector3, hi: Vector3) -> bool:
	return b.end.x > lo.x and b.position.x < hi.x and b.end.y > lo.y and b.position.y < hi.y


func _styles_hash() -> int:
	var parts := []
	for z in zones:
		if z == null or z.style == null:
			parts.append(0)
			continue
		var st := z.style
		parts.append([st.get_instance_id(), st.bay_length, st.threshold_mesh.get_instance_id() if st.threshold_mesh else 0])
		for r in st.rules:
			if r == null:
				continue
			var vals := []
			for prop in r.get_property_list():
				if prop.usage & PROPERTY_USAGE_STORAGE and prop.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
					var v: Variant = r.get(prop.name)
					vals.append(v.get_instance_id() if v is Object else v)
			parts.append(vals)
	return hash(var_to_bytes(parts))
