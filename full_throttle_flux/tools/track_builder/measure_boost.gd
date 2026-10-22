extends Node
## Flies the REAL default_racer over a BoostPad (scenes/boost_pad.tscn) on a
## straight lane, at several arrival speeds and pad strengths, and prints its
## speed every 10 m after the pad next to TrackSpeedProfile.boosted(), the
## model the validator uses for what a pad does to the next corner, crest or
## jump (v34).
##
##   godot --headless --fixed-fps 60 --path . -s res://tools/track_builder/measure_boost_boot.gd
##
## Env: MB_CASES = "v0:strength,v0:strength,..." (default
##      "120:150,90:150,60:150,120:80,120:250").

const SHIP_SCENE := "res://scenes/ships/default_racer.tscn"
const PAD_SCENE := "res://scenes/boost_pad.tscn"
const ROAD_POLY := [Vector2(21.5, 0.9), Vector2(19.5, 0.0), Vector2(-19.5, 0.0), Vector2(-21.5, 0.9),
		Vector2(-21.5, -2.0), Vector2(21.5, -2.0)]
const LANE := 1400.0
const PAD_AT := 500.0
const HOVER := 2.75
const STEP := 10.0
const COUNT := 41

var lanes: Array = []


func _ready() -> void:
	await get_tree().process_frame
	var env := OS.get_environment("MB_CASES")
	var cases := (env if not env.is_empty() else "120:150,90:150,60:150,120:80,120:250").split(",")
	var profile := TrackSpeedProfile.default_profile()
	var lab := Node3D.new()
	add_child(lab)
	for ci in cases.size():
		var parts := cases[ci].split_floats(":")
		var x := ci * 120.0
		var c := Curve3D.new()
		c.bake_interval = 0.5
		var k := 0.0
		while k <= LANE:
			c.add_point(Vector3(x, 0.0, -k))
			k += 50.0
		var path := Path3D.new()
		path.curve = c
		lab.add_child(path)
		var seg := TrackRoadSegment.new()
		seg.path_node = NodePath("..")
		seg.polygon = PackedVector2Array(ROAD_POLY)
		seg.interval = 1.0
		seg.collision_layer = 1
		path.add_child(seg)
		var pad: Node3D = load(PAD_SCENE).instantiate()
		pad.set("boost_strength", parts[1])
		lab.add_child(pad)
		pad.global_transform = TrackRoadSegment.frame_at(c, PAD_AT)
		var ship: ShipController = load(SHIP_SCENE).instantiate()
		ship.profile = profile
		ship.ai_controlled = true
		lab.add_child(ship)
		var f := TrackRoadSegment.frame_at(c, 20.0)
		ship.global_transform = Transform3D(f.basis, f.origin + f.basis.y * HOVER)
		ship.velocity = -f.basis.z * parts[0]
		lanes.append({ship = ship, curve = c, v0 = parts[0], strength = parts[1], hit_v = -1.0,
				hit_d = -1.0, rows = PackedFloat32Array(), next = 0.0, done = false})
	for i in 6:
		await get_tree().physics_frame
	for L in lanes:
		(L.ship as ShipController).settle_on_surface()
	var t := 0.0
	while t < 30.0:
		await get_tree().physics_frame
		t += 1.0 / 60.0
		var all_done := true
		for L in lanes:
			if not L.done:
				all_done = false
				_step(L)
		if all_done:
			break
	var sp := TrackSpeedProfile.new()
	sp.model = TrackSpeedProfile.default_model()
	var worst := 0.0
	for L in lanes:
		var model := sp.boosted(L.hit_v, L.strength, profile.overspeed_damping, STEP, COUNT)
		print("MB arrive %.0f (at the pad %.1f), strength %.0f, pad at %.0f m" % [L.v0, L.hit_v, L.strength, L.hit_d])
		var line := "MB   m:     "
		var meas := "MB   ship:  "
		var mod := "MB   model: "
		for i in COUNT:
			if i % 4 != 0:
				continue
			line += "%6.0f" % (i * STEP)
			meas += "%6.1f" % (L.rows[i] if i < L.rows.size() else -1.0)
			mod += "%6.1f" % model[i]
		print(line)
		print(meas)
		print(mod)
		var err := 0.0
		for i in mini(COUNT, L.rows.size()):
			err = maxf(err, absf(L.rows[i] - model[i]))
		worst = maxf(worst, err)
		print("MB   max |ship - model| %.1f u/s" % err)
	print("MB worst %.1f u/s" % worst)
	get_tree().quit(0)


func _step(L: Dictionary) -> void:
	var ship: ShipController = L.ship
	var curve: Curve3D = L.curve
	var d := curve.get_closest_offset(ship.global_position)
	var v := ship.velocity.length()
	var f := TrackRoadSegment.frame_at(curve, minf(d + 30.0, curve.get_baked_length()))
	var local := ship.global_transform.basis.inverse() * (f.origin - ship.global_position)
	ship.steer_input = clampf(atan2(-local.x, -local.z) * 2.4 - ship.measured_yaw_rate * 0.25, -1.0, 1.0)
	# Hold the arrival speed until the pad, then full throttle.
	if L.hit_v < 0.0:
		ship.throttle_input = clampf((float(L.v0) - v) * 0.2, 0.0, 1.0)
		var brake := 1.0 if v > float(L.v0) + 3.0 else 0.0
		ship.airbrake_left = brake
		ship.airbrake_right = brake
		if ship.get_boost_overspeed() > 0.0:
			L.hit_d = d
			# Speed just before the pad: the boost was added this frame.
			L.hit_v = v - float(L.strength)
			L.rows.append(v)
			L.next = d + STEP
	else:
		ship.throttle_input = 1.0
		ship.airbrake_left = 0.0
		ship.airbrake_right = 0.0
		while d >= L.next and L.rows.size() < COUNT:
			L.rows.append(v)
			L.next += STEP
		if L.rows.size() >= COUNT or d > LANE - 50.0:
			L.done = true
