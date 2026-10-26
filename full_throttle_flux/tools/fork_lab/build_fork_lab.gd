extends SceneTree
## Builds res://scenes/tracks/fork_lab.tscn -- a greybox test circuit with a
## FORK (two routes that split and rejoin) and two JUMPS (v31).
##
##   godot --headless --path . -s res://tools/fork_lab/build_fork_lab.gd
##
## Layout (top view, start line at the origin heading -Z = north):
##
##   start -> climb -> SHARED JUMP -> banked 180 right -> FORK
##     main route (A): bulges out east: 45 left, straight, banked 90 right,
##                     straight, 45 left (longer, no jump)
##     branch (B):     straight on, climb, BRANCH JUMP (bigger gap) (shorter)
##   -> REJOIN -> banked 180 right -> closing straight (starting grid) -> start
##
## The MainSpline is the canonical lap and runs the main route. The branch is
## a second Path3D ("BranchSpline") from the fork to the rejoin; a TrackGraph
## node maps its distances onto main distance (lap progress, positions,
## respawns) and holds the jumps. Road and walls are TrackRoadSegments (pieces
## of each spline, with gaps for the jumps); the two Y junctions are
## TrackJunctions (flat union road + splitter wedge).
##
## The jumps were sized with tools/fork_lab/jump_sim.gd (the real
## ShipController flown off the real kicker shapes), not from ballistics.
## Jump approaches climb first, so every jump is height-neutral and the
## junctions are level at y = 0.

const Turtle := preload("res://tools/fork_lab/fork_lab_turtle.gd")
const OUT_SCENE := "res://scenes/tracks/fork_lab.tscn"
const ROAD_MAT := "res://shaders/resources/grid_material.tres"
## v38: the driving surface of road segments (walls and junctions keep ROAD_MAT).
const ROAD_SURFACE_MAT := "res://shaders/track/track_surface_material.tres"
## v38 phase 5: the walls' surface (junctions keep ROAD_MAT).
const WALL_SURFACE_MAT := "res://shaders/track/track_wall_material.tres"
const MB_SCRIPT := "res://scripts/rendering/motion_blur_effect.gd"

# ---- layout (metres, degrees) ----------------------------------------------
const START_STRAIGHT := 60.0      # origin -> climb (line at START_LINE_AT)
const START_LINE_AT := 30.0
const CLIMB_DEG := 3.0
const CLIMB_TRANS := 40.0
const TURN_180_LENGTH := 420.0
const TURN_BANK_DEG := 18.0
const PRE_FORK := 120.0
const BULGE_DEG := 45.0           # main route's divergence angle
const BULGE_TURN := 220.0         # 45 deg turns (unbanked: they hold the junctions)
const BULGE_MID := 396.0          # 90 deg turn at the far side (banked)
const BULGE_MID_BANK := 12.0
const BRANCH_LENGTH := 1000.0     # straight-line length the bulge must span
const POST_REJOIN := 120.0
const GRID_SLOTS := 8
const GRID_SPACING := 22.0
const GRID_LATERAL := 8.0
const JUNCTION_SEPARATION := 62.0 # centre lines this far apart = junction ends

# Shared jump (start straight). Makeable from ~70 u/s; see FTF_v31_NOTES.md.
const SJ := {"runup": 64.0, "kick_deg": 6.0, "kick_len": 70.0, "gap": 55.0, "drop": 4.0,
		"land_deg": 6.0, "land_len": 40.0, "outrun": 80.0, "after": 65.0, "respawn_runup": 150.0}
# Branch jump: bigger gap, needs ~98 u/s.
const BJ := {"kick_deg": 8.0, "kick_len": 70.0, "gap": 100.0, "drop": 6.0,
		"land_deg": 6.0, "land_len": 40.0, "outrun": 80.0, "respawn_runup": 220.0}
const BRANCH_KICKER_AT := 470.0   # branch metres (after the junction + respawn run-up)

