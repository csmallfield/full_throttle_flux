extends SceneTree
## Surveys the RENDERED road (groundGeo + walls) with raycasts and writes a set
## of standalone utility rails that hug it exactly:
##   scenes/tracks/utopia/utopia_road_rails.tscn
##
##   Road         centre of the driving surface
##   WallFaceL/R  inner face of each wall, 3 m above the road
##   WallTopL/R   middle of each wall's flat top
##   WallOuterL/R outer face of each wall, 3 m above the road
##
## Every rail is a closed Curve3D (one point every STEP m) whose tilt is solved
## so `curve.sample_baked_with_rotation(..., true, true)` returns a basis whose
## Y axis is the real surface normal (banking included). The rails are NOT
## connected to MainSpline: re-run this if the track geometry ever changes.
##   godot --headless --path . -s res://tools/utopia/survey_road.gd

const STEP := 4.0
const GROUND_MASK := 1
const WALL_MASK := 4
const OUT := "res://scenes/tracks/utopia/utopia_road_rails.tscn"

## Optional args (other tracks): -- <track scene> <output rails scene>
func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var track_path := args[0] if args.size() > 0 else "res://scenes/tracks/test_circuit_3_live.tscn"
	var out_path := args[1] if args.size() > 1 else OUT
	var track: Node3D = load(track_path).instantiate()
	for n in ["UtopiaCity", "UtopiaLighting", "HairpinCity", "HairpinLighting", "SwoopyCity", "SwoopyLighting"]:
		if track.has_node(n):
			track.get_node(n).free()
	root.add_child(track)
	for i in range(4):
		await physics_frame
	var kit := UtopiaKit.new(track)
	var space := root.get_world_3d().direct_space_state
	var names := ["Road", "WallFaceL", "WallFaceR", "WallTopL", "WallTopR", "WallOuterL", "WallOuterR"]
	var pts := {}
	for nm in names:
		pts[nm] = PackedVector3Array()
	var normals := PackedVector3Array()
	var misses := 0
	var missed := {}   # rail name -> [indices]
	var d := 0.0
	while d < kit.length - STEP * 0.5:
		var c := kit.center(d)
		var f := kit.frame(d)
		# --- road surface ---
		var hit := _ray(space, c + f.y * 12.0, c - f.y * 12.0, GROUND_MASK)
		var s: Vector3 = c + f.y * 2.0
		var nrm: Vector3 = f.y
		if hit.is_empty():
			misses += 1
			print("  road miss at d=%d" % d)
		else:
			s = hit["position"]
			# CSG seams occasionally return an edge normal; trust the spline frame then
			if hit["normal"].angle_to(f.y) < deg_to_rad(12.0):
				nrm = hit["normal"]
			else:
				print("  normal rejected at d=%d" % d)
		# lateral axis in the surface plane
		var r := (-f.z).cross(nrm).normalized()
		var fwd := nrm.cross(r).normalized()
		r = fwd.cross(nrm).normalized()
		normals.append(nrm)
		pts["Road"].append(s)
		for side in [-1.0, 1.0]:
			var sfx := "L" if side < 0.0 else "R"
			var o: Vector3 = s + nrm * 3.0
			var dir: Vector3 = r * side
			var h := _ray(space, o, o + dir * 45.0, WALL_MASK)
			var face: Vector3 = o + dir * 20.0
			if h.is_empty():
				misses += 1
				missed.get_or_add("WallFace" + sfx, []).append(pts["Road"].size() - 1)
			else:
				face = h["position"]
			pts["WallFace" + sfx].append(face)
			# outer face: cast back inward from well outside
			var oo: Vector3 = o + dir * 45.0
			var ho := _ray(space, oo, face + dir * 0.5, WALL_MASK)
			var outer: Vector3 = face + dir * 7.5
			if ho.is_empty():
				misses += 1
				missed.get_or_add("WallOuter" + sfx, []).append(pts["Road"].size() - 1)
			else:
				outer = ho["position"]
			pts["WallOuter" + sfx].append(outer)
			# top: drop onto the flat top, halfway between bevel and outer edge
			var top_x: Vector3 = face.lerp(outer, 0.62)
			var ht := _ray(space, top_x + nrm * 20.0, top_x - nrm * 20.0, WALL_MASK)
			var top: Vector3 = top_x + nrm * 4.5
			if ht.is_empty() or absf((ht["position"] - s).dot(nrm) - 6.4) > 2.5:
				misses += 1
				missed.get_or_add("WallTop" + sfx, []).append(pts["Road"].size() - 1)
			else:
				top = ht["position"]
			pts["WallTop" + sfx].append(top)
		d += STEP
	# patch misses from their neighbours
	for nm in missed:
		var arr: PackedVector3Array = pts[nm]
		for i in missed[nm]:
			arr[i] = (arr[(i - 1 + arr.size()) % arr.size()] + arr[(i + 1) % arr.size()]) * 0.5
			print("  patched %s at d=%d" % [nm, i * STEP])
		pts[nm] = arr
	for sfx in ["L", "R"]:
		for i in range(pts["WallFace" + sfx].size()):
			var w: float = pts["WallFace" + sfx][i].distance_to(pts["WallOuter" + sfx][i])
			var tw: float = pts["WallFace" + sfx][i].distance_to(pts["Road"][i])
			if w < 5.0 or w > 10.0 or tw < 17.0 or tw > 24.0:
				print("  odd %s d=%d wall=%.1f face=%.1f" % [sfx, i * STEP, w, tw])
	# light smoothing of the normals (CSG facets)
	var sm := PackedVector3Array()
	var n := normals.size()
	for i in range(n):
		sm.append((normals[(i - 1 + n) % n] + normals[i] * 2.0 + normals[(i + 1) % n]).normalized())
	var rails := Node3D.new()
	rails.name = "UtopiaRoadRails"
	var report := ""
	for nm in names:
		var p := Path3D.new()
		p.name = nm
		p.curve = _build_curve(pts[nm], sm)
		rails.add_child(p)
		p.owner = rails
		report += "  %s: %d pts, %.0f m, tilt err p99 %.2f deg\n" % [nm, pts[nm].size(), p.curve.get_baked_length(), _tilt_error(p.curve, pts[nm], sm)]
	var ps := PackedScene.new()
	ps.pack(rails)
	ResourceSaver.save(ps, out_path)
	print("SURVEY: %d samples, %d ray misses\n%s" % [n, misses, report])
	quit()

