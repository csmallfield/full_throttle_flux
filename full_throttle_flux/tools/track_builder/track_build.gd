extends RefCounted
class_name TrackBuild
## Track Builder: the Build step (v34).
##
## Turns the TrackBuilder's inputs (BaseSpline, BankKeys, WidthKeys, StartKey)
## into what the game runs on, as direct children of the track root:
##
##   MainSpline (Path3D)          dense resample of the faired base, tilts SOLVED
##     Road, WallL, WallR         TrackRoadSegments with the width profile
##   StartingPoint
##     StartFinishLine, StartingGrid (Slot1..8)
##
## The MainSpline stays a direct child of the root because MagneticTrack,
## TrackGraph and the probes look for "../MainSpline" / the root.
##
## Generated nodes are tagged with the GROUP and UPDATED IN PLACE by name on
## every build (Godot 4.7 gives each saved node a random unique_id, so
## recreating nodes would churn the .tscn on every build). Building twice
## without changing anything leaves the scene file byte-identical. Nodes in
## the group that a build no longer makes are removed. Nothing outside the
## group is touched (set dressing, lights, environment are yours).

const Turtle := preload("res://tools/fork_lab/fork_lab_turtle.gd")
const GROUP := "track_builder_generated"
const META_HASH := "track_builder_input_hash"
const ROAD_MAT := "res://shaders/resources/grid_material.tres"
const LINE_SCENE := "res://scenes/start_finish_line.tscn"

# Control point spacing of the generated MainSpline: a new point when the
# tangent or the up vector has turned MAX_TURN_DEG since the last one, or
# after MAX_SPACING metres. Dense in corners and bank changes, sparse on
# straights (keeps the scene file small).
const MAX_SPACING := 12.0
const MIN_SPACING := 2.0
const MAX_TURN_DEG := 1.0
const TILT_LIMIT_DEG := 0.2

# Cross-sections: the circuits' (as on Loop Lab / Fork Lab).
const ROAD_HALF := 19.5
const ROAD_EDGE := 21.5
const ROAD_STRIP := 3.0
const WALL_RIGHT_POLY := [Vector2(28.5, 8.5), Vector2(23.5, 8.4), Vector2(21.1, 6.5), Vector2(21.1, -2.0), Vector2(28.6, -2.0)]
const WALL_LEFT_POLY := [Vector2(-21.1, 6.5), Vector2(-23.5, 8.4), Vector2(-28.5, 8.5), Vector2(-28.6, -2.0), Vector2(-21.1, -2.0)]
const LAYER_GROUND := 1
const LAYER_WALLS := 4

const GRID_SLOTS := 8
const GRID_SPACING := 22.0
const GRID_LATERAL := 8.0

var ok := true
var log: PackedStringArray = []
var root: Node
var curve: Curve3D
## MainSpline distance 0 sits at this base distance.
var origin_d := 0.0
var tilt_error_deg := 0.0
var _touched := {}


static func run(b: TrackBuilder) -> TrackBuild:
	var tb := TrackBuild.new()
	tb._run(b)
	return tb


func _run(b: TrackBuilder) -> void:
	var t0 := Time.get_ticks_usec()
	root = b.owner if b.owner else b.get_parent()
	if root == null:
		_fail("The TrackBuilder needs to be inside a track scene.")
		return
	if not b.evaluate():
		_fail("No BaseSpline curve to build from.")
		return
	var s := b.sampler
	if not s.closed:
		_fail("BaseSpline must be a closed loop (tick Closed on its Curve3D).")
		return
	var existing := root.get_node_or_null("MainSpline")
	if existing and not existing.is_in_group(GROUP):
		_fail("The scene already has a hand-made MainSpline. Rename or delete it; the builder makes its own.")
		return

	# --- where the lap starts ------------------------------------------------
	var starts := b.keys_of("StartKey")
	var line_d := starts[0].distance if starts.size() > 0 else 0.0
	if starts.size() > 1:
		log.append("⚠ %d StartKeys: using %s" % [starts.size(), starts[0].name])
	origin_d = fposmod(line_d - b.start_lead, s.length)

	# --- dense centre line, tilts solved against Godot's frame ---------------
	var t := Turtle.new()
	var src := PackedInt32Array()    # sample index behind each control point
	_emit_points(s, t, src)
	var offsets := PackedFloat32Array()
	var built := t.build_curve("TRACK BUILDER %s" % root.name, offsets)
	if built == null:
		_fail("Tilt solve failed (see the output log).")
		return
	tilt_error_deg = rad_to_deg(t._tilt_error(built, offsets))

	var main := _ensure(root, "MainSpline", "Path3D") as Path3D
	if main.curve == null:
		main.curve = Curve3D.new()
	_copy_curve(built, main.curve)
	curve = main.curve
	main.set_meta(META_HASH, b.input_hash())

	# --- road and walls ------------------------------------------------------
	var widths := _width_profile(s, src, offsets)
	var mat: Material = load(ROAD_MAT)
	_segment(main, "Road", _road_poly(), LAYER_GROUND, mat, 100.0, widths, ROAD_HALF)
	_segment(main, "WallL", WALL_LEFT_POLY, LAYER_WALLS, mat, 50.0, widths, 0.0)
	_segment(main, "WallR", WALL_RIGHT_POLY, LAYER_WALLS, mat, 50.0, widths, 0.0)

	# --- start line and grid -------------------------------------------------
	_start(b.start_lead)

	_remove_stale()
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	log.insert(0, "Built %.0f m lap: %d control points, tilt solve %.3f° max, %d width keys in the profile, %.0f ms"
			% [curve.get_baked_length(), curve.point_count, tilt_error_deg, widths.size(), ms])


# =============================================================================
# CENTRE LINE
# =============================================================================

func _emit_points(s: TrackSampler, t: Turtle, src: PackedInt32Array) -> void:
	var n := s.size()
	var i0 := posmod(int(round(origin_d / s.step())), n)
	var step := s.step()
	var last := i0
	var since := 0.0
	var arc := 0.0
	_add(t, s, i0, 0.0, src)
	for k in range(1, n):
		var j := (i0 + k) % n
		since += step
		arc += step
		var turned := rad_to_deg(s.T[last].angle_to(s.T[j]) + s.U[last].angle_to(s.U[j]))
		var remaining := (n - k) * step
		if remaining < MIN_SPACING:
			break
		if since >= MAX_SPACING or (turned >= MAX_TURN_DEG and since >= MIN_SPACING):
			_add(t, s, j, arc, src)
			last = j
			since = 0.0
	# Close on the first point: an OPEN curve with coincident ends (a closed
	# Curve3D's closing span would unwind the accumulated tilt).
	_add(t, s, i0, s.length, src)


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
# GEOMETRY
# =============================================================================

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
		widths: PackedVector3Array, stretch: float) -> void:
	var seg := _ensure(path, n, TrackRoadSegment) as TrackRoadSegment
	seg.path_node = NodePath("..")
	seg.start_distance = 0.0
	seg.end_distance = -1.0
	seg.polygon = PackedVector2Array(poly)
	seg.interval = 1.0
	seg.collision_layer = layer
	seg.material = mat
	seg.u_distance = u_dist
	seg.fade_in = 0.0
	seg.fade_out = 0.0
	seg.caps = false          # one piece round the whole lap: no seam caps
	seg.weld_lap_seam = true
	seg.width_profile = widths
	seg.width_reference = ROAD_EDGE
	seg.width_stretch_limit = stretch
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
