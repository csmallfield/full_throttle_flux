@tool
extends Node3D
class_name TrackRoadSegment

## Extrudes a 2D cross-section along a DISTANCE RANGE of a Path3D and builds
## its mesh and trimesh collision at load time (v31).
##
## What CSGPolygon3D (MODE_PATH) does for the other tracks, plus the two things
## a track with forks and jumps needs and CSG can't do:
##   * start/end distances, so one spline can carry several pieces of road with
##     gaps between them (a jump) or hand over to a junction;
##   * edge-lip fades: polygon points above y = 0 (the road's raised edge lips)
##     are scaled down to 0 over `fade_in` / `fade_out` metres, so a road can run
##     flush into a flat junction with no step under the walls.
##
## Polygon convention: x across (+x = right of travel), y up, road surface at
## y = 0. Frames come from the curve's tangent and its TILTED baked up vector
## (the same frame the ship's spline queries and the respawn manager use).
## Collision is one-sided (face normals point out of the solid), and each end
## gets a cap, so the front of a landing ramp is a solid face.
##
## Built in _ready() into internal children (nothing is saved into the scene),
## so a generated track file stays small and always matches its splines.

@export var path_node: NodePath = NodePath("..")
@export var start_distance: float = 0.0
## < 0 = to the end of the path.
@export var end_distance: float = -1.0
@export var polygon: PackedVector2Array = PackedVector2Array()
## Ring spacing in metres (the last ring is always exactly at end_distance).
@export var interval: float = 1.0
@export_flags_3d_physics var collision_layer: int = 1
@export var material: Material
## Metres of travel per texture U unit (and per V unit across the section).
@export var u_distance: float = 100.0
@export var fade_in: float = 0.0
@export var fade_out: float = 0.0
@export var caps: bool = true
@export var cast_shadows: bool = true

@export_group("Width profile (v34)")
## Optional road width along the segment: x = distance along the path (same
## metres as start/end_distance), y = left half width, z = right half width,
## sorted by x, linearly interpolated (held beyond the ends). Empty = the
## polygon as drawn (the exact pre-v34 code path).
##
## The polygon is drawn for `width_reference` on both sides. Points within
## `width_stretch_limit` of the centre are scaled (the road surface stretches);
## points beyond it are moved sideways by the width change (lips and walls
## keep their shape). Walls use a stretch limit of 0: they only move.
@export var width_profile: PackedVector3Array = PackedVector3Array()
@export var width_reference: float = 21.5
@export var width_stretch_limit: float = 19.5
## v34: for a curve whose ends coincide (a lap): a segment that runs to the
## end of the curve finishes on exactly the frame at distance 0, so the lap
## seam has no hairline crack for a ray to slip through (whether one segment
## runs the whole lap or two meet at the seam). Ends that meet at the seam get
## no cap (two caps back to back are vertical faces flush with the road, which
## a ray landing exactly on the seam can hit).
@export var weld_lap_seam: bool = false

var _mi: MeshInstance3D
var _body: StaticBody3D


func _ready() -> void:
	build()


