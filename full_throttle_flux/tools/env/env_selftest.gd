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
	ShipVisuals.swap_mesh(ship, load("res://scenes/ships/variants/variant_red_yellow.tscn"))
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
	var fx := ShipFx.of(ship)
	var thrust_pts := 0
	var air_pts := 0
	var head_gap := 0.0
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
		if fx and fx.active and not fx.thrust.is_empty():
			var r: TrailRibbon = fx.thrust[0]
			thrust_pts = maxi(thrust_pts, r.point_count())
			air_pts = maxi(air_pts, fx.air_left.point_count() + fx.air_right.point_count())
	_check(float(grounded_ticks) / ticks > 0.95, "grounded %d / %d ticks" % [grounded_ticks, ticks])
	_check(travelled > 200.0 and backwards == 0,
		"spline distance advances smoothly (%.0f m, %d backward steps)" % [travelled, backwards])
	_check(saw_wall, "side rays see the walls")
	_check(cover_seen == 1.0 and wet_in_cover == 0.0,
		"covered zone dries the local surface (min wet %.2f)" % wet_in_cover)

	# --- Phase 1: trails ------------------------------------------------------
	print("ENVTEST trails")
	_check(fx != null and fx.active, "ShipFx attached and active")
	if fx and fx.active:
		_check(fx.thrust.size() == 2, "two thrust sockets found on the variant (%d)" % fx.thrust.size())
		_check(fx.thrust[0].socket.name == "FX_Thrust_L", "sockets come from the model, not fallbacks (%s)" % fx.thrust[0].socket.name)
		_check(thrust_pts > 4, "thrust trail built (max %d points)" % thrust_pts)
		# v38.1: where the nozzle is DRAWN (the ships are physics-interpolated),
		# compared just before drawing, when both are this frame's; the raw
		# physics pose runs up to a tick ahead of it.
		for i in 20:
			_steer(ship, kit, probe.spline_distance, 1.0, 0.0)   # keep to the centre
			await RenderingServer.frame_pre_draw
			var r: TrailRibbon = fx.thrust[0]
			if r.point_count() > 0:
				head_gap = maxf(head_gap, r.head_position().distance_to(
						r.socket.get_global_transform_interpolated().origin))
		_check(head_gap < 0.01, "head pinned to the nozzle (max gap %.4f m)" % head_gap)
		_check(air_pts > 0, "air streams appear at speed in rain (max %d points)" % air_pts)
		var long_len := _trail_length(fx.thrust[0])
		_check(long_len > 5.0 and long_len <= fx.profile.thrust_max_length * fx.profile.boost_length_mult + 0.01,
			"trail length %.1f m within its cap" % long_len)
		ship.ship_respawned.emit()
		await get_tree().process_frame
		await get_tree().process_frame
		_check(fx.thrust[0].point_count() <= 3, "respawn clears the trails (%d points left)" % fx.thrust[0].point_count())
		await _dust_checks(ship, kit, probe, env, fx)

	# --- into the wall ---------------------------------------------------------
	_hits = 0
	_scrapes = 0
	var imp := FxImpacts.for_env(env)
	var sparks0 := imp.sparks_total
	var marks0 := imp.marks_total
	var pools := FxPools.for_env(env)
	var wall_dust0: int = pools.emitted_total[0] + pools.emitted_total[1] + pools.emitted_total[2]
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
	print("ENVTEST impacts")
	_check(imp.sparks_total - sparks0 > 10, "wall contact throws sparks (%d)" % (imp.sparks_total - sparks0))
	_check(imp.marks_total - marks0 >= 1, "scrape marks laid (%d)" % (imp.marks_total - marks0))
	var vis_marks := 0
	for d in imp.decals:
		if d.visible:
			vis_marks += 1
			_check(d.cull_mask & FxImpacts.SHIP_RENDER_LAYER == 0, "marks skip the ship layer")
			break
	_check(vis_marks > 0, "a mark is on the wall")
	var wall_dust: int = pools.emitted_total[0] + pools.emitted_total[1] + pools.emitted_total[2] - wall_dust0
	_check(wall_dust > 0, "wall contact kicks up surface particles too (%d carriers)" % wall_dust)
	var bad_layers := 0
	var meshes := ship.find_children("*", "MeshInstance3D", true, false)
	for m in meshes:
		if (m as MeshInstance3D).layers != FxImpacts.SHIP_RENDER_LAYER:
			bad_layers += 1
	_check(meshes.size() > 0 and bad_layers == 0,
		"ship meshes on their own render layer (%d meshes, %d not)" % [meshes.size(), bad_layers])
	var hard0 := imp.flashes_total
	ship.wall_hit.emit(ship.global_position, Vector3.RIGHT, 80.0, 60.0)
	_check(imp.flashes_total == hard0 + 1, "hard hit flashes")
	if fx and fx.active:
		await _perf_pack(kit, env)

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
	_check(n >= 13, "weather list: clear + 4 kinds x 3 intensities (%d presets)" % n)
	await _phase4_checks(ship, kit, probe, env, sky)

	# --- teardown ---------------------------------------------------------------
	env.free()
	g = RenderingServer.global_shader_parameter_get(&"env_wetness")
	if g != null:
		_check(float(g) == 0.0, "globals reset when EnvironmentState leaves")
	# physics_frame fires before the nodes' _physics_process: wait two.
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check(not probe.active, "probe goes idle without an EnvironmentState")
	_check(FxPrewarm.available() == FxPrewarm.COUNT,
		"particle nodes returned to the prewarm stash (%d / %d)" % [FxPrewarm.available(), FxPrewarm.COUNT])
	ship.queue_free()
	track.queue_free()
	await get_tree().process_frame


