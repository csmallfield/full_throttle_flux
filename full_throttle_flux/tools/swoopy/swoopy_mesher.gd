extends RefCounted
class_name SwoopyMesher
## Merges many greybox primitives (boxes, beams, tapered prisms) into ONE
## ArrayMesh with one surface per material, so a 600 m scaffold tower with a
## hundred members is a single draw call (plus its shadow pass).
##
##   var m := SwoopyMesher.new()
##   m.beam(a, b, 6.0, 6.0, "mid")
##   m.prism(base, 18.0, 9.0, 400.0, 8, "light")
##   m.commit(kit, parent, "Pier_0420", "pier_0420")
##
## Flat normals; winding is solved per face from the outward direction, so
## callers never have to think about vertex order.

var _st := {}      # material key -> SurfaceTool
var _n := {}       # material key -> vertex count
var boxes := 0

func _surf(mat: String) -> SurfaceTool:
	if not _st.has(mat):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_st[mat] = st
		_n[mat] = 0
	return _st[mat]

func is_empty() -> bool:
	return _st.is_empty()

## Quad a-b-c-d (any order around the loop) facing `out`.
func quad(mat: String, a: Vector3, b: Vector3, c: Vector3, d: Vector3, out: Vector3) -> void:
	var st := _surf(mat)
	var nrm := (b - a).cross(c - a)
	if nrm.length_squared() < 1e-10:
		nrm = (c - a).cross(d - a)
	if nrm.dot(out) > 0.0:     # Godot front faces are clockwise -> flip
		var t := b
		b = d
		d = t
	var fn := out.normalized()
	var i0: int = _n[mat]
	for p in [a, b, c, d]:
		st.set_normal(fn)
		st.add_vertex(p)
	for i in [0, 1, 2, 0, 2, 3]:
		st.add_index(i0 + i)
	_n[mat] = i0 + 4

## Hexahedron from 8 corners: bottom ring b0..b3, top ring t0..t3 (same order).
func hexa(mat: String, bot: Array, top: Array) -> void:
	var c := Vector3.ZERO
	for p in bot + top:
		c += p
	c /= 8.0
	for i in range(4):
		var j := (i + 1) % 4
		var a: Vector3 = bot[i]; var b: Vector3 = bot[j]; var e: Vector3 = top[j]; var f: Vector3 = top[i]
		quad(mat, a, b, e, f, (a + b + e + f) * 0.25 - c)
	quad(mat, bot[0], bot[1], bot[2], bot[3], (bot[0] + bot[2]) * 0.5 - c)
	quad(mat, top[0], top[1], top[2], top[3], (top[0] + top[2]) * 0.5 - c)
	boxes += 1

## Box by centre / size / basis.
func box(c: Vector3, size: Vector3, b: Basis, mat: String) -> void:
	var x := b.x.normalized() * size.x * 0.5
	var y := b.y.normalized() * size.y * 0.5
	var z := b.z.normalized() * size.z * 0.5
	hexa(mat, [c - x - y - z, c + x - y - z, c + x - y + z, c - x - y + z],
		[c - x + y - z, c + x + y - z, c + x + y + z, c - x + y + z])

## Box standing on a base point (bottom centre), up to absolute top_y.
func block(base: Vector3, w: float, dpt: float, top_y: float, b: Basis, mat: String) -> void:
	box(base + Vector3.UP * (top_y - base.y) * 0.5, Vector3(w, top_y - base.y, dpt), b, mat)

## Tapered rectangular shaft: footprint (w0 x d0) at base.y -> (w1 x d1) at top_y.
func shaft(base: Vector3, w0: float, d0: float, w1: float, d1: float, top_y: float, b: Basis, mat: String) -> void:
	var x := b.x.normalized()
	var z := b.z.normalized()
	var top := Vector3(base.x, top_y, base.z)
	var ring := func(c: Vector3, w: float, dd: float) -> Array:
		return [c - x * w * 0.5 - z * dd * 0.5, c + x * w * 0.5 - z * dd * 0.5,
			c + x * w * 0.5 + z * dd * 0.5, c - x * w * 0.5 + z * dd * 0.5]
	hexa(mat, ring.call(base, w0, d0), ring.call(top, w1, d1))

