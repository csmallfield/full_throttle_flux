extends RefCounted
class_name UtopiaKit
## Greybox architecture kit for the Utopia track.
##
## Everything is placed in TRACK SPACE: (d, lat, h)
##   d   = distance along MainSpline (0 .. track length, wraps)
##   lat = lateral offset, + = right of travel direction (flattened, world-horizontal)
##   h   = height relative to the spline centreline at d
## Architecture is always world-vertical (it ignores track banking), and is
## yaw-aligned to the track heading at d unless a yaw is given.
##
## Clearance envelope (keep geometry OUT of this):
##   |lat| < CLEAR_LAT  and  h < CLEAR_H   (in the track's own frame)
## run tools/utopia/check_clearance.gd after any layout change.

const FLOOR_Y := -90.0          # lowest city datum (hazed out by height fog)
const CLEAR_LAT := 33.0         # wall outer edge is ~28.6
const CLEAR_H := 20.0           # ship ~4, camera ~6.5 above the road

var helper: TrackSplineHelper
var length: float
## The extruded road (groundGeo / walls) carries its own node transform, a
## ~1 degree pitch about the world origin -- the road surface sits up to ~16 m
## off the raw spline in the north of the map. All track-space queries go
## through this transform so the city lines up with what is actually rendered.
var road_xf := Transform3D.IDENTITY
var mats := {}
var meshes := {}
var gen_mesh_dir := "res://scenes/tracks/utopia/meshes"
var _gen_count := 0
var current_district := ""

func _init(track_root: Node) -> void:
	helper = TrackSplineHelper.new(track_root)
	length = helper.total_length
	var gg := track_root.find_child("groundGeo", true, false) as Node3D
	if gg:
		road_xf = gg.transform  # child of MainSpline, which sits at the origin
	for m in ["light", "mid", "dark", "glow", "floor", "water", "accent", "far"]:
		mats[m] = load("res://scenes/tracks/utopia/materials/greybox_%s.tres" % m)
	for k in ["box", "cyl", "cyl16", "sphere", "dome", "cone", "taper"]:
		meshes[k] = load("res://scenes/tracks/utopia/meshes/unit_%s.tres" % k)

# ---------------------------------------------------------------------------
# TRACK FRAME
# ---------------------------------------------------------------------------

func wrapd(d: float) -> float:
	return fposmod(d, length)

## Road centreline (spline point through the road transform). The driving
## surface is ~2 m above this.
func center(d: float) -> Vector3:
	return road_xf * helper.spline_offset_to_world(wrapd(d) / length)

func tangent(d: float) -> Vector3:
	return (road_xf.basis * helper.get_tangent_at_offset(wrapd(d) / length)).normalized()

func fwd_flat(d: float) -> Vector3:
	var t := tangent(d)
	t.y = 0.0
	return t.normalized()

func right_flat(d: float) -> Vector3:
	return fwd_flat(d).cross(Vector3.UP).normalized()

func track_up(d: float) -> Vector3:
	return (road_xf.basis * helper.get_up_at_offset(wrapd(d) / length, true)).normalized()

## Banked track frame at d: x = right, y = up, -z = forward.
func frame(d: float) -> Basis:
	var t := tangent(d)
	var u := track_up(d)
	var r := t.cross(u).normalized()
	u = r.cross(t).normalized()
	return Basis(r, u, -t)

## World point in track space.
func at(d: float, lat: float, h: float = 0.0) -> Vector3:
	return center(d) + right_flat(d) * lat + Vector3.UP * h

## Same but h is an absolute world Y.
func at_y(d: float, lat: float, y: float) -> Vector3:
	var p := center(d) + right_flat(d) * lat
	p.y = y
	return p

## Yaw-only basis aligned with the track at d (-Z = travel direction).
func yaw_at(d: float, extra_deg: float = 0.0) -> Basis:
	var b := Basis.looking_at(fwd_flat(d), Vector3.UP)
	return b.rotated(Vector3.UP, deg_to_rad(extra_deg)) if extra_deg != 0.0 else b

func yaw_deg(deg: float) -> Basis:
	return Basis(Vector3.UP, deg_to_rad(deg))

## Lowest centreline Y within a window -- used to keep spans clear on hills.
func min_y(d0: float, d1: float) -> float:
	var y := INF
	var d := d0
	while d <= d1:
		y = minf(y, center(d).y)
		d += 4.0
	return y

func max_y(d0: float, d1: float) -> float:
	var y := -INF
	var d := d0
	while d <= d1:
		y = maxf(y, center(d).y)
		d += 4.0
	return y

