extends Node
## Sky Lab self test: drives the lab on the real track and checks what a
## person can't easily see. Writes only to user://sky_lab. Run with
##
##   LAB_SELFTEST=1 godot --path full_throttle_flux res://tools/sky_lab/sky_lab.tscn
##
## Prints SKYTEST lines and quits with the number of failures.

const OUT := "user://sky_lab"

## WeatherFx's per-kind numbers before they became PrecipLook files (v35).
const V35 := {
	WeatherPreset.Kind.RAIN: {fall_spread = 0.15, sway = 0.0, width = 0.012, min_length = 0.25,
		max_length = 3.5, shutter = 0.025, roundness = 0.0, opacity = 0.32, near_fade = 0.6,
		cells = Vector2(1.4, 0.06), scroll = Vector2(0.0, 11.0), threshold = 0.62, sharpness = 0.08,
		far_opacity = 0.08, carry = 0.6, fall = 11.0, density = 1.0},
	WeatherPreset.Kind.SNOW: {fall_spread = 0.35, sway = 0.6, width = 0.035, min_length = 0.035,
		max_length = 0.6, shutter = 0.01, roundness = 1.0, opacity = 0.6, near_fade = 1.5,
		cells = Vector2(0.9, 0.5), scroll = Vector2(0.3, 1.4), threshold = 0.72, sharpness = 0.08,
		far_opacity = 0.22, carry = 0.8, fall = 1.4, density = 0.55},
	WeatherPreset.Kind.DUST_STORM: {fall_spread = 0.3, sway = 0.3, width = 0.02, min_length = 0.05,
		max_length = 1.2, shutter = 0.02, roundness = 0.4, opacity = 0.45, near_fade = 1.0,
		cells = Vector2(0.05, 0.12), scroll = Vector2(14.0, 0.0), threshold = 0.45, sharpness = 0.4,
		far_opacity = 0.4, carry = 1.1, fall = 0.4, density = 1.0},
}

var lab: Node
var fails := 0