func build() -> void:
	var path := get_node_or_null(path_node) as Path3D
	if path == null or path.curve == null or polygon.size() < 3:
		return
	var curve := path.curve
	var length := curve.get_baked_length()
	var d0 := clampf(start_distance, 0.0, length)
	var d1 := length if end_distance < 0.0 else clampf(end_distance, 0.0, length)
	if d1 - d0 < 0.01:
		return
	
	# Path space -> this node's space.
	var to_local := Transform3D.IDENTITY
	if is_inside_tree():
		to_local = global_transform.affine_inverse() * path.global_transform
	
	# Ring distances.
	var ds := PackedFloat32Array()
	var n := maxi(1, int(ceil((d1 - d0) / maxf(interval, 0.05))))
	for i in n + 1:
		ds.append(lerpf(d0, d1, float(i) / n))
	
	# Polygon orientation (outward normals) and perimeter for V.
	var poly := polygon
	var m := poly.size()
	var area := 0.0
	for i in m:
		var a := poly[i]
		var b := poly[(i + 1) % m]
		area += a.x * b.y - b.x * a.y
	var ccw := area > 0.0
	var per := PackedFloat32Array()
	per.resize(m + 1)
	per[0] = 0.0
	for i in m:
		per[i + 1] = per[i] + poly[i].distance_to(poly[(i + 1) % m])
	
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	var faces := PackedVector3Array()
	
	var frames: Array[Transform3D] = []
	for d in ds:
		frames.append(to_local * frame_at(curve, d))
	if weld_lap_seam and d1 >= length and frames.size() > 1:
		frames[frames.size() - 1] = to_local * frame_at(curve, 0.0)

	if not width_profile.is_empty():
		_build_widened(poly, ccw, per, ds, frames, d0, d1, verts, norms, uvs, idx, faces)
		_finish(verts, norms, uvs, idx, faces)
		return

	# One pair of vertex columns per polygon edge: flat across, smooth along.
	for e in m:
		var p0 := poly[e]
		var p1 := poly[(e + 1) % m]
		var ed := p1 - p0
		var n2 := Vector2(ed.y, -ed.x) if ccw else Vector2(-ed.y, ed.x)
		n2 = n2.normalized()
		var base := verts.size()
		for k in ds.size():
			var fr: Transform3D = frames[k]
			var sc := _lip_scale(ds[k], d0, d1)
			var q0 := Vector2(p0.x, p0.y * sc if p0.y > 0.0 else p0.y)
			var q1 := Vector2(p1.x, p1.y * sc if p1.y > 0.0 else p1.y)
			var v0 := fr.origin + fr.basis.x * q0.x + fr.basis.y * q0.y
			var v1 := fr.origin + fr.basis.x * q1.x + fr.basis.y * q1.y
			var nn := (fr.basis.x * n2.x + fr.basis.y * n2.y).normalized()
			verts.append(v0)
			verts.append(v1)
			norms.append(nn)
			norms.append(nn)
			var u := ds[k] / u_distance
			uvs.append(Vector2(u, per[e] / u_distance))
			uvs.append(Vector2(u, per[e + 1] / u_distance))
		for k in ds.size() - 1:
			var a := base + k * 2
			var b := a + 1
			var c := a + 3
			var dd := a + 2
			var out: Vector3 = norms[a]
			_tri(verts, idx, faces, a, b, c, out)
			_tri(verts, idx, faces, a, c, dd, out)
	
	if caps:
		if not (weld_lap_seam and d0 <= 0.0):
			_cap(poly, frames[0], -1.0, d0, d0, d1, verts, norms, uvs, idx, faces)
		if not (weld_lap_seam and d1 >= length):
			_cap(poly, frames[frames.size() - 1], 1.0, d1, d0, d1, verts, norms, uvs, idx, faces)

	_finish(verts, norms, uvs, idx, faces)


func _finish(verts: PackedVector3Array, norms: PackedVector3Array, uvs: PackedVector2Array,
		idx: PackedInt32Array, faces: PackedVector3Array) -> void:
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	if material:
		mesh.surface_set_material(0, material)
	
	if _mi == null:
		_mi = MeshInstance3D.new()
		_mi.name = "Mesh"
		add_child(_mi, false, Node.INTERNAL_MODE_FRONT)
	_mi.mesh = mesh
	_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cast_shadows \
			else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	
	if collision_layer != 0:
		if _body == null:
			_body = StaticBody3D.new()
			_body.name = "Body"
			add_child(_body, false, Node.INTERNAL_MODE_FRONT)
			var cs := CollisionShape3D.new()
			cs.name = "Shape"
			_body.add_child(cs, false, Node.INTERNAL_MODE_FRONT)
		_body.collision_layer = collision_layer
		_body.collision_mask = 0
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(faces)
		(_body.get_child(0, true) as CollisionShape3D).shape = shape


## Road frame at `d` in path space: origin on the centre line, basis.x = right,
## basis.y = tilted up, -basis.z = direction of travel.
static func frame_at(curve: Curve3D, d: float) -> Transform3D:
	var length := curve.get_baked_length()
	var a := curve.sample_baked(clampf(d - 0.05, 0.0, length), true)
	var b := curve.sample_baked(clampf(d + 0.05, 0.0, length), true)
	var f := (b - a).normalized()
	var up := curve.sample_baked_up_vector(clampf(d, 0.0, length), true).slide(f).normalized()
	var r := f.cross(up).normalized()
	return Transform3D(Basis(r, up, -f), curve.sample_baked(clampf(d, 0.0, length), true))


