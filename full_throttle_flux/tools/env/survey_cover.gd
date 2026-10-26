extends SceneTree
## Finds where the road is COVERED -- tunnel, building, sky-bridge, arch, or
## the track crossing over itself -- and writes those stretches as TrackFxZones
## with covered = 1 (v35). Rain and snow cut out there, the road stays dry.
##
##   godot --headless --path . -s res://tools/env/survey_cover.gd -- [track scene] [out .tres]
##
## Defaults: Utopia -> res://resources/track_fx/test_circuit_3_live_cover.tres
## Then add the .tres to the track's TrackEnvironment.zone_sets (or a
## TrackFxZones node). Re-run after layout changes; it never touches
## hand-authored zones.
##
## How: the city meshes have no collision, so the tool gives every
## MeshInstance3D / MultiMeshInstance3D temporary trimesh collision on its own
## layer (never saved). Then every STEP metres along MainSpline it finds the
## road (through UtopiaKit's road transform, so the circuits' offset is
## handled) and casts up from three points across it. A point is covered when
## at least 2 of the 3 rays hit something within MAX_HEIGHT; runs closer than
## MERGE_GAP merge, runs shorter than MIN_SPAN are dropped (lamp arms, signs).

const STEP := 2.0
const LATERAL := 5.0          # metres either side of the centre ray
const ROAD_UP := 6.0          # road search: from this far above the centreline...
const ROAD_DOWN := 10.0       # ...to this far below it
const START_HEIGHT := 4.0     # cover rays start this far above the road
const MAX_HEIGHT := 80.0
const MERGE_GAP := 10.0
const MIN_SPAN := 8.0
const RAMP := 8.0
const GROUND_MASK := 1
const COVER_LAYER := 1 << 15
const MAX_MULTIMESH_INSTANCES := 4000
const DEFAULT_TRACK := "res://scenes/tracks/test_circuit_3_live.tscn"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var track_path: String = args[0] if args.size() > 0 else DEFAULT_TRACK
	var out_path: String = args[1] if args.size() > 1 else \
		"res://resources/track_fx/%s_cover.tres" % track_path.get_file().get_basename()

	var track: Node3D = load(track_path).instantiate()
	root.add_child(track)
	for i in 4:
		await physics_frame

	var spline := track.find_child("MainSpline", true, false) as Path3D
	if spline == null or spline.curve == null:
		push_error("survey_cover: no MainSpline in %s" % track_path)
		quit(1)
		return
	var length := spline.curve.get_baked_length()
	var kit := UtopiaKit.new(track)
	var space := root.get_world_3d().direct_space_state

	# --- 1. Road points, BEFORE any temporary collision exists ------------------
	var road: Array = []   # per sample: [surface point, up, right]
	var misses := 0
	var n := int(floor(length / STEP))
	for i in n:
		var d := i * STEP
		var c := kit.center(d)
		var b := kit.frame(d)
		var q := PhysicsRayQueryParameters3D.create(c + b.y * ROAD_UP, c - b.y * ROAD_DOWN, GROUND_MASK)
		var hit := space.intersect_ray(q)
		var p: Vector3 = hit.position if not hit.is_empty() else c + b.y * 2.0
		if hit.is_empty():
			misses += 1
		road.append([p, b.y, b.x])

	# --- 2. Temporary collision for everything that could be overhead ---------
	var bodies := _add_collision(track, spline)
	for i in 3:
		await physics_frame

	# --- 3. Cover rays -----------------------------------------------------------
	var covered := PackedByteArray()
	covered.resize(n)
	for i in n:
		var p: Vector3 = road[i][0]
		var up: Vector3 = road[i][1]
		var right: Vector3 = road[i][2]
		var hits := 0
		for lat in [-LATERAL, 0.0, LATERAL]:
			var from: Vector3 = p + right * lat + up * START_HEIGHT
			var q := PhysicsRayQueryParameters3D.create(from, from + up * MAX_HEIGHT, COVER_LAYER | GROUND_MASK)
			q.hit_back_faces = true
			if not space.intersect_ray(q).is_empty():
				hits += 1
		covered[i] = 1 if hits >= 2 else 0

	# --- 4. Spans ---------------------------------------------------------------
	var spans := _spans(covered, n)
	var zone_set := TrackFxZoneSet.new()
	zone_set.source = "tools/env/survey_cover.gd on %s, %s" % [track_path, Time.get_datetime_string_from_system()]
	for s in spans:
		var z := TrackFxZone.new()
		z.zone_name = "Covered %d-%d" % [int(s.x), int(s.y)]
		z.start_distance = s.x
		z.end_distance = s.y
		z.ramp_in = RAMP
		z.ramp_out = RAMP
		z.covered = 1.0
		zone_set.zones.append(z)

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_path.get_base_dir()))
	var err := ResourceSaver.save(zone_set, out_path)
	print("survey_cover: %s  length %.0f m  samples %d  road misses %d  collision bodies %d" % [
		track_path, length, n, misses, bodies])
	for z in zone_set.zones:
		print("  %-22s %7.0f -> %7.0f m" % [z.zone_name, z.start_distance, z.end_distance])
	print("survey_cover: %d spans -> %s (%s)" % [zone_set.zones.size(), out_path, error_string(err)])
	quit(0 if err == OK else 1)


