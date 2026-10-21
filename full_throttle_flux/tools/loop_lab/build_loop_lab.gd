extends SceneTree
## Builds res://scenes/tracks/loop_lab.tscn -- a short greybox test circuit with
## a vertical loop and a 360-degree barrel roll, plus the MagneticTrack zones
## that hold ships to the road through both. (v30)
##
##   godot --headless --path . -s res://tools/loop_lab/build_loop_lab.gd
##
## Layout (top view, start line at the origin heading -Z):
##
##   start -> straight -> LOOP (teardrop, steps 90 m right) -> straight
##   -> banked 180 right -> straight with BARREL ROLL -> banked 180 right
##   -> closing straight (starting grid) -> start
##
## Everything is generated from a "turtle" that integrates curvature, so the
## lap closes exactly and every curvature change ramps in smoothly (sin^2
## curvature profiles; no instant g onset entering the loop or the turns).
##
## Road orientation is authored as a desired up vector per sample. Curve3D
## tilts are then solved against Godot's own baked (rotation-minimising) up
## vectors, so the loop's twist and the roll's full turn come out exactly and
## the CSG road, the ship's spline queries and the respawn frames all agree.
##
## The curve is OPEN with its last point on top of its first. A closed curve
## can't carry a barrel roll: tilts interpolate linearly around the closing
## segment, so the lap's net +360 degrees of tilt would unwind there as a
## second roll. With coincident ends the full turn is geometrically invisible.

const OUT_SCENE := "res://scenes/tracks/loop_lab.tscn"
const ROAD_MAT := "res://shaders/resources/grid_material.tres"
const MB_SCRIPT := "res://scripts/rendering/motion_blur_effect.gd"

# ---- layout parameters (metres) --------------------------------------------
const START_STRAIGHT := 260.0
const LOOP_LENGTH := 820.0        # in-plane arc length; top radius = L / 4pi = 65 m
const LOOP_SHIFT := 90.0          # sideways step so the exit clears the entry
const MID_STRAIGHT := 260.0
const TURN1_LENGTH := 420.0       # 180 deg, min radius = L / 2pi = 67 m
const TURN_BANK_DEG := 18.0
## One full roll, centred on the return leg. Peak roll rate is 1.5 * 360 / L
## deg per metre (smoothstep): 800 m gives ~0.68 deg/m, ~80 deg/s at full
## speed. 460 m with smootherstep (176 deg/s) was measured to throw an
## off-centre ship into the wall: the road surface 15 m off centre pitches
## ~24 deg and the rotating frame pushes the ship outward.
const ROLL_LENGTH := 800.0
const CLOSING_TARGET := 300.0     # closing straight (holds the grid)
const START_LINE_AT := 30.0       # line distance into the lap
const GRID_SLOTS := 8
const GRID_SPACING := 22.0
const GRID_LATERAL := 8.0

# ---- cross-sections (x across, y up; road surface at y = 0) ----------------
## Road surface is subdivided across its width. A twisting road is a ruled
## surface: one 39 m quad per ring splits into two triangles whose normals
## zigzag ~26 deg in pitch through the barrel roll (measured), which the hover
## ray reads as a washboard. 3 m strips bring that down to ~2 deg.
const ROAD_HALF := 19.5
const ROAD_STRIP := 3.0
const WALL_L_POLY := [Vector2(28.5, 8.5), Vector2(23.5, 8.4), Vector2(21.1, 6.5), Vector2(21.1, -2.0), Vector2(28.6, -2.0)]
const WALL_R_POLY := [Vector2(-21.1, 6.5), Vector2(-23.5, 8.4), Vector2(-28.5, 8.5), Vector2(-28.6, -2.0), Vector2(-21.1, -2.0)]

const DS := 0.05                  # integration step

# Samples emitted by the turtle.
var P: Array[Vector3] = []        # position
var T: Array[Vector3] = []        # unit tangent
var U: Array[Vector3] = []        # desired road up (unit, perpendicular to T)
var S: Array[float] = []          # true 3D arc length at sample
var marks := {}                   # name -> arc length

# Turtle state.
var pos := Vector3.ZERO
var fwd := Vector3.FORWARD        # -Z
var arc := 0.0


func _initialize() -> void:
	_build_centerline()
	var curve := _build_curve()
	if curve == null:
		quit(1)
		return
	var root := _build_scene(curve)
	_save(root)
	quit(0)


# =============================================================================
# CENTRE LINE
# =============================================================================

