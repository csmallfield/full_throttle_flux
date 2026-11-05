extends RefCounted
## Surface Lab: everything the lab can edit, as one flat dictionary of
## "key -> value". Undo, the compare key, snapshots and "what's unsaved" are all
## the same operation: capture() the dictionary, restore() an older one, and
## only the keys that differ touch the track.
##
## Keys:
##   road/<param>             base road material (shared by every track)
##   wall/<param>             base wall material (shared by every track)
##   var                      the previewed variation's path ("" = none)
##   var:<file>/<prop>        a TrackSurfaceVariation
##   prof:<name>/mirror       a profile's mirror flag
##   prof:<name>/bands        its bands: [[type, width, flex, light, vents], ...]
##   style:<name>/bay_length  a greeble style
##   style:<name>/threshold_mesh
##   style:<name>/n           how many rules
##   style:<name>/rule:<i>/<prop>
##   mat:<name>/<prop>        a shared greybox material
##
## The lab edits the resources the track already holds, so the game's own code
## draws them; saving writes those resources to their .tres files. Nothing in
## here knows about the UI.

signal changed

const ROAD_MATERIAL := "res://shaders/track/track_surface_material.tres"
const WALL_MATERIAL := "res://shaders/track/track_wall_material.tres"
const VARIATION_DIR := "res://resources/track_surface/variations"
const STYLE_DIR := "res://resources/greeble_presets"
const GREYBOX_DIR := "res://scenes/tracks/utopia/materials"
const GREYBOX := ["light", "mid", "dark", "accent", "glow", "glow_cool", "floor"]
const MAT_PROPS := ["albedo_color", "roughness", "metallic", "emission", "emission_energy_multiplier"]
## Shader parameters that are data, not style.
const PARAM_SKIP := ["csg_", "surf_"]
const DEFAULT_PROFILE := "industrial"
## At or past this many edited rules in one go, a full re-scatter is simpler.
const RULE_LIMIT := 6
## One rule re-scatters at most this often while it's being dragged.
const RULE_REBUILD_EVERY := 0.1
## A whole re-scatter waits for this long with no new edit.
const FULL_REBUILD_QUIET := 0.25

var surface: TrackSurface
var greebles: TrackGreebles
var road_base: ShaderMaterial
var wall_base: ShaderMaterial
## The walls' own copy, so a previewed variation doesn't touch the base.
var wall_live: ShaderMaterial
var road_params: Array[Dictionary] = []
var wall_params: Array[Dictionary] = []
var variations := {}    # file name -> TrackSurfaceVariation
var variation_file := ""
var profiles := {}      # name -> TrackSurfaceProfile
var styles := {}        # name -> UtopiaGreebleStyle
var materials := {}     # name -> StandardMaterial3D

## What's on disk, as last loaded or saved.
var saved := {}
var history: Array[Dictionary] = []
var history_i := -1

var _bands_dirty := false
var _rules_dirty := {}     # "style name:rule index" -> true
var _full_rebuild := false
var _quiet := 0.0
var _edited := false
## Seconds since the last edit in the UI.
var since_edit := 1000.0
var _since_rule_flush := 1000.0


func setup(track: Node) -> void:
	surface = track.find_child("TrackSurface", true, false) as TrackSurface
	greebles = track.find_child("TrackGreebles", true, false) as TrackGreebles
	road_base = load(ROAD_MATERIAL) as ShaderMaterial
	wall_base = load(WALL_MATERIAL) as ShaderMaterial
	wall_live = wall_base.duplicate() as ShaderMaterial
	for n in track.find_children("*", "TrackRoadSegment", true, false):
		var mi := (n as TrackRoadSegment).mesh_instance()
		if mi and mi.mesh and mi.mesh.get_surface_count() > 0 and mi.mesh.surface_get_material(0) == wall_base:
			mi.mesh.surface_set_material(0, wall_live)
	road_params = editable_params(road_base.shader)
	wall_params = editable_params(wall_base.shader)
	for f in _files(VARIATION_DIR):
		variations[f] = load("%s/%s" % [VARIATION_DIR, f])
	for name in TrackSurfaceProfile.list_presets():
		profiles[name] = load(TrackSurfaceProfile.preset_path(name))
	for f in _files(STYLE_DIR):
		if f.begins_with("style_"):
			styles[f.trim_prefix("style_").trim_suffix(".tres")] = load("%s/%s" % [STYLE_DIR, f])
	for m in GREYBOX:
		materials[m] = load("%s/greybox_%s.tres" % [GREYBOX_DIR, m])
	var track_var := surface.variation if surface else null
	if track_var and track_var.resource_path != "":
		variation_file = track_var.resource_path.get_file()
	saved = capture()
	history = [saved.duplicate()]
	history_i = 0


