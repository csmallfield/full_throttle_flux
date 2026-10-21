@tool
extends Node3D
class_name TrackJunction

## Road surface and splitter for a Y junction (v31): where a branch leaves or
## rejoins the main road, the two roads overlap, so neither can be extruded on
## its own (each road's edge lips would stand up in the middle of the other,
## and a wall extruded along a whole path can't open to let the other road
## through). Built at load time like TrackRoadSegment:
##
##   * the road: the 2D union of the two road strips over the junction,
##     triangulated as one flat surface (collision layer 1), with a skirt;
##   * the splitter: a wedge between the two roads' INNER wall faces, from the
##     nose (where those faces meet, a sharp point) to the open end, where the
##     two inner walls (ordinary TrackRoadSegments) take over (layer 4).
##
##   fork (point_at_start = true)        rejoin (point_at_start = false)
##       ====\                                  ====\
##   ========>  nose                   nose  <========
##       ====/                                  ====/
##
## The junction must be FLAT and LEVEL (zero bank and pitch on both paths over
## the whole range): the union is built in the horizontal plane at the height
## of path A at the point. The outer walls are ordinary segments along each
## path; the roads either side should fade their edge lips out/in at the
## junction ends (TrackRoadSegment.fade_in / fade_out).

@export var path_a: NodePath
@export var path_b: NodePath
@export var a_start: float = 0.0
@export var a_end: float = 0.0
@export var b_start: float = 0.0
@export var b_end: float = 0.0
## Fork: the roads coincide at the start. Rejoin: at the end.
@export var point_at_start: bool = true
## Half width of each road strip (to the outer edge of its lips).
@export var road_half_width: float = 21.5
## Distance from a road's centre line to the face of its inner wall.
@export var wall_offset: float = 21.1
@export var wedge_height: float = 6.5
@export var wedge_bottom: float = -2.0
@export var interval: float = 1.0
@export var material: Material
@export var u_distance: float = 100.0

## Filled by build(): world-space nose point and the splitter outline (debug).
var nose := Vector3.ZERO
var wedge_outline := PackedVector2Array()

var _parts: Array[Node] = []


func _ready() -> void:
	build()


func build() -> void:
	for p in _parts:
		if is_instance_valid(p):
			p.queue_free()
	_parts.clear()
	var pa := get_node_or_null(path_a) as Path3D
	var pb := get_node_or_null(path_b) as Path3D
	if pa == null or pb == null or pa.curve == null or pb.curve == null:
		return
	
	var y0 := (pa.global_transform * pa.curve.sample_baked(a_start if point_at_start else a_end, true)).y
	
	# Centre-line frames, world space.
	var fa := _frames(pa, a_start, a_end)
	var fb := _frames(pb, b_start, b_end)
	
	# Which side of A is B? Decide at the open end.
	var ia := fa.size() - 1 if point_at_start else 0
	var ib := fb.size() - 1 if point_at_start else 0
	var side := signf((fb[ib].origin - fa[ia].origin).dot(fa[ia].basis.x))
	if side == 0.0:
		side = 1.0
	
	# --- road: union of the two strips -------------------------------------
	var strip_a := _strip(fa, road_half_width)
	var strip_b := _strip(fb, road_half_width)
	var merged := Geometry2D.merge_polygons(strip_a, strip_b)
	var outer := PackedVector2Array()
	for poly in merged:
		if not Geometry2D.is_polygon_clockwise(poly) and poly.size() > outer.size():
			outer = poly
	if outer.is_empty() and not merged.is_empty():
		outer = merged[0]
	_add_slab("Road", outer, y0, y0 - 2.0, 1, true)
	
	# --- splitter: between the inner wall faces ----------------------------
	var face_a := _offset_line(fa, side * wall_offset)
	var face_b := _offset_line(fb, -side * wall_offset)
	# Walk from the point end until the faces cross (the nose).
	if not point_at_start:
		face_a.reverse()
		face_b.reverse()
	var hit := _first_crossing(face_a, face_b)
	if hit.is_empty():
		push_warning("TrackJunction %s: inner wall faces never meet; no splitter" % name)
		return
	var poly := PackedVector2Array()
	poly.append(hit.point)
	for i in range(int(hit.ia) + 1, face_a.size()):
		poly.append(face_a[i])
	for i in range(face_b.size() - 1, int(hit.ib), -1):
		poly.append(face_b[i])
	nose = Vector3(hit.point.x, y0, hit.point.y)
	wedge_outline = poly
	_add_slab("Splitter", poly, y0 + wedge_height, y0 + wedge_bottom, 4, false)


