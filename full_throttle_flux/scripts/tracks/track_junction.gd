@tool
extends Node3D
class_name TrackJunction

## Road surface and splitter for a Y junction (v31): where a branch leaves or
## rejoins the main road, the two roads overlap, so neither can be extruded on
## its own (each road's edge lips would stand up in the middle of the other,
## and a wall extruded along a whole path can't open to let the other road
## through). Built at load time like TrackRoadSegment:
##
##   * the road: the 2D union of the two road strips over the junction, flat
##     (collision layer 1), with a skirt;
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
##
## v38: the road is drawn with the track surface shader, so its top carries
## the same UV2 / CUSTOM0 / TANGENT as a TrackRoadSegment (see its header), in
## two meshes, one per path frame. Where the roads overlap, path A's (the main
## road's) frame wins:
##   Road        path A's whole strip, in A's frame: the main road runs
##               through unchanged, its edge lips (flat here) included
##   RoadBranch  what's left of path B's strip outside A's, in B's frame
## So each mesh meets its own path's road segments at the junction's ends
## with the same s, t, class and half widths, and the only change of frame is
## along A's outer lip edge. Each mesh gets its path's material from
## TrackSurface (road_mesh_for()) and its own path_length. The skirt is drawn
## in A's frame (underside class). Collision is still the union outline.

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
## v38: half width of each road's driving surface (the lips lie flat beyond it).
@export var surface_half_width: float = 19.5
## v38: width of the surface strips across (TrackRoadSegment's road polygon
## spacing, so the vertices line up with the roads either side).
@export var surface_strip: float = 3.0
## Distance from a road's centre line to the face of its inner wall.
@export var wall_offset: float = 21.1
@export var wedge_height: float = 6.5
@export var wedge_bottom: float = -2.0
@export var interval: float = 1.0
## The road (v38: shaders/track/track_surface_material.tres).
@export var material: Material
## v38: the splitter wedge (the grid). Empty = `material`.
@export var splitter_material: Material
@export var u_distance: float = 100.0

## Filled by build(): world-space nose point and the splitter outline (debug).
var nose := Vector3.ZERO
var wedge_outline := PackedVector2Array()

var _parts: Array[Node] = []
var _road_a: MeshInstance3D
var _road_b: MeshInstance3D


## One mesh's arrays, as TrackRoadSegment builds them.
class _Buf:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()
	var cust := PackedFloat32Array()
	var tans := PackedFloat32Array()
	var idx := PackedInt32Array()
	var faces := PackedVector3Array()

	func add(v: Vector3, n: Vector3, uv: Vector2, st: Vector2, cls: int, half: Vector2, tan: Vector3) -> int:
		verts.append(v)
		norms.append(n)
		uvs.append(uv)
		uv2s.append(st)
		TrackRoadSegment._append_custom(cust, cls, half, 0.0)
		TrackRoadSegment._append_tangent(tans, tan, 1)
		return verts.size() - 1


func _ready() -> void:
	build()


func build() -> void:
	for p in _parts:
		if is_instance_valid(p):
			# Out of the tree now, so the new parts get their own names.
			remove_child(p)
			p.queue_free()
	_parts.clear()
	_road_a = null
	_road_b = null
	var pa := get_node_or_null(path_a) as Path3D
	var pb := get_node_or_null(path_b) as Path3D
	if pa == null or pb == null or pa.curve == null or pb.curve == null:
		return

	var y0 := (pa.global_transform * pa.curve.sample_baked(a_start if point_at_start else a_end, true)).y
	var inv := global_transform.affine_inverse() if is_inside_tree() else Transform3D.IDENTITY

	# Centre-line frames, world space.
	var da := _dists(a_start, a_end)
	var db := _dists(b_start, b_end)
	var fa := _frames(pa, da)
	var fb := _frames(pb, db)

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
	# v38: drawn per path frame; the union outline is the collision and skirt.
	var none: Array[Transform3D] = []
	_road_a = _add_road("Road", fa, da, y0, inv, none, pa.curve.get_baked_length())
	# B is cut by A's strip carried a little past the point end, where the
	# road before the fork (after the rejoin) lies, so B's first ring, a hair
	# askew of A's, can't poke past it.
	var cut := fa.duplicate()
	if point_at_start:
		var f0: Transform3D = fa[0]
		cut.push_front(Transform3D(f0.basis, f0.origin + f0.basis.z * POINT_OVERLAP))
	else:
		var f1: Transform3D = fa[fa.size() - 1]
		cut.push_back(Transform3D(f1.basis, f1.origin - f1.basis.z * POINT_OVERLAP))
	_road_b = _add_road("RoadBranch", fb, db, y0, inv, cut, pb.curve.get_baked_length())
	_add_slab("RoadSkirt", outer, y0, y0 - 2.0, 1, true, fa, da, pa.curve.get_baked_length())

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
	_add_slab("Splitter", poly, y0 + wedge_height, y0 + wedge_bottom, 4, false, fa, da,
			pa.curve.get_baked_length())