## The shader's style parameters, in declaration order, with their group:
## {name, type, hint, hint_string, group}.
static func editable_params(shader: Shader) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var group := "general"
	for u: Dictionary in shader.get_shader_uniform_list(true):
		if u.usage & PROPERTY_USAGE_GROUP:
			group = String(u.name) if String(u.name) != "" else "general"
			continue
		var n := String(u.name)
		var skip := false
		for pre: String in PARAM_SKIP:
			skip = skip or n.begins_with(pre)
		if skip or u.type not in [TYPE_FLOAT, TYPE_INT, TYPE_BOOL, TYPE_COLOR, TYPE_VECTOR2, TYPE_VECTOR3]:
			continue
		out.append({name = n, type = u.type, hint = u.hint, hint_string = u.hint_string, group = group})
	return out


# =============================================================================
# THE DICTIONARY
# =============================================================================

func capture() -> Dictionary:
	var d := {}
	for p in road_params:
		d["road/" + p.name] = road_base.get_shader_parameter(p.name)
	for p in wall_params:
		d["wall/" + p.name] = wall_base.get_shader_parameter(p.name)
	d["var"] = variation_file
	for f: String in variations:
		for p: String in TrackSurfaceVariation.PARAMS:
			d["var:%s/%s" % [f, p]] = variations[f].get(p)
	for name: String in profiles:
		var pr: TrackSurfaceProfile = profiles[name]
		d["prof:%s/mirror" % name] = pr.mirror
		d["prof:%s/bands" % name] = pack_bands(pr)
	for name: String in styles:
		var st: UtopiaGreebleStyle = styles[name]
		d["style:%s/bay_length" % name] = st.bay_length
		d["style:%s/threshold_mesh" % name] = st.threshold_mesh
		d["style:%s/n" % name] = st.rules.size()
		for i in st.rules.size():
			for prop: String in rule_props():
				d["style:%s/rule:%d/%s" % [name, i, prop]] = st.rules[i].get(prop)
	for name: String in materials:
		for prop: String in MAT_PROPS:
			d["mat:%s/%s" % [name, prop]] = materials[name].get(prop)
	return d


## Brings the track to `target`. Returns how many keys differed.
func restore(target: Dictionary) -> int:
	var cur := capture()
	var n := 0
	# Rule counts first, so rule keys have somewhere to land; the selection
	# before the variation values it decides how to draw.
	for k: String in target:
		if k == "var" or k.ends_with("/n"):
			if not same(cur.get(k), target[k]):
				set_v(k, target[k], false)
				n += 1
	for k: String in target:
		if k == "var" or k.ends_with("/n"):
			continue
		if not cur.has(k) or not same(cur[k], target[k]):
			set_v(k, target[k], false)
			n += 1
	if n > 0:
		_edited = false
		changed.emit()
	return n


## Value equality that tolerates a colour held as Vector3 on one side (shader
## parameters arrive both ways, and != between them is a script error).
static func same(a: Variant, b: Variant) -> bool:
	if typeof(a) == typeof(b):
		return a == b
	if a is Vector3 and b is Color:
		return is_equal_approx((a as Vector3).x, (b as Color).r) and is_equal_approx((a as Vector3).y, (b as Color).g) \
				and is_equal_approx((a as Vector3).z, (b as Color).b)
	if a is Color and b is Vector3:
		return same(b, a)
	return false


func get_v(key: String) -> Variant:
	var slash := key.find("/")
	if key == "var":
		return variation_file
	var head := key.substr(0, slash)
	var rest := key.substr(slash + 1)
	if head == "road":
		return road_base.get_shader_parameter(rest)
	if head == "wall":
		return wall_base.get_shader_parameter(rest)
	var kind := head.get_slice(":", 0)
	var name := head.get_slice(":", 1)
	match kind:
		"var":
			return variations[name].get(rest)
		"prof":
			return profiles[name].mirror if rest == "mirror" else pack_bands(profiles[name])
		"style":
			var st: UtopiaGreebleStyle = styles[name]
			if rest == "n":
				return st.rules.size()
			if rest.begins_with("rule:"):
				return st.rules[int(rest.get_slice("/", 0).trim_prefix("rule:"))].get(rest.get_slice("/", 1))
			return st.get(rest)
		"mat":
			return materials[name].get(rest)
	return null