# ---------------------------------------------------------------------------
# PRIMITIVES  (unit meshes scaled per node -> tiny files, easy to edit)
# ---------------------------------------------------------------------------

func _mi(parent: Node, name: String, mesh_key: String, xf: Transform3D, mat: String) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = name
	mi.mesh = meshes[mesh_key]
	mi.material_override = mats[mat]
	mi.transform = xf
	parent.add_child(mi)
	return mi

## Box by centre.
func box(parent: Node, name: String, c: Vector3, size: Vector3, basis := Basis.IDENTITY, mat := "light") -> MeshInstance3D:
	return _mi(parent, name, "box", Transform3D(basis.scaled_local(size), c), mat)

## Box standing on base point (bottom-centre).
func block(parent: Node, name: String, base: Vector3, size: Vector3, basis := Basis.IDENTITY, mat := "light") -> MeshInstance3D:
	return box(parent, name, base + Vector3.UP * size.y * 0.5, size, basis, mat)

## Block from base point up to an absolute top Y (bottom at base.y).
func block_to(parent: Node, name: String, base: Vector3, w: float, dpt: float, top_y: float, basis := Basis.IDENTITY, mat := "light") -> MeshInstance3D:
	return block(parent, name, base, Vector3(w, top_y - base.y, dpt), basis, mat)

func cyl(parent: Node, name: String, base: Vector3, radius: float, height: float, mat := "light", key := "cyl", basis := Basis.IDENTITY) -> MeshInstance3D:
	var b := basis.scaled_local(Vector3(radius * 2.0, height, radius * 2.0))
	return _mi(parent, name, key, Transform3D(b, base + basis.y.normalized() * height * 0.5), mat)

func sphere(parent: Node, name: String, c: Vector3, radius: float, mat := "light", squash := 1.0) -> MeshInstance3D:
	return _mi(parent, name, "sphere", Transform3D(Basis.IDENTITY.scaled(Vector3(radius * 2, radius * 2 * squash, radius * 2)), c), mat)

func dome(parent: Node, name: String, base: Vector3, radius: float, mat := "light", squash := 1.0) -> MeshInstance3D:
	return _mi(parent, name, "dome", Transform3D(Basis.IDENTITY.scaled(Vector3(radius * 2, radius * squash, radius * 2)), base), mat)

func group(parent: Node, name: String) -> Node3D:
	var n := Node3D.new()
	n.name = name
	parent.add_child(n)
	return n

# ---------------------------------------------------------------------------
# GENERATED MESHES
# ---------------------------------------------------------------------------

func _save_mesh(mesh: ArrayMesh, tag: String) -> ArrayMesh:
	_gen_count += 1
	var path := "%s/gen_%s_%s.res" % [gen_mesh_dir, current_district, tag]
	ResourceSaver.save(mesh, path, ResourceSaver.FLAG_COMPRESS)
	var loaded: ArrayMesh = load(path)
	loaded.take_over_path(path)
	return loaded

func mesh_node(parent: Node, name: String, mesh: Mesh, xf: Transform3D, mat := "light") -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = name
	mi.mesh = mesh
	mi.material_override = mats[mat]
	mi.transform = xf
	parent.add_child(mi)
	return mi

## Annular arch profile (semi-ellipse), extruded along local Z.
## local X = across, Y = up, origin at the springing line centre.
func arch_mesh(half_span: float, rise: float, thickness: float, depth: float, segs := 28) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var inner := []
	var outer := []
	for i in range(segs + 1):
		var a := PI * float(i) / float(segs)
		var ci := Vector2(cos(a) * half_span, sin(a) * rise)
		var co := Vector2(cos(a) * (half_span + thickness), sin(a) * (rise + thickness))
		inner.append(ci)
		outer.append(co)
	var hz := depth * 0.5
	for i in range(segs):
		var i0: Vector2 = inner[i]; var i1: Vector2 = inner[i + 1]
		var o0: Vector2 = outer[i]; var o1: Vector2 = outer[i + 1]
		# front (+z) and back (-z) faces
		_quad(st, Vector3(o0.x, o0.y, hz), Vector3(o1.x, o1.y, hz), Vector3(i1.x, i1.y, hz), Vector3(i0.x, i0.y, hz))
		_quad(st, Vector3(i0.x, i0.y, -hz), Vector3(i1.x, i1.y, -hz), Vector3(o1.x, o1.y, -hz), Vector3(o0.x, o0.y, -hz))
		# outer and inner (intrados) surfaces
		_quad(st, Vector3(o0.x, o0.y, -hz), Vector3(o1.x, o1.y, -hz), Vector3(o1.x, o1.y, hz), Vector3(o0.x, o0.y, hz))
		_quad(st, Vector3(i0.x, i0.y, hz), Vector3(i1.x, i1.y, hz), Vector3(i1.x, i1.y, -hz), Vector3(i0.x, i0.y, -hz))
	# end caps at springing
	var e0i: Vector2 = inner[0]; var e0o: Vector2 = outer[0]
	var e1i: Vector2 = inner[segs]; var e1o: Vector2 = outer[segs]
	_quad(st, Vector3(e0i.x, 0, hz), Vector3(e0i.x, 0, -hz), Vector3(e0o.x, 0, -hz), Vector3(e0o.x, 0, hz))
	_quad(st, Vector3(e1o.x, 0, hz), Vector3(e1o.x, 0, -hz), Vector3(e1i.x, 0, -hz), Vector3(e1i.x, 0, hz))
	st.generate_normals()
	return st.commit()

