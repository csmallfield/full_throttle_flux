extends Node
## Speed-wobble probe (v35). Flies the real default_racer down a track's
## MainSpline centre line on a simple autopilot at a CONSTANT throttle (no
## speed controller to add wobble of its own) and logs, every physics frame,
## the ship's speed split into planar and along-normal parts, its hover
## height, grounded state, slope and magnet weight. Reports where planar
## speed oscillates and what the hover was doing there.
##
##   godot --headless --fixed-fps 60 --path . -s res://tools/dev/wobble_probe_boot.gd
##
## Env:
##   WP_TRACK     track scene id (default builder_lab)
##   WP_THROTTLE  constant throttle (default 0.8 -- settles below max_speed,
##                so the speed limiter doesn't hide anything)
##   WP_LAPS      laps to fly (default 1)
##   WP_LATERAL   fly this many metres right (+) / left (-) of the centre line
##   WP_ROUTE     forked tracks: fly route r (through branch r) instead of the
##                main lap
##   WP_LINE      1 = fly the track's trained racing line laterals (uses the
##                whole road like a player does) instead of a fixed lateral
##   WP_CSV       per-frame log path (optional)

const LOOKAHEAD := 30.0
const HOVER := 2.75

func _env(k: String, d: String) -> String:
	var v := OS.get_environment(k)
	return v if v != "" else d

func _ready() -> void:
	await get_tree().process_frame
	var track_id := _env("WP_TRACK", "builder_lab")
	var throttle := _env("WP_THROTTLE", "0.8").to_float()
	var laps := _env("WP_LAPS", "1").to_float()
	var profile := load("res://resources/ships/default_racer.tres") as ShipProfile
	var track: Node = (load("res://scenes/tracks/%s.tscn" % track_id) as PackedScene).instantiate()
	add_child(track)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var lateral := _env("WP_LATERAL", "0").to_float()
	var helper := TrackSplineHelper.new(track)
	if OS.get_environment("WP_ROUTE") != "" and helper.graph:
		helper = TrackSplineHelper.for_path(helper.graph.route_path(int(OS.get_environment("WP_ROUTE"))), track)
	var line: BakedRacingLine = null
	if OS.get_environment("WP_LINE") == "1":
		line = load(AILineTrainer.trained_path(track_id, "default_racer")) as BakedRacingLine
	var path := helper.track_path
	var curve := helper.curve
	var length := helper.total_length
	var ship := AILineTrainer.spawn_ship(profile)
	ship.ai_controlled = true
	add_child(ship)
	var d0 := 40.0
	var f := path.global_transform * TrackRoadSegment.frame_at(curve, d0)
	ship.global_transform = Transform3D(f.basis, f.origin + f.basis.y * HOVER)
	ship.velocity = -f.basis.z * 60.0
	for i in 4:
		await get_tree().physics_frame
	ship.settle_on_surface()

	var rows: Array = []
	var dist := 0.0
	var prev_d := d0
	var t := 0.0
	var local_inv := path.global_transform.affine_inverse()
	while dist < length * laps + 200.0 and t < 400.0:
		await get_tree().physics_frame
		t += 1.0 / 60.0
		var d := curve.get_closest_offset(local_inv * ship.global_position)
		var dd := d - prev_d
		if dd < -length * 0.5:
			dd += length
		elif dd > length * 0.5:
			dd -= length
		if absf(dd) < 50.0:
			dist += dd
		prev_d = d
		# steer toward the centre line ahead
		var fa := path.global_transform * TrackRoadSegment.frame_at(curve, fposmod(d + LOOKAHEAD, length))
		var lat := lateral
		if line:
			lat = line.get_lateral_at(fposmod(d + LOOKAHEAD, length) / length)
		var local := ship.global_transform.basis.inverse() * (fa.origin + fa.basis.x * lat - ship.global_position)
		ship.steer_input = clampf(atan2(-local.x, -local.z) * 2.4 - ship.measured_yaw_rate * 0.25, -1.0, 1.0)
		ship.throttle_input = throttle
		ship.airbrake_left = 0.0
		ship.airbrake_right = 0.0
		if t < 4.0:
			continue
		var n: Vector3 = ship.current_track_normal.normalized()
		var vn := ship.velocity.dot(n)
		var vp := (ship.velocity - n * vn).length()
		var fr := path.global_transform * TrackRoadSegment.frame_at(curve, d)
		var slope := rad_to_deg(asin(clampf(-fr.basis.z.y, -1.0, 1.0)))
		var scraping: bool = ship.get("_is_scraping_wall") == true
		rows.append([t, d, ship.velocity.length(), vp, vn, ship.ground_distance if ship.is_grounded else -1.0,
				1.0 if ship.is_grounded else 0.0, slope, ship.magnet_weight, 1.0 if scraping else 0.0,
				ship.get_boost_overspeed(), (ship.global_position - fr.origin).dot(fr.basis.x)])

	# ---- report ----------------------------------------------------------
	var n := rows.size()
	var w := 20   # 1/3 s half window
	var hp := PackedFloat32Array()
	hp.resize(n)
	for i in range(w, n - w):
		var avg := 0.0
		for k in range(i - w, i + w + 1):
			avg += rows[k][3]
		hp[i] = rows[i][3] - avg / (2 * w + 1)
	print("WOBBLE track=%s throttle=%.2f frames=%d" % [track_id, throttle, n])
	var i := w
	var found := 0
	while i < n - w - 60:
		var lo := 1e9
		var hi := -1e9
		var vlo := 1e9
		var vhi := -1e9
		var air := 0
		var glo := 1e9
		var ghi := -1e9
		var mw := 0.0
		var scr := 0
		var over := 0.0
		for k in range(i, i + 60):
			lo = minf(lo, hp[k]); hi = maxf(hi, hp[k])
			vlo = minf(vlo, rows[k][4]); vhi = maxf(vhi, rows[k][4])
			if rows[k][6] < 0.5:
				air += 1
			else:
				glo = minf(glo, rows[k][5]); ghi = maxf(ghi, rows[k][5])
			mw = maxf(mw, rows[k][8])
			scr += int(rows[k][9])
			over = maxf(over, rows[k][10])
		if hi - lo > 4.0 and over < 1.0:
			found += 1
			print("WOBBLE d=%5.0f-%5.0fm v=%5.1f planar p2p=%4.1f  v_normal %5.1f..%5.1f  hover %s  air=%2d/60 magnet=%.2f scrape=%d slope=%5.1f" % [
				rows[i][1], rows[i + 59][1], rows[i][2], hi - lo, vlo, vhi,
				("%.2f..%.2f" % [glo, ghi]) if ghi > 0.0 else "-", air, mw, scr, rows[i][7]])
			i += 60
		else:
			i += 10
	print("WOBBLE windows=%d" % found)
	var csv := OS.get_environment("WP_CSV")
	if csv != "":
		var fl := FileAccess.open(csv, FileAccess.WRITE)
		fl.store_line("t,d,v,vplanar,vnormal,hover,grounded,slope,magnet,scrape,over,lateral")
		for r in rows:
			fl.store_line(",".join(r.map(func(x): return "%.3f" % x)))
		fl.close()
	get_tree().quit(0)