## Writes one value to its resource and queues whatever it needs redrawn.
## `user` = an edit in the UI (goes into the undo history once things go quiet).
func set_v(key: String, value: Variant, user := true) -> void:
	if key == "var":
		set_variation(String(value))
	else:
		var slash := key.find("/")
		var head := key.substr(0, slash)
		var rest := key.substr(slash + 1)
		if head == "road":
			road_base.set_shader_parameter(rest, value)
			apply_param(rest)
		elif head == "wall":
			wall_base.set_shader_parameter(rest, value)
			apply_param(rest)
		else:
			_set_named(head.get_slice(":", 0), head.get_slice(":", 1), rest, value)
	if user:
		_edited = true
		_quiet = 0.0
		since_edit = 0.0
		changed.emit()


func _set_named(kind: String, name: String, rest: String, value: Variant) -> void:
	match kind:
		"var":
			variations[name].set(rest, value)
			if name == variation_file:
				apply_param(rest)
		"prof":
			var pr: TrackSurfaceProfile = profiles[name]
			if rest == "mirror":
				pr.mirror = value
			else:
				_unpack_bands(pr, value)
			_bands_dirty = true
		"style":
			var st: UtopiaGreebleStyle = styles[name]
			if rest == "n":
				_resize_rules(st, int(value))
				_full_rebuild = true
			elif rest.begins_with("rule:"):
				var i := int(rest.get_slice("/", 0).trim_prefix("rule:"))
				st.rules[i].set(rest.get_slice("/", 1), value)
				_rules_dirty["%s:%d" % [name, i]] = true
			else:
				st.set(rest, value)
				_full_rebuild = true
		"mat":
			materials[name].set(rest, value)


## What a road or wall parameter should draw as right now: the variation's
## override where it has one, else the style.
func apply_param(p: String) -> void:
	var over: Variant = variation_override(p)
	if surface:
		for m in surface.live_materials():
			m.set_shader_parameter(p, over if over != null else road_base.get_shader_parameter(p))
	wall_live.set_shader_parameter(p, over if over != null else wall_base.get_shader_parameter(p))


## The previewed variation's value of `p` as a shader value, or null.
func variation_override(p: String) -> Variant:
	if variation_file == "" or p not in TrackSurfaceVariation.PARAMS:
		return null
	var v: Variant = variations[variation_file].get(p)
	if v is Color:
		return null if (v as Color).a <= 0.0 else Vector3((v as Color).r, (v as Color).g, (v as Color).b)
	return null if float(v) < 0.0 else v


func set_variation(file: String) -> void:
	variation_file = file
	for p: String in TrackSurfaceVariation.PARAMS:
		apply_param(p)


## Makes an empty variation (saved with the rest). Returns its file name.
func new_variation(name: String) -> String:
	var file := "variation_%s.tres" % name.to_snake_case()
	if variations.has(file):
		return ""
	var v := TrackSurfaceVariation.new()
	v.take_over_path("%s/%s" % [VARIATION_DIR, file])
	variations[file] = v
	return file


func pack_bands(pr: TrackSurfaceProfile) -> Array:
	var out := []
	for b in pr.bands:
		if b:
			out.append([int(b.type), b.width, b.flex, int(b.light), b.vents])
	return out


func _unpack_bands(pr: TrackSurfaceProfile, data: Array) -> void:
	var list: Array[TrackSurfaceBand] = []
	for i in data.size():
		var e: Array = data[i]
		var b: TrackSurfaceBand = pr.bands[i] if i < pr.bands.size() and pr.bands[i] else TrackSurfaceBand.new()
		b.type = e[0]
		b.width = e[1]
		b.flex = e[2]
		b.light = e[3]
		b.vents = e[4]
		list.append(b)
	pr.bands = list


static func _resize_rules(st: UtopiaGreebleStyle, n: int) -> void:
	while st.rules.size() > n:
		st.rules.pop_back()
	while st.rules.size() < n:
		st.rules.append(UtopiaGreebleRule.new())


