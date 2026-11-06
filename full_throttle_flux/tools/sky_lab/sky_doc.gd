extends RefCounted
## Sky Lab: everything the lab can edit, as one flat "key -> value" dictionary,
## the same model as Surface Lab's lab_doc.gd. Undo, the compare key,
## snapshots and "what's unsaved" all capture() the dictionary or restore() an
## older one.
##
## Keys:
##   sky/<prop>         the track's UtopiaSkyController, as authored (no weather)
##   env/<prop>         the track's Environment: fog, glow, AO, grading
##   te/<prop>          the track's TrackEnvironment: dust
##   w:<file>/<prop>    a WeatherPreset in resources/weather
##   p:<kind>/<prop>    a PrecipLook (rain, snow, dust_storm)
##   weather            the weather being previewed (not saved)
##
## The weather changes the sky controller and some Environment fog values at
## runtime (EnvironmentState._apply_sky). So the authored values live here, not
## on the nodes: apply() writes them to the nodes, lets EnvironmentState take
## its snapshot of them, then lays the previewed weather on top, exactly as a
## race start does. What's saved is never the weather-changed value.

signal changed

const WEATHER_DIR := "res://resources/weather"
const PRECIP_KINDS := {"rain": WeatherPreset.Kind.RAIN, "snow": WeatherPreset.Kind.SNOW,
	"dust_storm": WeatherPreset.Kind.DUST_STORM}
## Node paths, and the preset name (setting it re-applies the preset).
const SKY_SKIP := ["world_environment", "sun", "sky_fill", "preset"]
## Environment values the lab edits: [group, property, min, max]. The sky
## controller owns fog colour and density, ambient, exposure and volumetrics,
## so those are on the Sky tab, not here.
const ENV_PROPS := [
	["distance fog", "fog_sun_scatter", 0.0, 1.0],
	["distance fog", "fog_aerial_perspective", 0.0, 1.0],
	["distance fog", "fog_sky_affect", 0.0, 1.0],
	["height fog", "fog_height", -200.0, 200.0],
	["height fog", "fog_height_density", 0.0, 0.2],
	["tonemap", "tonemap_white", 1.0, 16.0],
	["glow", "glow_enabled", 0.0, 0.0],
	["glow", "glow_intensity", 0.0, 4.0],
	["glow", "glow_strength", 0.0, 2.0],
	["glow", "glow_bloom", 0.0, 1.0],
	["glow", "glow_hdr_threshold", 0.0, 4.0],
	["ambient occlusion", "ssao_enabled", 0.0, 0.0],
	["ambient occlusion", "ssao_radius", 0.1, 16.0],
	["ambient occlusion", "ssao_intensity", 0.0, 8.0],
	["ambient occlusion", "ssil_enabled", 0.0, 0.0],
	["ambient occlusion", "ssil_intensity", 0.0, 4.0],
	["grading", "adjustment_enabled", 0.0, 0.0],
	["grading", "adjustment_brightness", 0.0, 3.0],
	["grading", "adjustment_contrast", 0.0, 3.0],
	["grading", "adjustment_saturation", 0.0, 3.0],
]
const TE_PROPS := ["dust", "dust_color"]

var track: Node
var sky: UtopiaSkyController
var world_env: WorldEnvironment
var environment: Environment
var env_state: EnvironmentState
var track_env: TrackEnvironment

var sky_props: Array[Dictionary] = []
var env_props: Array[Dictionary] = []
var weather_props: Array[Dictionary] = []
var look_props: Array[Dictionary] = []
var te_props: Array[Dictionary] = []

## The authored values (what's saved), and the weather-free state.
var sky_vals := {}
var env_vals := {}
var weathers := {}      # file name -> WeatherPreset
var looks := {}         # kind stem -> PrecipLook
var weather_file := "clear.tres"

## Where things are saved.
var sky_file := ""
var sky_section := ""   # the controller's [node ...] header, up to its name
var sky_parent := ""
var env_file := ""
var env_section := ""

var saved := {}
var history: Array[Dictionary] = []
var history_i := -1
var since_edit := 1000.0
var _edited := false
var _quiet := 0.0
var _apply_due := false