func _right() -> Vector3:
	return fwd.cross(Vector3.UP).normalized()

func _emit(t: Vector3, up: Vector3) -> void:
	P.append(pos)
	T.append(t.normalized())
	U.append(up.slide(t.normalized()).normalized())
	S.append(arc)

## Straight, optionally rolling the road `turns` full turns (+ = to the left).
func _straight(length: float, every: float, turns: float = 0.0) -> void:
	var n := int(ceil(length / every))
	var step := length / n
	for i in n:
		var s0 := i * step
		var a := TAU * turns * _smoothstep01(s0 / length)
		_emit(fwd, Vector3.UP.rotated(fwd, -a))
		pos += fwd * step
		arc += step

## Yaw turn with sin^2 curvature. dpsi > 0 turns left. Banks into the turn.
func _turn(length: float, dpsi: float, bank_deg: float, every: float) -> void:
	var n := int(round(length / DS))
	var emit_every := int(round(every / DS))
	var kmax := dpsi * 2.0 / length
	var bank := deg_to_rad(bank_deg) * signf(-dpsi)   # right turn -> lean right
	for i in n:
		var s := (i + 0.5) * DS
		var shape := pow(sin(PI * s / length), 2.0)
		if i % emit_every == 0:
			var lean := bank * pow(sin(PI * (i * DS) / length), 2.0)
			_emit(fwd, Vector3.UP * cos(lean) + _right() * sin(lean))
		fwd = fwd.rotated(Vector3.UP, kmax * shape * DS).normalized()
		pos += fwd * DS
		arc += DS

## Teardrop vertical loop, stepping `shift` metres to the right.
func _loop(length: float, shift: float, every: float) -> void:
	var f0 := fwd
	var u0 := Vector3.UP
	var r0 := _right()
	var kmax := 4.0 * PI / length
	var phi := 0.0
	var n := int(round(length / DS))
	var emit_every := int(round(every / DS))
	for i in n:
		var s := (i + 0.5) * DS
		var lat_rate := shift * (1.0 - cos(TAU * (i * DS) / length)) / length
		var t := f0 * cos(phi) + u0 * sin(phi) + r0 * lat_rate
		if i % emit_every == 0:
			var inward := -f0 * sin(phi) + u0 * cos(phi)
			_emit(t, inward)
		phi += kmax * pow(sin(PI * s / length), 2.0) * DS
		var step := f0 * cos(phi) + u0 * sin(phi) + r0 * (shift * (1.0 - cos(TAU * s / length)) / length)
		pos += step * DS
		arc += step.length() * DS
	fwd = f0

func _build_centerline() -> void:
	# Turn displacements depend only on length (fixed shape), so solve turn 2
	# for lateral closure and the closing straight for longitudinal closure.
	var d1 := _turn_displacement(TURN1_LENGTH)
	var lat_per_m: float = d1.y / TURN1_LENGTH
	var turn2_len: float = (d1.y + LOOP_SHIFT) / lat_per_m
	
	_straight(START_STRAIGHT, 10.0)
	marks["loop_start"] = arc
	_loop(LOOP_LENGTH, LOOP_SHIFT, 4.0)
	marks["loop_end"] = arc
	_straight(MID_STRAIGHT, 10.0)
	_turn(TURN1_LENGTH, -PI, TURN_BANK_DEG, 8.0)
	# Return leg long enough that the closing straight comes out at
	# CLOSING_TARGET (heading +Z now; turn 2 adds its own forward drift).
	var d2 := _turn_displacement(turn2_len)
	var ret: float = -pos.z + CLOSING_TARGET - d2.x
	var lead: float = (ret - ROLL_LENGTH) * 0.5
	if lead < 100.0:
		push_error("return leg too short for the roll")
	_straight(lead, 10.0)
	marks["roll_start"] = arc
	_straight(ROLL_LENGTH, 4.0, 1.0)
	marks["roll_end"] = arc
	_straight(ret - ROLL_LENGTH - lead, 10.0)
	_turn(turn2_len, -PI, TURN_BANK_DEG, 8.0)
	marks["closing_start"] = arc
	
	# Closing straight back to the origin (heading -Z, so pos.z > 0 here).
	var closing := pos.z
	var lateral_err := pos.x
	print("LOOPLAB turn2 %.1f m, closing straight %.1f m, lateral closure error %.3f m"
			% [turn2_len, closing, lateral_err])
	if closing < GRID_SLOTS * GRID_SPACING + 60.0:
		push_error("closing straight too short for the grid")
	pos.x = lerpf(pos.x, 0.0, 1.0)   # absorb the (tiny) integration error
	_straight(closing, 10.0)
	# Final point exactly on the first.
	_emit(fwd, Vector3.UP)
	P[P.size() - 1] = P[0]
	marks["length"] = arc
	print("LOOPLAB centre line %.1f m, %d samples, end gap %.4f m" % [arc, P.size(), pos.distance_to(P[0])])