## A rule's stored properties, in inspector order.
static func rule_props() -> PackedStringArray:
	var out := PackedStringArray()
	for p: Dictionary in UtopiaGreebleRule.new().get_property_list():
		if p.usage & PROPERTY_USAGE_STORAGE and p.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			out.append(p.name)
	return out


# =============================================================================
# REDRAW AND HISTORY
# =============================================================================

## Call every frame: does the queued redraws, and files finished edits in the
## undo history once `commit_after` seconds pass with no new edit.
func tick(delta: float, commit_after := 0.4) -> void:
	since_edit += delta
	_since_rule_flush += delta
	# A whole re-scatter takes a visible moment, so it waits for a slider to
	# stop; one rule is quick enough to follow it, a few times a second.
	if _full_rebuild or _rules_dirty.size() >= RULE_LIMIT:
		if since_edit >= FULL_REBUILD_QUIET:
			flush()
		else:
			_flush_bands()
	elif _since_rule_flush >= RULE_REBUILD_EVERY or _rules_dirty.is_empty():
		if not _rules_dirty.is_empty():
			_since_rule_flush = 0.0
		flush()
	else:
		_flush_bands()
	if _edited:
		_quiet += delta
		if _quiet >= commit_after:
			commit()


func _flush_bands() -> void:
	if _bands_dirty:
		_bands_dirty = false
		if surface:
			surface.refresh_bands()


func flush() -> void:
	_flush_bands()
	if greebles == null:
		_full_rebuild = false
		_rules_dirty.clear()
		return
	if _full_rebuild or _rules_dirty.size() >= RULE_LIMIT:
		_full_rebuild = false
		_rules_dirty.clear()
		greebles.rebuild()
	elif not _rules_dirty.is_empty():
		for k: String in _rules_dirty:
			var st: UtopiaGreebleStyle = styles[k.get_slice(":", 0)]
			greebles.rebuild_rule(st, int(k.get_slice(":", 1)))
		_rules_dirty.clear()


## Files the current state in the undo history (no-op if nothing changed).
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
# SAVING
# =============================================================================

## The files with unsaved edits: res:// path -> how many values differ.
func dirty_files() -> Dictionary:
	var out := {}
	var cur := capture()
	for k: String in cur:
		if k == "var":
			continue    # which variation is previewed isn't saved
		if not saved.has(k) or not same(saved[k], cur[k]):
			var f := file_of(k)
			out[f] = int(out.get(f, 0)) + 1
	for k: String in saved:
		if not cur.has(k):
			var f := file_of(k)
			out[f] = int(out.get(f, 0)) + 1
	return out


func file_of(key: String) -> String:
	var head := key.get_slice("/", 0)
	if head == "road":
		return ROAD_MATERIAL
	if head == "wall":
		return WALL_MATERIAL
	var name := head.get_slice(":", 1)
	match head.get_slice(":", 0):
		"var":
			return "%s/%s" % [VARIATION_DIR, name]
		"prof":
			return TrackSurfaceProfile.preset_path(name)
		"style":
			return "%s/style_%s.tres" % [STYLE_DIR, name]
		"mat":
			return "%s/greybox_%s.tres" % [GREYBOX_DIR, name]
	return ""


## Writes every dirty file. With `redirect` (a user:// folder, for the self
## test) copies land there and the baseline stays. Returns error strings.
func save(redirect := "") -> PackedStringArray:
	commit()
	var errors := PackedStringArray()
	var files := dirty_files()
	var cur := capture()
	# Materials: only the edited lines change. The saver would write out every
	# shader default as well, which then stops following the shader.
	var mat_edits := {ROAD_MATERIAL: {}, WALL_MATERIAL: {}}
	for k: String in cur:
		if (k.begins_with("road/") or k.begins_with("wall/")) and not same(saved.get(k), cur[k]):
			mat_edits[file_of(k)][k.get_slice("/", 1)] = cur[k]
	# The base material's slot 0 mirrors the industrial preset (what a track
	# without zones draws): as sync_surface_presets does.
	if files.has(TrackSurfaceProfile.preset_path(DEFAULT_PROFILE)):
		_sync_default_profile()
		mat_edits[ROAD_MATERIAL]["surf_bands"] = road_base.get_shader_parameter("surf_bands")
		mat_edits[ROAD_MATERIAL]["surf_profiles"] = road_base.get_shader_parameter("surf_profiles")
		files[ROAD_MATERIAL] = int(files.get(ROAD_MATERIAL, 0))
	for path: String in files:
		var target := path if redirect == "" else "%s/%s" % [redirect, path.get_file()]
		var err := OK
		if mat_edits.has(path):
			err = _patch_material(path, target, mat_edits[path])
		else:
			var res := _resource_at(path)
			if res == null:
				errors.append("nothing to save for %s" % path)
				continue
			var before := FileAccess.get_file_as_string(path)
			err = ResourceSaver.save(res, target)
			if err == OK and before != "":
				_keep_uids(before, target)
		if err != OK:
			errors.append("%s: %s" % [target, error_string(err)])
	if errors.is_empty() and redirect == "":
		saved = capture()
	changed.emit()
	return errors