## Call with the track in the tree, before EnvironmentState is installed, so
## the values read are the track's own.
func setup(p_track: Node, p_track_env: TrackEnvironment) -> void:
	track = p_track
	track_env = p_track_env
	sky = EnvironmentState._find_sky(track)
	world_env = EnvironmentState._find_world_env(track)
	environment = world_env.environment if world_env else null
	if sky:
		sky_props = script_props(sky, SKY_SKIP)
		for p in sky_props:
			sky_vals[p.name] = sky.get(p.name)
		sky_vals["preset"] = sky.preset
		var holder: Node = sky.owner if sky.owner else track
		sky_file = holder.scene_file_path
		sky_section = '[node name="%s"' % sky.name
		sky_parent = String(holder.get_path_to(sky.get_parent()))
	if environment:
		for e: Array in ENV_PROPS:
			var t := typeof(environment.get(e[1]))
			env_props.append({name = e[1], type = t, group = e[0],
					hint = PROPERTY_HINT_RANGE if t == TYPE_FLOAT else PROPERTY_HINT_NONE,
					hint_string = "%s,%s,%s" % [e[2], e[3], (float(e[3]) - float(e[2])) / 400.0]})
			env_vals[e[1]] = environment.get(e[1])
		var rp := environment.resource_path
		if rp.contains("::"):
			env_file = rp.get_slice("::", 0)
			env_section = '[sub_resource type="Environment" id="%s"]' % rp.get_slice("::", 1)
		elif rp != "":
			env_file = rp
			env_section = "[resource]"
	weather_props = script_props(WeatherPreset.new(), [])
	look_props = script_props(PrecipLook.new(), [])
	if track_env and track_env.resource_path != "":
		for p in script_props(track_env, []):
			if p.name in TE_PROPS:
				te_props.append(p)
	for f in files(WEATHER_DIR):
		weathers[f] = load("%s/%s" % [WEATHER_DIR, f])
	for stem: String in PRECIP_KINDS:
		looks[stem] = PrecipLook.for_kind(PRECIP_KINDS[stem])
	saved = capture()
	history = [saved.duplicate()]
	history_i = 0


func attach(p_env_state: EnvironmentState) -> void:
	env_state = p_env_state
	apply()


