extends Node
## v35 Phase 0 self-test. Run through env_selftest_boot.gd:
##   godot --headless --fixed-fps 60 --path . -s res://tools/env/env_selftest_boot.gd [-- <track scene>]
##
##  1. SplineSpan == the old MagneticZone.weight_at() maths, bit for bit
##  2. TrackFxZones blending
##  3. On a real track: EnvironmentState + one driven ship. Probe grounded,
##     wall rays, spline distance agrees with UtopiaKit (road_xf), covered zone
##     dries the local surface, wall_hit / wall_scrape fire, weather presets
##     change the sky's weather keys but never the sun, Clear restores the
##     authored sky, globals reset when the state leaves the tree.
## Prints PASS/FAIL per check, exits 0 only if everything passed.

const DEFAULT_TRACK := "res://scenes/tracks/test_circuit_3_live.tscn"
const SHIP_SCENE := "res://scenes/ships/default_racer.tscn"
const SHIP_PROFILE := "res://resources/ships/default_racer.tres"
const START_D := 300.0
const DRIVE_SECONDS := 8.0

var _fails := 0
var _hits := 0
var _scrapes := 0


func _ready() -> void:
	await get_tree().process_frame
	_test_span()
	_test_zone_blend()
	var args := OS.get_cmdline_user_args()
	await _test_track(args[0] if args.size() > 0 else DEFAULT_TRACK)
	print("ENVTEST %s (%d failed)" % ["PASS" if _fails == 0 else "FAIL", _fails])
	get_tree().quit(0 if _fails == 0 else 1)