func _frames(p: Path3D, d0: float, d1: float) -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	var n := maxi(1, int(ceil((d1 - d0) / maxf(interval, 0.05))))
	for i in n + 1:
		out.append(p.global_transform * TrackRoadSegment.frame_at(p.curve, lerpf(d0, d1, float(i) / n)))
	return out


static func _xz(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)


## Closed outline of a strip +-hw either side of the frames' centre line.
static func _strip(fr: Array[Transform3D], hw: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for f in fr:
		out.append(_xz(f.origin + f.basis.x * hw))
	for i in range(fr.size() - 1, -1, -1):
		out.append(_xz(fr[i].origin - fr[i].basis.x * hw))
	return out


static func _offset_line(fr: Array[Transform3D], off: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for f in fr:
		out.append(_xz(f.origin + f.basis.x * off))
	return out


## First crossing of two polylines walking from their first points.
static func _first_crossing(a: PackedVector2Array, b: PackedVector2Array) -> Dictionary:
	# Skip the coincident start (the faces start on top of each other's side).
	for i in range(1, a.size() - 1):
		for j in range(maxi(1, i - 40), mini(b.size() - 1, i + 40)):
			var p = Geometry2D.segment_intersects_segment(a[i], a[i + 1], b[j], b[j + 1])
			if p != null:
				return {"point": p, "ia": i, "ib": j}
	return {}


## Extrudes a horizontal 2D outline into a slab from y_top down to y_bot:
## top face, skirt, (optionally no bottom). Collision on `layer`.
func _add_slab(n: String, outline: PackedVector2Array, y_top: float, y_bot: float, layer: int,
		road_uv: bool) -> void:
	if outline.size() < 3:
		return
	var poly := outline
	if Geometry2D.is_polygon_clockwise(poly):
		poly = poly.duplicate()
		poly.reverse()
	var tri := Geometry2D.triangulate_polygon(poly)
	if tri.is_empty():
		push_warning("TrackJunction %s: could not triangulate %s" % [name, n])
		return
	var inv := global_transform.affine_inverse() if is_inside_tree() else Transform3D.IDENTITY
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	var faces := PackedVector3Array()
	# Top.
	for p in poly:
		verts.append(inv * Vector3(p.x, y_top, p.y))
		norms.append(inv.basis * Vector3.UP)
		uvs.append(p / u_distance if road_uv else p / u_distance * 2.0)
	var up := inv.basis * Vector3.UP
	for i in range(0, tri.size(), 3):
		TrackRoadSegment._tri(verts, idx, faces, tri[i], tri[i + 1], tri[i + 2], up)
	# Skirt (sides), each quad facing away from the interior.
	var m := poly.size()
	for i in m:
		var p0 := poly[i]
		var p1 := poly[(i + 1) % m]
		var e := p1 - p0
		if e.length() < 1e-4:
			continue
		var n2 := Vector2(e.y, -e.x).normalized()
		# Outward = away from the polygon interior: test a point just off the edge.
		var mid := (p0 + p1) * 0.5
		if Geometry2D.is_point_in_polygon(mid + n2 * 0.01, poly):
			n2 = -n2
		var out := inv.basis * Vector3(n2.x, 0.0, n2.y)
		var base := verts.size()
		for q in [Vector3(p0.x, y_top, p0.y), Vector3(p1.x, y_top, p1.y),
				Vector3(p1.x, y_bot, p1.y), Vector3(p0.x, y_bot, p0.y)]:
			verts.append(inv * q)
			norms.append(out)
		uvs.append(Vector2(0.0, 0.0))
		uvs.append(Vector2(e.length() / u_distance, 0.0))
		uvs.append(Vector2(e.length() / u_distance, (y_top - y_bot) / u_distance))
		uvs.append(Vector2(0.0, (y_top - y_bot) / u_distance))
		TrackRoadSegment._tri(verts, idx, faces, base, base + 1, base + 2, out)
		TrackRoadSegment._tri(verts, idx, faces, base, base + 2, base + 3, out)
	
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
	var mi := MeshInstance3D.new()
	mi.name = n
	mi.mesh = mesh
	add_child(mi, false, Node.INTERNAL_MODE_FRONT)
	_parts.append(mi)
	var body := StaticBody3D.new()
	body.name = n + "Body"
	body.collision_layer = layer
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	cs.shape = shape
	body.add_child(cs, false, Node.INTERNAL_MODE_FRONT)
	add_child(body, false, Node.INTERNAL_MODE_FRONT)
	_parts.append(body)