## Phase 4: surfaces, zone mask, sky / fog per preset, SSR, falling weather.
func _phase4_checks(ship: ShipController, kit: UtopiaKit, probe: ShipEnvProbe,
		env: EnvironmentState, sky: UtopiaSkyController) -> void:
	print("ENVTEST weather (phase 4)")
	var rep := env.surfaces
	_check(rep != null and rep.materials >= 3 and rep.conflicts == 0,
		"road + walls adopted the weather shader (%d materials, %d conflicts)" % [rep.materials, rep.conflicts])
	# v38 phase 5b: with a TrackSurface the circuit's road is on the v38
	# surface in CSG mode (material_override), its s already in metres.
	var road_csg := env.main_spline.get_node("groundGeo") as CSGPolygon3D
	var ov := road_csg.material_override as ShaderMaterial
	var v38 := ov != null and ov.shader != null and ov.shader.resource_path == EnvSurfaces.SURFACE_SHADER_PATH
	_check(rep.road_u_scale == (1.0 if v38 else 100.0), "road UVs map to MainSpline (u_scale %.0f%s)"
			% [rep.road_u_scale, ", v38 surface: metres" if v38 else ""])
	var v := EnvSurfaces.driving_surface_v(PackedVector2Array([Vector2(21.58349, 2.9622357),
		Vector2(17.218266, 2.0412953), Vector2(-16.617033, 1.8802173), Vector2(-20.253164, 2.7683895),
		Vector2(-20.286919, -1.9581314), Vector2(21.968796, -1.8501513)]))
	_check(is_equal_approx(v.x, 3.0 / 12.0) and is_equal_approx(v.y, 4.0 / 12.0),
		"driving surface UV.y range %.4f..%.4f (3/12..4/12, measured)" % [v.x, v.y])
	_check(env.track_mask != null, "zone mask built")
	if env.track_mask:
		var img := env.track_mask.get_image()
		var w := img.get_width()
		var px_in := img.get_pixel(int((START_D + 170.0) / env.spline_length * w), 0)
		var px_out := img.get_pixel(int((START_D + 20.0) / env.spline_length * w), 0)
		_check(px_in.r > 0.95 and px_out.r < 0.05 and absf(px_out.a - 0.25) < 0.01,
			"mask: covered %.2f inside the test cover, %.2f outside, dust scale %.2f" % [px_in.r, px_out.r, px_out.a * 4.0])
	var road := road_csg
	var sm := road.material as ShaderMaterial
	# The driving surface's UV.y range: the grid wrapper's road_v0/v1, or the
	# v38 CSG edge table's surface edge.
	var dv := Vector2(-1.0, -1.0)
	if v38:
		var edges: PackedVector4Array = ov.get_shader_parameter("csg_edges")
		var ys: PackedVector4Array = ov.get_shader_parameter("csg_edges_y")
		for i in int(ov.get_shader_parameter("csg_edge_count")):
			if int(ys[i].z) == TrackRoadSegment.EDGE_SURFACE:
				dv = Vector2(edges[i].x, edges[i].y)
	elif sm and sm.get_shader_parameter("road_v1") != null:
		dv = Vector2(sm.get_shader_parameter("road_v0"), sm.get_shader_parameter("road_v1"))
	# On the real mesh: vertices inside road_v0..v1 are the driving surface
	# (top of the extrusion), the rest are banks / sides / bottom.
	var meshes: Array = road.get_meshes()
	if meshes.size() >= 2:
		var arr := (meshes[1] as ArrayMesh).surface_get_arrays(0)
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var uvs: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
		var xf: Transform3D = road.global_transform * (meshes[0] as Transform3D)
		var tr := env.make_spline_tracker()
		var v0: float = dv.x
		var v1: float = dv.y
		# CSG vertices sit only at the polygon's corners, so the road_v0 / v1
		# rows are the driving surface's two edges: ~2 m up, ~17 m out.
		var h_sum := 0.0
		var lat_sum := 0.0
		var cnt := 0
		for i in range(0, verts.size(), 37):
			if absf(uvs[i].y - v0) > 0.002 and absf(uvs[i].y - v1) > 0.002:
				continue
			var wp: Vector3 = xf * verts[i]
			tr.reset()
			tr.update(wp)
			var fr := tr.frame()
			h_sum += (wp - fr.origin).dot(fr.basis.y)
			lat_sum += absf((wp - fr.origin).dot(fr.basis.x))
			cnt += 1
		var hh := h_sum / maxi(cnt, 1)
		var ll := lat_sum / maxi(cnt, 1)
		_check(cnt > 10 and hh > 1.0 and ll > 14.0 and ll < 19.0,
			"road_v0/v1 rows are the driving surface edges on the mesh (%d verts: %+.1f m up, %.1f m out)" % [cnt, hh, ll])
	if v38:
		_check(is_equal_approx(float(ov.get_shader_parameter("csg_u_scale")), 100.0)
				and float(road.get_instance_shader_parameter("along_main")) > 0.5 and dv.y > 0.1,
				"road: v38 surface in CSG mode (u 100 m, along_main), driving surface %.3f..%.3f" % [dv.x, dv.y])
	else:
		_check(sm and sm.shader.resource_path == EnvSurfaces.SHADER_PATH and dv.y > 0.1,
			"road material: weather shader, driving surface %.3f..%.3f" % [dv.x, dv.y])

	# Sky / fog per preset, then back to the authored look.
	var we := env.world_env
	var base_hfog: float = we.environment.fog_height_density if we else 0.0
	var base_fog_col: Color = sky.fog_color if sky else Color()
	var base_sun: float = sky.sun_energy if sky else 0.0
	for path in EnvironmentState.DEBUG_PRESETS:
		var pr := load(path) as WeatherPreset
		_check(pr != null, "preset loads: %s" % path.get_file())
	env.apply_weather(load("res://resources/weather/fog_heavy.tres"), true)
	if we:
		_check(we.environment.fog_height_density > base_hfog, "fog: height fog up (%.3f -> %.3f)" % [base_hfog, we.environment.fog_height_density])
	if sky:
		_check(sky.sun_energy < base_sun, "fog: sun dimmed (%.2f -> %.2f)" % [base_sun, sky.sun_energy])
	_check(env.line_glow > 0.5, "fog: track lines glow (%.2f)" % env.line_glow)
	env.apply_weather(load("res://resources/weather/dust_storm_heavy.tres"), true)
	if sky:
		var fc := sky.fog_color
		_check(fc.r > fc.b + 0.1, "dust storm: fog takes the dust colour (%s)" % str(fc))
	env.apply_weather(load("res://resources/weather/rain_heavy.tres"), true)
	# process_frame fires before the nodes' _process: wait two.
	await get_tree().process_frame
	await get_tree().process_frame
	if we:
		_check(we.environment.ssr_enabled, "rain: SSR on for the wet road")
	env.apply_weather(null, true)
	await get_tree().process_frame
	await get_tree().process_frame
	if we:
		_check(not we.environment.ssr_enabled and is_equal_approx(we.environment.fog_height_density, base_hfog),
			"clear: SSR off, height fog back (%.3f)" % we.environment.fog_height_density)
	if sky:
		_check(sky.fog_color.is_equal_approx(base_fog_col) and is_equal_approx(sky.sun_energy, base_sun),
			"clear: fog colour and sun back to the track's own")

	# Falling weather: needs a camera with a `ship`, like the race's chase cam.
	var wfx := WeatherFx.of(env)
	_check(wfx != null and wfx.near != null, "WeatherFx built")
	var cam := Camera3D.new()
	var cam_script := GDScript.new()
	cam_script.source_code = "extends Camera3D\nvar ship: Node3D\n"
	cam_script.reload()
	cam.set_script(cam_script)
	add_child(cam)
	cam.make_current()
	cam.set("ship", ship)
	env.apply_weather(load("res://resources/weather/snow_medium.tres"), true)
	var b := kit.frame(START_D + 20.0)
	ship.global_transform = Transform3D(b, kit.center(START_D + 20.0) + b.y * 4.0)
	ship.velocity = Vector3.ZERO
	if probe._tracker:
		probe._tracker.reset()
	cam.global_position = ship.global_position + b.z * 12.0
	for i in 20:
		await get_tree().process_frame
	_check(wfx.kind == WeatherPreset.Kind.SNOW and wfx.near.emitting and absf(wfx.shown - env.precipitation) < 0.01,
		"snow falls in the open (shown %.2f of %.2f)" % [wfx.shown, env.precipitation])
	var b2 := kit.frame(START_D + 170.0)
	ship.global_transform = Transform3D(b2, kit.center(START_D + 170.0) + b2.y * 4.0)
	ship.velocity = Vector3.ZERO
	if probe._tracker:
		probe._tracker.reset()
	for i in 40:
		await get_tree().physics_frame
	await get_tree().process_frame
	_check(probe.zone.covered > 0.95 and wfx.shown < 0.05,
		"cut out under cover (covered %.2f, shown %.2f)" % [probe.zone.covered, wfx.shown])
	env.apply_weather(load("res://resources/weather/fog_medium.tres"), true)
	await get_tree().process_frame
	_check(not wfx.near.emitting, "nothing falls in fog")
	env.apply_weather(null, true)
	cam.queue_free()


