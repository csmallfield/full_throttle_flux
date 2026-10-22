extends Node
## Measures every JumpFeature's clean_speed (v34) by flying the REAL
## ShipController (default_racer, TrackJump flight physics) off the feature's
## exact shape on a straight test lane, at a sweep of lip speeds, one lane
## per speed. Then writes clean_speed into each feature, rebuilds the track
## and saves the scene.
##
##   godot --headless --fixed-fps 60 --path . -s res://tools/track_builder/measure_jumps_boot.gd -- --scene=res://scenes/tracks/builder_lab.tscn
##
## Clean landing (as measured for Fork Lab, FTF_v31_NOTES.md): it lands on the
## landing ramp, the hull stays at least 2.1 above the road (hover height
## 2.75) and it rebounds at most 3.6 u/s. Near the threshold the outcome isn't
## monotonic (the hover spring is still oscillating off the kicker), so
## clean_speed is the lowest speed from which EVERY faster tested speed is
## clean too.
##
## Env: MJ_SPEEDS = "from,to,step" lip speeds (default "40,120,2"),
##      MJ_NOSAVE=1 (measure and print only).

const Turtle := preload("res://tools/fork_lab/fork_lab_turtle.gd")
const SHIP_SCENE := "res://scenes/ships/default_racer.tscn"
const SHIP_PROFILE := "res://resources/ships/default_racer.tres"
const ROAD_POLY := [Vector2(21.5, 0.9), Vector2(19.5, 0.0), Vector2(-19.5, 0.0), Vector2(-21.5, 0.9),
		Vector2(-21.5, -2.0), Vector2(21.5, -2.0)]
const RUNUP := 400.0
const HOVER := 2.75
const MIN_HOVER := 2.1
const MAX_REBOUND := 3.6

var lanes: Array = []


func _ready() -> void:
	await get_tree().process_frame
	TrackBuilder.keep_at_runtime = true
	var path := _arg("scene", "res://scenes/tracks/builder_lab.tscn")
	var scene := (load(path) as PackedScene).instantiate()
	add_child(scene)
	var tb := scene.find_child("TrackBuilder", true, false) as TrackBuilder
	if tb == null:
		push_error("no TrackBuilder in %s" % path)
		get_tree().quit(1)
		return
	var jumps: Array[JumpFeature] = []
	var all := tb.features()
	for bf in tb.branch_nodes():
		all.append_array(TrackBranchEval.new(bf).features())
	for f in all:
		if f is JumpFeature and f.enabled:
			jumps.append(f)
	if jumps.is_empty():
		print("MJ no jumps in %s" % path)
		get_tree().quit(0)
		return
	var sp := OS.get_environment("MJ_SPEEDS")
	var r := (sp if not sp.is_empty() else "40,120,2").split_floats(",")
	var speeds: Array[float] = []
	var v := r[0]
	while v <= r[1] + 0.01:
		speeds.append(v)
		v += r[2]
	# Take the track out of the tree while flying: its MagneticTrack and
	# TrackGraph would otherwise act on the test ships (they find them by group).
	remove_child(scene)
	var lab := Node3D.new()
	lab.name = "JumpLanes"
	lab.position = Vector3(0, 0, 0)
	add_child(lab)
	var profile: ShipProfile = load(SHIP_PROFILE)
	var jump_res := TrackJump.new()
	var lane := 0
	for ji in jumps.size():
		var jf := jumps[ji]
		for speed in speeds:
			var x := lane * 150.0
			var built := _lane(jf, x)
			var curve: Curve3D = built.curve
			var p := Path3D.new()
			p.curve = curve
			lab.add_child(p)
			_road(p, 0.0, built.lip)
			_road(p, built.landing, curve.get_baked_length())
			var ship: ShipController = load(SHIP_SCENE).instantiate()
			ship.profile = profile
			ship.ai_controlled = true
			lab.add_child(ship)
			var f := TrackRoadSegment.frame_at(curve, 40.0)
			ship.global_transform = Transform3D(f.basis, f.origin + f.basis.y * HOVER)
			ship.velocity = -f.basis.z * speed
			lanes.append({ship = ship, curve = curve, jump = ji, speed = speed,
					lip_d = built.lip, land_d = built.landing, end_d = built.end,
					lip = TrackRoadSegment.frame_at(curve, built.lip),
					took_off = false, vlip = 0.0, td = false, t_land = -1.0, min_h = INF,
					rebound = 0.0, fell = false, done = false, td_d = -1.0})
			lane += 1
	for i in 6:
		await get_tree().physics_frame
	for L in lanes:
		(L.ship as ShipController).settle_on_surface()
	var t := 0.0
	while t < 40.0:
		await get_tree().physics_frame
		t += 1.0 / 60.0
		var all_done := true
		for L in lanes:
			if not L.done:
				all_done = false
				_step(L, t, jump_res)
		if all_done:
			break
	# Results per jump.
	var changed := false
	for ji in jumps.size():
		var jf := jumps[ji]
		var rows := lanes.filter(func(L: Dictionary) -> bool: return L.jump == ji)
		var clean := -1.0
		for k in range(rows.size() - 1, -1, -1):
			var L: Dictionary = rows[k]
			if _is_clean(L):
				clean = L.vlip
			else:
				break
		for L: Dictionary in rows:
			print("MJ %s v=%3.0f lip=%5.1f %s td=%s min_hover=%.2f rebound=%.1f" % [jf.name, L.speed, L.vlip,
					"CLEAN" if _is_clean(L) else ("FELL" if L.fell else "rough"),
					"%.0f" % (L.td_d - L.land_d) if L.td_d >= 0.0 else "--", L.min_h, L.rebound])
		if clean < 0.0:
			print("MJ %s: no clean landing at any tested speed" % jf.name)
			continue
		clean = ceilf(clean)
		print("MJ %s: clean_speed %.0f u/s at the lip (was %.0f%s)" % [jf.name, clean, jf.clean_speed,
				"" if jf.clean_speed_valid() else ", stale or unmeasured"])
		if not is_equal_approx(jf.clean_speed, clean) or jf.clean_speed_hash != jf.shape_hash():
			jf.clean_speed = clean
			jf.clean_speed_hash = jf.shape_hash()
			changed = true
	remove_child(lab)
	lab.free()
	add_child(scene)
	await get_tree().process_frame
	if OS.get_environment("MJ_NOSAVE") == "1" or not changed:
		print("MJ nothing saved")
		get_tree().quit(0)
		return
	var b := TrackBuild.run(tb)
	print("\n".join(b.log))
	var ps := PackedScene.new()
	var err := ps.pack(scene)
	if err == OK:
		err = ResourceSaver.save(ps, path)
	print("MJ saved %s (%s)" % [path, error_string(err)])
	get_tree().quit(0 if err == OK and b.ok else 1)


