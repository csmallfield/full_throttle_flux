extends SceneTree
## Verifies the generated Fork Lab geometry by raycasting it (v31).
##   godot --headless --path . -s res://tools/fork_lab/check_fork_lab.gd
##
##  1. Road rays every 5 m along the MainSpline and the BranchSpline at five
##     laterals: the road is there (except over the jump gaps), at the frame's
##     height, with the frame's normal.
##  2. Gaps: no collision of any kind straight down through the middle of each
##     jump gap (the visual floor has none either).
##  3. Seams: every 0.25 m across each place one piece of road hands over to
##     another (junction ends, the lap seam), at laterals out to the walls:
##     the hover ray always hits, and the surface height never steps.
##  4. Junctions: a 2 m grid of rays over each junction's road; and horizontal
##     rays at hover height along both paths through each junction: no wall
##     (layer 4) inside either road's drivable width, i.e. neither route is
##     blocked by the splitter or the other route's walls.

func _initialize() -> void:
	var scene: Node3D = load("res://scenes/tracks/fork_lab.tscn").instantiate()
	root.add_child(scene)
	for i in 10:
		await physics_frame
	var g: TrackGraph = scene.get_node("TrackGraph")
	var space := scene.get_world_3d().direct_space_state
	var br: TrackBranch = g.branches[0]
	
	# --- 1. road rays --------------------------------------------------------
	for pi: int in [-1, 0]:
		var length := g.path_length(pi)
		var misses := 0
		var worst_h := 0.0
		var worst_n := 0.0
		var d := 0.0
		while d < length:
			if _in_gap(g, pi, d, 0.0):
				d += 5.0
				continue
			var f := g.frame_at(pi, d)
			var up := f.basis.y.normalized()
			for lat: float in [-18.0, -9.0, 0.0, 9.0, 18.0]:
				var o := f.origin + up * 5.0 + f.basis.x.normalized() * lat
				var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(o, o - up * 10.0, 1))
				if hit.is_empty():
					misses += 1
					if misses < 6:
						print("MISS path %d at %.0f m lat %.0f" % [pi, d, lat])
					continue
				worst_h = maxf(worst_h, absf(o.distance_to(hit.position) - 5.0))
				var ne := rad_to_deg((hit.normal as Vector3).angle_to(up))
				if ne > 1.0:
					print("NORMAL off %.2f deg path %d at %.0f m lat %.0f" % [ne, pi, d, lat])
				worst_n = maxf(worst_n, ne)
			d += 5.0
		print("CHECK road %s: misses=%d worst height err=%.3f m worst normal err=%.2f deg" % [
				"main" if pi < 0 else "branch", misses, worst_h, worst_n])
	
	# --- 2. gaps ---------------------------------------------------------------
	for j in g.jumps:
		var hits := 0
		var n := 0
		var d := j.lip + 1.0
		while d < j.landing - 1.0:
			var f := g.frame_at(j.branch, d)
			for lat: float in [-25.0, -15.0, 0.0, 15.0, 25.0]:
				var o := f.origin + Vector3.UP * 20.0 + f.basis.x.normalized() * lat
				var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(o, o + Vector3.DOWN * 400.0, 0xFFFFFFFF))
				n += 1
				if not hit.is_empty():
					hits += 1
			d += 2.0
		var lip := g.frame_at(j.branch, j.lip).origin
		var land := g.frame_at(j.branch, j.landing).origin
		print("CHECK gap '%s': %d/%d rays hit anything (want 0); gap %.1f m horizontal, landing lip %.2f m below the kicker lip"
				% [j.jump_name, hits, n, Vector2(land.x - lip.x, land.z - lip.z).length(), lip.y - land.y])
	
	# --- 3. seams --------------------------------------------------------------
	var jf_m := _seg_start(scene, "MainSpline/Road_MainRoute")
	var jr_m := _seg_end(scene, "MainSpline/Road_MainRoute")
	var jf_b := _seg_start(scene, "BranchSpline/Road_BranchA")
	var jr_b := _seg_end(scene, "BranchSpline/Road_BranchB")
	var seams := [[-1, br.fork_distance, "fork (main, shared road -> junction)"],
			[-1, jf_m, "fork junction end (main route)"], [0, jf_b, "fork junction end (branch)"],
			[-1, jr_m, "rejoin junction start (main route)"], [0, jr_b, "rejoin junction start (branch)"],
			[-1, br.rejoin_distance, "rejoin (junction -> shared road)"], [-1, 0.0, "lap seam"]]
	for s in seams:
		var pi: int = s[0]
		var d0: float = s[1]
		var miss := 0
		var worst_step := 0.0
		var worst_off := 0.0
		for lat: float in [-21.0, -19.5, -15.0, -5.0, 0.0, 5.0, 15.0, 19.5, 21.0]:
			var prev := NAN
			var x := -6.0
			while x <= 6.0:
				var d := fposmod(d0 + x, g.path_length(pi))
				var f := g.frame_at(pi, d)
				var up := f.basis.y.normalized()
				var o := f.origin + up * 3.0 + f.basis.x.normalized() * lat
				var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(o, o - up * 8.25, 1))
				if hit.is_empty():
					miss += 1
				else:
					var h := (hit.position as Vector3 - f.origin).dot(up)
					if absf(lat) <= 19.5:
						worst_off = maxf(worst_off, absf(h))
					if not is_nan(prev):
						worst_step = maxf(worst_step, absf(h - prev))
					prev = h
				x += 0.25
		print("CHECK seam %-40s misses=%d max step between 0.25 m samples=%.4f m, max |height| on road=%.4f m"
				% [s[2], miss, worst_step, worst_off])
	
	# --- 4. junctions ----------------------------------------------------------
	for jn: TrackJunction in [scene.get_node("ForkJunction"), scene.get_node("RejoinJunction")]:
		var grid_miss := 0
		var grid_n := 0
		var bad_h := 0
		# Grid over the union: points within 19.5 m of either centre line.
		for pi: int in [-1, 0]:
			var d0: float = jn.a_start if pi < 0 else jn.b_start
			var d1: float = jn.a_end if pi < 0 else jn.b_end
			var d := d0
			while d <= d1:
				var f := g.frame_at(pi, d)
				var lat := -19.0
				while lat <= 19.0:
					var o := f.origin + Vector3.UP * 5.0 + f.basis.x.normalized() * lat
					var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(o, o + Vector3.DOWN * 10.0, 1))
					grid_n += 1
					if hit.is_empty():
						grid_miss += 1
					elif absf((hit.position as Vector3).y - f.origin.y) > 0.01:
						bad_h += 1
					lat += 2.0
				d += 2.0
		# Walls along each route through the junction, at hover height.
		var blocked := 0
		var nb := 0
		var first := ""
		for pi: int in [-1, 0]:
			var d0: float = jn.a_start if pi < 0 else jn.b_start
			var d1: float = jn.a_end if pi < 0 else jn.b_end
			for lat: float in [-17.0, -12.0, -6.0, 0.0, 6.0, 12.0, 17.0]:
				var d := d0 - 20.0
				while d < d1 + 20.0:
					var fa := g.frame_at(pi, fposmod(d, g.path_length(pi)))
					var fb := g.frame_at(pi, fposmod(d + 2.0, g.path_length(pi)))
					var a := fa.origin + fa.basis.y * 2.75 + fa.basis.x.normalized() * lat
					var b := fb.origin + fb.basis.y * 2.75 + fb.basis.x.normalized() * lat
					var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(a, b, 4))
					nb += 1
					if not hit.is_empty():
						blocked += 1
						if first == "":
							first = "path %d d=%.0f lat=%.0f" % [pi, d, lat]
					d += 2.0
		print("CHECK %s: grid rays %d, misses=%d, off-plane=%d; wall rays along both routes %d, blocked=%d %s; nose at %s"
				% [jn.name, grid_n, grid_miss, bad_h, nb, blocked, first, jn.nose.snapped(Vector3.ONE * 0.1)])
	
	# --- start gate and grid on the road --------------------------------------
	var grid: StartingGrid = scene.get_node("StartingPoint/StartingGrid")
	for i in grid.get_grid_capacity():
		var t := grid.get_start_transform(i)
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(t.origin, t.origin - t.basis.y * 8.0, 1))
		if hit.is_empty() or absf(t.origin.distance_to(hit.position) - 3.0) > 0.05:
			print("CHECK grid slot %d NOT on the road" % i)
	print("CHECK grid: %d slots checked" % grid.get_grid_capacity())
	
	# --- branch -> main mapping ------------------------------------------------
	var prev_m := -1.0
	var worst_slope := 0.0
	var min_slope := INF
	var b := 0.0
	while b <= g.path_length(0):
		var m := g.branch_to_main(0, b)
		if prev_m >= 0.0:
			worst_slope = maxf(worst_slope, (m - prev_m) / 1.0)
			min_slope = minf(min_slope, (m - prev_m) / 1.0)
		prev_m = m
		b += 1.0
	print("CHECK branch->main map: %.1f -> %.1f, slope per branch metre %.3f..%.3f (monotonic=%s)" % [
			g.branch_to_main(0, 0.0), g.branch_to_main(0, g.path_length(0)), min_slope, worst_slope,
			str(min_slope > 0.0)])
	quit(0)

func _in_gap(g: TrackGraph, pi: int, d: float, margin: float) -> bool:
	for j in g.jumps:
		if j.branch == pi and d > j.lip - margin and d < j.landing + margin:
			return true
	return false

func _seg_start(scene: Node, p: String) -> float:
	return (scene.get_node(p) as TrackRoadSegment).start_distance

func _seg_end(scene: Node, p: String) -> float:
	return (scene.get_node(p) as TrackRoadSegment).end_distance