## Straight member from a to b with a w x h section. `up` orients the section.
func beam(a: Vector3, b: Vector3, w: float, h: float, mat: String, up := Vector3.UP) -> void:
	var ax := b - a
	var L := ax.length()
	if L < 0.01:
		return
	var f := ax / L
	var u := up - f * up.dot(f)
	if u.length_squared() < 1e-4:
		u = Vector3.RIGHT - f * f.x
	u = u.normalized()
	var s := f.cross(u).normalized()
	box((a + b) * 0.5, Vector3(w, h, L), Basis(s, u, f), mat)

## Tapered n-gon prism (r0 at base -> r1 at base + axis*h). r1 = 0 makes a cone.
func prism(base: Vector3, r0: float, r1: float, h: float, segs: int, mat: String, b := Basis.IDENTITY, caps := true) -> void:
	var ax := b.y.normalized()
	var ux := b.x.normalized()
	var uz := b.z.normalized()
	var top := base + ax * h
	var pts0 := []
	var pts1 := []
	for i in range(segs):
		var a := TAU * (float(i) + 0.5) / segs
		var dir := ux * cos(a) + uz * sin(a)
		pts0.append(base + dir * r0)
		pts1.append(top + dir * r1)
	for i in range(segs):
		var j := (i + 1) % segs
		var mid := (float(i) + 1.0) / segs * TAU
		var out := (ux * cos(mid) + uz * sin(mid))
		if r1 < 0.01:
			# cone: triangle as a degenerate quad
			quad(mat, pts0[i], pts0[j], top, top + (pts0[i] - pts0[j]) * 0.0001, out)
		else:
			quad(mat, pts0[i], pts0[j], pts1[j], pts1[i], out)
	if caps:
		_fan(mat, base, pts0, -ax)
		if r1 >= 0.01:
			_fan(mat, top, pts1, ax)
	boxes += 1

func _fan(mat: String, c: Vector3, ring: Array, out: Vector3) -> void:
	for i in range(ring.size()):
		var j := (i + 1) % ring.size()
		quad(mat, c, ring[i], ring[j], c + (ring[j] - c) * 0.0001 + (ring[i] - c) * 0.0001, out)

## Lattice truss between two points: 2 chords (depth apart, vertical),
## posts + alternating diagonals every `panel` m. For bridges between piers.
func truss(a: Vector3, b: Vector3, depth: float, chord: float, panel: float, mat: String) -> void:
	var L := a.distance_to(b)
	var n := maxi(2, int(round(L / panel)))
	var dn := Vector3.DOWN * depth
	beam(a, b, chord, chord, mat)
	beam(a + dn, b + dn, chord, chord, mat)
	for i in range(n + 1):
		var p := a.lerp(b, float(i) / n)
		beam(p, p + dn, chord * 0.7, chord * 0.7, mat)
		if i < n:
			var q := a.lerp(b, float(i + 1) / n)
			if i % 2 == 0:
				beam(p, q + dn, chord * 0.55, chord * 0.55, mat)
			else:
				beam(p + dn, q, chord * 0.55, chord * 0.55, mat)

func commit(kit: UtopiaKit, parent: Node, name: String, tag: String, shadows := true) -> MeshInstance3D:
	if _st.is_empty():
		return null
	var mesh := ArrayMesh.new()
	for mat in _st:
		var st: SurfaceTool = _st[mat]
		st.commit(mesh)
		mesh.surface_set_material(mesh.get_surface_count() - 1, kit.mats[mat])
	var saved := kit._save_mesh(mesh, tag)
	var mi := MeshInstance3D.new()
	mi.name = name
	mi.mesh = saved
	if not shadows:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	_st.clear()
	_n.clear()
	return mi
