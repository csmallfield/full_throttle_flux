extends RefCounted
class_name TrackBuild
## Track Builder: the Build step (v34).
##
## Turns the TrackBuilder's inputs (BaseSpline, keys, features) into what the
## game runs on, as direct children of the track root:
##
##   MainSpline (Path3D)          dense resample of the composite track, tilts SOLVED
##     Road, WallL, WallR (+ _2, _3 ... when jumps cut gaps)
##                                TrackRoadSegments with the width profile
##   StartingPoint
##     StartFinishLine, StartingGrid (Slot1..8)
##   MagneticTrack                one zone per roll / loop (only if there are any)
##   TrackGraph                   the branches and jumps (only if there are any)
##   GapTrigger_1, _2 ...         respawn triggers under each jump's gap
##   BoostPads                    one BoostPad (scenes/boost_pad.tscn) per pad
##                                of every BoostPadKey, on the road surface
##   TrackGreebles                the greeble zones from the GreebleZoneKeys
##                                (v36; scattered at load, see TrackGreebler)
##   TrackSurface                 the road surface zones from the
##                                SurfaceZoneKeys (v38; applied at load, see
##                                TrackSurfacer)
##   per branch (split track):
##     BranchSpline (_2 ...)      the branch, tilts solved; Road / WallL / WallR
##     RouteSpline_Branch (_2 ...)  a whole lap through the branch (AI, rig)
##     ForkJunction, RejoinJunction (_2 ...)  flat Y junctions
##
## The MainSpline stays a direct child of the root because MagneticTrack,
## TrackGraph and the probes look for "../MainSpline" / the root.
##
## Generated nodes are tagged with the GROUP and UPDATED IN PLACE by name on
## every build (Godot 4.7 gives each saved node a random unique_id, so
## recreating nodes would churn the .tscn on every build); sub-resources
## (the curve, zones, jumps, trigger shapes) are reused the same way. Building
## twice without changing anything leaves the scene file byte-identical.
## Nodes in the group that a build no longer makes are removed. Nothing
## outside the group is touched (set dressing, lights, environment are yours).

const Turtle := preload("res://tools/fork_lab/fork_lab_turtle.gd")
const GROUP := "track_builder_generated"
const META_HASH := "track_builder_input_hash"
const ROAD_MAT := "res://shaders/resources/grid_material.tres"
## v38: the driving surface of road segments and junction roads (junction
## splitters keep ROAD_MAT).
const ROAD_SURFACE_MAT := "res://shaders/track/track_surface_material.tres"
## v38 phase 5: the walls' surface (junction splitters keep ROAD_MAT).
const WALL_SURFACE_MAT := "res://shaders/track/track_wall_material.tres"
const LINE_SCENE := "res://scenes/start_finish_line.tscn"
const GAP_TRIGGER_SCRIPT := "res://scripts/respawn_trigger.gd"
const PAD_SCENE := "res://scenes/boost_pad.tscn"

# Control point spacing of the generated MainSpline: a new point when the
# tangent or the up vector has turned MAX_TURN_DEG since the last one, or
# after MAX_SPACING metres. Dense in corners and bank changes, sparse on
# straights (keeps the scene file small). Points always land on the jump
# lips and landings (the road ends exactly there).
const MAX_SPACING := 12.0
const MIN_SPACING := 2.0
## Inside features (loops, rolls) the road turns fast enough that 2 m spans
## let Godot's interpolated frame drift ~0.85° off the shape (measured on a
## loop); 1 m keeps it under 0.5°.
const MIN_SPACING_FEATURE := 1.0
## Inside features a point also every 0.5° of turn (a roll twists 0.68°/m:
## at 1° the bank between points drifted up to ~0.5° off the shape).
const MAX_TURN_DEG_FEATURE := 0.5
const MAX_TURN_DEG := 1.0

# Cross-sections: the circuits' (as on Loop Lab / Fork Lab).
const ROAD_HALF := 19.5
const ROAD_EDGE := 21.5
const ROAD_STRIP := 3.0
const WALL_RIGHT_POLY := [Vector2(28.5, 8.5), Vector2(23.5, 8.4), Vector2(21.1, 6.5), Vector2(21.1, -2.0), Vector2(28.6, -2.0)]
const WALL_LEFT_POLY := [Vector2(-21.1, 6.5), Vector2(-23.5, 8.4), Vector2(-28.5, 8.5), Vector2(-28.6, -2.0), Vector2(-21.1, -2.0)]
const LIP_FADE := 30.0
const LAYER_GROUND := 1
const LAYER_WALLS := 4

const GRID_SLOTS := 8
const GRID_SPACING := 22.0
const GRID_LATERAL := 8.0

var ok := true
var log: PackedStringArray = []
var root: Node
var curve: Curve3D
var tilt_error_deg := 0.0
var _main_sampler: TrackSampler
var _touched := {}
# Composite distance -> MainSpline baked distance, at the emitted points.
var _map_s := PackedFloat32Array()
var _map_d := PackedFloat32Array()


