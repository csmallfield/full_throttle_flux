extends RefCounted
## Greybox greeble meshes. Each is saved as its own .tres so a detailed model
## can replace it 1:1. CONVENTION for every greeble:
##   origin = attachment point on its rail
##   +Y = rail up (road normal), -Z = direction of travel,
##   +X = toward the track centre (side-mounted pieces)
## Units: metres. Surface materials are the shared greybox materials.

const DIR := "res://scenes/tracks/utopia/greebles"

var mats := {}
var _st := {}

func _init() -> void:
	for m in ["light", "mid", "dark", "accent", "glow", "glow_cool", "floor"]:
		mats[m] = load("res://scenes/tracks/utopia/materials/greybox_%s.tres" % m)

func _begin() -> void:
	_st = {}

## Axis-aligned box from min corner to max corner (local coords).
func box(mn: Vector3, mx: Vector3, mat: String) -> void:
	if not _st.has(mat):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_st[mat] = st
	var st: SurfaceTool = _st[mat]
	var c := [Vector3(mn.x, mn.y, mn.z), Vector3(mx.x, mn.y, mn.z), Vector3(mx.x, mx.y, mn.z), Vector3(mn.x, mx.y, mn.z),
		Vector3(mn.x, mn.y, mx.z), Vector3(mx.x, mn.y, mx.z), Vector3(mx.x, mx.y, mx.z), Vector3(mn.x, mx.y, mx.z)]
	var faces := [[0, 3, 2, 1, Vector3.FORWARD], [4, 5, 6, 7, Vector3.BACK], [0, 4, 7, 3, Vector3.LEFT],
		[1, 2, 6, 5, Vector3.RIGHT], [3, 7, 6, 2, Vector3.UP], [0, 1, 5, 4, Vector3.DOWN]]
	for f in faces:
		st.set_normal(f[4])
		for idx in [0, 2, 1, 0, 3, 2]:
			st.add_vertex(c[f[idx]])

## Oriented box: unit cube transformed by xf scaled to size (centre = xf.origin).
func tbox(xf: Transform3D, size: Vector3, mat: String) -> void:
	if not _st.has(mat):
		var st0 := SurfaceTool.new()
		st0.begin(Mesh.PRIMITIVE_TRIANGLES)
		_st[mat] = st0
	var st: SurfaceTool = _st[mat]
	var h := size * 0.5
	var c := []
	for v in [Vector3(-1, -1, -1), Vector3(1, -1, -1), Vector3(1, 1, -1), Vector3(-1, 1, -1),
			Vector3(-1, -1, 1), Vector3(1, -1, 1), Vector3(1, 1, 1), Vector3(-1, 1, 1)]:
		c.append(xf * (v * h))
	var faces := [[0, 3, 2, 1, Vector3.FORWARD], [4, 5, 6, 7, Vector3.BACK], [0, 4, 7, 3, Vector3.LEFT],
		[1, 2, 6, 5, Vector3.RIGHT], [3, 7, 6, 2, Vector3.UP], [0, 1, 5, 4, Vector3.DOWN]]
	for f in faces:
		st.set_normal((xf.basis * f[4]).normalized())
		for idx in [0, 2, 1, 0, 3, 2]:
			st.add_vertex(c[f[idx]])

## Box by centre + size.
func cbox(c: Vector3, s: Vector3, mat: String) -> void:
	box(c - s * 0.5, c + s * 0.5, mat)

func _save(name: String) -> void:
	var mesh := ArrayMesh.new()
	for m in _st:
		var st: SurfaceTool = _st[m]
		st.commit(mesh)
		mesh.surface_set_material(mesh.get_surface_count() - 1, mats[m])
	ResourceSaver.save(mesh, "%s/gb_%s.tres" % [DIR, name])

