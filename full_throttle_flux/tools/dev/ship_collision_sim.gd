extends Node
## Ship-to-ship collision simulator (v34). Two REAL ShipControllers on a flat,
## straight road with scripted inputs, so the contact response can be measured
## tick by tick instead of felt. Reports contact episodes, the largest single-
## tick velocity change either ship receives (the "shunt"), overspeed, vertical
## kicks, yaw and lateral jitter, plus a per-tick CSV trace.
##
##   godot --headless --fixed-fps 60 --path . -s res://tools/dev/ship_collision_sim_boot.gd
##
## Env:
##   CS_SCENARIO  rearend | push | sideswipe | merge | all (default all)
##   CS_SECONDS   sim length per scenario (default 8)
##   CS_TRACE     1 = print every contact tick
##   CS_CSV       path to write the per-tick trace to (default: none)
##   CS_PROFILE   override ship profile resource path (A and B)
##   CS_PROFILE_A / CS_PROFILE_B  per-ship overrides
##
## Scenarios (A is the "attacker", B the "victim"; both ai_controlled, inputs scripted):
##   rearend   B cruises at 70 holding speed; A starts 40 m behind, flat out (120).
##   push      B cruises at 100 holding speed; A flat out from 25 m behind, then
##             stays on the throttle in sustained contact (the pack-racing case).
##   sideswipe both at 110 in lanes 4 m apart; A steers into B for 0.6 s.
##   merge     A 15 m behind and 8 m beside B, both at 105, A heads 12 deg into B's lane.

const SHIP_SCENE := "res://scenes/ships/default_racer.tscn"
const SHIP_PROFILE := "res://resources/ships/default_racer.tres"
const ROAD_POLY := [Vector2(21.5, 0.9), Vector2(19.5, 0.0), Vector2(-19.5, 0.0), Vector2(-21.5, 0.9),
		Vector2(-21.5, -2.0), Vector2(21.5, -2.0)]
const ROAD_LEN := 2500.0
const HOVER := 2.75

var root: Node3D
var csv_lines: PackedStringArray = []
var trace := false

func _env(k: String, d: String) -> String:
	var v := OS.get_environment(k)
	return v if v != "" else d

func _ready() -> void:
	await get_tree().process_frame
	trace = _env("CS_TRACE", "0") == "1"
	var which := _env("CS_SCENARIO", "all")
	var seconds := _env("CS_SECONDS", "8").to_float()
	var names: Array = ["rearend", "push", "sideswipe", "merge", "solo"] if which == "all" else which.split(",")
	csv_lines.append("scenario,t,ship,x,y,z,vx,vy,vz,speed,dv_tick,contact,closing,yaw_rate,ground_dist,ray_on_ship")
	for n in names:
		await _run(n, seconds)
	var csv := _env("CS_CSV", "")
	if csv != "":
		var f := FileAccess.open(csv, FileAccess.WRITE)
		for l in csv_lines:
			f.store_line(l)
		f.close()
		print("CS csv -> %s (%d rows)" % [csv, csv_lines.size() - 1])
	get_tree().quit(0)

func _spawn(profile_path: String, pos: Vector3, speed: float, heading_deg: float = 0.0) -> ShipController:
	var ship: ShipController = load(SHIP_SCENE).instantiate()
	ship.profile = load(profile_path)
	ship.ai_controlled = true
	root.add_child(ship)
	var basis := Basis(Vector3.UP, deg_to_rad(heading_deg))
	ship.global_transform = Transform3D(basis, pos + Vector3.UP * HOVER)
	ship.velocity = -basis.z * speed
	return ship

func _build_road() -> void:
	root = Node3D.new()
	root.name = "CollisionSim"
	get_tree().root.add_child(root)
	var curve := Curve3D.new()
	curve.add_point(Vector3(0, 0, 0))
	curve.add_point(Vector3(0, 0, -ROAD_LEN))
	var path := Path3D.new()
	path.curve = curve
	root.add_child(path)
	var seg := TrackRoadSegment.new()
	seg.path_node = NodePath("..")
	seg.start_distance = 0.0
	seg.end_distance = ROAD_LEN
	seg.polygon = PackedVector2Array(ROAD_POLY)
	seg.interval = 2.0
	seg.collision_layer = 1
	path.add_child(seg)

## Hold a target speed with throttle / airbrakes (what a cruising AI does).
static func _hold(ship: ShipController, target: float) -> void:
	var v := ship.velocity.length()
	ship.throttle_input = clampf((target - v) * 0.2, 0.0, 1.0)
	var brake := 1.0 if v > target + 3.0 else 0.0
	ship.airbrake_left = brake
	ship.airbrake_right = brake