## The saver only knows uids inside the editor, so a save from a running game
## drops them from the file: puts back the ones `before` had.
static func _keep_uids(before: String, target: String) -> void:
	var ext := RegEx.create_from_string('\\[ext_resource type="[^"]*" uid="([^"]*)" path="([^"]*)"')
	var uids := {}
	for m in ext.search_all(before):
		uids[m.get_string(2)] = m.get_string(1)
	var head := RegEx.create_from_string('^\\[gd_resource [^\\n]*uid="([^"]*)"')
	var hm := head.search(before)
	var text := FileAccess.get_file_as_string(target)
	if hm:
		var bare := RegEx.create_from_string('^(\\[gd_resource [^\\n]*format=3)\\]')
		text = bare.sub(text, '$1 uid="%s"]' % hm.get_string(1))
	var plain := RegEx.create_from_string('\\[ext_resource type="([^"]*)" path="([^"]*)"')
	var out := ""
	var from := 0
	for m in plain.search_all(text):
		out += text.substr(from, m.get_start() - from)
		var p := m.get_string(2)
		out += m.get_string() if not uids.has(p) else '[ext_resource type="%s" uid="%s" path="%s"' % [m.get_string(1), uids[p], p]
		from = m.get_end()
	out += text.substr(from)
	var f := FileAccess.open(target, FileAccess.WRITE)
	if f:
		f.store_string(out)


## Writes `source` to `target` with these shader parameters set (null = unset),
## every other line as it was.
static func _patch_material(source: String, target: String, edits: Dictionary) -> Error:
	var text := FileAccess.get_file_as_string(source)
	if text == "":
		return FileAccess.get_open_error()
	var lines := Array(text.split("\n"))
	var cr := "\r" if text.contains("\r\n") else ""
	for p: String in edits:
		var prefix := "shader_parameter/%s = " % p
		var line: String = prefix + var_to_str(edits[p]) + cr
		var at := -1
		var last := -1
		for i in lines.size():
			var l: String = lines[i]
			if l.begins_with(prefix):
				at = i
			if l.begins_with("shader_parameter/") or l.begins_with("shader = "):
				last = i
		if edits[p] == null:
			if at >= 0:
				lines.remove_at(at)
		elif at >= 0:
			lines[at] = line
		else:
			lines.insert(last + 1, line)
	var f := FileAccess.open(target, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string("\n".join(PackedStringArray(lines)))
	return OK


func _resource_at(path: String) -> Resource:
	if path == ROAD_MATERIAL:
		return road_base
	if path == WALL_MATERIAL:
		return wall_base
	for table: Dictionary in [variations, profiles, styles, materials]:
		for k: String in table:
			if (table[k] as Resource).resource_path == path:
				return table[k]
	return null


func _sync_default_profile() -> void:
	var pr: TrackSurfaceProfile = profiles.get(DEFAULT_PROFILE)
	if pr == null:
		return
	var bands := PackedVector4Array()
	bands.resize(TrackSurface.MAX_PROFILES * TrackSurface.MAX_BANDS)
	var pk := pr.packed()
	for i in pk.size():
		bands[i] = pk[i]
	var info := PackedVector4Array()
	info.resize(TrackSurface.MAX_PROFILES)
	var sums := pr.sums()
	info[0] = Vector4(pk.size(), sums.x, sums.y, 0.0)
	road_base.set_shader_parameter("surf_bands", bands)
	road_base.set_shader_parameter("surf_profiles", info)


static func _files(dir_path: String) -> PackedStringArray:
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