func _turn_displacement(length: float) -> Vector2:
	# (forward, lateral toward the turn) for a 180 sin^2 turn
	var psi := 0.0
	var f := 0.0
	var l := 0.0
	var n := int(round(length / DS))
	var kmax := PI * 2.0 / length
	for i in n:
		var s := (i + 0.5) * DS
		psi += kmax * pow(sin(PI * s / length), 2.0) * DS
		f += cos(psi) * DS
		l += sin(psi) * DS
	return Vector2(f, l)

static func _smoothstep01(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)

static func _smootherstep(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return x * x * x * (x * (x * 6.0 - 15.0) + 10.0)


# =============================================================================
# CURVE + TILTS
# =============================================================================

func _build_curve() -> Curve3D:
	var c := Curve3D.new()
	c.closed = false
	c.bake_interval = 0.2
	c.up_vector_enabled = true
	var n := P.size()
	for i in n:
		var prev_len := P[i].distance_to(P[i - 1]) if i > 0 else P[1].distance_to(P[0])
		var next_len := P[i].distance_to(P[i + 1]) if i < n - 1 else prev_len
		c.add_point(P[i], -T[i] * prev_len / 3.0, T[i] * next_len / 3.0)
	
	# Baked offset of every control point (walk the bake, monotonically).
	var offs := PackedFloat32Array()
	offs.resize(n)
	offs[0] = 0.0
	var baked_len := c.get_baked_length()
	var cursor := 0.0
	for i in range(1, n):
		cursor = _find_offset_after(c, P[i], cursor, baked_len)
		offs[i] = cursor
	offs[n - 1] = baked_len
	
	# Solve tilts against the baked RMF up vectors, then unwrap.
	var raw := PackedFloat32Array()
	raw.resize(n)
	for i in n:
		var xf := c.sample_baked_with_rotation(offs[i], true, false)
		var t: Vector3 = -xf.basis.z.normalized()
		if t.dot(T[i]) < 0.0:
			t = -t
		var up0 := c.sample_baked_up_vector(offs[i], false).slide(t).normalized()
		var want := U[i].slide(t).normalized()
		raw[i] = atan2(up0.cross(want).dot(t), up0.dot(want))
	var acc := raw[0]
	c.set_point_tilt(0, acc)
	for i in range(1, n):
		var d := wrapf(raw[i] - raw[i - 1], -PI, PI)
		acc += d
		c.set_point_tilt(i, acc)
	
	# Godot's tilt sign convention: verify, flip if needed.
	if _tilt_error(c, offs) > 0.2:
		for i in n:
			c.set_point_tilt(i, -c.get_point_tilt(i))
	var err := _tilt_error(c, offs)
	print("LOOPLAB tilt solve: max up error at control points %.3f deg, total tilt %.1f deg"
			% [rad_to_deg(err), rad_to_deg(c.get_point_tilt(n - 1) - c.get_point_tilt(0))])
	
	# Also check between control points (interpolation quality).
	var worst := 0.0
	for i in range(n - 1):
		var mid := (offs[i] + offs[i + 1]) * 0.5
		var up := c.sample_baked_up_vector(mid, true)
		var want := (U[i] + U[i + 1]).normalized()
		worst = maxf(worst, up.angle_to(want))
	print("LOOPLAB mid-segment up error max %.3f deg" % rad_to_deg(worst))
	if rad_to_deg(err) > 1.0:
		push_error("tilt solve failed")
		return null
	
	# Record zone distances on the baked curve.
	for k in ["loop_start", "loop_end", "roll_start", "roll_end", "closing_start"]:
		var idx := _sample_index_at_arc(marks[k])
		marks[k + "_baked"] = offs[idx]
	marks["baked_length"] = baked_len
	print("LOOPLAB baked length %.1f m; loop %.0f-%.0f, roll %.0f-%.0f" % [baked_len,
			marks["loop_start_baked"], marks["loop_end_baked"],
			marks["roll_start_baked"], marks["roll_end_baked"]])
	return c

func _tilt_error(c: Curve3D, offs: PackedFloat32Array) -> float:
	var e := 0.0
	for i in P.size():
		e = maxf(e, c.sample_baked_up_vector(offs[i], true).angle_to(U[i]))
	return e

func _find_offset_after(c: Curve3D, p: Vector3, from: float, length: float) -> float:
	# Coarse-to-fine search forward from `from` (control points are < 12 m apart).
	var best := from
	var best_d := INF
	var s := from
	while s <= minf(from + 30.0, length):
		var d := c.sample_baked(s, true).distance_squared_to(p)
		if d < best_d:
			best_d = d
			best = s
		s += 0.25
	var lo := maxf(best - 0.25, 0.0)
	var hi := minf(best + 0.25, length)
	for i in 20:
		var a := lo + (hi - lo) / 3.0
		var b := hi - (hi - lo) / 3.0
		if c.sample_baked(a, true).distance_squared_to(p) < c.sample_baked(b, true).distance_squared_to(p):
			hi = b
		else:
			lo = a
	return (lo + hi) * 0.5

func _sample_index_at_arc(a: float) -> int:
	var best := 0
	for i in S.size():
		if absf(S[i] - a) < absf(S[best] - a):
			best = i
	return best


# =============================================================================
# SCENE
# =============================================================================

func _build_scene(curve: Curve3D) -> Node3D:
	var root := Node3D.new()
	root.name = "LoopLab"
	
	_add_environment(root)
	
	var spline := Path3D.new()
	spline.name = "MainSpline"
	spline.curve = curve
	root.add_child(spline)
	
	var road_mat: Material = load(ROAD_MAT)
	_add_csg(spline, "groundGeo", _road_poly(), 0.5, 1, road_mat, 100.0)
	_add_csg(spline, "wallLeftGeo", WALL_L_POLY, 1.0, 4, road_mat, 50.0)
	_add_csg(spline, "wallRightGeo", WALL_R_POLY, 1.0, 4, road_mat, 50.0)
	
	_add_start(root, curve)
	_add_magnetic(root)
	_add_floor(root)
	return root

func _road_poly() -> Array:
	var pts := [Vector2(ROAD_HALF + 2.0, 0.9)]
	var n := int(ceil(2.0 * ROAD_HALF / ROAD_STRIP))
	for i in n + 1:
		pts.append(Vector2(ROAD_HALF - 2.0 * ROAD_HALF * i / n, 0.0))
	pts.append(Vector2(-ROAD_HALF - 2.0, 0.9))
	pts.append(Vector2(-ROAD_HALF - 2.0, -2.0))
	pts.append(Vector2(ROAD_HALF + 2.0, -2.0))
	return pts

func _add_csg(parent: Node, n: String, poly: Array, interval: float, layer: int, mat: Material, u_dist: float) -> void:
	var g := CSGPolygon3D.new()
	g.name = n
	g.use_collision = true
	g.collision_layer = layer
	g.polygon = PackedVector2Array(poly)
	g.mode = CSGPolygon3D.MODE_PATH
	g.path_node = NodePath("..")
	g.path_interval_type = CSGPolygon3D.PATH_INTERVAL_DISTANCE
	g.path_interval = interval
	# 0, not the 1.0 used elsewhere: simplification merges collinear segments,
	# and the barrel roll is a straight line whose road ROTATES -- with
	# simplification on, the roll would be merged away.
	g.path_simplify_angle = 0.0
	g.path_rotation = CSGPolygon3D.PATH_ROTATION_PATH_FOLLOW
	g.path_rotation_accurate = true
	g.path_local = false
	g.path_continuous_u = true
	g.path_u_distance = u_dist
	g.path_joined = false   # ends coincide (see header)
	g.material = mat
	parent.add_child(g)

func _frame_at(curve: Curve3D, d: float) -> Transform3D:
	var xf := curve.sample_baked_with_rotation(d, true, true)
	var f: Vector3 = -xf.basis.z.normalized()
	var ahead := curve.sample_baked(minf(d + 1.0, curve.get_baked_length()), true)
	if f.dot(ahead - xf.origin) < 0.0:
		f = -f
	var up := curve.sample_baked_up_vector(d, true).slide(f).normalized()
	var r := f.cross(up).normalized()
	return Transform3D(Basis(r, up, -f), xf.origin)

func _add_start(root: Node3D, curve: Curve3D) -> void:
	var sp := Node.new()
	sp.name = "StartingPoint"
	root.add_child(sp)
	
	var line: Node3D = load("res://scenes/start_finish_line.tscn").instantiate()
	line.name = "StartFinishLine"
	var lf := _frame_at(curve, START_LINE_AT)
	lf.basis = lf.basis.scaled(Vector3(1.5, 1.5, 1.5))
	lf.origin += lf.basis.y.normalized() * 0.05
	line.transform = lf
	sp.add_child(line)
	
	var grid := StartingGrid.new()
	grid.name = "StartingGrid"
	sp.add_child(grid)
	var length := curve.get_baked_length()
	for i in GRID_SLOTS:
		var d := length - (i * GRID_SPACING + 25.0) + START_LINE_AT
		d = fposmod(d, length)
		var f := _frame_at(curve, d)
		var side := GRID_LATERAL if i % 2 == 0 else -GRID_LATERAL
		var m := Marker3D.new()
		m.name = "Slot%d" % (i + 1)
		m.gizmo_extents = 3.25
		m.transform = Transform3D(f.basis, f.origin + f.basis.x * side + f.basis.y * 3.0)
		grid.add_child(m)

func _add_magnetic(root: Node3D) -> void:
	var mt := MagneticTrack.new()
	mt.name = "MagneticTrack"
	mt.spline_path = NodePath("../MainSpline")
	var loop := MagneticZone.new()
	loop.zone_name = "Loop"
	loop.start_distance = marks["loop_start_baked"]
	loop.end_distance = marks["loop_end_baked"]
	loop.ramp_in = 60.0
	loop.ramp_out = 60.0
	var roll := MagneticZone.new()
	roll.zone_name = "Barrel Roll"
	roll.start_distance = marks["roll_start_baked"]
	roll.end_distance = marks["roll_end_baked"]
	roll.ramp_in = 50.0
	roll.ramp_out = 50.0
	mt.zones = [loop, roll] as Array[MagneticZone]
	root.add_child(mt)

func _add_environment(root: Node3D) -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.10, 0.14, 0.30)
	sky_mat.sky_horizon_color = Color(0.45, 0.50, 0.62)
	# Lighter ground tones than usual: upside-down road faces the ground and
	# takes its ambient from here.
	sky_mat.ground_bottom_color = Color(0.20, 0.22, 0.28)
	sky_mat.ground_horizon_color = Color(0.36, 0.39, 0.48)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.6
	env.glow_bloom = 0.2
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = env
	if ResourceLoader.exists(MB_SCRIPT):
		var mb: CompositorEffect = load(MB_SCRIPT).new()
		var comp := Compositor.new()
		comp.compositor_effects = [mb] as Array[CompositorEffect]
		we.compositor = comp
	root.add_child(we)
	
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.transform = Transform3D(Basis.from_euler(Vector3(deg_to_rad(-50), deg_to_rad(210), 0)), Vector3(0, 80, 0))
	sun.light_color = Color(1.0, 0.95, 0.9)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 600.0
	root.add_child(sun)
	
	# Upward fill, no shadows. On the loop top and mid-roll the driving
	# surface faces the ground and the sun can't reach it; without this it
	# renders near black (seen in the first chase-cam stills).
	var fill := DirectionalLight3D.new()
	fill.name = "GroundFill"
	fill.rotation_degrees = Vector3(90, 0, 0)   # shines straight up
	fill.light_color = Color(0.75, 0.82, 1.0)
	fill.light_energy = 0.55
	fill.shadow_enabled = false
	root.add_child(fill)

func _add_floor(root: Node3D) -> void:
	# Visual reference only: NO collision, so a ship that leaves the track keeps
	# falling to the respawn threshold instead of getting stranded down here.
	var mi := MeshInstance3D.new()
	mi.name = "FloorVisual"
	var pm := PlaneMesh.new()
	pm.size = Vector2(4000, 4000)
	mi.mesh = pm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.07, 0.08, 0.11)
	mat.roughness = 1.0
	mi.material_override = mat
	mi.position = Vector3(150, -40, 0)
	root.add_child(mi)

func _set_owner(n: Node, owner: Node) -> void:
	for c in n.get_children():
		c.owner = owner
		# Instanced sub-scenes keep their own internals.
		if c.scene_file_path.is_empty():
			_set_owner(c, owner)

func _save(root: Node3D) -> void:
	_set_owner(root, root)
	var ps := PackedScene.new()
	var err := ps.pack(root)
	if err != OK:
		push_error("pack failed %d" % err)
		return
	err = ResourceSaver.save(ps, OUT_SCENE)
	print("LOOPLAB saved %s (%s)" % [OUT_SCENE, error_string(err)])