## v38: the road mesh drawn in `path`'s frame (internal child), or null.
func road_mesh_for(path: Path3D) -> MeshInstance3D:
	if path == null:
		return null
	if get_node_or_null(path_a) == path:
		return _road_a
	if get_node_or_null(path_b) == path:
		return _road_b
	return null


## v38: the path whose frame `part` (one of this junction's internal meshes)
## is drawn in: path B for RoadBranch, path A for the rest.
func path_of(part: Node) -> Path3D:
	return get_node_or_null(path_b if part != null and part == _road_b else path_a) as Path3D


func _dists(d0: float, d1: float) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	var n := maxi(1, int(ceil((d1 - d0) / maxf(interval, 0.05))))
	for i in n + 1:
		out.append(lerpf(d0, d1, float(i) / n))
	return out


func _frames(p: Path3D, ds: PackedFloat64Array) -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	for d in ds:
		out.append(p.global_transform * TrackRoadSegment.frame_at(p.curve, d))
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


## v38: the road's top in one path's frame, flat at y0: a ring at each frame,
## and across it TrackRoadSegment's road section (lip, surface strips, lip;
## the lips flat, as the roads fade theirs into the junction). With `cut`
## (the other road's frames), everything inside that road's strip is left
## out: triangles wholly inside are dropped, those across its edge are
## clipped to a local piece of it, and a clipped vertex takes its triangle's
## s, t and tangent at that point.
func _add_road(n: String, fr: Array[Transform3D], ds: PackedFloat64Array, y0: float,
		inv: Transform3D, cut: Array[Transform3D], path_length: float) -> MeshInstance3D:
	var hw := surface_half_width
	var rw := maxf(road_half_width, hw)
	var xs := PackedFloat32Array([-rw])
	var strips := maxi(1, int(ceil(2.0 * hw / maxf(surface_strip, 0.1))))
	for i in strips + 1:
		xs.append(-hw + 2.0 * hw * i / strips)
	xs.append(rw)
	var half := Vector2(hw, hw)
	var up := inv.basis * Vector3.UP
	var buf := _Buf.new()
	var rings := fr.size()
	var cursor := 0
	for e in xs.size() - 1:
		var x0 := xs[e]
		var x1 := xs[e + 1]
		if x1 - x0 < 1e-4:
			continue
		var cls := TrackRoadSegment.EDGE_LIP if e == 0 or e == xs.size() - 2 \
				else TrackRoadSegment.EDGE_SURFACE
		# A vertex pair per ring, made when a kept triangle first uses it.
		var p2 := PackedVector2Array()
		var st := PackedVector2Array()
		var tn: Array[Vector3] = []
		var vid := PackedInt32Array()
		var state := PackedInt32Array()   # against `cut`: _OUT, _IN, _EDGE
		var near := PackedInt32Array()    # nearest ring of `cut`
		for k in rings:
			var f := fr[k]
			var tan := (inv.basis * -f.basis.z).normalized()
			for x in [x0, x1]:
				var q := _xz(f.origin + f.basis.x * x)
				p2.append(q)
				st.append(Vector2(ds[k], x))
				tn.append(tan)
				vid.append(-1)
				if cut.is_empty():
					state.append(_OUT)
					near.append(0)
				else:
					cursor = _nearest_ring(q, cut, cursor)
					state.append(_inside(q, cut, cursor, rw))
					near.append(cursor)
		for k in rings - 1:
			var a := 2 * k
			for tri: Array in [[a, a + 1, a + 3], [a, a + 3, a + 2]]:
				var s0 := state[tri[0]]
				var s1 := state[tri[1]]
				var s2 := state[tri[2]]
				if s0 == _IN and s1 == _IN and s2 == _IN:
					continue
				if s0 == _OUT and s1 == _OUT and s2 == _OUT:
					var ids := PackedInt32Array()
					for c: int in tri:
						if vid[c] < 0:
							vid[c] = buf.add(inv * Vector3(p2[c].x, y0, p2[c].y), up, p2[c] / u_distance,
									st[c], cls, half, tn[c])
						ids.append(vid[c])
					TrackRoadSegment._tri(buf.verts, buf.idx, buf.faces, ids[0], ids[1], ids[2], up)
					continue
				var k0 := mini(near[tri[0]], mini(near[tri[1]], near[tri[2]])) - 3
				var k1 := maxi(near[tri[0]], maxi(near[tri[1]], near[tri[2]])) + 3
				var local := _strip(cut.slice(maxi(k0, 0), mini(k1, cut.size() - 1) + 1), rw)
				_clipped_tri(buf, tri, p2, st, tn, cls, half, y0, inv, up, local)
	if buf.idx.is_empty():
		return null
	var mi := _mesh_instance(n, buf, material)
	mi.set_instance_shader_parameter("path_length", path_length)
	return mi


