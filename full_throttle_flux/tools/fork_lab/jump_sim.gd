extends Node
## Jump simulator (v31). Flies the REAL ShipController off a kicker ramp at a
## range of approach speeds and kicker angles, one lane per case, and prints
## where it comes down. The airborne physics are not ballistic (gravity ramps
## 1x -> 2x over 0.5 s, vertical velocity decays at 0.74/s, thrust continues
## horizontally, air drag), so Fork Lab's gaps and landing ramps are sized from
## this rather than from a formula.
##
##   godot --headless --fixed-fps 60 --path . -s res://tools/fork_lab/jump_sim_boot.gd
##
## Env:
##   JS_ANGLES   kicker angles in degrees (default "6,8,10,12")
##   JS_SPEEDS   approach speeds (default "50,60,70,80,90,100,110,120")
##   JS_KLEN     kicker length in metres (default 70)
##   JS_PHYS     "stock" = profile air physics, "jump" = TrackJump flight
##               physics (default jump: ground drag in the air)
##   JS_PULLG / JS_DAMP / JS_FORCE  TrackJump landing_pull_limit_g /
##               landing_damping_scale / landing_force_scale (default: the
##               resource defaults; JS_PULLG=-1 JS_DAMP=1 JS_FORCE=1 = stock
##               landing with jump air drag)
##   JS_LAND     "gap,drop,a1,l1[,a2,lc,l2],outrun": add a landing ramp `gap`
##               m after the lip (horizontal), its top `drop` m below the lip,
##               sloping down at a1 deg for l1 m, optionally steepening to a2
##               over lc m and running l2 m, then levelling over `outrun` m;
##               reports touchdown, peak hover compression and vertical speed
##   JS_TRACE    lane index to print every tick of

const Turtle := preload("res://tools/fork_lab/fork_lab_turtle.gd")
const SHIP_SCENE := "res://scenes/ships/default_racer.tscn"
const SHIP_PROFILE := "res://resources/ships/default_racer.tres"
const ROAD_POLY := [Vector2(21.5, 0.9), Vector2(19.5, 0.0), Vector2(-19.5, 0.0), Vector2(-21.5, 0.9),
		Vector2(-21.5, -2.0), Vector2(21.5, -2.0)]
const RUNUP := 300.0

var lanes: Array = []   # dictionaries
var jump_res: TrackJump

func _env(k: String, d: String) -> String:
	var v := OS.get_environment(k)
	return v if v != "" else d