func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	# CW winding when viewed from the front (Godot front faces are clockwise)
	st.add_vertex(a); st.add_vertex(b); st.add_vertex(c)
	st.add_vertex(a); st.add_vertex(c); st.add_vertex(d)

## Arch spanning the track at d. spring_y = world Y of the springing line.
## Piers continue straight down to pier_to_y.
func arch_over(parent: Node, name: String, d: float, half_span: float, rise: float,
		thickness: float, depth: float, spring_y: float, pier_to_y := FLOOR_Y,
		mat := "light", yaw_extra := 0.0, lat := 0.0) -> Node3D:
	var g := group(parent, name)
	var b := yaw_at(d, yaw_extra)
	var o := at_y(d, lat, spring_y)
	var key := "arch_%d_%d_%d_%d" % [int(half_span), int(rise), int(thickness), int(depth)]
	if not meshes.has(key):
		meshes[key] = _save_mesh(arch_mesh(half_span, rise, thickness, depth), key)
	mesh_node(g, "Arch", meshes[key], Transform3D(b, o), mat)
	if pier_to_y < spring_y - 0.5:
		for s: float in [-1.0, 1.0]:
			var px := s * (half_span + thickness * 0.5)
			var pc := o + b.x * px
			var ph := spring_y - pier_to_y
			box(g, "Pier%s" % ("L" if s < 0 else "R"), Vector3(pc.x, pier_to_y + ph * 0.5, pc.z),
				Vector3(thickness, ph, depth), b, mat)
	return g

## Flat bridge deck across the track at d (perpendicular unless yaw_extra).
func bridge_over(parent: Node, name: String, d: float, deck_y: float, length_across: float,
		width: float, thickness: float, mat := "light", yaw_extra := 0.0, lat := 0.0) -> MeshInstance3D:
	var b := yaw_at(d, yaw_extra)
	var c := at_y(d, lat, deck_y - thickness * 0.5)
	return box(parent, name, c, Vector3(length_across, thickness, width), b, mat)

## Pylons under the track every `step` metres between d0 and d1.
func pylons(parent: Node, name: String, d0: float, d1: float, step: float, w := 7.0, mat := "mid", ok := Callable()) -> void:
	var g := group(parent, name)
	var d := d0
	var i := 0
	while d < d1:
		var c := center(d)
		var u := track_up(d)
		var tilt_s := sqrt(maxf(0.0, 1.0 - u.y * u.y))
		# cap is rolled with the deck, so it sits flush under a banked road
		var cap_b := frame(d)
		var cap_c := c - u * 4.4
		var top := c.y - 6.0 - 12.0 * tilt_s
		if top - FLOOR_Y > 4.0 and (not ok.is_valid() or ok.call(d)):
			var b := yaw_at(d)
			box(g, "Pylon%02d" % i, Vector3(c.x, (top + FLOOR_Y) * 0.5, c.z), Vector3(w * 2.6, top - FLOOR_Y, w), b, mat)
			box(g, "Cap%02d" % i, cap_c, Vector3(44.0, 3.6, w * 1.2), cap_b, mat)
		d += step
		i += 1