## Composite distance -> baked distance on a built curve, from the emitted
## points' (composite distance, baked offset) pairs.
class DistMap:
	var s := PackedFloat32Array()
	var d := PackedFloat32Array()

	func at(x: float) -> float:
		var n := s.size()
		if x <= s[0]:
			return d[0]
		if x >= s[n - 1]:
			return d[n - 1]
		var lo := 0
		var hi := n - 1
		while hi - lo > 1:
			var mid := (lo + hi) >> 1
			if s[mid] <= x:
				lo = mid
			else:
				hi = mid
		var t := (x - s[lo]) / maxf(s[hi] - s[lo], 1e-6)
		return lerpf(d[lo], d[hi], t)


static func run(b: TrackBuilder) -> TrackBuild:
	var tb := TrackBuild.new()
	tb._run(b)
	return tb


## Removes every generated node under the builder's scene root. Returns the
## number of nodes removed.
static func clear(b: TrackBuilder) -> int:
	var tb := TrackBuild.new()
	tb.root = b.owner if b.owner else b.get_parent()
	if tb.root == null:
		return 0
	var stale: Array[Node] = []
	tb._collect_stale(tb.root, stale)
	for n in stale:
		if is_instance_valid(n):
			n.get_parent().remove_child(n)
			n.free()
	return stale.size()


func _run(b: TrackBuilder) -> void:
	var t0 := Time.get_ticks_usec()
	root = b.owner if b.owner else b.get_parent()
	if root == null:
		_fail("The TrackBuilder needs to be inside a track scene.")
		return
	if not b.evaluate():
		_fail("No BaseSpline curve to build from.")
		return
	for e in b.errors():
		_fail(e)
	if not ok:
		return
	var s := b.sampler
	_main_sampler = s
	var existing := root.get_node_or_null("MainSpline")
	if existing and not existing.is_in_group(GROUP):
		_fail("The scene already has a hand-made MainSpline. Rename or delete it; the builder makes its own.")
		return
	if b.keys_of("StartKey").size() > 1:
		log.append("⚠ %d StartKeys: using the first" % b.keys_of("StartKey").size())

	# --- dense centre line, tilts solved against Godot's frame ---------------
	var must := PackedFloat32Array()   # composite distances that need a point
	for p in b.composer.placed:
		for k in ["lip", "landing"]:
			if p.marks.has(k):
				must.append(p.marks[k])
	var t := Turtle.new()
	var src := PackedInt32Array()    # sample index behind each control point
	_emit_points(s, t, src, must, true)
	var offsets := PackedFloat32Array()
	var built := t.build_curve("TRACK BUILDER %s" % root.name, offsets)
	if built == null:
		_fail("Tilt solve failed (see the output log).")
		return
	tilt_error_deg = rad_to_deg(t._tilt_error(built, offsets))
	_map_s = PackedFloat32Array(t.S)
	_map_d = offsets

	var main := _ensure(root, "MainSpline", "Path3D") as Path3D
	if main.curve == null:
		main.curve = Curve3D.new()
	_copy_curve(built, main.curve)
	curve = main.curve
	main.set_meta(META_HASH, b.input_hash())
	var length := curve.get_baked_length()

	# --- jumps: where the road stops -------------------------------------------
	var jumps: Array[Dictionary] = []
	for p in b.composer.placed:
		if p.node is JumpFeature:
			jumps.append({node = p.node, kicker = to_main(p.marks.kicker), lip = to_main(p.marks.lip),
					landing = to_main(p.marks.landing), end = to_main(p.marks.end)})

	# --- branches: their own splines, before the main road is cut ---------------
	var mat: Material = load(ROAD_MAT)
	var road_mat: Material = load(ROAD_SURFACE_MAT)
	var wall_mat: Material = load(WALL_SURFACE_MAT)
	var main_map := DistMap.new()
	main_map.s = _map_s
	main_map.d = _map_d
	var built_branches: Array[Dictionary] = []
	for bi in b.branches.size():
		var be: TrackBranchEval = b.branches[bi]
		var bb := _branch(be, bi, main_map, mat, road_mat, wall_mat)
		if bb.is_empty():
			return
		built_branches.append(bb)
	
	# --- main road and walls, in pieces between the gaps and junctions -----
	var widths := _width_profile(s, src, offsets)
	var gaps: Array[Dictionary] = []
	for j in jumps:
		gaps.append({a = j.lip, b = j.landing, junction = false})
	var junctions_l: Array[Dictionary] = []
	var junctions_r: Array[Dictionary] = []
	for bb in built_branches:
		var spans := [{a = bb.fork, b = bb.jf_m, junction = true}, {a = bb.jr_m, b = bb.rejoin, junction = true}]
		if bb.side > 0.0:
			junctions_r.append_array(spans)
		else:
			junctions_l.append_array(spans)
	_pieces_out(main, "Road", _road_poly(), LAYER_GROUND, 100.0, ROAD_HALF, widths, road_mat,
			_pieces(_cat([gaps, junctions_l, junctions_r]), length), true)
	# A wall stops only where its own side opens into a junction.
	_pieces_out(main, "WallL", WALL_LEFT_POLY, LAYER_WALLS, 50.0, 0.0, widths, wall_mat,
			_pieces(_cat([gaps, junctions_l]), length), true)
	_pieces_out(main, "WallR", WALL_RIGHT_POLY, LAYER_WALLS, 50.0, 0.0, widths, wall_mat,
			_pieces(_cat([gaps, junctions_r]), length), true)

	# --- start line and grid -------------------------------------------------
	_start(b.start_lead)

	# --- magnetic zones (rolls, loops) ---------------------------------------
	var zones: Array[Dictionary] = []
	for p in b.composer.placed:
		if not p.zone.is_empty():
			zones.append({name = String(p.node.name),
					from = to_main(p.marks[p.zone.from]), to = to_main(p.marks[p.zone.to]),
					ramp_in = p.zone.ramp_in, ramp_out = p.zone.ramp_out, magnet = p.zone.magnet})
	if not zones.is_empty():
		_magnetic(zones)

	# --- graph: branches and jumps ---------------------------------------------
	var all_jumps: Array[Dictionary] = jumps.duplicate()
	for bi in built_branches.size():
		for j: Dictionary in built_branches[bi].jumps:
			all_jumps.append(j)
	if not all_jumps.is_empty() or not built_branches.is_empty():
		_graph(all_jumps, built_branches)
		for i in all_jumps.size():
			var j: Dictionary = all_jumps[i]
			_gap_trigger("GapTrigger_%d" % (i + 1), j.curve if j.has("curve") else curve, j.lip, j.landing)

	# --- boost pads ------------------------------------------------------------
	var pads := _pads(b, built_branches)

	# --- greebles (v36): only once the splines and pads above exist -----------
	var greebles := _greebles(b)
	# --- surface zones (v38): on the road segments built above -------------------
	var surface := _surface(b)

	_remove_stale()
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	log.insert(0, "Built %.0f m lap: %d control points, tilt solve %.3f° max, %d features, %d branches, %d boost pads, %d greeble zones, %d surface zones, %.0f ms"
			% [length, curve.point_count, tilt_error_deg, b.composer.placed.size(), built_branches.size(), pads, greebles,
			surface, ms])
	for bb in built_branches:
		log.append("  %s: %.0f m, fork %.0f, rejoin %.0f (main), junctions to %.0f / from %.0f (branch), route lap %.0f m"
				% [bb.name, bb.length, bb.fork, bb.rejoin, bb.jf_b, bb.jr_b, bb.route_length])
	for j in all_jumps:
		var jf: JumpFeature = j.node
		if not jf.clean_speed_valid():
			log.append("⚠ %s: clean_speed not measured for this shape (run measure_jumps_boot.gd)" % jf.name)