# ---- cross-sections (same as the test circuits / Loop Lab) -----------------
const ROAD_HALF := 19.5
const ROAD_STRIP := 3.0
## The test circuits' wall sections. TrackRoadSegment puts +x on the RIGHT of
## travel, so the +x section is the right wall here (Loop Lab's CSG calls the
## same polygon "wallLeftGeo").
const WALL_RIGHT_POLY := [Vector2(28.5, 8.5), Vector2(23.5, 8.4), Vector2(21.1, 6.5), Vector2(21.1, -2.0), Vector2(28.6, -2.0)]
const WALL_LEFT_POLY := [Vector2(-21.1, 6.5), Vector2(-23.5, 8.4), Vector2(-28.5, 8.5), Vector2(-28.6, -2.0), Vector2(-21.1, -2.0)]
const LIP_FADE := 30.0

var main_t: Turtle
var branch_t: Turtle
var main_offs := PackedFloat32Array()
var branch_offs := PackedFloat32Array()
var M := {}    # main marks, baked metres
var B := {}    # branch marks, baked metres
var fork_pos := Vector3.ZERO
var fork_heading := Vector3.FORWARD
var rejoin_pos := Vector3.ZERO


func _initialize() -> void:
	_build_main()
	var main_curve := main_t.build_curve("FORKLAB main", main_offs)
	if main_curve == null:
		quit(1)
		return
	_build_branch(main_curve)
	var branch_curve := branch_t.build_curve("FORKLAB branch", branch_offs)
	if branch_curve == null:
		quit(1)
		return
	for k in main_t.marks:
		M[k] = main_t.baked_at_arc(main_t.marks[k], main_offs)
	for k in branch_t.marks:
		B[k] = branch_t.baked_at_arc(branch_t.marks[k], branch_offs)
	M["length"] = main_curve.get_baked_length()
	B["length"] = branch_curve.get_baked_length()
	var route_curve := _build_route()
	if route_curve == null:
		quit(1)
		return
	var root := _build_scene(main_curve, branch_curve, route_curve)
	_save(root)
	quit(0)


# =============================================================================
# CENTRE LINES
# =============================================================================

## Climb (or descend) by `rise` metres on a CLIMB_DEG ramp with sin^2
## transitions in and out.
func _climb(t: Turtle, rise: float) -> void:
	if absf(rise) < 0.01:
		return
	var a := deg_to_rad(CLIMB_DEG) * signf(rise)
	var tr := Turtle.pitch_displacement(CLIMB_TRANS, 0.0, a).y
	var tr2 := Turtle.pitch_displacement(CLIMB_TRANS, a, -a).y
	var straight := (rise - tr - tr2) / sin(a)
	if straight < 0.0:
		push_error("climb of %.1f m too small for the transitions" % rise)
		straight = 0.0
	t.pitch_change(CLIMB_TRANS, a, 4.0)
	t.straight(straight, 10.0)
	t.pitch_change(CLIMB_TRANS, -a, 4.0)
	t.pitch = 0.0

## Kicker, gap, landing ramp and outrun. Marks <prefix>_kicker/_lip/_landing/_end.
## Across the gap the turtle just jumps to the landing lip: the curve's cubic
## between the two samples is a smooth arc (logic only; no road there).
func _jump(t: Turtle, j: Dictionary, prefix: String) -> void:
	t.mark(prefix + "_kicker")
	t.pitch_change(j.kick_len, deg_to_rad(j.kick_deg), 2.0)
	t.pitch = deg_to_rad(j.kick_deg)
	t.mark(prefix + "_lip")
	t.emit()
	var land := t.pos + t.heading * float(j.gap) + Vector3.DOWN * float(j.drop)
	t.arc += t.pos.distance_to(land)
	t.pos = land
	t.pitch = -deg_to_rad(j.land_deg)
	t.mark(prefix + "_landing")
	t.straight(j.land_len, 2.0)
	t.pitch_change(j.outrun, deg_to_rad(j.land_deg), 2.0)
	t.pitch = 0.0
	t.mark(prefix + "_end")