## A script's stored properties, in inspector order, with their group:
## {name, type, hint, hint_string, group, tooltip}.
static func script_props(obj: Object, skip: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var group := "general"
	for p: Dictionary in obj.get_property_list():
		if p.usage & PROPERTY_USAGE_GROUP:
			group = String(p.name) if String(p.name) != "" else "general"
			continue
		if not (p.usage & PROPERTY_USAGE_STORAGE and p.usage & PROPERTY_USAGE_SCRIPT_VARIABLE):
			continue
		if p.name in skip or p.type == TYPE_NODE_PATH or p.type == TYPE_OBJECT or p.type == TYPE_ARRAY:
			continue
		out.append({name = p.name, type = p.type, hint = p.hint, hint_string = p.hint_string,
				group = group})
	return out


# =============================================================================
# THE DICTIONARY
# =============================================================================

func capture() -> Dictionary:
	var d := {}
	d["weather"] = weather_file
	for k: String in sky_vals:
		d["sky/" + k] = sky_vals[k]
	for k: String in env_vals:
		d["env/" + k] = env_vals[k]
	for p in te_props:
		d["te/" + p.name] = track_env.get(p.name)
	for f: String in weathers:
		for p in weather_props:
			d["w:%s/%s" % [f, p.name]] = weathers[f].get(p.name)
	for stem: String in looks:
		for p in look_props:
			d["p:%s/%s" % [stem, p.name]] = looks[stem].get(p.name)
	return d


## Brings everything to `target`. Returns how many keys differed.
func restore(target: Dictionary) -> int:
	var cur := capture()
	var n := 0
	for k: String in target:
		if not cur.has(k) or cur[k] != target[k]:
			set_v(k, target[k], false)
			n += 1
	if n > 0:
		_edited = false
		apply()
		changed.emit()
	return n


func get_v(key: String) -> Variant:
	if key == "weather":
		return weather_file
	var head := key.get_slice("/", 0)
	var rest := key.substr(head.length() + 1)
	match head:
		"sky":
			return sky_vals.get(rest)
		"env":
			return env_vals.get(rest)
		"te":
			return track_env.get(rest)
	match head.get_slice(":", 0):
		"w":
			return weathers[head.get_slice(":", 1)].get(rest)
		"p":
			return looks[head.get_slice(":", 1)].get(rest)
	return null


## Writes one value and queues the redraw. `user` = an edit in the UI (goes
## into the undo history once things go quiet).
func set_v(key: String, value: Variant, user := true) -> void:
	if key == "weather":
		weather_file = String(value)
		_apply_due = true
	else:
		var head := key.get_slice("/", 0)
		var rest := key.substr(head.length() + 1)
		match head:
			"sky":
				sky_vals[rest] = value
				_apply_due = true
			"env":
				env_vals[rest] = value
				_apply_due = true
			"te":
				track_env.set(rest, value)
				if rest == "dust_color" and env_state:
					env_state.dust_color = value
				_apply_due = true
			_:
				var kind := head.get_slice(":", 0)
				var name := head.get_slice(":", 1)
				if kind == "w":
					weathers[name].set(rest, value)
					if name == weather_file:
						_apply_due = true
				elif kind == "p":
					looks[name].set(rest, value)
					var fx := WeatherFx.of(env_state)
					if fx:
						fx.reconfigure()
	if user:
		_edited = true
		_quiet = 0.0
		since_edit = 0.0
		changed.emit()


## Every key of a sky preset (UtopiaSkyController.PRESETS), as one edit.
func start_from_preset(name: String) -> void:
	var src: Dictionary = UtopiaSkyController.PRESETS.get(name, {})
	for k: String in src:
		if sky_vals.has(k):
			set_v("sky/" + k, src[k])
	set_v("sky/preset", name)


func weather() -> WeatherPreset:
	return weathers.get(weather_file)


## The look of the weather being previewed, or null if nothing falls in it.
func current_look_stem() -> String:
	var w := weather()
	return PrecipLook.stem(w.kind) if w else ""


## Writes the authored values to the nodes, then puts the previewed weather on
## top of them, the way a race starts.
func apply() -> void:
	_apply_due = false
	if sky:
		sky._suspend = true
		for k: String in sky_vals:
			if k != "preset":
				sky.set(k, sky_vals[k])
		sky._suspend = false
		sky._apply()
	if environment:
		for k: String in env_vals:
			environment.set(k, env_vals[k])
	if env_state:
		env_state._snapshot_sky()
		env_state.apply_weather(weather(), true)


## Plays the change from `from` to the previewed weather at race speed (its
## own surface_change_time and sky_transition_time).
func play_change(from: WeatherPreset) -> void:
	apply()
	if env_state:
		env_state.apply_weather(from, true)
		env_state.apply_weather(weather(), false)


## What the previewed weather does to `key` ("" = nothing): [text, is it
## replaced outright].
func weather_effect(key: String) -> Array:
	var w := weather()
	if w == null:
		return ["", false]
	var k := key.get_slice("/", 1)
	if key.begins_with("sky/"):
		var src: Dictionary = UtopiaSkyController.PRESETS.get(w.sky_preset, {})
		if k == "coverage" and w.sky_coverage >= 0.0:
			return ["weather sets it", true]
		if k == "fog_density" and w.fog_density >= 0.0:
			return ["weather sets it", true]
		if k == "volumetric_density" and w.volumetric_density >= 0.0:
			return ["weather sets it", true]
		if k in EnvironmentState.SKY_WEATHER_KEYS and src.has(k):
			return ["weather sets it", true]
		if k in EnvironmentState.SKY_MOOD_KEYS and src.has(k) and w.sky_mood > 0.0:
			return ["weather blends %d%%" % roundi(w.sky_mood * 100.0), false]
		if k == "fog_color" and (w.fog_tint.a > 0.0 or w.fog_tint_dust):
			return ["weather tints it", false]
		if k == "sun_energy" and w.sun_scale != 1.0:
			return ["weather x %.2f" % w.sun_scale, false]
	elif key.begins_with("env/"):
		if (k == "fog_height_density" or k == "fog_height") and w.height_fog_density >= 0.0:
			return ["weather sets it", true]
		if k == "fog_sky_affect" and w.fog_sky_affect >= 0.0:
			return ["weather sets it", true]
	return ["", false]


# =============================================================================
# REDRAW AND HISTORY
# =============================================================================

## Call every frame: applies queued edits, and files finished edits in the undo
## history once `commit_after` seconds pass with no new edit.
func tick(delta: float, commit_after := 0.4) -> void:
	since_edit += delta
	if _apply_due:
		apply()
	if _edited:
		_quiet += delta
		if _quiet >= commit_after:
			commit()


func commit() -> void:
	_edited = false
	var now := capture()
	if history_i >= 0 and now == history[history_i]:
		return
	history.resize(history_i + 1)
	history.append(now)
	if history.size() > 200:
		history.pop_front()
	history_i = history.size() - 1
	changed.emit()


func undo() -> bool:
	if _edited:
		commit()
	if history_i <= 0:
		return false
	history_i -= 1
	restore(history[history_i])
	return true


func redo() -> bool:
	if history_i >= history.size() - 1:
		return false
	history_i += 1
	restore(history[history_i])
	return true


# =============================================================================
# SAVING: only the edited lines change, in every file
# =============================================================================

## The files with unsaved edits: res:// path -> how many values differ.
func dirty_files() -> Dictionary:
	var out := {}
	var cur := capture()
	for k: String in cur:
		if k == "weather":
			continue
		if not saved.has(k) or saved[k] != cur[k]:
			var f := file_of(k)
			out[f] = int(out.get(f, 0)) + 1
	return out


func file_of(key: String) -> String:
	var head := key.get_slice("/", 0)
	match head:
		"sky":
			return sky_file
		"env":
			return env_file
		"te":
			return track_env.resource_path
	match head.get_slice(":", 0):
		"w":
			return "%s/%s" % [WEATHER_DIR, head.get_slice(":", 1)]
		"p":
			return PrecipLook.path_for(PRECIP_KINDS[head.get_slice(":", 1)])
	return ""


## Which section of its file a key's line lives in.
func _section_of(key: String) -> Callable:
	var head := key.get_slice("/", 0)
	if head == "sky":
		var name := sky_section
		var parent := 'parent="%s"' % sky_parent
		return func(line: String) -> bool:
			return line.begins_with(name + " ") and (line.contains(parent) or (sky_parent == "" and not line.contains("parent=")))
	if head == "env":
		var sec := env_section
		return func(line: String) -> bool: return line == sec
	return func(line: String) -> bool: return line == "[resource]"


## Writes every dirty file. With `redirect` (a user:// folder, for the self
## test) the copies land there and the baseline stays. Returns error strings.
func save(redirect := "") -> PackedStringArray:
	commit()
	var errors := PackedStringArray()
	var cur := capture()
	# path -> [[section matcher, {prop: value}], ...]
	var edits := {}
	var sections := {}   # path + section key -> index in edits[path]
	for k: String in cur:
		if k == "weather" or (saved.has(k) and saved[k] == cur[k]):
			continue
		var path := file_of(k)
		if path == "":
			errors.append("no file for %s" % k)
			continue
		var skey := path + "|" + k.get_slice("/", 0).get_slice(":", 0)
		if not edits.has(path):
			edits[path] = []
		if not sections.has(skey):
			sections[skey] = (edits[path] as Array).size()
			(edits[path] as Array).append([_section_of(k), {}])
		(edits[path][sections[skey]][1] as Dictionary)[k.substr(k.get_slice("/", 0).length() + 1)] = cur[k]
	for path: String in edits:
		var text := FileAccess.get_file_as_string(path)
		if text == "":
			errors.append("can't read %s" % path)
			continue
		for e: Array in edits[path]:
			var out := patch_section(text, e[0], e[1])
			if out == "":
				errors.append("%s: section not found" % path)
				text = ""
				break
			text = out
		if text == "":
			continue
		var target := path if redirect == "" else "%s/%s" % [redirect, path.get_file()]
		var f := FileAccess.open(target, FileAccess.WRITE)
		if f == null:
			errors.append("%s: %s" % [target, error_string(FileAccess.get_open_error())])
			continue
		f.store_string(text)
		f.close()
	if errors.is_empty() and redirect == "":
		saved = cur
	changed.emit()
	return errors


## `text` with these `prop = value` lines set inside the first section whose
## header line `is_section` accepts; every other line as it was. "" if there's
## no such section.
static func patch_section(text: String, is_section: Callable, values: Dictionary) -> String:
	var cr := "\r" if text.contains("\r\n") else ""
	var lines := Array(text.replace("\r\n", "\n").split("\n"))
	var start := -1
	for i in lines.size():
		if (lines[i] as String).begins_with("[") and is_section.call(lines[i]):
			start = i
			break
	if start < 0:
		return ""
	for p: String in values:
		var end := lines.size()
		for i in range(start + 1, lines.size()):
			if (lines[i] as String).begins_with("["):
				end = i
				break
		var last := start
		var at := -1
		for i in range(start + 1, end):
			var l: String = lines[i]
			if l.strip_edges() != "":
				last = i
			if l.begins_with(p + " = "):
				at = i
		var line := "%s = %s" % [p, var_to_str(values[p])]
		if at >= 0:
			lines[at] = line
		else:
			lines.insert(last + 1, line)
	return (cr + "\n").join(PackedStringArray(lines))


static func files(dir_path: String) -> PackedStringArray:
	var out := PackedStringArray()
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	for f in dir.get_files():
		f = f.trim_suffix(".remap")
		if f.ends_with(".tres"):
			out.append(f)
	out.sort()
	return out