## Composite distance -> MainSpline (baked) distance.
func to_main(s: float) -> float:
	var n := _map_s.size()
	if s <= _map_s[0]:
		return _map_d[0]
	if s >= _map_s[n - 1]:
		return _map_d[n - 1]
	var lo := 0
	var hi := n - 1
	while hi - lo > 1:
		var mid := (lo + hi) >> 1
		if _map_s[mid] <= s:
			lo = mid
		else:
			hi = mid
	var t := (s - _map_s[lo]) / maxf(_map_s[hi] - _map_s[lo], 1e-6)
	return lerpf(_map_d[lo], _map_d[hi], t)


# =============================================================================
# CENTRE LINE
# =============================================================================

## Control points from the composite samples. `must` = composite distances
## that get a point of their own (jump lips and landings).
func _emit_points(s: TrackSampler, t: Turtle, src: PackedInt32Array, must: PackedFloat32Array,
		closed: bool) -> void:
	var n := s.size()
	var need := {}
	for m in must:
		need[clampi(int(round(m / s.step())), 1, n - 1)] = true
	var last := 0
	var since := 0.0
	_add(t, s, 0, 0.0, src)
	for k in range(1, n):
		since += s.step()
		var remaining := (n - k) * s.step()
		if remaining < MIN_SPACING:
			break
		var turned := rad_to_deg(s.T[last].angle_to(s.T[k]) + s.U[last].angle_to(s.U[k]))
		var in_feat := s.feat[k] >= 0
		var min_sp := MIN_SPACING_FEATURE if in_feat else MIN_SPACING
		var max_turn := MAX_TURN_DEG_FEATURE if in_feat else MAX_TURN_DEG
		if need.has(k) or since >= MAX_SPACING or (turned >= max_turn and since >= min_sp - 0.001):
			_add(t, s, k, s.S[k], src)
			last = k
			since = 0.0
	if closed:
		# Close on the first point: an OPEN curve with coincident ends (a closed
		# Curve3D's closing span would unwind the accumulated tilt).
		_add(t, s, 0, s.length, src)
	else:
		_add(t, s, n - 1, s.length, src)