## Trimesh collision on COVER_LAYER for every mesh outside MainSpline's own
## road geometry. Returns how many bodies were added.
func _add_collision(track: Node, spline: Node) -> int:
	var count := 0
	for n in track.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null or spline.is_ancestor_of(mi):
			continue
		count += _body(mi, mi.mesh, [Transform3D.IDENTITY])
	for n in track.find_children("*", "MultiMeshInstance3D", true, false):
		var mmi := n as MultiMeshInstance3D
		var mm := mmi.multimesh
		if mm == null or mm.mesh == null or spline.is_ancestor_of(mmi):
			continue
		if mm.instance_count > MAX_MULTIMESH_INSTANCES:
			print("survey_cover: skipping %s (%d instances)" % [mmi.name, mm.instance_count])
			continue
		var xfs: Array = []
		for i in mm.instance_count:
			xfs.append(mm.get_instance_transform(i))
		count += _body(mmi, mm.mesh, xfs)
	return count


func _body(parent: Node3D, mesh: Mesh, xfs: Array) -> int:
	var shape := mesh.create_trimesh_shape()
	if shape == null:
		return 0
	var body := StaticBody3D.new()
	body.collision_layer = COVER_LAYER
	body.collision_mask = 0
	for xf in xfs:
		var cs := CollisionShape3D.new()
		cs.shape = shape
		cs.transform = xf
		body.add_child(cs)
	parent.add_child(body)
	return 1


## Covered runs as Vector2(start, end) in metres, merged across small gaps and
## across the lap seam, short runs dropped.
func _spans(covered: PackedByteArray, n: int) -> Array[Vector2]:
	var runs: Array[Vector2] = []   # sample indices, end inclusive
	var i := 0
	while i < n:
		if covered[i] == 0:
			i += 1
			continue
		var j := i
		while j + 1 < n and covered[j + 1] == 1:
			j += 1
		runs.append(Vector2(i, j))
		i = j + 1
	if runs.is_empty():
		return []
	var gap := int(ceil(MERGE_GAP / STEP))
	var merged: Array[Vector2] = [runs[0]]
	for k in range(1, runs.size()):
		var last := merged[-1]
		if runs[k].x - last.y <= gap:
			merged[-1] = Vector2(last.x, runs[k].y)
		else:
			merged.append(runs[k])
	# Across the lap seam: last run + first run = one wrapping run.
	if merged.size() > 1 and (n - 1 - merged[-1].y) + merged[0].x <= gap:
		var first: Vector2 = merged.pop_front()
		merged[-1] = Vector2(merged[-1].x, first.y)   # end < start = wraps
	var out: Array[Vector2] = []
	for r in merged:
		var a := r.x * STEP
		var b := r.y * STEP
		var span_len := b - a if b >= a else (n * STEP - a) + b
		if span_len + STEP >= MIN_SPAN:
			out.append(Vector2(a, b))
	return out