## v34: the extrusion with a width profile. Same layout as the plain path, but
## each ring's section is re-shaped for the width there, and normals come from
## the re-shaped section.
func _build_widened(poly: PackedVector2Array, ccw: bool, per: PackedFloat32Array,
		ds: PackedFloat32Array, frames: Array[Transform3D], d0: float, d1: float,
		verts: PackedVector3Array, norms: PackedVector3Array, uvs: PackedVector2Array,
		idx: PackedInt32Array, faces: PackedVector3Array) -> void:
	var m := poly.size()
	var sections: Array[PackedVector2Array] = []
	for k in ds.size():
		var w := width_at(ds[k])
		var sc := _lip_scale(ds[k], d0, d1)
		var sec := PackedVector2Array()
		sec.resize(m)
		for i in m:
			var p := poly[i]
			sec[i] = Vector2(_widen_x(p.x, w), p.y * sc if p.y > 0.0 else p.y)
		sections.append(sec)
	for e in m:
		var base := verts.size()
		for k in ds.size():
			var fr: Transform3D = frames[k]
			var q0: Vector2 = sections[k][e]
			var q1: Vector2 = sections[k][(e + 1) % m]
			var ed := q1 - q0
			var n2 := Vector2(ed.y, -ed.x) if ccw else Vector2(-ed.y, ed.x)
			n2 = n2.normalized()
			var nn := (fr.basis.x * n2.x + fr.basis.y * n2.y).normalized()
			verts.append(fr.origin + fr.basis.x * q0.x + fr.basis.y * q0.y)
			verts.append(fr.origin + fr.basis.x * q1.x + fr.basis.y * q1.y)
			norms.append(nn)
			norms.append(nn)
			var u := ds[k] / u_distance
			uvs.append(Vector2(u, per[e] / u_distance))
			uvs.append(Vector2(u, per[e + 1] / u_distance))
		for k in ds.size() - 1:
			var a := base + k * 2
			_tri(verts, idx, faces, a, a + 1, a + 3, norms[a])
			_tri(verts, idx, faces, a, a + 3, a + 2, norms[a])
	if caps:
		# _cap applies the lip fade itself: hand it the widened, unfaded section.
		var length := (get_node_or_null(path_node) as Path3D).curve.get_baked_length()
		if not (weld_lap_seam and d0 <= 0.0):
			_cap(_widened(poly, width_at(d0)), frames[0], -1.0, d0, d0, d1, verts, norms, uvs, idx, faces)
		if not (weld_lap_seam and d1 >= length):
			_cap(_widened(poly, width_at(d1)), frames[frames.size() - 1], 1.0, d1, d0, d1,
					verts, norms, uvs, idx, faces)


func _widened(poly: PackedVector2Array, w: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in poly:
		out.append(Vector2(_widen_x(p.x, w), p.y))
	return out


## Half widths (left, right) at distance `d`.
func width_at(d: float) -> Vector2:
	var n := width_profile.size()
	if n == 0:
		return Vector2(width_reference, width_reference)
	if d <= width_profile[0].x:
		return Vector2(width_profile[0].y, width_profile[0].z)
	if d >= width_profile[n - 1].x:
		return Vector2(width_profile[n - 1].y, width_profile[n - 1].z)
	var lo := 0
	var hi := n - 1
	while hi - lo > 1:
		var mid := (lo + hi) >> 1
		if width_profile[mid].x <= d:
			lo = mid
		else:
			hi = mid
	var a := width_profile[lo]
	var b := width_profile[hi]
	var t := (d - a.x) / (b.x - a.x) if b.x > a.x else 1.0
	return Vector2(lerpf(a.y, b.y, t), lerpf(a.z, b.z, t))


## Polygon x re-shaped for half widths `w` (x = left, y = right).
func _widen_x(x: float, w: Vector2) -> float:
	var side := w.y if x > 0.0 else w.x
	var delta := side - width_reference
	var lim := width_stretch_limit
	if lim > 0.0 and absf(x) <= lim:
		return x * (lim + delta) / lim
	return x + signf(x) * delta


func _lip_scale(d: float, d0: float, d1: float) -> float:
	var s := 1.0
	if fade_in > 0.0:
		s = minf(s, clampf((d - d0) / fade_in, 0.0, 1.0))
	if fade_out > 0.0:
		s = minf(s, clampf((d1 - d) / fade_out, 0.0, 1.0))
	return s


## Triangle a-b-c facing `out` (Godot front faces are clockwise).
static func _tri(verts: PackedVector3Array, idx: PackedInt32Array, faces: PackedVector3Array,
		a: int, b: int, c: int, out: Vector3) -> void:
	var nrm := (verts[b] - verts[a]).cross(verts[c] - verts[a])
	if nrm.dot(out) > 0.0:
		var t := b
		b = c
		c = t
	idx.append(a)
	idx.append(b)
	idx.append(c)
	faces.append(verts[a])
	faces.append(verts[b])
	faces.append(verts[c])


func _cap(poly: PackedVector2Array, fr: Transform3D, dir: float, d: float, d0: float, d1: float,
		verts: PackedVector3Array, norms: PackedVector3Array, uvs: PackedVector2Array,
		idx: PackedInt32Array, faces: PackedVector3Array) -> void:
	var tri := Geometry2D.triangulate_polygon(poly)
	if tri.is_empty():
		return
	var out := (-fr.basis.z * dir).normalized()
	var sc := _lip_scale(d, d0, d1)
	var base := verts.size()
	for p in poly:
		var q := Vector2(p.x, p.y * sc if p.y > 0.0 else p.y)
		verts.append(fr.origin + fr.basis.x * q.x + fr.basis.y * q.y)
		norms.append(out)
		uvs.append(q / u_distance)
	for i in range(0, tri.size(), 3):
		_tri(verts, idx, faces, base + tri[i], base + tri[i + 1], base + tri[i + 2], out)