func _add(t: Turtle, s: TrackSampler, j: int, arc: float, src: PackedInt32Array) -> void:
	t.P.append(s.P[j])
	t.T.append(s.T[j])
	t.U.append(s.U[j])
	t.S.append(arc)
	src.append(j)


## Copies points, handles and tilts into an existing curve, so the scene keeps
## the same sub-resource (and the file stays stable from build to build).
static func _copy_curve(from: Curve3D, to: Curve3D) -> void:
	to.clear_points()
	to.closed = from.closed
	to.bake_interval = from.bake_interval
	to.up_vector_enabled = from.up_vector_enabled
	for i in from.point_count:
		to.add_point(from.get_point_position(i), from.get_point_in(i), from.get_point_out(i))
		to.set_point_tilt(i, from.get_point_tilt(i))


# =============================================================================
# BRANCHES
# =============================================================================

## Builds one branch: its spline, road and walls (the main track's are cut
## around the junctions by the caller), the junctions, the route lap. Returns
## what the graph needs, or {} after _fail().
func _branch(be: TrackBranchEval, bi: int, main_map: DistMap, mat: Material, road_mat: Material,
		wall_mat: Material) -> Dictionary:
	var sfx := "" if bi == 0 else "_%d" % (bi + 1)
	var bs := be.track
	# Spline.
	var must := PackedFloat32Array()
	for p in be.composer.placed:
		for k in ["lip", "landing"]:
			if p.marks.has(k):
				must.append(p.marks[k])
	var t := Turtle.new()
	var src := PackedInt32Array()
	_emit_points(bs, t, src, must, false)
	var offs := PackedFloat32Array()
	var built := t.build_curve("TRACK BUILDER %s" % be.node.name, offs)
	if built == null:
		_fail("%s: tilt solve failed" % be.node.name)
		return {}
	var bmap := DistMap.new()
	bmap.s = PackedFloat32Array(t.S)
	bmap.d = offs
	var path := _ensure(root, "BranchSpline" + sfx, "Path3D") as Path3D
	if path.curve == null:
		path.curve = Curve3D.new()
	_copy_curve(built, path.curve)
	var blen := path.curve.get_baked_length()
	var jf_b := bmap.at(be.jf_b)
	var jr_b := bmap.at(be.jr_b)
	# Jumps on the branch.
	var jumps: Array[Dictionary] = []
	for p in be.composer.placed:
		if p.node is JumpFeature:
			jumps.append({node = p.node, branch = bi, curve = path.curve,
					kicker = bmap.at(p.marks.kicker), lip = bmap.at(p.marks.lip),
					landing = bmap.at(p.marks.landing), end = bmap.at(p.marks.end)})
	# Road and walls. The branch's inner wall faces the main track.
	var widths := _width_profile(bs, src, offs)
	var gaps: Array[Dictionary] = []
	for j in jumps:
		gaps.append({a = j.lip, b = j.landing, junction = false})
	var juncs: Array[Dictionary] = [{a = 0.0, b = jf_b, junction = true}, {a = jr_b, b = blen, junction = true}]
	var none: Array[Dictionary] = []
	_pieces_out(path, "Road", _road_poly(), LAYER_GROUND, 100.0, ROAD_HALF, widths, road_mat,
			_pieces(_cat([gaps, juncs]), blen), false)
	var inner_left := be.side > 0.0
	_pieces_out(path, "WallL", WALL_LEFT_POLY, LAYER_WALLS, 50.0, 0.0, widths, wall_mat,
			_pieces(_cat([gaps, juncs if inner_left else none]), blen), false)
	_pieces_out(path, "WallR", WALL_RIGHT_POLY, LAYER_WALLS, 50.0, 0.0, widths, wall_mat,
			_pieces(_cat([gaps, none if inner_left else juncs]), blen), false)
	# Junctions (flat union road + splitter wedge).
	var fork := main_map.at(be.s_fork)
	var rejoin := main_map.at(be.s_rejoin)
	var jf_m := main_map.at(be.jf_m)
	var jr_m := main_map.at(be.jr_m)
	_junction("ForkJunction" + sfx, "BranchSpline" + sfx, fork, jf_m, 0.0, jf_b, true, road_mat, mat)
	_junction("RejoinJunction" + sfx, "BranchSpline" + sfx, jr_m, rejoin, jr_b, blen, false, road_mat,
			mat)
	# Route lap: main to the fork, the branch, main from the rejoin.
	var route := _route_lap(be, Turtle.new())
	if route.is_empty():
		return {}
	var rpath := _ensure(root, "RouteSpline_Branch" + sfx, "Path3D") as Path3D
	if rpath.curve == null:
		rpath.curve = Curve3D.new()
	_copy_curve(route.curve, rpath.curve)
	return {name = "BranchSpline" + sfx, route_name = "RouteSpline_Branch" + sfx, label = be.node.branch_name,
			length = blen, fork = fork, rejoin = rejoin, jf_b = jf_b, jr_b = jr_b, jf_m = jf_m, jr_m = jr_m,
			side = be.side, jumps = jumps, route_fork = route.fork, route_rejoin = route.rejoin,
			route_length = rpath.curve.get_baked_length(), curve = path.curve, map = bmap}