## Net height change of a jump (kicker start -> outrun end).
func _jump_rise(j: Dictionary) -> float:
	var k := Turtle.pitch_displacement(j.kick_len, 0.0, deg_to_rad(j.kick_deg)).y
	var l := -float(j.land_len) * sin(deg_to_rad(j.land_deg))
	var o := Turtle.pitch_displacement(j.outrun, -deg_to_rad(j.land_deg), deg_to_rad(j.land_deg)).y
	return k - float(j.drop) + l + o

func _build_main() -> void:
	var t := Turtle.new()
	main_t = t
	t.straight(START_STRAIGHT, 10.0)
	_climb(t, -_jump_rise(SJ))
	t.straight(SJ.runup, 8.0)
	_jump(t, SJ, "sj")
	t.straight(SJ.after, 8.0)
	t.turn(TURN_180_LENGTH, -PI, TURN_BANK_DEG, 8.0)
	t.straight(PRE_FORK, 8.0)
	t.mark("fork")
	fork_pos = t.pos
	fork_heading = t.heading
	# Main route: a symmetric bulge, so it comes back onto the branch's line.
	var th := deg_to_rad(BULGE_DEG)
	var f1 := Turtle.turn_displacement(BULGE_TURN, th)
	var f2 := Turtle.turn_displacement(BULGE_MID, 2.0 * th)
	var chord := f2.length()
	var a := (BRANCH_LENGTH - 2.0 * f1.x - chord) / (2.0 * cos(th))
	t.turn(BULGE_TURN, th, 0.0, 4.0)
	t.straight(a, 10.0)
	t.turn(BULGE_MID, -2.0 * th, BULGE_MID_BANK, 8.0)
	t.straight(a, 10.0)
	t.turn(BULGE_TURN, th, 0.0, 4.0)
	t.mark("rejoin")
	rejoin_pos = t.pos
	print("FORKLAB bulge straight %.1f m; rejoin lateral error %.3f m, height %.3f m" % [a,
			(t.pos - fork_pos).dot(fork_heading.cross(Vector3.UP)), t.pos.y])
	t.straight(POST_REJOIN, 8.0)
	t.turn(TURN_180_LENGTH, -PI, TURN_BANK_DEG, 8.0)
	t.mark("closing_start")
	var closing := t.pos.z
	print("FORKLAB closing straight %.1f m, lateral closure error %.3f m, height %.3f m"
			% [closing, t.pos.x, t.pos.y])
	if closing < GRID_SLOTS * GRID_SPACING + 60.0:
		push_error("closing straight too short for the grid")
	t.pos.x = 0.0
	t.pos.y = 0.0
	t.straight(closing, 10.0)
	t.emit()
	t.P[t.P.size() - 1] = t.P[0]

func _build_branch(main_curve: Curve3D) -> void:
	var t := Turtle.new()
	branch_t = t
	t.pos = fork_pos
	t.heading = fork_heading
	var rejoin := rejoin_pos
	var span: float = (rejoin - t.pos).dot(t.heading)
	# Junction + run-up, climb, then the jump at BRANCH_KICKER_AT.
	var climb_rise := -_jump_rise(BJ)
	t.straight(200.0, 4.0)
	_climb(t, climb_rise)
	t.straight(BRANCH_KICKER_AT - t.arc, 8.0)
	_jump(t, BJ, "bj")
	var used: float = (t.pos - fork_pos).dot(t.heading)
	t.straight(span - used, 4.0)
	t.emit()
	var err: float = t.P[t.P.size() - 1].distance_to(rejoin)
	print("FORKLAB branch span %.1f m, end error vs rejoin %.4f m (snapped)" % [span, err])
	t.P[t.P.size() - 1] = rejoin


## v32: a whole lap THROUGH the branch (main to the fork, the branch, main
## from the rejoin), as its own closed-lap curve. The AI, its baker and
## trainer, and the cinematic rig all work in "a lap along one spline"; giving
## the shortcut route its own lap spline lets all of them run unchanged on it.
## Logic only: no geometry is built from it. Tilts are re-solved for the
## joined curve.
var route_t: Turtle
var route_offs := PackedFloat32Array()
var R := {}