## Phase 2: which pool, how much, from where.
func _dust_checks(ship: ShipController, kit: UtopiaKit, probe: ShipEnvProbe,
		env: EnvironmentState, fx: ShipFx) -> void:
	print("ENVTEST dust")
	_check(fx.dust != null, "ShipDust built")
	if fx.dust == null:
		return
	var pools := FxPools.for_env(env)
	_check(pools != null and pools.carriers.size() == 3 and pools.puffs.size() == 3, "three looks, each carriers + puffs")
	_check(str(pools.carriers[0].sub_emitter) != "", "carriers feed the puff emitter (sub-emitter set)")
	env.apply_weather(null, true)   # clear; the test TrackEnvironment has dust 0.3
	await _drive_count(ship, kit, probe, pools, 0.25, 0.0, 0.0)   # let the probe see the change
	var counts := await _drive_count(ship, kit, probe, pools, 2.0, 0.0, 0.0)
	_check(fx.dust.kind == FxPools.Kind.DUST and counts[0] > 5 and counts[1] == 0,
		"dry: dust carriers %d, spray %d (2 s)" % [counts[0], counts[1]])
	var dry_ground: float = fx.dust.rates["ground"]
	_check(dry_ground > 1.0, "ground rate %.0f/s at speed" % dry_ground)
	counts = await _drive_count(ship, kit, probe, pools, 1.0, 1.0, 0.0)
	_check(fx.dust.rates["brake_l"] > 1.0 and fx.dust.rates["brake_r"] == 0.0,
		"left airbrake throws dust on the left only (L %.0f, R %.0f /s)" % [fx.dust.rates["brake_l"], fx.dust.rates["brake_r"]])
	env.apply_weather(load("res://resources/weather/rain_medium.tres"), true)
	counts = await _drive_count(ship, kit, probe, pools, 1.5, 0.0, 0.0)
	_check(fx.dust.kind == FxPools.Kind.SPRAY and counts[1] > 5,
		"rain: spray instead of dust (spray %d, dust %d)" % [counts[1], counts[0]])
	env.apply_weather(load("res://resources/weather/snow_medium.tres"), true)
	counts = await _drive_count(ship, kit, probe, pools, 1.5, 0.0, 0.0)
	_check(fx.dust.kind == FxPools.Kind.POWDER and counts[2] > 5,
		"snow: powder (powder %d)" % counts[2])
	env.apply_weather(load("res://resources/weather/dust_storm_medium.tres"), true)
	counts = await _drive_count(ship, kit, probe, pools, 1.0, 0.0, 0.0)
	_check(fx.dust.rates["ground"] > dry_ground * 1.5,
		"dust storm raises dust (ground %.0f/s vs %.0f dry)" % [fx.dust.rates["ground"], dry_ground])
	env.apply_weather(load("res://resources/weather/rain_medium.tres"), true)