func build_all() -> void:
	# --- ROAD SURFACE (all under 0.13 m: ships hover at ~2 m) ---------------
	_begin()   # deck plate: bolted service panel
	box(Vector3(-1.2, 0.0, -2.6), Vector3(1.2, 0.06, 2.6), "dark")
	box(Vector3(-0.9, 0.06, -2.2), Vector3(0.9, 0.08, -2.05), "mid")
	box(Vector3(-0.9, 0.06, 2.05), Vector3(0.9, 0.08, 2.2), "mid")
	for z: float in [-2.4, 2.4]:
		for x: float in [-1.0, 1.0]:
			cbox(Vector3(x, 0.08, z), Vector3(0.18, 0.04, 0.18), "light")
	_save("deck_plate")
	_begin()   # deck vent: frame + slats
	box(Vector3(-0.9, 0.0, -1.6), Vector3(0.9, 0.08, 1.6), "dark")
	for i in range(7):
		var z := -1.35 + i * 0.45
		cbox(Vector3(0, 0.1, z), Vector3(1.5, 0.05, 0.16), "mid")
	_save("deck_vent")
	_begin()   # stud: lane light
	box(Vector3(-0.22, 0.0, -0.45), Vector3(0.22, 0.04, 0.45), "dark")
	box(Vector3(-0.12, 0.04, -0.35), Vector3(0.12, 0.07, 0.35), "glow_cool")
	_save("stud")
	# --- INNER WALL FACE (protrude <= 0.16 m into the corridor) ---------------
	_begin()   # wall panel with louvres
	box(Vector3(0.0, -1.2, -2.2), Vector3(0.1, 1.2, 2.2), "mid")
	for i in range(4):
		var y := -0.75 + i * 0.5
		box(Vector3(0.1, y - 0.08, -1.9), Vector3(0.16, y + 0.08, 1.9), "dark")
	_save("wall_panel")
	_begin()   # wall light dash
	box(Vector3(0.0, -0.18, -1.6), Vector3(0.05, 0.18, 1.6), "dark")
	box(Vector3(0.05, -0.1, -1.45), Vector3(0.1, 0.1, 1.45), "glow_cool")
	_save("wall_dash")
	# --- WALL TOP ------------------------------------------------------------
	_begin()   # bollard
	box(Vector3(-0.8, 0.0, -0.8), Vector3(0.8, 1.6, 0.8), "light")
	box(Vector3(-0.85, 1.0, -0.85), Vector3(0.85, 1.2, 0.85), "dark")
	box(Vector3(-0.55, 1.6, -0.55), Vector3(0.55, 2.3, 0.55), "mid")
	_save("bollard")
	_begin()   # lamp pole with an arm reaching over the track (+X)
	box(Vector3(-0.6, 0.0, -0.6), Vector3(0.6, 0.6, 0.6), "mid")
	box(Vector3(-0.22, 0.6, -0.22), Vector3(0.22, 10.5, 0.22), "light")
	box(Vector3(-0.22, 10.2, -0.18), Vector3(3.6, 10.6, 0.18), "light")
	box(Vector3(2.6, 9.95, -0.3), Vector3(3.8, 10.2, 0.3), "mid")
	box(Vector3(2.7, 9.9, -0.22), Vector3(3.7, 9.95, 0.22), "glow")
	_save("lamp_pole")
	# --- OUTSIDE THE WALL -----------------------------------------------------
	_begin()   # fin: rhythmic blade standing just outside the wall
	box(Vector3(-0.6, 0.0, -2.0), Vector3(0.6, 13.0, 2.0), "light")
	box(Vector3(-0.4, 13.0, -1.3), Vector3(0.4, 20.0, 1.3), "light")
	box(Vector3(-0.65, 11.0, -2.05), Vector3(0.65, 11.7, 2.05), "dark")
	box(Vector3(0.4, 17.8, -0.5), Vector3(0.48, 19.2, 0.5), "glow_cool")
	_save("fin")
	# --- SPANNING THE TRACK ---------------------------------------------------
	_begin()   # gantry: legs on both wall tops, beam + sign at ~15 m
	for x: float in [-24.8, 24.8]:
		box(Vector3(x - 0.8, 4.0, -0.8), Vector3(x + 0.8, 17.0, 0.8), "light")
		box(Vector3(x - 1.2, 4.0, -1.2), Vector3(x + 1.2, 5.0, 1.2), "mid")
	box(Vector3(-26.0, 15.6, -0.9), Vector3(26.0, 17.6, 0.9), "light")
	box(Vector3(-11.0, 13.4, -0.4), Vector3(11.0, 15.6, 0.4), "dark")
	box(Vector3(-10.0, 13.5, 0.4), Vector3(10.0, 13.65, 0.45), "glow_cool")
	_save("gantry")

	build_zone_kit()