func _build_route() -> Curve3D:
	var t := Turtle.new()
	route_t = t
	var fork_arc: float = main_t.marks["fork"]
	var rejoin_arc: float = main_t.marks["rejoin"]
	var arc := 0.0
	var prev := Vector3.INF
	var add := func(p: Vector3, tan: Vector3, up: Vector3) -> void:
		if prev != Vector3.INF:
			arc += p.distance_to(prev)
		t.P.append(p)
		t.T.append(tan)
		t.U.append(up)
		t.S.append(arc)
		prev = p
	for i in main_t.P.size():
		if main_t.S[i] < fork_arc - 0.001:
			add.call(main_t.P[i], main_t.T[i], main_t.U[i])
	var fork_index := t.P.size()
	for i in branch_t.P.size() - 1:
		add.call(branch_t.P[i], branch_t.T[i], branch_t.U[i])
	var rejoin_index := t.P.size()
	for i in main_t.P.size():
		if main_t.S[i] >= rejoin_arc - 0.001:
			add.call(main_t.P[i], main_t.T[i], main_t.U[i])
	var c := t.build_curve("FORKLAB route via branch", route_offs)
	if c == null:
		return null
	R["fork"] = route_offs[fork_index]
	R["rejoin"] = route_offs[rejoin_index]
	R["length"] = c.get_baked_length()
	print("FORKLAB route via branch: %.1f m, fork at %.1f, rejoin at %.1f" % [R.length, R.fork, R.rejoin])
	return c


# =============================================================================
# SCENE
# =============================================================================