## Where a point is against a road strip (_inside()).
const _OUT := 0
const _IN := 1
const _EDGE := 2
## Points closer than this to a strip's outline count as on it.
const _EDGE_EPS := 0.05
## Metres A's strip is carried past the point end when it cuts B.
const POINT_OVERLAP := 5.0
## Clipped pieces smaller than this (m^2) are dropped.
const MIN_PIECE_AREA := 1e-4


static func _area(p: PackedVector2Array) -> float:
	var a := 0.0
	for i in p.size():
		var q := p[(i + 1) % p.size()]
		a += p[i].x * q.y - q.x * p[i].y
	return a * 0.5


## Nearest ring of `fr` to `p`, climbing from ring `k` (the junction is a
## short, gently curved range, so the distance has one minimum).
static func _nearest_ring(p: Vector2, fr: Array[Transform3D], k: int) -> int:
	var d := _xz(fr[k].origin).distance_squared_to(p)
	while k + 1 < fr.size():
		var d2 := _xz(fr[k + 1].origin).distance_squared_to(p)
		if d2 >= d:
			break
		k += 1
		d = d2
	while k > 0:
		var d2 := _xz(fr[k - 1].origin).distance_squared_to(p)
		if d2 >= d:
			break
		k -= 1
		d = d2
	return k


## `p` against the strip +-hw either side of the frames' centre line, seen
## from its nearest ring `k`.
static func _inside(p: Vector2, fr: Array[Transform3D], k: int, hw: float) -> int:
	var f := fr[k]
	var rel := p - _xz(f.origin)
	var across := absf(rel.dot(_xz(f.basis.x).normalized()))
	var along := rel.dot(_xz(-f.basis.z).normalized())
	var past := 0.0
	if k == 0:
		past = -along
	elif k == fr.size() - 1:
		past = along
	var out := maxf(across - hw, past)
	if out > _EDGE_EPS:
		return _OUT
	if out < -_EDGE_EPS:
		return _IN
	return _EDGE


## One triangle of a road ribbon (corner indices into the ribbon's ring
## arrays), clipped to outside `cut`, with its own vertices.
func _clipped_tri(buf: _Buf, tri: Array, p2: PackedVector2Array, st: PackedVector2Array,
		tn: Array[Vector3], cls: int, half: Vector2, y0: float, inv: Transform3D, up: Vector3,
		cut: PackedVector2Array) -> void:
	var a: Vector2 = p2[tri[0]]
	var b: Vector2 = p2[tri[1]]
	var c: Vector2 = p2[tri[2]]
	for piece: PackedVector2Array in Geometry2D.clip_polygons(PackedVector2Array([a, b, c]), cut):
		if Geometry2D.is_polygon_clockwise(piece):
			continue   # a hole: can't happen (the cut is far bigger than a triangle)
		if absf(_area(piece)) < MIN_PIECE_AREA:
			continue   # a sliver along the cut (e.g. where both roads start at the point)
		var ids := Geometry2D.triangulate_polygon(piece)
		if ids.is_empty():
			continue
		var first := buf.verts.size()
		for q in piece:
			var w := _bary(q, a, b, c)
			var s2: Vector2 = st[tri[0]] * w.x + st[tri[1]] * w.y + st[tri[2]] * w.z
			var t3: Vector3 = tn[tri[0]] * w.x + tn[tri[1]] * w.y + tn[tri[2]] * w.z
			buf.add(inv * Vector3(q.x, y0, q.y), up, q / u_distance, s2, cls, half, t3)
		for i in range(0, ids.size(), 3):
			TrackRoadSegment._tri(buf.verts, buf.idx, buf.faces, first + ids[i], first + ids[i + 1],
					first + ids[i + 2], up)


## Barycentric weights of `p` in triangle a, b, c.
static func _bary(p: Vector2, a: Vector2, b: Vector2, c: Vector2) -> Vector3:
	var v0 := b - a
	var v1 := c - a
	var v2 := p - a
	var d := v0.x * v1.y - v1.x * v0.y
	if absf(d) < 1e-12:
		return Vector3(1.0, 0.0, 0.0)
	var l1 := (v2.x * v1.y - v1.x * v2.y) / d
	var l2 := (v0.x * v2.y - v2.x * v0.y) / d
	return Vector3(1.0 - l1 - l2, l1, l2)