## A whole lap through the branch as one curve (the AI, its trainer and the
## cinematic rig all work in "a lap along one spline"). Logic only. Emitted
## adaptively like the MainSpline, from main samples up to the fork, the
## branch, and main samples from the rejoin.
func _route_lap(be: TrackBranchEval, t: Turtle) -> Dictionary:
	var main := _main_sampler
	var rs := TrackSampler.new()
	rs.closed = true
	# (Not a lambda: GDScript lambdas capture locals by value.)
	var st := {arc = 0.0, prev = Vector3.INF}
	for i in main.size():
		if main.S[i] < be.s_fork - 0.5:
			_take(rs, st, main, i)
	var fork_s: float = st.arc
	for i in be.track.size():
		_take(rs, st, be.track, i)
	var rejoin_s: float = st.arc
	for i in main.size():
		if main.S[i] > be.s_rejoin + 0.5:
			_take(rs, st, main, i)
	rs.length = st.arc + (st.prev as Vector3).distance_to(rs.P[0])
	var src := PackedInt32Array()
	var must := PackedFloat32Array([fork_s, rejoin_s])
	_emit_points_arc(rs, t, src, must)
	var offs := PackedFloat32Array()
	var c := t.build_curve("TRACK BUILDER route via %s" % be.node.name, offs)
	if c == null:
		_fail("%s: route lap tilt solve failed" % be.node.name)
		return {}
	var m := DistMap.new()
	m.s = PackedFloat32Array(t.S)
	m.d = offs
	return {curve = c, fork = m.at(fork_s), rejoin = m.at(rejoin_s)}


func _take(rs: TrackSampler, st: Dictionary, src_s: TrackSampler, i: int) -> void:
	var p := src_s.P[i]
	if st.prev != Vector3.INF:
		if p.distance_to(st.prev) < 0.5:
			return
		st.arc += p.distance_to(st.prev)
	rs.P.append(p)
	rs.T.append(src_s.T[i])
	rs.U.append(src_s.U[i])
	rs.S.append(st.arc)
	rs.feat.append(src_s.feat[i] if src_s.feat.size() > i else -1)
	st.prev = p


## The route lap is logic only (AI steering and the rig on that route; no road
## is built from it), so its points are sparser: every 2° of turn, at most
## 20 m apart. Keeps the scene file about half the size.
const ROUTE_MAX_TURN_DEG := 2.0
const ROUTE_MAX_SPACING := 20.0

## _emit_points for a closed sample list whose spacing isn't uniform (the
## route lap): uses the samples' own S.
func _emit_points_arc(s: TrackSampler, t: Turtle, src: PackedInt32Array, must: PackedFloat32Array) -> void:
	var n := s.size()
	var need := {}
	for m in must:
		var best := 0
		for i in n:
			if absf(s.S[i] - m) < absf(s.S[best] - m):
				best = i
		need[best] = true
	var last := 0
	_add(t, s, 0, 0.0, src)
	for k in range(1, n):
		var since := s.S[k] - s.S[last]
		if s.length - s.S[k] < MIN_SPACING:
			break
		var turned := rad_to_deg(s.T[last].angle_to(s.T[k]) + s.U[last].angle_to(s.U[k]))
		if need.has(k) or since >= ROUTE_MAX_SPACING or (turned >= ROUTE_MAX_TURN_DEG and since >= MIN_SPACING - 0.001):
			_add(t, s, k, s.S[k], src)
			last = k
	_add(t, s, 0, s.length, src)


func _junction(n: String, branch_path: String, a0: float, a1: float, b0: float, b1: float, fork: bool,
		mat: Material, splitter_mat: Material) -> void:
	var j := _ensure(root, n, TrackJunction) as TrackJunction
	j.path_a = NodePath("../MainSpline")
	j.path_b = NodePath("../" + branch_path)
	j.a_start = a0
	j.a_end = a1
	j.b_start = b0
	j.b_end = b1
	j.point_at_start = fork
	j.material = mat
	j.splitter_material = splitter_mat
	if j.is_inside_tree():
		j.build()