func _build_scene(main_curve: Curve3D, branch_curve: Curve3D, route_curve: Curve3D) -> Node3D:
	var root := Node3D.new()
	root.name = "ForkLab"
	_add_environment(root)
	
	var main := Path3D.new()
	main.name = "MainSpline"
	main.curve = main_curve
	root.add_child(main)
	var br := Path3D.new()
	br.name = "BranchSpline"
	br.curve = branch_curve
	root.add_child(br)
	var rt := Path3D.new()
	rt.name = "RouteSpline_Branch"
	rt.curve = route_curve
	root.add_child(rt)
	
	var g := TrackGraph.new()
	g.name = "TrackGraph"
	g.main_path = NodePath("../MainSpline")
	root.add_child(g)
	var tb := TrackBranch.new()
	tb.branch_name = "Jump shortcut"
	tb.path = NodePath("../BranchSpline")
	tb.fork_distance = M.fork
	tb.rejoin_distance = M.rejoin
	tb.route_path = NodePath("../RouteSpline_Branch")
	tb.route_fork = R.fork
	tb.route_rejoin = R.rejoin
	g.branches = [tb] as Array[TrackBranch]
	
	# Junction extents from the geometry: where the centre lines are
	# JUNCTION_SEPARATION apart (inner walls clear of each other).
	var jf := _junction_extent(main_curve, branch_curve, true)
	var jr := _junction_extent(main_curve, branch_curve, false)
	tb.fork_blend = jf.b
	tb.rejoin_blend = B.length - jr.b
	print("FORKLAB fork junction: main %.0f-%.0f, branch 0-%.0f; rejoin junction: main %.0f-%.0f, branch %.0f-%.0f"
			% [M.fork, jf.m, jf.b, jr.m, M.rejoin, jr.b, B.length])
	
	var sj := TrackJump.new()
	sj.jump_name = "Shared jump"
	sj.branch = -1
	sj.kicker_start = M.sj_kicker
	sj.lip = M.sj_lip
	sj.landing = M.sj_landing
	sj.landing_end = M.sj_end
	sj.respawn_runup = SJ.respawn_runup
	sj.clean_speed = 66.0   # measured (FTF_v31_NOTES.md)
	var bj := TrackJump.new()
	bj.jump_name = "Branch jump"
	bj.branch = 0
	bj.kicker_start = B.bj_kicker
	bj.lip = B.bj_lip
	bj.landing = B.bj_landing
	bj.landing_end = B.bj_end
	bj.respawn_runup = BJ.respawn_runup
	bj.clean_speed = 93.0   # measured (FTF_v31_NOTES.md)
	g.jumps = [sj, bj] as Array[TrackJump]
	print("FORKLAB shared jump: kicker %.1f lip %.1f landing %.1f end %.1f (main m)" % [M.sj_kicker, M.sj_lip, M.sj_landing, M.sj_end])
	print("FORKLAB branch jump: kicker %.1f lip %.1f landing %.1f end %.1f (branch m)" % [B.bj_kicker, B.bj_lip, B.bj_landing, B.bj_end])
	print("FORKLAB main %.1f m (via main route), branch %.1f m, main route %.1f m -> shortcut saves %.1f m"
			% [M.length, B.length, M.rejoin - M.fork, (M.rejoin - M.fork) - B.length])
	
	var mat: Material = load(ROAD_MAT)
	var road_mat: Material = load(ROAD_SURFACE_MAT)
	var wall_mat: Material = load(WALL_SURFACE_MAT)
	var L: float = M.length
	# --- main road -----------------------------------------------------------
	_seg(main, "Road_Start", _road_poly(), 0.0, M.sj_lip, 1, road_mat, 100.0, 0.5, 0.0, 0.0)
	_seg(main, "Road_PreFork", _road_poly(), M.sj_landing, M.fork, 1, road_mat, 100.0, 0.5, 0.0, LIP_FADE)
	_seg(main, "Road_MainRoute", _road_poly(), jf.m, jr.m, 1, road_mat, 100.0, 0.5, LIP_FADE, LIP_FADE)
	_seg(main, "Road_PostRejoin", _road_poly(), M.rejoin, L, 1, road_mat, 100.0, 0.5, LIP_FADE, 0.0)
	# Main walls. +x is the right of travel. At the fork the branch goes
	# straight on and the main route bears LEFT, so the main route's right wall
	# is the inner one (between the routes) and the branch's left wall is.
	_seg(main, "WallL_Start", WALL_LEFT_POLY, 0.0, M.sj_lip, 4, wall_mat, 50.0, 1.0)
	_seg(main, "WallL_Rest", WALL_LEFT_POLY, M.sj_landing, L, 4, wall_mat, 50.0, 1.0)
	_seg(main, "WallR_Start", WALL_RIGHT_POLY, 0.0, M.sj_lip, 4, wall_mat, 50.0, 1.0)
	_seg(main, "WallR_PreFork", WALL_RIGHT_POLY, M.sj_landing, M.fork, 4, wall_mat, 50.0, 1.0)
	_seg(main, "WallR_MainRouteInner", WALL_RIGHT_POLY, jf.m, jr.m, 4, wall_mat, 50.0, 1.0)
	_seg(main, "WallR_PostRejoin", WALL_RIGHT_POLY, M.rejoin, L, 4, wall_mat, 50.0, 1.0)
	_check_sides(main_curve, branch_curve, jf)
	# --- branch road ---------------------------------------------------------
	_seg(br, "Road_BranchA", _road_poly(), jf.b, B.bj_lip, 1, road_mat, 100.0, 0.5, LIP_FADE, 0.0)
	_seg(br, "Road_BranchB", _road_poly(), B.bj_landing, jr.b, 1, road_mat, 100.0, 0.5, 0.0, LIP_FADE)
	_seg(br, "WallR_A", WALL_RIGHT_POLY, 0.0, B.bj_lip, 4, wall_mat, 50.0, 1.0)
	_seg(br, "WallR_B", WALL_RIGHT_POLY, B.bj_landing, B.length, 4, wall_mat, 50.0, 1.0)
	_seg(br, "WallL_InnerA", WALL_LEFT_POLY, jf.b, B.bj_lip, 4, wall_mat, 50.0, 1.0)
	_seg(br, "WallL_InnerB", WALL_LEFT_POLY, B.bj_landing, jr.b, 4, wall_mat, 50.0, 1.0)
	# --- junctions -----------------------------------------------------------
	_junction(root, "ForkJunction", M.fork, jf.m, 0.0, jf.b, true, mat)
	_junction(root, "RejoinJunction", jr.m, M.rejoin, jr.b, B.length, false, mat)
	# --- jump gaps: respawn the moment a ship that fell short drops below ----
	_gap_trigger(root, main_curve, M.sj_lip, M.sj_landing, "GapTrigger_Shared")
	_gap_trigger(root, branch_curve, B.bj_lip, B.bj_landing, "GapTrigger_Branch")
	
	_add_start(root, main_curve)
	_add_floor(root)
	return root