func _is_clean(L: Dictionary) -> bool:
	return not L.fell and L.td and L.td_d >= L.land_d - 1.0 and L.min_h >= MIN_HOVER and L.rebound <= MAX_REBOUND


## A straight test lane: RUNUP m of level road, then the feature's canonical
## shape. Returns {curve, lip, landing, end} (baked metres).
func _lane(jf: JumpFeature, x: float) -> Dictionary:
	var sh := jf.shape()
	var t := Turtle.new()
	var arc := 0.0
	var prev := Vector3.INF
	var add := func(p: Vector3, up: Vector3) -> void:
		if prev != Vector3.INF:
			arc += p.distance_to(prev)
		t.P.append(p)
		t.U.append(up)
		t.S.append(arc)
		prev = p
	var n0 := int(RUNUP / 4.0)
	for i in n0:
		add.call(Vector3(x, 0.0, -i * 4.0), Vector3.UP)
	for k in sh.size():
		var c := sh.up[k]
		add.call(Vector3(x + sh.y[k], sh.h[k], -RUNUP - sh.x[k]), Vector3(c.x, c.y, -c.z))
	var last: Vector3 = t.P[t.P.size() - 1]
	for i in range(1, 60):
		add.call(last + Vector3(0, 0, -i * 4.0), Vector3.UP)
	for i in t.P.size():
		var a := t.P[maxi(i - 1, 0)]
		var b := t.P[mini(i + 1, t.P.size() - 1)]
		t.T.append((b - a).normalized())
	var offs := PackedFloat32Array()
	var curve := t.build_curve("MJ lane", offs)
	var base := n0
	return {curve = curve, lip = offs[base + sh.marks.lip], landing = offs[base + sh.marks.landing],
			end = offs[base + sh.marks.end]}


func _road(path: Path3D, d0: float, d1: float) -> void:
	var seg := TrackRoadSegment.new()
	seg.path_node = NodePath("..")
	seg.start_distance = d0
	seg.end_distance = d1
	seg.polygon = PackedVector2Array(ROAD_POLY)
	seg.interval = 1.0
	seg.collision_layer = 1
	path.add_child(seg)


func _step(L: Dictionary, t: float, jump_res: TrackJump) -> void:
	var ship: ShipController = L.ship
	var curve: Curve3D = L.curve
	var d := curve.get_closest_offset(ship.global_position)
	var v := ship.velocity.length()
	var f := TrackRoadSegment.frame_at(curve, minf(d + 30.0, curve.get_baked_length()))
	var local := ship.global_transform.basis.inverse() * (f.origin - ship.global_position)
	ship.steer_input = clampf(atan2(-local.x, -local.z) * 2.4 - ship.measured_yaw_rate * 0.25, -1.0, 1.0) \
			if ship.is_grounded else 0.0
	if d < L.lip_d - 2.0 and not L.took_off:
		ship.throttle_input = clampf((float(L.speed) - v) * 0.2, 0.0, 1.0)
		var brake := 1.0 if v > float(L.speed) + 3.0 else 0.0
		ship.airbrake_left = brake
		ship.airbrake_right = brake
	else:
		ship.throttle_input = 1.0
		ship.airbrake_left = 0.0
		ship.airbrake_right = 0.0
	if not L.took_off and d > L.lip_d - 2.0 and not ship.is_grounded:
		L.took_off = true
		L.vlip = v
		ship.begin_jump_flight(jump_res)
	if L.took_off:
		if not L.td and ship.is_grounded and d > L.lip_d + 1.0:
			L.td = true
			L.td_d = d
			L.t_land = t
		if L.td:
			if ship.is_grounded:
				L.min_h = minf(L.min_h, ship.ground_distance)
			L.rebound = maxf(L.rebound, ship.velocity.dot(TrackRoadSegment.frame_at(curve, d).basis.y))
			if t - float(L.t_land) > 2.5:
				L.done = true
		var lip: Transform3D = L.lip
		if ship.global_position.y < lip.origin.y - 45.0:
			L.fell = true
			L.done = true
	if t > 30.0:
		L.done = true


func _arg(key: String, fallback: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % key):
			return a.substr(key.length() + 3)
	return fallback