# =============================================================================
# GEOMETRY
# =============================================================================

## Road pieces (MainSpline distances) between the jump gaps. One piece for the
## whole lap when there are no jumps; otherwise the piece across the lap seam
## is split at the seam (the two halves are welded).
static func _cat(parts: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for p: Array in parts:
		for d: Dictionary in p:
			out.append(d)
	return out


## `cuts`: [{a, b, junction}] ranges with no road (gaps) or another road's
## junction. Returns [{a, b, fade_in, fade_out, caps}]: the edge lips fade
## out into a junction and back in after it (TrackJunction is flat).
func _pieces(cuts: Array[Dictionary], length: float) -> Array[Dictionary]:
	cuts = cuts.duplicate()
	cuts.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return x.a < y.a)
	var out: Array[Dictionary] = []
	var cursor := 0.0
	var prev_junction := false
	for c in cuts:
		if c.a - cursor > 0.5:
			out.append({a = cursor, b = c.a, fade_in = LIP_FADE if prev_junction else 0.0,
					fade_out = LIP_FADE if c.junction else 0.0})
		cursor = maxf(cursor, c.b)
		prev_junction = c.junction
	if length - cursor > 0.5:
		out.append({a = cursor, b = length, fade_in = LIP_FADE if prev_junction else 0.0, fade_out = 0.0})
	for p in out:
		p.caps = cuts.size() > 0
	return out


func _pieces_out(path: Path3D, base_name: String, poly: Array, layer: int, u_dist: float, stretch: float,
		widths: PackedVector3Array, mat: Material, pieces: Array[Dictionary], weld: bool) -> void:
	for i in pieces.size():
		var sfx := "" if i == 0 else "_%d" % (i + 1)
		var pc: Dictionary = pieces[i]
		_segment(path, base_name + sfx, poly, layer, mat, u_dist, widths, stretch, Vector2(pc.a, pc.b),
				pc.caps, weld, pc.fade_in, pc.fade_out)


## (MainSpline distance, left, right) at the control points, keeping only the
## points where the width is changing (and the ends of each change). Empty when
## the width is the standard all the way round.
func _width_profile(s: TrackSampler, src: PackedInt32Array, offsets: PackedFloat32Array) -> PackedVector3Array:
	var all := PackedVector3Array()
	var any := false
	for k in src.size():
		var j := src[k]
		var w := Vector3(offsets[k], s.width_l[j], s.width_r[j])
		all.append(w)
		if not is_equal_approx(w.y, ROAD_EDGE) or not is_equal_approx(w.z, ROAD_EDGE):
			any = true
	if not any:
		return PackedVector3Array()
	var out := PackedVector3Array()
	var n := all.size()
	for k in n:
		var keep := k == 0 or k == n - 1
		if not keep:
			var a := all[k - 1]
			var c := all[k + 1]
			var w := all[k]
			keep = not (_same_w(a, w) and _same_w(w, c))
		if keep:
			out.append(all[k])
	return out


static func _same_w(a: Vector3, b: Vector3) -> bool:
	return absf(a.y - b.y) < 0.005 and absf(a.z - b.z) < 0.005


func _segment(path: Path3D, n: String, poly: Array, layer: int, mat: Material, u_dist: float,
		widths: PackedVector3Array, stretch: float, piece: Vector2, caps: bool, weld: bool = true,
		fade_in: float = 0.0, fade_out: float = 0.0) -> void:
	var seg := _ensure(path, n, TrackRoadSegment) as TrackRoadSegment
	seg.path_node = NodePath("..")
	seg.start_distance = piece.x
	seg.end_distance = -1.0 if piece.y >= path.curve.get_baked_length() - 0.001 else piece.y
	seg.polygon = PackedVector2Array(poly)
	seg.interval = 1.0
	seg.collision_layer = layer
	seg.material = mat
	seg.u_distance = u_dist
	seg.fade_in = fade_in
	seg.fade_out = fade_out
	# Caps close the road at a jump's lip and landing (the front of a landing
	# ramp is a solid face). A whole-lap piece has none: no seam faces.
	seg.caps = caps
	seg.width_profile = widths
	seg.width_reference = ROAD_EDGE
	seg.width_stretch_limit = stretch
	seg.weld_lap_seam = weld
	if seg.is_inside_tree():
		seg.build()


func _road_poly() -> Array:
	var pts := [Vector2(ROAD_HALF + 2.0, 0.9)]
	var n := int(ceil(2.0 * ROAD_HALF / ROAD_STRIP))
	for i in n + 1:
		pts.append(Vector2(ROAD_HALF - 2.0 * ROAD_HALF * i / n, 0.0))
	pts.append(Vector2(-ROAD_HALF - 2.0, 0.9))
	pts.append(Vector2(-ROAD_HALF - 2.0, -2.0))
	pts.append(Vector2(ROAD_HALF + 2.0, -2.0))
	return pts