func _check(ok: bool, what: String) -> void:
	print("  %s  %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_fails += 1


# ----------------------------------------------------------------------------
# 1. Span maths
# ----------------------------------------------------------------------------

func _test_span() -> void:
	print("ENVTEST span maths")
	var rng := RandomNumberGenerator.new()
	rng.seed = 35
	var worst := 0.0
	for i in 20000:
		var length := rng.randf_range(200.0, 6000.0)
		var start := rng.randf_range(-100.0, length + 100.0)
		var end := rng.randf_range(-100.0, length + 100.0)
		var ri := rng.randf_range(0.0, 80.0) if rng.randf() > 0.2 else 0.0
		var ro := rng.randf_range(0.0, 80.0) if rng.randf() > 0.2 else 0.0
		var d := rng.randf_range(-length, 2.0 * length)
		var a := SplineSpan.weight(d, length, start, end, ri, ro)
		var b := _old_weight(d, length, start, end, ri, ro)
		worst = maxf(worst, absf(a - b))
	_check(worst == 0.0, "SplineSpan matches pre-v35 MagneticZone maths (max diff %f)" % worst)
	var z := MagneticZone.new()
	z.start_distance = 100.0
	z.end_distance = 200.0
	_check(z.weight_at(150.0, 1000.0) == 1.0 and z.weight_at(400.0, 1000.0) == 0.0,
		"MagneticZone.weight_at still answers through SplineSpan")


## Verbatim copy of MagneticZone.weight_at() before v35.
static func _old_weight(distance: float, length: float, start_distance: float,
		end_distance: float, ramp_in: float, ramp_out: float) -> float:
	if length <= 0.0:
		return 0.0
	var span := _w(end_distance - start_distance, length)
	var into := _w(distance - start_distance, length)
	if into <= span:
		return 1.0
	var before := _w(start_distance - distance, length)
	if ramp_in > 0.0 and before < ramp_in:
		return _s(1.0 - before / ramp_in)
	var after := _w(distance - end_distance, length)
	if ramp_out > 0.0 and after < ramp_out:
		return _s(1.0 - after / ramp_out)
	return 0.0


static func _w(d: float, length: float) -> float:
	var r := fmod(d, length)
	return r + length if r < 0.0 else r


static func _s(t: float) -> float:
	t = clampf(t, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


# ----------------------------------------------------------------------------
# 2. Zone blending
# ----------------------------------------------------------------------------

func _test_zone_blend() -> void:
	print("ENVTEST zone blending")
	var a := TrackFxZone.new()
	a.start_distance = 100.0
	a.end_distance = 200.0
	a.dust_scale = 2.0
	a.covered = 1.0
	var b := TrackFxZone.new()
	b.start_distance = 150.0
	b.end_distance = 250.0
	b.dust_scale = 3.0
	b.standing_water = 0.5
	var c := TrackFxZone.new()   # wraps the seam
	c.start_distance = 950.0
	c.end_distance = 50.0
	c.snow_drift = 1.0
	var list: Array[TrackFxZone] = [a, b, c]
	var s := TrackFxZones.sample_zones(list, 175.0, 1000.0)
	_check(is_equal_approx(s.dust_scale, 6.0) and s.covered == 1.0 and s.standing_water == 0.5,
		"overlap: dust multiplies (%.2f), others take the max" % s.dust_scale)
	s = TrackFxZones.sample_zones(list, 10.0, 1000.0, s)
	_check(s.snow_drift == 1.0 and s.covered == 0.0, "zone wrapping the lap seam")
	s = TrackFxZones.sample_zones(list, 600.0, 1000.0, s)
	_check(s.weight == 0.0 and s.dust_scale == 1.0, "outside every zone = neutral")


# ----------------------------------------------------------------------------
# 3. On a track
# ----------------------------------------------------------------------------

func _test_track(track_path: String) -> void:
	print("ENVTEST track %s" % track_path)
	var track: Node3D = (load(track_path) as PackedScene).instantiate()
	add_child(track)
	await get_tree().physics_frame
	var kit := UtopiaKit.new(track)

	# A covered test zone ahead of the start point, rain as the start weather.
	var covered := TrackFxZone.new()
	covered.zone_name = "test cover"
	covered.start_distance = START_D + 120.0
	covered.end_distance = START_D + 220.0
	covered.ramp_in = 10.0
	covered.ramp_out = 10.0
	covered.covered = 1.0
	var tenv := TrackEnvironment.new()
	tenv.dust = 0.3
	tenv.default_weather = load("res://resources/weather/rain_medium.tres")
	tenv.zones.append(covered)
	var profile := TrackProfile.new()
	profile.environment = tenv

	var env := EnvironmentState.install(self, track, profile)
	await get_tree().process_frame
	_check(EnvironmentState.find(get_tree()) == env, "EnvironmentState installed and findable")
	_check(env.main_spline != null and env.spline_length > 100.0,
		"MainSpline found (%.0f m)" % env.spline_length)
	_check(is_equal_approx(env.spline_length, kit.length),
		"spline length agrees with UtopiaKit (%.1f vs %.1f)" % [env.spline_length, kit.length])
	_check(is_equal_approx(env.wetness, 0.85) and is_equal_approx(env.dust, 0.3),
		"start weather applied instantly (wet %.2f dust %.2f)" % [env.wetness, env.dust])
	var g: Variant = RenderingServer.global_shader_parameter_get(&"env_wetness")
	if g != null:
		_check(is_equal_approx(float(g), 0.85), "env_wetness global published (%s)" % str(g))
	else:
		print("  --    global readback unavailable on this renderer (headless)")

	var sky := env.sky
	var sun_el := 0.0
	var base_cov := 0.0
	if sky:
		sun_el = sky.sun_elevation
		base_cov = env._sky_base.get("coverage", sky.coverage)
		_check(not is_equal_approx(sky.coverage, base_cov),
			"rain changed cloud coverage (%.2f -> %.2f)" % [base_cov, sky.coverage])

	# --- ship ---------------------------------------------------------------
	var ship: ShipController = (load(SHIP_SCENE) as PackedScene).instantiate()
	ship.profile = load(SHIP_PROFILE)
	ship.ai_controlled = true
	add_child(ship)
	ship.wall_hit.connect(func(_p, _n, _s, _c): _hits += 1)
	ship.wall_scrape.connect(func(_p, _n, _s, _c): _scrapes += 1)
	var b := kit.frame(START_D)
	ship.global_transform = Transform3D(b, kit.center(START_D) + b.y * 4.0)
	await get_tree().physics_frame
	ship.settle_on_surface()
	for i in 10:
		await get_tree().physics_frame
	var probe := ShipEnvProbe.of(ship)
	_check(probe != null and probe.active, "probe attached and active")
	_check(probe.has_ground and probe.ground_distance < 4.0,
		"grounded, ground %.2f m" % probe.ground_distance)
	_check(absf(probe.spline_distance - START_D) < 6.0,
		"spline distance %.1f matches UtopiaKit d=%.0f (road_xf)" % [probe.spline_distance, START_D])

	# --- drive the centre line --------------------------------------------
	var t := 0.0
	var last_d := probe.spline_distance
	var travelled := 0.0
	var backwards := 0
	var grounded_ticks := 0
	var ticks := 0
	var saw_wall := false
	var cover_seen := 0.0
	var wet_in_cover := 1.0
	while t < DRIVE_SECONDS:
		_steer(ship, kit, probe.spline_distance, 1.0, 0.0)
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		ticks += 1
		if probe.has_ground:
			grounded_ticks += 1
		if probe.wall_left != INF or probe.wall_right != INF:
			saw_wall = true
		var step := SplineSpan.wrap_distance(probe.spline_distance - last_d + env.spline_length * 0.5,
			env.spline_length) - env.spline_length * 0.5
		if step < -0.5:
			backwards += 1
		travelled += step
		last_d = probe.spline_distance
		if probe.zone.covered > 0.99:
			cover_seen = 1.0
			wet_in_cover = minf(wet_in_cover, probe.wetness)
	_check(float(grounded_ticks) / ticks > 0.95, "grounded %d / %d ticks" % [grounded_ticks, ticks])
	_check(travelled > 200.0 and backwards == 0,
		"spline distance advances smoothly (%.0f m, %d backward steps)" % [travelled, backwards])
	_check(saw_wall, "side rays see the walls")
	_check(cover_seen == 1.0 and wet_in_cover == 0.0,
		"covered zone dries the local surface (min wet %.2f)" % wet_in_cover)

	# --- into the wall ---------------------------------------------------------
	_hits = 0
	_scrapes = 0
	t = 0.0
	while t < 2.5 and _scrapes < 5:
		_steer(ship, kit, probe.spline_distance, 1.0, 45.0)
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	print("  --    walls L %s R %s, speed %.0f" % [str(probe.wall_left), str(probe.wall_right), ship.get_speed()])
	_check(_hits >= 1, "wall_hit fired (%d)" % _hits)
	_check(_scrapes >= 1, "wall_scrape fired while sliding (%d)" % _scrapes)
	_check(probe.seconds_since_hit() < 3.0 and probe.last_hit_point != Vector3.ZERO,
		"probe recorded the hit point")

	# --- weather presets --------------------------------------------------------
	env.apply_weather(load("res://resources/weather/snow_medium.tres"), true)
	_check(is_equal_approx(env.frost, 0.8) and env.wetness == 0.0, "snow: frost %.2f" % env.frost)
	env.apply_weather(load("res://resources/weather/rain_medium.tres"), false)
	await get_tree().create_timer(1.0).timeout
	_check(env.wetness > 0.0 and env.wetness < 0.85, "mid-race change blends (wet %.2f after 1 s)" % env.wetness)
	env.apply_weather(null, true)
	if sky:
		_check(is_equal_approx(sky.sun_elevation, sun_el), "sun never moved (%.1f deg)" % sky.sun_elevation)
		_check(is_equal_approx(sky.coverage, base_cov), "Clear restores the authored coverage (%.2f)" % sky.coverage)
	var n := env.weather_choices().size()
	_check(n >= 5, "debug weather list (%d presets)" % n)

	# --- teardown ---------------------------------------------------------------
	env.free()
	g = RenderingServer.global_shader_parameter_get(&"env_wetness")
	if g != null:
		_check(float(g) == 0.0, "globals reset when EnvironmentState leaves")
	# physics_frame fires before the nodes' _physics_process: wait two.
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check(not probe.active, "probe goes idle without an EnvironmentState")
	ship.queue_free()
	track.queue_free()
	await get_tree().process_frame


## Follows the road centre `lat` metres to the right, throttle `thr`.
func _steer(ship: ShipController, kit: UtopiaKit, d: float, thr: float, lat: float) -> void:
	var aim := kit.center(d + 30.0) + kit.right_flat(d + 30.0) * lat
	var local := ship.global_transform.basis.inverse() * (aim - ship.global_position)
	ship.steer_input = clampf(atan2(-local.x, -local.z) * 2.4 - ship.measured_yaw_rate * 0.25, -1.0, 1.0)
	ship.throttle_input = thr
	ship.airbrake_left = 0.0
	ship.airbrake_right = 0.0