## Ribbon slab that follows the track (e.g. a parallel promenade or a roof).
## lat0/lat1 = lateral extents, y_off = height relative to the centreline,
## follows the spline in steps. Returns a mesh node.
func ribbon(parent: Node, name: String, d0: float, d1: float, lat0: float, lat1: float,
		y_off: float, thickness: float, mat := "light", step := 4.0, abs_y := NAN) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var prev := []
	var d := d0
	var first := true
	while true:
		var dd := minf(d, d1)
		var a := at(dd, lat0, y_off)
		var bb := at(dd, lat1, y_off)
		if not is_nan(abs_y):
			a.y = abs_y; bb.y = abs_y
		var cur := [a, bb, a - Vector3.UP * thickness, bb - Vector3.UP * thickness]
		if not first:
			var p: Array = prev
			_quad(st, p[0], p[1], cur[1], cur[0])          # top
			_quad(st, p[3], p[2], cur[2], cur[3])          # bottom
			_quad(st, p[2], p[0], cur[0], cur[2])          # side lat0
			_quad(st, p[1], p[3], cur[3], cur[1])          # side lat1
		else:
			_quad(st, cur[0], cur[1], cur[3], cur[2])
		prev = cur
		first = false
		if dd >= d1:
			_quad(st, cur[1], cur[0], cur[2], cur[3])
			break
		d += step
	st.generate_normals()
	var mesh := _save_mesh(st.commit(), name.to_snake_case())
	# winding may be flipped depending on lat order; keep both sides visible
	var mi := mesh_node(parent, name, mesh, Transform3D.IDENTITY, mat)
	return mi

## Wall that follows the track (vertical), from y_bot to y_top (absolute or relative).
func ribbon_wall(parent: Node, name: String, d0: float, d1: float, lat: float, thickness: float,
		h_bot: float, h_top: float, mat := "light", step := 4.0, relative := true) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var prev := []
	var d := d0
	var first := true
	while true:
		var dd := minf(d, d1)
		var c := center(dd)
		var r := right_flat(dd)
		var yb := (c.y + h_bot) if relative else h_bot
		var yt := (c.y + h_top) if relative else h_top
		var pi := c + r * (lat - thickness * 0.5)
		var po := c + r * (lat + thickness * 0.5)
		var cur := [Vector3(pi.x, yb, pi.z), Vector3(pi.x, yt, pi.z), Vector3(po.x, yt, po.z), Vector3(po.x, yb, po.z)]
		if not first:
			var p: Array = prev
			_quad(st, p[0], p[1], cur[1], cur[0])
			_quad(st, p[1], p[2], cur[2], cur[1])
			_quad(st, p[2], p[3], cur[3], cur[2])
			_quad(st, p[3], p[0], cur[0], cur[3])
		else:
			_quad(st, cur[0], cur[1], cur[2], cur[3])
		prev = cur
		first = false
		if dd >= d1:
			_quad(st, cur[3], cur[2], cur[1], cur[0])
			break
		d += step
	st.generate_normals()
	var mesh := _save_mesh(st.commit(), name.to_snake_case())
	return mesh_node(parent, name, mesh, Transform3D.IDENTITY, mat)

## Tunnel through a building: side walls + ceiling following the track,
## with repeated lighting ribs. The massing around it is built separately
## from boxes that stop at the tunnel walls.
func tunnel(parent: Node, name: String, d0: float, d1: float, half_w := 36.0, ceil_h := 24.0,
		rib_step := 18.0, mat := "mid", strip_mat := "glow", rib_mat := "light") -> Node3D:
	var g := group(parent, name)
	ribbon_wall(g, "WallL", d0, d1, -half_w - 2.0, 4.0, -12.0, ceil_h + 6.0, mat)
	ribbon_wall(g, "WallR", d0, d1, half_w + 2.0, 4.0, -12.0, ceil_h + 6.0, mat)
	ribbon(g, "Ceiling", d0, d1, -half_w - 4.0, half_w + 4.0, ceil_h + 6.0, 6.0, mat)
	# ribs + light strips
	var d := d0 + rib_step * 0.5
	var i := 0
	var ribs := group(g, "Ribs")
	while d < d1 - 2.0:
		var c := center(d)
		var b := yaw_at(d)
		var r := right_flat(d)
		box(ribs, "Rib%02d" % i, Vector3(c.x, c.y + ceil_h - 1.0, c.z), Vector3(half_w * 2.0, 2.4, 2.0), b, rib_mat)
		for s: float in [-1.0, 1.0]:
			var p := c + r * s * (half_w - 1.0)
			p = c + r * s * (half_w + 1.0)
			box(ribs, "RibCol%02d%s" % [i, "L" if s < 0 else "R"], Vector3(p.x, c.y + ceil_h * 0.5 - 2.0, p.z), Vector3(2.0, ceil_h, 2.0), b, rib_mat)
		box(ribs, "Strip%02d" % i, Vector3(c.x, c.y + ceil_h - 2.4, c.z), Vector3(half_w * 1.5, 0.5, 0.8), b, strip_mat)
		d += rib_step
		i += 1
	return g