func _ray(space: PhysicsDirectSpaceState3D, a: Vector3, b: Vector3, mask: int) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(a, b, mask)
	q.hit_back_faces = false
	return space.intersect_ray(q)

## Smooth closed curve through pts (Catmull-Rom handles), tilt solved so the
## baked up vector matches the surveyed normal.
func _build_curve(pts: PackedVector3Array, nrm: PackedVector3Array) -> Curve3D:
	var cv := Curve3D.new()
	cv.bake_interval = 1.0
	cv.up_vector_enabled = true
	cv.closed = true
	var n := pts.size()
	for i in range(n):
		var tan := (pts[(i + 1) % n] - pts[(i - 1 + n) % n]) / 6.0
		cv.add_point(pts[i], -tan, tan)
	# solve tilt, then verify the sign and flip if needed
	var offs := _offsets(cv, pts)
	var tilts := PackedFloat32Array()
	for i in range(n):
		var t := (pts[(i + 1) % n] - pts[(i - 1 + n) % n]).normalized()
		var u0 := cv.sample_baked_up_vector(offs[i], false)
		var a := (u0 - t * u0.dot(t)).normalized()
		var b := (nrm[i] - t * nrm[i].dot(t)).normalized()
		var tl := atan2(t.dot(a.cross(b)), a.dot(b))
		# unwrap: tilt is interpolated between points, so it must not jump by 2*PI
		if i > 0:
			while tl - tilts[i - 1] > PI:
				tl -= TAU
			while tl - tilts[i - 1] < -PI:
				tl += TAU
		tilts.append(tl)
	for i in range(n):
		cv.set_point_tilt(i, tilts[i])
	var e_pos := _tilt_error(cv, pts, nrm, 0.5)
	for i in range(n):
		cv.set_point_tilt(i, -tilts[i])
	var e_neg := _tilt_error(cv, pts, nrm, 0.5)
	if e_pos < e_neg:
		for i in range(n):
			cv.set_point_tilt(i, tilts[i])
	return cv

## Baked offset of every control point. get_closest_offset() is ambiguous
## where the track passes over/next to itself, so walk the curve locally.
func _offsets(cv: Curve3D, pts: PackedVector3Array) -> PackedFloat32Array:
	var n := pts.size()
	var cum := PackedFloat32Array([0.0])
	for i in range(1, n):
		cum.append(cum[i - 1] + pts[i].distance_to(pts[i - 1]))
	var total := cum[n - 1] + pts[0].distance_to(pts[n - 1])
	var k := cv.get_baked_length() / total
	var out := PackedFloat32Array()
	for i in range(n):
		var est := cum[i] * k
		var best := est
		var bd := INF
		var o := est - 3.0
		while o <= est + 3.0:
			var dd := cv.sample_baked(fposmod(o, cv.get_baked_length())).distance_squared_to(pts[i])
			if dd < bd:
				bd = dd
				best = o
			o += 0.1
		out.append(fposmod(best, cv.get_baked_length()))
	return out

func _tilt_error(cv: Curve3D, pts: PackedVector3Array, nrm: PackedVector3Array, pct := 0.99) -> float:
	var offs := _offsets(cv, pts)
	var errs := []
	for i in range(pts.size()):
		var u := cv.sample_baked_up_vector(offs[i], true)
		errs.append(rad_to_deg(u.angle_to(nrm[i])))
		if errs[-1] > 10.0 and OS.has_environment("SURVEY_DEBUG") and pct > 0.9:
			print("  tilt err %.1f at d=%d n=%d" % [errs[-1], i * STEP, pts.size()]); print("    pt ", pts[i], " up ", u, " nrm ", nrm[i])
	errs.sort()
	return errs[int(errs.size() * pct)]