func _junction_extent(mc: Curve3D, bc: Curve3D, at_fork: bool) -> Dictionary:
	var bl := bc.get_baked_length()
	var b := 0.0 if at_fork else bl
	var step := 1.0 if at_fork else -1.0
	var guess: float = M.fork if at_fork else M.rejoin
	while b >= 0.0 and b <= bl:
		var f := TrackRoadSegment.frame_at(bc, b)
		var m := _cross(mc, f.origin, -f.basis.z, guess)
		guess = m
		var sep := (mc.sample_baked(m, true) - f.origin).length()
		if sep >= JUNCTION_SEPARATION:
			return {"b": b, "m": m}
		b += step
	push_error("junction never separates")
	return {"b": b, "m": guess}

static func _cross(mc: Curve3D, p: Vector3, t: Vector3, guess: float) -> float:
	var lo := guess
	var glo := (mc.sample_baked(lo, true) - p).dot(t)
	var stp := 1.0 if glo < 0.0 else -1.0
	var hi := lo
	for i in 600:
		hi = lo + stp
		var ghi := (mc.sample_baked(hi, true) - p).dot(t)
		if signf(ghi) != signf(glo):
			break
		lo = hi
		glo = ghi
	for i in 30:
		var mid := (lo + hi) * 0.5
		var gm := (mc.sample_baked(mid, true) - p).dot(t)
		if signf(gm) == signf(glo):
			lo = mid
			glo = gm
		else:
			hi = mid
	return (lo + hi) * 0.5

## Asserts the side assumption used for the inner walls (branch to the right).
func _check_sides(mc: Curve3D, bc: Curve3D, jf: Dictionary) -> void:
	var fm := TrackRoadSegment.frame_at(mc, jf.m)
	var side := (bc.sample_baked(jf.b, true) - fm.origin).dot(fm.basis.x)
	if side <= 0.0:
		push_error("branch is not to the right of the main route at the fork")

func _road_poly() -> Array:
	var pts := [Vector2(ROAD_HALF + 2.0, 0.9)]
	var n := int(ceil(2.0 * ROAD_HALF / ROAD_STRIP))
	for i in n + 1:
		pts.append(Vector2(ROAD_HALF - 2.0 * ROAD_HALF * i / n, 0.0))
	pts.append(Vector2(-ROAD_HALF - 2.0, 0.9))
	pts.append(Vector2(-ROAD_HALF - 2.0, -2.0))
	pts.append(Vector2(ROAD_HALF + 2.0, -2.0))
	return pts

func _seg(path: Path3D, n: String, poly: Array, d0: float, d1: float, layer: int, mat: Material,
		u_dist: float, interval: float, fade_in: float = 0.0, fade_out: float = 0.0) -> void:
	var s := TrackRoadSegment.new()
	s.name = n
	s.path_node = NodePath("..")
	s.start_distance = d0
	s.end_distance = d1
	s.polygon = PackedVector2Array(poly)
	s.interval = interval
	s.collision_layer = layer
	s.material = mat
	s.u_distance = u_dist
	s.fade_in = fade_in
	s.fade_out = fade_out
	path.add_child(s)

func _junction(root: Node3D, n: String, a0: float, a1: float, b0: float, b1: float, fork: bool,
		mat: Material) -> void:
	var j := TrackJunction.new()
	j.name = n
	j.path_a = NodePath("../MainSpline")
	j.path_b = NodePath("../BranchSpline")
	j.a_start = a0
	j.a_end = a1
	j.b_start = b0
	j.b_end = b1
	j.point_at_start = fork
	j.material = mat
	root.add_child(j)