func _ready() -> void:
	await get_tree().process_frame
	var angles := _env("JS_ANGLES", "6,8,10,12").split_floats(",")
	var speeds := _env("JS_SPEEDS", "50,60,70,80,90,100,110,120").split_floats(",")
	var klen := _env("JS_KLEN", "70").to_float()
	var phys := _env("JS_PHYS", "jump")
	var land := _env("JS_LAND", "").split_floats(",")
	var trace := int(_env("JS_TRACE", "-1"))
	jump_res = TrackJump.new()
	jump_res.landing_pull_limit_g = _env("JS_PULLG", str(jump_res.landing_pull_limit_g)).to_float()
	jump_res.landing_damping_scale = _env("JS_DAMP", str(jump_res.landing_damping_scale)).to_float()
	jump_res.landing_force_scale = _env("JS_FORCE", str(jump_res.landing_force_scale)).to_float()
	
	var root := Node3D.new()
	root.name = "JumpSim"
	get_tree().root.add_child(root)
	var profile: ShipProfile = load(SHIP_PROFILE)
	var lane := 0
	for a in angles:
		for v in speeds:
			var x := lane * 150.0
			var t := Turtle.new()
			t.pos = Vector3(x, 0, 0)
			t.straight(RUNUP, 10.0)
			t.pitch_change(klen, deg_to_rad(a), 2.0)
			var lip_arc := t.arc
			var lip_pos := t.pos
			var land_arc := -1.0
			var land_end := -1.0
			if land.size() >= 4:
				# Logic path through the gap to the landing lip, then the ramp:
				# gap, drop, a1, l1 [, a2, lc, l2], outrun.
				var gap_h: float = land[0]
				var drop: float = land[1]
				var a1 := deg_to_rad(land[2])
				var target := lip_pos + t.heading * gap_h + Vector3.DOWN * drop
				var chord := target - t.pos
				t.pitch = atan2(chord.y, Vector2(chord.x, chord.z).length())
				t.straight(chord.length(), 2.0)
				t.pitch = -a1
				land_arc = t.arc
				t.straight(land[3], 2.0)
				var a_last := a1
				if land.size() >= 7:
					var a2 := deg_to_rad(land[4])
					t.pitch_change(land[5], -(a2 - a1), 2.0)
					t.straight(land[6], 2.0)
					a_last = a2
				var lo: float = land[land.size() - 1] if land.size() in [5, 8] else 60.0
				t.pitch_change(lo, a_last, 2.0)
				t.straight(200.0, 10.0)
				land_end = t.arc
			else:
				t.straight(10.0, 2.0)
			var offs := PackedFloat32Array()
			var curve := t.build_curve("JS lane %d" % lane, offs)
			var path := Path3D.new()
			path.curve = curve
			root.add_child(path)
			var lip_d := t.baked_at_arc(lip_arc, offs)
			_road(path, 0.0, lip_d)
			var land_d := -1.0
			if land_arc > 0.0:
				land_d = t.baked_at_arc(land_arc, offs)
				_road(path, land_d, curve.get_baked_length())
			var ship: ShipController = load(SHIP_SCENE).instantiate()
			ship.profile = profile
			ship.ai_controlled = true
			root.add_child(ship)
			var f := TrackRoadSegment.frame_at(curve, 40.0)
			ship.global_transform = Transform3D(f.basis, f.origin + f.basis.y * 2.75)
			ship.velocity = -f.basis.z * v
			var lip_frame := TrackRoadSegment.frame_at(curve, lip_d)
			lanes.append({"ship": ship, "path": path, "curve": curve, "angle": a, "speed": v,
					"lip_d": lip_d, "lip": lip_frame, "land_d": land_d, "air": false, "done": false,
					"t_air": 0.0, "vlip": 0.0, "vylip": 0.0, "apex": -INF, "track": [],
					"td_x": -1.0, "td_v": 0.0, "td_vy": 0.0, "min_h": INF, "peak_vy_up": 0.0,
					"land_v_min": INF, "flips": 0, "prev_g": true, "trace": lane == trace,
					"phys": phys, "took_off": false, "fell": false, "t_land": -1.0,
					"g_after": 0, "after": 0})
			lane += 1
	for i in 6:
		await get_tree().physics_frame
	for L in lanes:
		(L.ship as ShipController).settle_on_surface()
	
	var t_sim := 0.0
	while t_sim < 30.0:
		await get_tree().physics_frame
		t_sim += 1.0 / 60.0
		var all_done := true
		for L in lanes:
			if not L.done:
				all_done = false
				_step(L, t_sim)
		if all_done:
			break
	_report(land.size() >= 4)
	get_tree().quit(0)

func _road(path: Path3D, d0: float, d1: float) -> void:
	var seg := TrackRoadSegment.new()
	seg.path_node = NodePath("..")
	seg.start_distance = d0
	seg.end_distance = d1
	seg.polygon = PackedVector2Array(ROAD_POLY)
	seg.interval = 1.0
	seg.collision_layer = 1
	path.add_child(seg)