## Drives `seconds`, returns particles emitted per pool meanwhile.
func _drive_count(ship: ShipController, kit: UtopiaKit, probe: ShipEnvProbe, pools: FxPools,
		seconds: float, brake_l: float, brake_r: float) -> PackedInt64Array:
	var before := pools.emitted_total.duplicate()
	var t := 0.0
	while t < seconds:
		_steer(ship, kit, probe.spline_distance, 1.0, 0.0)
		ship.airbrake_left = brake_l
		ship.airbrake_right = brake_r
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	ship.airbrake_left = 0.0
	ship.airbrake_right = 0.0
	var out := PackedInt64Array([0, 0, 0])
	for k in 3:
		out[k] = pools.emitted_total[k] - before[k]
	return out


func _trail_length(r: TrailRibbon) -> float:
	var pts := r.trail_points()
	var total := 0.0
	for i in range(1, pts.size()):
		total += pts[i].distance_to(pts[i - 1])
	return total


## Seven more ships around the test ship, all driving: CPU cost of every
## ribbon in the race, per frame.
func _perf_pack(kit: UtopiaKit, env: EnvironmentState) -> void:
	var ships: Array[ShipController] = []
	for i in 7:
		var s: ShipController = (load(SHIP_SCENE) as PackedScene).instantiate()
		s.profile = load(SHIP_PROFILE)
		s.ai_controlled = true
		add_child(s)
		var d := START_D + 900.0 + 14.0 * i
		var b := kit.frame(d)
		s.global_transform = Transform3D(b, kit.center(d) + kit.right_flat(d) * (5.0 if i % 2 else -5.0) + b.y * 4.0)
		ships.append(s)
	await get_tree().physics_frame
	for s in ships:
		s.settle_on_surface()
	var probes: Array[ShipEnvProbe] = []
	for s in ships:
		probes.append(ShipEnvProbe.of(s))
	var samples := PackedInt32Array()
	var fx_samples := PackedInt32Array()
	var t := 0.0
	while t < 4.0:
		for i in ships.size():
			_steer(ships[i], kit, probes[i].spline_distance, 1.0, 0.0)
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		if t > 1.0:
			samples.append(TrailRibbon.frame_usec)
			fx_samples.append(TrailRibbon.frame_usec + ShipFx.frame_usec)
	var total := 0
	var worst := 0
	for v in samples:
		total += v
		worst = maxi(worst, v)
	var avg := float(total) / maxi(samples.size(), 1) / 1000.0
	var fx_total := 0
	for v in fx_samples:
		fx_total += v
	var fx_avg := float(fx_total) / maxi(fx_samples.size(), 1) / 1000.0
	print("  --    8 ships, %d ribbons: trail CPU avg %.2f ms (worst %.2f); all ship FX incl. dust avg %.2f ms" % [
		ships.size() * 4 + 4, avg, worst / 1000.0, fx_avg])
	# Budget on the slowest machine we test on (2 vCPU cloud box); a desktop
	# is several times faster.
	_check(fx_avg < 3.0, "all ship FX for a full grid under 3 ms/frame here (avg %.2f ms)" % fx_avg)
	for s in ships:
		s.queue_free()


## Follows the road centre `lat` metres to the right, throttle `thr`.
func _steer(ship: ShipController, kit: UtopiaKit, d: float, thr: float, lat: float) -> void:
	var aim := kit.center(d + 30.0) + kit.right_flat(d + 30.0) * lat
	var local := ship.global_transform.basis.inverse() * (aim - ship.global_position)
	ship.steer_input = clampf(atan2(-local.x, -local.z) * 2.4 - ship.measured_yaw_rate * 0.25, -1.0, 1.0)
	ship.throttle_input = thr
	ship.airbrake_left = 0.0
	ship.airbrake_right = 0.0