func _gap_trigger(root: Node3D, c: Curve3D, lip: float, landing: float, n: String) -> void:
	var a := c.sample_baked(lip, true)
	var b := c.sample_baked(landing, true)
	var low := minf(a.y, b.y)
	var area := Area3D.new()
	area.name = n
	area.set_script(load("res://scripts/respawn_trigger.gd"))
	var mid := (a + b) * 0.5
	var fwd := (b - a).slide(Vector3.UP).normalized()
	var basis := Basis(fwd.cross(Vector3.UP).normalized(), Vector3.UP, -fwd)
	# Top 10 m below the landing lip: a ship that clears the gap never gets
	# there; one that falls short is caught a moment after it drops.
	var top := low - 10.0
	var bottom := low - 70.0
	area.transform = Transform3D(basis, Vector3(mid.x, (top + bottom) * 0.5, mid.z))
	area.collision_layer = 0
	area.collision_mask = 2
	var cs := CollisionShape3D.new()
	cs.name = "Shape"
	var box := BoxShape3D.new()
	box.size = Vector3(90.0, top - bottom, a.distance_to(b) + 80.0)
	cs.shape = box
	area.add_child(cs)
	root.add_child(area)

func _add_start(root: Node3D, curve: Curve3D) -> void:
	var sp := Node.new()
	sp.name = "StartingPoint"
	root.add_child(sp)
	var line: Node3D = load("res://scenes/start_finish_line.tscn").instantiate()
	line.name = "StartFinishLine"
	var lf := TrackRoadSegment.frame_at(curve, START_LINE_AT)
	lf.basis = lf.basis.scaled(Vector3(1.5, 1.5, 1.5))
	lf.origin += lf.basis.y.normalized() * 0.05
	line.transform = lf
	sp.add_child(line)
	var grid := StartingGrid.new()
	grid.name = "StartingGrid"
	sp.add_child(grid)
	var length := curve.get_baked_length()
	for i in GRID_SLOTS:
		var d := fposmod(length - (i * GRID_SPACING + 25.0) + START_LINE_AT, length)
		var f := TrackRoadSegment.frame_at(curve, d)
		var side := GRID_LATERAL if i % 2 == 0 else -GRID_LATERAL
		var m := Marker3D.new()
		m.name = "Slot%d" % (i + 1)
		m.gizmo_extents = 3.25
		m.transform = Transform3D(f.basis, f.origin + f.basis.x * side + f.basis.y * 3.0)
		grid.add_child(m)

func _add_environment(root: Node3D) -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.10, 0.14, 0.30)
	sky_mat.sky_horizon_color = Color(0.45, 0.50, 0.62)
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
	# Same shadowless upward fill as Loop Lab: lights the ramps' undersides
	# and the gap walls seen from the air.
	var fill := DirectionalLight3D.new()
	fill.name = "GroundFill"
	fill.rotation_degrees = Vector3(90, 0, 0)
	fill.light_color = Color(0.75, 0.82, 1.0)
	fill.light_energy = 0.35
	fill.shadow_enabled = false
	root.add_child(fill)

func _add_floor(root: Node3D) -> void:
	# Visual only, NO collision: a ship that misses a jump falls into the gap
	# trigger (or, failing that, to the respawn threshold).
	var mi := MeshInstance3D.new()
	mi.name = "FloorVisual"
	var pm := PlaneMesh.new()
	pm.size = Vector2(5000, 5000)
	mi.mesh = pm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.07, 0.08, 0.11)
	mat.roughness = 1.0
	mi.material_override = mat
	mi.position = Vector3(300, -40, -600)
	root.add_child(mi)

func _set_owner(n: Node, owner: Node) -> void:
	for c in n.get_children():
		c.owner = owner
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
	print("FORKLAB saved %s (%s)" % [OUT_SCENE, error_string(err)])