func _start(lead: float) -> void:
	var sp := _ensure(root, "StartingPoint", "Node")
	var line := _ensure(sp, "StartFinishLine", load(LINE_SCENE)) as Node3D
	var lf := TrackRoadSegment.frame_at(curve, lead)
	lf.basis = lf.basis.scaled(Vector3(1.5, 1.5, 1.5))
	lf.origin += lf.basis.y.normalized() * 0.05
	line.transform = lf
	var grid := _ensure(sp, "StartingGrid", StartingGrid) as Node3D
	var length := curve.get_baked_length()
	for i in GRID_SLOTS:
		var d := fposmod(length - (i * GRID_SPACING + 25.0) + lead, length)
		var f := TrackRoadSegment.frame_at(curve, d)
		var side := GRID_LATERAL if i % 2 == 0 else -GRID_LATERAL
		var m := _ensure(grid, "Slot%d" % (i + 1), "Marker3D") as Marker3D
		m.gizmo_extents = 3.25
		m.transform = Transform3D(f.basis, f.origin + f.basis.x * side + f.basis.y * 3.0)


func _magnetic(zones: Array[Dictionary]) -> void:
	var mt := _ensure(root, "MagneticTrack", MagneticTrack) as MagneticTrack
	mt.spline_path = NodePath("../MainSpline")
	var old := mt.zones
	var list: Array[MagneticZone] = []
	for i in zones.size():
		var z: MagneticZone = old[i] if i < old.size() and old[i] != null else MagneticZone.new()
		var d: Dictionary = zones[i]
		z.zone_name = d.name
		z.start_distance = d.from
		z.end_distance = d.to
		z.ramp_in = d.ramp_in
		z.ramp_out = d.ramp_out
		z.magnet_strength = d.magnet
		list.append(z)
	mt.zones = list


func _graph(jumps: Array[Dictionary], branches: Array[Dictionary]) -> void:
	var g := _ensure(root, "TrackGraph", TrackGraph) as TrackGraph
	g.main_path = NodePath("../MainSpline")
	var oldb := g.branches
	var blist: Array[TrackBranch] = []
	for i in branches.size():
		var tb: TrackBranch = oldb[i] if i < oldb.size() and oldb[i] != null else TrackBranch.new()
		var d: Dictionary = branches[i]
		tb.branch_name = d.label
		tb.path = NodePath("../" + d.name)
		tb.fork_distance = d.fork
		tb.rejoin_distance = d.rejoin
		tb.fork_blend = d.jf_b
		tb.rejoin_blend = d.length - d.jr_b
		tb.route_path = NodePath("../" + d.route_name)
		tb.route_fork = d.route_fork
		tb.route_rejoin = d.route_rejoin
		blist.append(tb)
	g.branches = blist
	var old := g.jumps
	var list: Array[TrackJump] = []
	for i in jumps.size():
		var j: TrackJump = old[i] if i < old.size() and old[i] != null else TrackJump.new()
		var d: Dictionary = jumps[i]
		var jf: JumpFeature = d.node
		j.jump_name = jf.name
		j.branch = d.get("branch", -1)
		j.kicker_start = d.kicker
		j.lip = d.lip
		j.landing = d.landing
		j.landing_end = d.end
		j.respawn_runup = jf.respawn_runup
		j.clean_speed = jf.clean_speed if jf.clean_speed_valid() else 0.0
		list.append(j)
	g.jumps = list


## The BoostPads: each pad on the built road (the MainSpline's or its branch's
## frame), so it sits exactly on the surface the ship hovers over. Returns
## how many.
func _pads(b: TrackBuilder, built_branches: Array[Dictionary]) -> int:
	var placements := b.pad_placements()
	if placements.is_empty():
		return 0
	var holder := _ensure(root, "BoostPads", "Node3D") as Node3D
	holder.transform = Transform3D.IDENTITY
	var scene: PackedScene = load(PAD_SCENE)
	var used := {}
	for p in placements:
		var key: BoostPadKey = p.key
		var c := curve
		var d := 0.0
		if p.branch < 0:
			d = to_main(p.s)
		else:
			var bb: Dictionary = built_branches[p.branch]
			c = bb.curve
			d = (bb.map as DistMap).at(p.s)
		var f := TrackRoadSegment.frame_at(c, d)
		var n := String(key.name) if key.count == 1 else "%s_%d" % [key.name, p.i + 1]
		while used.has(n):
			n += "_"     # same key name in two folders
		used[n] = true
		var pad := _ensure(holder, n, scene) as Node3D
		# The pad scene's chevrons point down its +Z (as the hand-placed pads
		# on the old circuits face): +Z along the direction of travel.
		var pb := Basis(-f.basis.x, f.basis.y, -f.basis.z)
		pad.transform = Transform3D(pb, f.origin + f.basis.x * float(p.x))
		pad.set("boost_strength", key.strength)
	return placements.size()