func _ready() -> void:
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func check(ok: bool, what: String) -> void:
	print("SKYTEST %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		fails += 1


func _run() -> void:
	await _frames(8)
	var doc = lab.doc
	check(doc.sky != null, "found the track's sky controller")
	check(doc.sky_file.ends_with(".tscn") and doc.env_file == doc.sky_file,
			"sky and Environment save to one lighting scene (%s)" % doc.sky_file)
	_looks_match_v35()
	await _weather_never_leaks(doc)
	await _edits_reach_the_track(doc)
	await _history(doc)
	await _saving(doc)
	if DisplayServer.get_name() != "headless":
		lab._measure_exposure()
		check(lab.exposure.mean > 0.02 and lab.exposure.mean < 0.98,
				"exposure reads the frame (average %.2f)" % lab.exposure.mean)
	print("SKYTEST done: %d failed" % fails)
	get_tree().quit(fails)


## The files and builtin() are the numbers WeatherFx had hard-coded.
func _looks_match_v35() -> void:
	for kind: int in V35:
		var e: Dictionary = V35[kind]
		var file := PrecipLook.for_kind(kind)
		var b := PrecipLook.builtin(kind)
		for l: PrecipLook in [file, b]:
			var p := ShaderMaterial.new()
			var d := ShaderMaterial.new()
			var f := ShaderMaterial.new()
			l.configure(p, d, f)
			var ok := true
			for k in ["fall_spread", "sway"]:
				ok = ok and is_equal_approx(float(p.get_shader_parameter(k)), e[k])
			for k in ["width", "min_length", "max_length", "shutter", "roundness", "opacity", "near_fade"]:
				ok = ok and is_equal_approx(float(d.get_shader_parameter(k)), e[k])
			ok = ok and (f.get_shader_parameter("cells") as Vector2).is_equal_approx(e.cells)
			ok = ok and (f.get_shader_parameter("scroll") as Vector2).is_equal_approx(e.scroll)
			ok = ok and is_equal_approx(float(f.get_shader_parameter("threshold")), e.threshold)
			ok = ok and is_equal_approx(float(f.get_shader_parameter("sharpness")), e.sharpness)
			ok = ok and is_equal_approx(l.far_opacity, e.far_opacity)
			ok = ok and is_equal_approx(l.density_scale, e.density)
			var wind := Vector3(3.0, 0.0, -2.0)
			ok = ok and l.fall(wind).is_equal_approx(wind * float(e.carry) + Vector3(0, -float(e.fall), 0))
			check(ok, "%s look (%s) matches v35" % [PrecipLook.stem(kind), "file" if l == file else "builtin"])
	# The colours: the old formulas, on a test fog and dust colour.
	var fog := Color(0.6, 0.62, 0.7)
	var dust := Color(0.62, 0.52, 0.38)
	check(PrecipLook.for_kind(WeatherPreset.Kind.RAIN).tint(fog, dust).is_equal_approx(fog.lerp(Color(0.85, 0.88, 0.92), 0.3))
			and PrecipLook.for_kind(WeatherPreset.Kind.SNOW).tint(fog, dust).is_equal_approx(fog.lerp(Color(0.95, 0.96, 1.0), 0.6))
			and PrecipLook.for_kind(WeatherPreset.Kind.DUST_STORM).tint(fog, dust).is_equal_approx(dust.lerp(fog, 0.3)),
			"precipitation tints match v35")


## Every weather on and off again: the authored values stay, and the nodes
## come back to them exactly.
func _weather_never_leaks(doc) -> void:
	var authored: Dictionary = doc.sky_vals.duplicate()
	var env_authored: Dictionary = doc.env_vals.duplicate()
	var keys := ["rain_heavy.tres", "snow_medium.tres", "fog_heavy.tres", "dust_storm_heavy.tres"]
	for f: String in keys:
		lab._pick_weather(f)
		await _frames(2)
	var heavy: WeatherPreset = doc.weathers["dust_storm_heavy.tres"]
	check(heavy.sky_coverage < 0.0 or is_equal_approx(doc.sky.coverage, heavy.sky_coverage),
			"the weather is laid on top (dust storm coverage %.2f)" % doc.sky.coverage)
	lab._pick_weather("clear.tres")
	await _frames(2)
	check(doc.sky_vals == authored and doc.env_vals == env_authored, "weather changes no authored value")
	var same := true
	for k: String in authored:
		if k != "preset" and doc.sky.get(k) != authored[k]:
			same = false
			print("SKYTEST   %s is %s, authored %s" % [k, doc.sky.get(k), authored[k]])
	check(same, "clear weather puts the sky controller back exactly")
	same = true
	for k: String in env_authored:
		if doc.environment.get(k) != env_authored[k]:
			same = false
			print("SKYTEST   env %s is %s, authored %s" % [k, doc.environment.get(k), env_authored[k]])
	check(same, "clear weather puts the Environment back exactly")
	check(doc.dirty_files().is_empty(), "looking at weathers leaves nothing unsaved")


func _edits_reach_the_track(doc) -> void:
	lab._pick_weather("rain_medium.tres")
	var rain: WeatherPreset = doc.weathers["rain_medium.tres"]
	doc.set_v("sky/sun_azimuth", 120.0)
	doc.set_v("sky/coverage", 0.1)
	doc.set_v("env/fog_sun_scatter", 0.45)
	doc.set_v("w:rain_medium.tres/wetness", 0.5)
	doc.set_v("p:rain/fall_speed", 20.0)
	await _frames(3)
	check(is_equal_approx(doc.sky.sun_azimuth, 120.0), "a sky edit reaches the controller under rain")
	check(rain.sky_coverage < 0.0 or is_equal_approx(doc.sky.coverage, rain.sky_coverage),
			"rain still sets the coverage over the edit (%.2f)" % doc.sky.coverage)
	check(doc.weather_effect("sky/coverage")[0] != "" and doc.weather_effect("sky/sun_azimuth")[0] == "",
			"the badges say which values the weather changes")
	check(is_equal_approx(doc.environment.fog_sun_scatter, 0.45), "a Post edit reaches the Environment")
	check(is_equal_approx(lab.env.wetness, 0.5), "a weather edit reaches the road (wetness %.2f)" % lab.env.wetness)
	var fx := WeatherFx.of(lab.env)
	check(fx != null and fx.look == doc.looks["rain"] and is_equal_approx(fx.look.fall(Vector3.ZERO).y, -20.0),
			"a Falling edit reaches the rain")
	lab._pick_weather("clear.tres")
	await _frames(2)
	check(is_equal_approx(doc.sky.coverage, 0.1), "in clear weather the coverage edit shows")


func _history(doc) -> void:
	doc.commit()
	var edited: Dictionary = doc.capture()
	doc.set_v("sky/sun_elevation", 5.0)
	doc.commit()
	check(doc.undo() and is_equal_approx(doc.sky.sun_elevation, float(edited["sky/sun_elevation"])), "undo")
	check(doc.redo() and is_equal_approx(doc.sky.sun_elevation, 5.0), "redo")
	doc.undo()
	lab._set_compare(true)
	await _frames(2)
	check(is_equal_approx(doc.sky.sun_azimuth, float(doc.saved["sky/sun_azimuth"])), "holding C shows the saved sky")
	lab._set_compare(false)
	await _frames(2)
	check(is_equal_approx(doc.sky.sun_azimuth, 120.0) and doc.capture() == edited, "letting go of C puts the edits back")
	doc.start_from_preset("dusk")
	doc.commit()
	await _frames(2)
	check(is_equal_approx(doc.sky.sun_elevation, UtopiaSkyController.PRESETS.dusk.sun_elevation)
			and doc.sky_vals.preset == "dusk", "Start from preset")
	doc.undo()
	check(doc.capture() == edited, "Start from preset undoes in one step")


func _saving(doc) -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	var files: Dictionary = doc.dirty_files()
	check(files.size() == 3 and files.has(doc.sky_file) and files.has("res://resources/weather/rain_medium.tres")
			and files.has(PrecipLook.path_for(WeatherPreset.Kind.RAIN)),
			"unsaved: the lighting scene, rain_medium and precip_rain (%s)" % str(files))
	var errors: PackedStringArray = doc.save(ProjectSettings.globalize_path(OUT))
	check(errors.is_empty(), "save to %s (%s)" % [OUT, "; ".join(errors)])
	var w := ResourceLoader.load(OUT + "/rain_medium.tres", "", ResourceLoader.CACHE_MODE_IGNORE) as WeatherPreset
	check(w != null and is_equal_approx(w.wetness, 0.5) and w.display_name == "Rain", "the saved weather loads with the edit")
	var l := ResourceLoader.load(OUT + "/precip_rain.tres", "", ResourceLoader.CACHE_MODE_IGNORE) as PrecipLook
	check(l != null and is_equal_approx(l.fall_speed, 20.0) and is_equal_approx(l.width, 0.012), "the saved look loads with the edit")
	var scene_copy: String = OUT + "/" + doc.sky_file.get_file()
	var ps := ResourceLoader.load(scene_copy, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	var inst := ps.instantiate() if ps else null
	var sky: UtopiaSkyController = EnvironmentState._find_sky(inst) if inst else null
	var we: WorldEnvironment = EnvironmentState._find_world_env(inst) if inst else null
	check(sky != null and is_equal_approx(sky.sun_azimuth, 120.0) and is_equal_approx(sky.coverage, 0.1)
			and we != null and is_equal_approx(we.environment.fog_sun_scatter, 0.45),
			"the saved lighting scene loads with the sky and Post edits")
	if inst:
		inst.free()
	# Only the edited lines differ.
	for pair: Array in [[doc.sky_file, scene_copy, 3], ["res://resources/weather/rain_medium.tres", OUT + "/rain_medium.tres", 1],
			[PrecipLook.path_for(WeatherPreset.Kind.RAIN), OUT + "/precip_rain.tres", 1]]:
		var seen := {}
		for x in FileAccess.get_file_as_string(pair[0]).split("\n"):
			seen[x] = int(seen.get(x, 0)) + 1
		var changed := 0
		for x in FileAccess.get_file_as_string(pair[1]).split("\n"):
			if int(seen.get(x, 0)) > 0:
				seen[x] -= 1
			else:
				changed += 1
		check(changed == pair[2], "%s: %d line(s) changed or added" % [String(pair[0]).get_file(), changed])
	check(not doc.dirty_files().is_empty(), "a redirected save keeps the edits unsaved")
	doc.restore(doc.saved)
	doc.commit()
	check(doc.dirty_files().is_empty(), "restoring the saved look leaves nothing unsaved")