## (s, t) of the world xz point `p` in the frames `fr` (nearest ring, then
## projected onto it), and that ring's direction of travel.
static func _project(p: Vector2, fr: Array[Transform3D], ds: PackedFloat64Array) -> Array:
	var best := 0
	var best_d := INF
	var step := 8
	for k in range(0, fr.size(), step):
		var d := _xz(fr[k].origin).distance_squared_to(p)
		if d < best_d:
			best_d = d
			best = k
	for k in range(maxi(0, best - step), mini(fr.size(), best + step + 1)):
		var d := _xz(fr[k].origin).distance_squared_to(p)
		if d < best_d:
			best_d = d
			best = k
	var f := fr[best]
	var rel := p - _xz(f.origin)
	var fwd := -f.basis.z
	return [Vector2(ds[best] + rel.dot(_xz(fwd).normalized()), rel.dot(_xz(f.basis.x).normalized())), fwd]


## Extrudes a horizontal 2D outline into a slab from y_top down to y_bot:
## top face, skirt, (optionally no bottom). Collision on `layer`. The road's
## top face is collision only (v38: drawn by _add_road()). Vertices carry the
## surface data in the frames `fr` (underside class).
func _add_slab(n: String, outline: PackedVector2Array, y_top: float, y_bot: float, layer: int,
		road: bool, fr: Array[Transform3D], ds: PackedFloat64Array, path_length: float) -> void:
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
	var buf := _Buf.new()
	var other := TrackRoadSegment.EDGE_OTHER
	var half := Vector2(surface_half_width, surface_half_width)
	var proj: Array[Array] = []
	for p in poly:
		proj.append(_project(p, fr, ds))
	# Top.
	var up := inv.basis * Vector3.UP
	if road:
		# Collision only: faces wound like TrackRoadSegment._tri's (facing up).
		var tv := PackedVector3Array()
		for p in poly:
			tv.append(inv * Vector3(p.x, y_top, p.y))
		var no_idx := PackedInt32Array()
		for i in range(0, tri.size(), 3):
			TrackRoadSegment._tri(tv, no_idx, buf.faces, tri[i], tri[i + 1], tri[i + 2], up)
	else:
		for i in poly.size():
			var p := poly[i]
			buf.add(inv * Vector3(p.x, y_top, p.y), up, p / u_distance * 2.0, proj[i][0], other, half,
					inv.basis * proj[i][1])
		for i in range(0, tri.size(), 3):
			TrackRoadSegment._tri(buf.verts, buf.idx, buf.faces, tri[i], tri[i + 1], tri[i + 2], up)
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
		var j := (i + 1) % m
		var base := buf.add(inv * Vector3(p0.x, y_top, p0.y), out, Vector2(0.0, 0.0), proj[i][0], other,
				half, inv.basis * proj[i][1])
		buf.add(inv * Vector3(p1.x, y_top, p1.y), out, Vector2(e.length() / u_distance, 0.0),
				proj[j][0], other, half, inv.basis * proj[j][1])
		buf.add(inv * Vector3(p1.x, y_bot, p1.y), out,
				Vector2(e.length() / u_distance, (y_top - y_bot) / u_distance), proj[j][0], other, half,
				inv.basis * proj[j][1])
		buf.add(inv * Vector3(p0.x, y_bot, p0.y), out, Vector2(0.0, (y_top - y_bot) / u_distance),
				proj[i][0], other, half, inv.basis * proj[i][1])
		TrackRoadSegment._tri(buf.verts, buf.idx, buf.faces, base, base + 1, base + 2, out)
		TrackRoadSegment._tri(buf.verts, buf.idx, buf.faces, base, base + 2, base + 3, out)

	var mat := material if road or splitter_material == null else splitter_material
	var mi := _mesh_instance(n, buf, mat)
	if road:
		mi.set_instance_shader_parameter("path_length", path_length)
	var body := StaticBody3D.new()
	body.name = n + "Body"
	body.collision_layer = layer
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(buf.faces)
	cs.shape = shape
	body.add_child(cs, false, Node.INTERNAL_MODE_FRONT)
	add_child(body, false, Node.INTERNAL_MODE_FRONT)
	_parts.append(body)


func _mesh_instance(n: String, buf: _Buf, mat: Material) -> MeshInstance3D:
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = buf.verts
	arr[Mesh.ARRAY_NORMAL] = buf.norms
	arr[Mesh.ARRAY_TEX_UV] = buf.uvs
	arr[Mesh.ARRAY_TEX_UV2] = buf.uv2s
	arr[Mesh.ARRAY_CUSTOM0] = buf.cust
	arr[Mesh.ARRAY_TANGENT] = buf.tans
	arr[Mesh.ARRAY_INDEX] = buf.idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr, [], {},
			Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)
	if mat:
		mesh.surface_set_material(0, mat)
	var mi := MeshInstance3D.new()
	mi.name = n
	mi.mesh = mesh
	add_child(mi, false, Node.INTERNAL_MODE_FRONT)
	_parts.append(mi)
	return mi