## TrackGreebles from the GreebleZoneKeys (TrackGreebler), if there are any.
## With no keys nothing is made (and a TrackGreebles left from an earlier
## build is removed as stale). Returns the zone count.
func _greebles(b: TrackBuilder) -> int:
	if TrackGreebler.all_keys(b).is_empty():
		return 0
	var node := _ensure(root, TrackBuilder.GREEBLES_NODE, load(TrackBuilder.GREEBLES_SCRIPT)) as TrackGreebles
	var g := TrackGreebler.resolve(b, root)
	g.write(node, b)
	for n in g.notes:
		log.append("⚠ " + n)
	if node.is_inside_tree() and Engine.is_editor_hint():
		node.rebuild()
	return node.zones.size()


## TrackSurface from the SurfaceZoneKeys (TrackSurfacer), if there are any.
## With no keys nothing is made (a TrackSurface left from an earlier build is
## removed as stale). Returns the zone count.
func _surface(b: TrackBuilder) -> int:
	if not TrackSurfacer.has_keys(b):
		return 0
	var node := _ensure(root, TrackBuilder.SURFACE_NODE, load(TrackBuilder.SURFACE_SCRIPT)) as TrackSurface
	var sf := TrackSurfacer.resolve(b, root)
	sf.write(node, b)
	for n in sf.notes:
		log.append("⚠ " + n)
	if node.is_inside_tree():
		node.apply()
	return node.zones.size()


## A respawn trigger below the gap, as on Fork Lab: a ship that clears the gap
## never gets there; one that falls short is caught a moment after it drops.
func _gap_trigger(n: String, c: Curve3D, lip: float, landing: float) -> void:
	var area := _ensure(root, n, load(GAP_TRIGGER_SCRIPT)) as Area3D
	var a := c.sample_baked(lip, true)
	var b := c.sample_baked(landing, true)
	var low := minf(a.y, b.y)
	var mid := (a + b) * 0.5
	var fwd := (b - a).slide(Vector3.UP).normalized()
	var basis := Basis(fwd.cross(Vector3.UP).normalized(), Vector3.UP, -fwd)
	var top := low - 10.0
	var bottom := low - 70.0
	area.transform = Transform3D(basis, Vector3(mid.x, (top + bottom) * 0.5, mid.z))
	area.collision_layer = 0
	area.collision_mask = 2
	var cs := _ensure(area, "Shape", "CollisionShape3D") as CollisionShape3D
	var box := cs.shape as BoxShape3D
	if box == null:
		box = BoxShape3D.new()
		cs.shape = box
	box.size = Vector3(90.0, top - bottom, a.distance_to(b) + 80.0)


# =============================================================================
# NODE BOOKKEEPING
# =============================================================================

## The child `n` of `parent`, of the given kind (a class name, a Script or a
## PackedScene), made if missing. Existing generated nodes are reused as they
## are; a generated node of the wrong kind is replaced.
func _ensure(parent: Node, n: String, kind: Variant) -> Node:
	var node := parent.get_node_or_null(NodePath(n))
	if node and not _is_kind(node, kind):
		if not node.is_in_group(GROUP):
			push_warning("TrackBuild: %s is hand-made; renaming it out of the way" % node.get_path())
			node.name = n + "_old"
		else:
			parent.remove_child(node)
			node.free()
		node = null
	if node == null:
		if kind is PackedScene:
			node = (kind as PackedScene).instantiate()
		elif kind is Script:
			node = (kind as Script).new()
		else:
			node = ClassDB.instantiate(kind)
		node.name = n
		parent.add_child(node)
		node.owner = root
		node.add_to_group(GROUP, true)
	elif not node.is_in_group(GROUP):
		# A hand-made node with the right name and kind (e.g. a StartingPoint
		# left over from a manual setup): adopt it.
		node.add_to_group(GROUP, true)
	_touched[node] = true
	return node


static func _is_kind(node: Node, kind: Variant) -> bool:
	if kind is PackedScene:
		return node.scene_file_path == (kind as PackedScene).resource_path
	if kind is Script:
		return node.get_script() == kind
	return node.get_class() == kind and node.get_script() == null


func _remove_stale() -> void:
	var stale: Array[Node] = []
	_collect_stale(root, stale)
	for n in stale:
		if is_instance_valid(n):
			log.append("Removed %s (no longer generated)" % root.get_path_to(n))
			n.get_parent().remove_child(n)
			n.free()


func _collect_stale(n: Node, out: Array[Node]) -> void:
	for c in n.get_children():
		if c.is_in_group(GROUP) and not _touched.has(c):
			out.append(c)
			continue
		if c.owner == root:
			_collect_stale(c, out)


func _fail(msg: String) -> void:
	ok = false
	log.append("✗ " + msg)
	push_warning("TrackBuild: " + msg)