## Keep the lane: steer toward x = lane, damp yaw.
static func _lane(ship: ShipController, lane: float, gain := 0.08) -> void:
	var err := lane - ship.global_position.x
	var fwd := -ship.global_transform.basis.z
	var heading := atan2(-fwd.x, -fwd.z)  # 0 = -Z, + = turned left (toward -x)
	var want := clampf(-err * gain, -0.4, 0.4)
	ship.steer_input = clampf((want - heading) * 3.0 - ship.measured_yaw_rate * 0.3, -1.0, 1.0)

func _run(name: String, seconds: float) -> void:
	_build_road()
	var pa := _env("CS_PROFILE_A", _env("CS_PROFILE", SHIP_PROFILE))
	var pb := _env("CS_PROFILE_B", _env("CS_PROFILE", SHIP_PROFILE))
	var A: ShipController
	var B: ShipController
	var z0 := -200.0
	match name:
		"rearend":
			B = _spawn(pb, Vector3(0, 0, z0), 70.0)
			A = _spawn(pa, Vector3(0, 0, z0 + 40.0), 120.0)
		"push":
			B = _spawn(pb, Vector3(0, 0, z0), 100.0)
			A = _spawn(pa, Vector3(0, 0, z0 + 25.0), 120.0)
		"sideswipe":
			B = _spawn(pb, Vector3(0, 0, z0), 110.0)
			A = _spawn(pa, Vector3(4.0, 0, z0), 110.0)
		"merge":
			B = _spawn(pb, Vector3(0, 0, z0), 105.0)
			A = _spawn(pa, Vector3(5.0, 0, z0 + 3.0), 105.0, 8.0)
		"pushsteer":
			B = _spawn(pb, Vector3(0, 0, z0), 100.0)
			A = _spawn(pa, Vector3(0, 0, z0 + 25.0), 120.0)
		"solo":
			B = _spawn(pb, Vector3(0, 0, z0), 100.0)
			A = _spawn(pa, Vector3(15.0, 0, z0 + 200.0), 100.0)
		_:
			push_error("unknown scenario " + name)
			return
	A.name = "A"
	B.name = "B"
	var ships: Array[ShipController] = [A, B]
	for i in 6:
		await get_tree().physics_frame
	var resolver: ShipContactResolver = ShipContactResolver.current()
	print("CS mode=%s" % ("legacy" if resolver == null else "resolver"))
	for s in ships:
		s.settle_on_surface()

	# Metrics
	var stats := {}
	for s in ships:
		stats[s] = {"contact_ticks": 0, "episodes": 0, "max_dv": 0.0, "max_dv_t": 0.0, "max_speed": 0.0,
				"max_vy": 0.0, "max_yaw": 0.0, "lat_flips": 0, "ray_on_ship": 0, "events": 0,
				"max_impact": 0.0, "min_gap": INF, "prev_contact": false, "prev_vel": s.velocity,
				"prev_lat_sign": 0, "prev_yaw": 0.0, "max_yaw_accel": 0.0, "speed_at_end": 0.0,
				"min_ground": INF}
		s.ship_collision.connect(func(other: ShipController, impact: float):
			stats[s]["events"] += 1
			stats[s]["max_impact"] = maxf(stats[s]["max_impact"], impact))

	var t := 0.0
	var n := int(seconds * 60.0)
	var first_contact_t := -1.0
	for tick in n:
		# --- scripted inputs ---
		match name:
			"rearend":
				_hold(B, 70.0); _lane(B, 0.0)
				A.throttle_input = 1.0; _lane(A, 0.0)
			"push":
				_hold(B, 100.0); _lane(B, 0.0)
				A.throttle_input = 1.0; _lane(A, 0.0)
			"sideswipe":
				_hold(B, 110.0); _lane(B, 0.0)
				_hold(A, 110.0)
				if t < 1.0:
					_lane(A, 4.0)
				elif t < 1.6:
					A.steer_input = 0.45   # steer left, into B
				else:
					_lane(A, 2.5)
			"merge":
				_hold(B, 105.0); _lane(B, 0.0)
				_hold(A, 105.0)
				if t < 1.0:
					A.steer_input = 0.0    # hold the 8 deg heading into B
				else:
					_lane(A, 0.0)
			"pushsteer":
				_hold(B, 100.0); _lane(B, 0.0)
				A.throttle_input = 1.0
				if t < 3.0:
					_lane(A, 0.0)
				else:
					A.steer_input = -1.0   # hard right out of the leader's wake
			"solo":
				_hold(B, 100.0); _lane(B, 0.0)
				_hold(A, 100.0); _lane(A, 15.0)

		await get_tree().physics_frame
		t += 1.0 / 60.0

		var gap := A.global_position.distance_to(B.global_position)
		for s in ships:
			var st: Dictionary = stats[s]
			var contact := false
			var closing := 0.0
			var other: ShipController = B if s == A else A
			if resolver != null:
				contact = resolver.is_touching(A, B)
				if contact:
					var nrm: Vector3 = (s.global_position - other.global_position)
					nrm.y = 0.0
					closing = (s.velocity - other.velocity).dot(nrm.normalized())
			else:
				for i in s.get_slide_collision_count():
					var c: KinematicCollision3D = s.get_slide_collision(i)
					if c.get_collider() is ShipController:
						contact = true
						closing = (s.velocity - other.velocity).dot(c.get_normal())
			var dv: float = (s.velocity - st["prev_vel"]).length()
			var lat: float = s.velocity.x
			var lat_sign: int = int(sign(lat)) if absf(lat) > 0.5 else 0
			var ray_on_ship: bool = s.hover_ray.is_colliding() and s.hover_ray.get_collider() is ShipController
			var yaw_accel: float = absf(s.measured_yaw_rate - st["prev_yaw"]) * 60.0

			st["contact_ticks"] += 1 if contact else 0
			if contact and not st["prev_contact"]:
				st["episodes"] += 1
				if first_contact_t < 0.0:
					first_contact_t = t
			if dv > st["max_dv"]:
				st["max_dv"] = dv
				st["max_dv_t"] = t
			st["max_speed"] = maxf(st["max_speed"], s.velocity.length())
			st["max_vy"] = maxf(st["max_vy"], absf(s.velocity.y))
			st["max_yaw"] = maxf(st["max_yaw"], absf(s.measured_yaw_rate))
			st["max_yaw_accel"] = maxf(st["max_yaw_accel"], yaw_accel)
			if lat_sign != 0 and st["prev_lat_sign"] != 0 and lat_sign != st["prev_lat_sign"]:
				st["lat_flips"] += 1
			st["ray_on_ship"] += 1 if ray_on_ship else 0
			st["min_gap"] = minf(st["min_gap"], gap)
			st["min_ground"] = minf(st["min_ground"], s.ground_distance)
			st["prev_contact"] = contact
			st["prev_vel"] = s.velocity
			st["prev_lat_sign"] = lat_sign
			st["prev_yaw"] = s.measured_yaw_rate
			st["speed_at_end"] = s.velocity.length()

			var p: Vector3 = s.global_position
			var v: Vector3 = s.velocity
			csv_lines.append("%s,%.3f,%s,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%.3f,%d,%.2f,%.3f,%.2f,%d" % [
				name, t, s.name, p.x, p.y, p.z, v.x, v.y, v.z, v.length(), dv, int(contact), closing,
				s.measured_yaw_rate, s.ground_distance, int(ray_on_ship)])
			if trace and (contact or dv > 2.0):
				print("  %5.2f %s gap=%5.2f v=%6.2f dv=%5.2f vy=%+5.2f lat=%+5.2f closing=%+6.2f yaw=%+.2f gd=%.2f%s" % [
					t, s.name, gap, v.length(), dv, v.y, v.x, closing, s.measured_yaw_rate, s.ground_distance,
					" RAY-ON-SHIP" if ray_on_ship else ""])

	print("CS %-9s first_contact=%.2fs" % [name, first_contact_t])
	for s in ships:
		var st: Dictionary = stats[s]
		print("CS %-9s %s contact_ticks=%3d episodes=%2d events=%2d max_impact=%5.1f max_dv/tick=%5.2f@%.2fs max_v=%6.1f max_vy=%5.2f max_yaw=%.2f yaw_accel=%6.1f lat_flips=%2d ray_on_ship=%d min_gap=%.2f min_gd=%.2f v_end=%.1f" % [
			name, s.name, st["contact_ticks"], st["episodes"], st["events"], st["max_impact"], st["max_dv"],
			st["max_dv_t"], st["max_speed"], st["max_vy"], st["max_yaw"], st["max_yaw_accel"],
			st["lat_flips"], st["ray_on_ship"], st["min_gap"], st["min_ground"], st["speed_at_end"]])
	root.queue_free()
	await get_tree().physics_frame
	await get_tree().physics_frame