func _step(L: Dictionary, t: float) -> void:
	var ship: ShipController = L.ship
	var curve: Curve3D = L.curve
	var lip: Transform3D = L.lip
	var d := curve.get_closest_offset(ship.global_position)
	var fwd_h := (-lip.basis.z).slide(Vector3.UP).normalized()
	var rel := ship.global_position - lip.origin
	var x := rel.dot(fwd_h)
	var y := rel.y
	var v := ship.velocity.length()
	# Steering: hold the lane centre while on the road.
	var f := TrackRoadSegment.frame_at(curve, minf(d + 30.0, curve.get_baked_length()))
	var local := ship.global_transform.basis.inverse() * (f.origin - ship.global_position)
	ship.steer_input = clampf(atan2(-local.x, -local.z) * 2.4 - ship.measured_yaw_rate * 0.25, -1.0, 1.0) \
			if ship.is_grounded else 0.0
	if x < 0.0 and not L.took_off:
		ship.throttle_input = clampf((float(L.speed) - v) * 0.2, 0.0, 1.0)
		if v > float(L.speed) + 3.0:
			ship.airbrake_left = 1.0
			ship.airbrake_right = 1.0
		else:
			ship.airbrake_left = 0.0
			ship.airbrake_right = 0.0
	else:
		ship.throttle_input = 1.0
		ship.airbrake_left = 0.0
		ship.airbrake_right = 0.0
	
	if not L.took_off and x > -2.0 and not ship.is_grounded:
		L.took_off = true
		L.vlip = v
		L.vylip = ship.velocity.y
		L.t_air = t
		if L.phys == "jump":
			ship.begin_jump_flight(jump_res)
	if L.took_off:
		L.apex = maxf(L.apex, y)
		var tr: Array = L.track
		tr.append([x, y, ship.velocity.y, v, ship.is_grounded, ship.ground_distance])
		if L.td_x < 0.0 and ship.is_grounded and x > 1.0:
			L.td_x = x
			L.td_v = v
			L.td_vy = ship.velocity.y
			L.t_land = t
		if L.td_x >= 0.0 and not L.has("vn_hover") and ship.is_grounded and ship.ground_distance < 2.75 \
				and ship.hover_ray.is_colliding():
			L.vn_hover = ship.velocity.dot(ship.hover_ray.get_collision_normal())
			L.x_hover = x
		if L.td_x >= 0.0 and not L.has("vn_ray") and ship.hover_ray.is_colliding():
			L.vn_ray = ship.velocity.dot(ship.hover_ray.get_collision_normal())
		if L.td_x >= 0.0:
			L.after += 1
			if ship.is_grounded:
				L.g_after += 1
				L.min_h = minf(L.min_h, ship.ground_distance)
			L.peak_vy_up = maxf(L.peak_vy_up, ship.velocity.y)
			L.land_v_min = minf(L.land_v_min, v)
			if bool(L.prev_g) != ship.is_grounded:
				L.flips += 1
		L.prev_g = ship.is_grounded
		if y < -45.0:
			L.fell = true
			L.done = true
		if L.td_x >= 0.0 and t - float(L.t_land) > 2.5:
			L.done = true
		if x > 400.0:
			L.done = true
	if L.trace:
		print("TR t=%.3f x=%.1f y=%.2f vy=%.2f v=%.1f g=%s h=%.2f jump=%s" % [t, x, y,
				ship.velocity.y, v, ship.is_grounded, ship.ground_distance, ship.jump != null])

func _report(with_land: bool) -> void:
	var drops := [0.0, 2.0, 4.0, 6.0, 8.0, 10.0, 14.0, 20.0, 30.0]
	for L in lanes:
		var tr: Array = L.track
		var line := "JS ang=%4.1f v=%3.0f lip v=%5.1f vy=%5.1f apex=%5.1f |" % [L.angle, L.speed,
				L.vlip, L.vylip, float(L.apex) - 2.75]
		if not with_land:
			# x where the ship centre is `drop` below the lip surface + hover height
			# (nominal touchdown on a surface `drop` m below the lip), with the
			# descent angle and speed there.
			for D in drops:
				var hit := false
				for i in range(1, tr.size()):
					var yc: float = tr[i][1] - 2.75
					var yp: float = tr[i - 1][1] - 2.75
					if yp >= -D and yc < -D and tr[i][2] < 0.0:
						var ang := rad_to_deg(atan2(-tr[i][2], sqrt(maxf(tr[i][3] * tr[i][3] - tr[i][2] * tr[i][2], 0.0))))
						line += " %2.0f:%5.1fm/%4.1fd/%3.0f" % [D, tr[i][0], ang, tr[i][3]]
						hit = true
						break
				if not hit:
					line += " %2.0f:   --        " % D
		else:
			line += " ray_contact x=%s vn=%.1f | at_hover x=%.1f vn=%.1f | min_hover=%.2f peak_vy_up=%.1f min_v=%.0f gnd_flips=%d air_after_td=%d%% %s" % [
				"%.1f" % L.td_x if L.td_x >= 0.0 else "--", L.get("vn_ray", 0.0),
				L.get("x_hover", -1.0), L.get("vn_hover", 0.0),
				L.min_h, L.peak_vy_up, L.land_v_min if L.land_v_min < INF else 0.0,
				L.flips, int(100.0 * (1.0 - float(L.g_after) / maxf(float(L.after), 1.0))),
				"FELL" if L.fell else ""]
		print(line)