## Second kit for the zoned styles (v3).
func build_zone_kit() -> void:
	# --- GROUND (<= 0.1 m) ---
	_begin()   # seam: expansion joint across the whole road (place centred)
	box(Vector3(-17.0, 0.0, -0.35), Vector3(17.0, 0.03, 0.35), "dark")
	box(Vector3(-17.0, 0.0, -0.45), Vector3(17.0, 0.05, -0.35), "mid")
	box(Vector3(-17.0, 0.0, 0.35), Vector3(17.0, 0.05, 0.45), "mid")
	_save("seam")
	_begin()   # floor chevron: arrow pointing down-track (-Z)
	for sgn: float in [-1.0, 1.0]:
		tbox(Transform3D(Basis(Vector3.UP, sgn * deg_to_rad(-40.0)), Vector3(sgn * 0.9, 0.04, 0.6)), Vector3(2.6, 0.06, 0.45), "glow_cool")
	_save("chevron_floor")
	_begin()   # gutter grate along the road edge
	box(Vector3(-0.7, 0.0, -3.0), Vector3(0.7, 0.07, 3.0), "mid")
	for i in range(11):
		var z := -2.5 + i * 0.5
		box(Vector3(-0.55, 0.07, z - 0.1), Vector3(0.55, 0.1, z + 0.1), "dark")
	_save("grate")
	_begin()   # hazard edge: diagonal tiles (light/dark) along the gutter
	box(Vector3(-0.5, 0.0, -3.0), Vector3(0.5, 0.02, 3.0), "dark")
	for i in range(6):
		tbox(Transform3D(Basis(Vector3.UP, deg_to_rad(45.0)), Vector3(0, 0.03, -2.5 + i * 1.0)), Vector3(0.25, 0.03, 0.9), "light")
	_save("hazard_edge")
	# --- WALL FACE (x >= 0, <= 0.16 into the corridor; rail is road + 3 m) ---
	_begin()   # rib / pilaster
	box(Vector3(0.0, -3.0, -0.4), Vector3(0.14, 1.5, 0.4), "light")
	box(Vector3(0.0, 1.2, -0.55), Vector3(0.16, 1.5, 0.55), "mid")
	_save("rib")
	_begin()   # pipe run, authored 1 m long: stretched to its slot
	box(Vector3(0.02, -1.95, -0.5), Vector3(0.14, -1.75, 0.5), "mid")
	box(Vector3(0.02, -1.6, -0.5), Vector3(0.12, -1.45, 0.5), "dark")
	box(Vector3(0.0, -2.05, -0.5), Vector3(0.03, -1.35, 0.5), "dark")
	_save("pipe_run")
	_begin()   # lit sign panel
	box(Vector3(0.0, -1.2, -3.0), Vector3(0.1, 1.2, 3.0), "dark")
	box(Vector3(0.1, 0.95, -2.8), Vector3(0.13, 1.05, 2.8), "glow")
	box(Vector3(0.1, -1.05, -2.8), Vector3(0.13, -0.95, 2.8), "glow")
	box(Vector3(0.1, -0.6, -2.4), Vector3(0.12, 0.6, -0.6), "mid")
	_save("ad_panel")
	_begin()   # turn chevron board (faces +X, arrow points down-track)
	box(Vector3(0.0, -1.1, -1.6), Vector3(0.08, 1.1, 1.6), "dark")
	for sgn: float in [-1.0, 1.0]:
		tbox(Transform3D(Basis(Vector3.RIGHT, sgn * deg_to_rad(40.0)), Vector3(0.11, sgn * 0.42, 0.0)), Vector3(0.04, 1.1, 0.32), "glow")
	_save("chevron_sign")
	_begin()   # right-hand variant: same board, arrow toward +Z (see UtopiaGreebleRule.mesh_right)
	box(Vector3(0.0, -1.1, -1.6), Vector3(0.08, 1.1, 1.6), "dark")
	for sgn: float in [-1.0, 1.0]:
		tbox(Transform3D(Basis(Vector3.RIGHT, -sgn * deg_to_rad(40.0)), Vector3(0.11, sgn * 0.42, 0.0)), Vector3(0.04, 1.1, 0.32), "glow")
	_save("chevron_sign_r")
	# --- WALL TOP ---
	_begin()   # railing segment, authored 6 m (stretched to slot)
	for i in range(3):
		var z := -2.0 + i * 2.0
		box(Vector3(-0.08, 0.0, z - 0.08), Vector3(0.08, 1.15, z + 0.08), "light")
	box(Vector3(-0.07, 1.05, -3.0), Vector3(0.07, 1.2, 3.0), "light")
	box(Vector3(-0.04, 0.5, -3.0), Vector3(0.04, 0.58, 3.0), "mid")
	_save("railing")
	_begin()   # planter with greybox shrub
	box(Vector3(-1.2, 0.0, -2.0), Vector3(1.2, 0.9, 2.0), "light")
	box(Vector3(-1.0, 0.9, -1.8), Vector3(1.0, 1.6, 1.8), "floor")
	box(Vector3(-0.6, 1.6, -1.2), Vector3(0.7, 2.3, 1.0), "floor")
	_save("planter")
	_begin()   # antenna mast
	box(Vector3(-0.5, 0.0, -0.5), Vector3(0.5, 0.5, 0.5), "mid")
	box(Vector3(-0.08, 0.5, -0.08), Vector3(0.08, 7.0, 0.08), "light")
	for y: float in [3.0, 4.6, 6.2]:
		box(Vector3(-0.05, y, -0.8), Vector3(0.05, y + 0.08, 0.8), "light")
	box(Vector3(-0.12, 6.9, -0.12), Vector3(0.12, 7.15, 0.12), "glow")
	_save("antenna")
	_begin()   # sensor pod on a stem, lens facing the track
	box(Vector3(-0.15, 0.0, -0.15), Vector3(0.15, 1.4, 0.15), "mid")
	box(Vector3(-0.5, 1.4, -0.45), Vector3(0.5, 2.1, 0.45), "light")
	box(Vector3(0.5, 1.55, -0.25), Vector3(0.6, 1.95, 0.25), "dark")
	_save("sensor_pod")
	# --- OUTSIDE (x < 0 is outward) ---
	_begin()   # structural pylon pair with cross bars
	for x: float in [-0.9, -4.1]:
		box(Vector3(x - 0.45, -8.0, -0.45), Vector3(x + 0.45, 20.0, 0.45), "light")
	for y: float in [6.0, 13.0, 19.0]:
		box(Vector3(-4.4, y, -0.3), Vector3(-0.6, y + 0.8, 0.3), "mid")
	box(Vector3(-1.3, 18.2, -0.2), Vector3(-0.5, 18.5, 0.2), "glow_cool")
	_save("pylon_tall")
	_begin()   # mast with pennant
	box(Vector3(-1.4, -6.0, -0.15), Vector3(-1.1, 18.0, 0.15), "light")
	box(Vector3(-1.25, 13.0, 0.15), Vector3(-1.2, 17.5, 2.6), "accent")
	box(Vector3(-1.5, 17.9, -0.25), Vector3(-1.0, 18.3, 0.25), "glow")
	_save("mast")
	# --- OVERHEAD (centred on the road, legs on the wall tops) ---
	_begin()   # truss bridge
	for x: float in [-24.8, 24.8]:
		box(Vector3(x - 0.6, 4.0, -0.6), Vector3(x + 0.6, 18.2, 0.6), "mid")
	box(Vector3(-25.5, 17.2, -0.6), Vector3(25.5, 18.2, 0.6), "light")
	box(Vector3(-25.5, 15.2, -0.5), Vector3(25.5, 15.8, 0.5), "light")
	for i in range(10):
		var x := -22.5 + i * 5.0
		var sgn := 1.0 if i % 2 == 0 else -1.0
		tbox(Transform3D(Basis(Vector3.BACK, sgn * deg_to_rad(38.0)), Vector3(x, 16.6, 0.0)), Vector3(0.3, 2.6, 0.4), "mid")
	_save("truss")
	_begin()   # district portal: thick frame with a light band underneath
	for x: float in [-26.5, 26.5]:
		box(Vector3(x - 1.6, 4.0, -1.6), Vector3(x + 1.6, 23.0, 1.6), "light")
	box(Vector3(-28.0, 19.5, -2.2), Vector3(28.0, 24.0, 2.2), "light")
	box(Vector3(-24.0, 19.3, -1.0), Vector3(24.0, 19.5, 1.0), "glow_cool")
	box(Vector3(-28.4, 21.0, 2.2), Vector3(28.4, 22.6, 2.4), "dark")
	_save("portal")
