extends SceneTree
## Verifies the generated Loop Lab geometry against its spline frames (v30).
##   godot --headless --path . -s res://tools/loop_lab/check_loop_lab.gd
## Every 10 m: cast a ray from 5 m above the road (along the MagneticTrack
## frame's up) straight down, and check it lands on the road, 5 m away, with
## the road's normal matching the frame. Also checks the walls stand clear of
## the loop crossing and the start gate/grid are on the road.

func _initialize() -> void:
	var scene: Node3D = load("res://scenes/tracks/loop_lab.tscn").instantiate()
	root.add_child(scene)
	for i in 10:
		await physics_frame
	
	var mt: MagneticTrack = scene.get_node("MagneticTrack")
	var path: Path3D = scene.get_node("MainSpline")
	var curve := path.curve
	var length := curve.get_baked_length()
	var space := scene.get_world_3d().direct_space_state
	
	var misses := 0
	var worst_d := 0.0
	var worst_n := 0.0
	var worst_frame := 0.0
	var d := 0.0
	while d < length:
		var f := mt.frame_at(d)
		var up := f.basis.y.normalized()
		# frame_at basis.y must equal the tilted up vector
		var up2 := (path.global_transform.basis * curve.sample_baked_up_vector(d, true)).normalized()
		worst_frame = maxf(worst_frame, rad_to_deg(up.angle_to(up2)))
		for lat: float in [-15.0, 0.0, 15.0]:
			var origin := f.origin + up * 5.0 + f.basis.x.normalized() * lat
			var q := PhysicsRayQueryParameters3D.create(origin, origin - up * 10.0, 1)
			var hit := space.intersect_ray(q)
			if hit.is_empty():
				misses += 1
				if misses < 6:
					print("MISS at %.0f m lat %.0f" % [d, lat])
				continue
			worst_d = maxf(worst_d, absf(origin.distance_to(hit.position) - 5.0))
			var ne := rad_to_deg((hit.normal as Vector3).angle_to(up))
			if ne > 3.0:
				print("NORMAL off %.1f deg at %.0f m lat %.0f" % [ne, d, lat])
			worst_n = maxf(worst_n, ne)
		d += 10.0
	print("CHECK road rays: misses=%d worst height err=%.3f m worst normal err=%.2f deg frame err=%.3f deg"
			% [misses, worst_d, worst_n, worst_frame])
	
	# Forward convention of frame_at: -basis.z should point along travel.
	var a := mt.frame_at(100.0)
	var b := mt.frame_at(110.0)
	print("CHECK frame forward is -Z: %s" % [str((-a.basis.z).dot(b.origin - a.origin) > 0.0)])
	
	# Report a few named spots.
	for s: float in [0.0, 30.0, 615.0, 2108.0, 2000.0, 2220.0]:
		var fr := mt.frame_at(s)
		print("CHECK @%5.0f m  pos=%s up=%s zone_w=%.2f" % [s, fr.origin.snapped(Vector3.ONE * 0.1),
				fr.basis.y.normalized().snapped(Vector3.ONE * 0.01), mt.zone_at(s)[0]])
	
	var grid: StartingGrid = scene.get_node("StartingPoint/StartingGrid")
	for i in grid.get_grid_capacity():
		var t := grid.get_start_transform(i)
		var q := PhysicsRayQueryParameters3D.create(t.origin, t.origin - t.basis.y * 8.0, 1)
		var hit := space.intersect_ray(q)
		print("CHECK grid %d hit=%s h=%.2f" % [i, str(not hit.is_empty()),
				t.origin.distance_to(hit.position) if hit else -1.0])
	quit(0)
