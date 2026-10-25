@tool
extends ProfileKey
class_name GreebleZoneKey
## Start of a greeble zone (v36). Drop it anywhere near the BUILT road: from
## here to the next GreebleZoneKey the track is dressed with this key's style
## (a lap wraps: the last key's zone runs on past the start line to the first
## key). Under a BranchFeature the key dresses that branch; a branch with no
## key of its own carries on with the main track's style at the fork.
##
## Pick a preset from the library (res://resources/greeble_presets), or
## "None" for a bare stretch. Editing a preset's rules changes every zone (on
## every track) that uses it: "Make local copy" gives this zone its own copy,
## saved in the scene, to tweak freely; "Save as preset" adds this zone's
## style to the library.
##
## Greeble keys never change the drivable track: moving one doesn't make the
## Build out of date (the AI lines stay valid). The greebles update live in
## the editor; Build writes them too.
##
## `distance` here is metres along the BUILT spline (MainSpline, or the
## branch's BranchSpline), unlike the bank and width keys' base distance.

const PRESET_DIR := "res://resources/greeble_presets"
const NONE := "None"
const LOCAL := "(local copy)"
const CUSTOM := "(other file)"

## Style from the preset library.
@export var preset: String = NONE:
	set(v):
		if v == preset and style != null:
			return
		preset = v
		if v == NONE:
			style = null
		elif v != LOCAL and v != CUSTOM:
			var path := preset_path(v)
			if ResourceLoader.exists(path):
				style = load(path) as UtopiaGreebleStyle
		_changed()

## The style this zone uses (set by `preset`, or drag any
## UtopiaGreebleStyle .tres here). Expand it to edit its rules.
@export var style: UtopiaGreebleStyle:
	set(v):
		style = v
		var p := _preset_for(v)
		if p != preset:
			preset = p
		_changed()

## Swap left/right rules (side-specific pieces such as turn chevrons belong
## on the outside of the corner).
@export var mirror: bool = false:
	set(v):
		mirror = v
		_changed()

## Multiplies every rule's probability in this zone.
@export_range(0.0, 2.0, 0.05) var density: float = 1.0:
	set(v):
		density = v
		_changed()

## Reshuffles the random parts (probability, jitter, scale) of this zone.
@export var seed: int = 1:
	set(v):
		seed = v
		_changed()

## Layers left out in this zone.
@export_flags("Ground", "Wall face", "Wall top", "Outside", "Overhead") var skip_layers: int = 0:
	set(v):
		skip_layers = v
		_changed()

@export_group("Library")
@export_tool_button("Make local copy", "Duplicate") var _btn_local := make_local_copy
## File name for "Save as preset" (style_<name>.tres in the library).
@export var new_preset_name: String = ""
@export_tool_button("Save as preset", "Save") var _btn_save := save_as_preset


func _validate_property(property: Dictionary) -> void:
	super(property)
	if property.name == "ease":
		property.usage = PROPERTY_USAGE_NO_EDITOR    # zones switch, they don't blend
	elif property.name == "preset":
		var names := PackedStringArray([NONE])
		names.append_array(list_presets())
		if preset == LOCAL or preset == CUSTOM:
			names.append(preset)
		property.hint = PROPERTY_HINT_ENUM
		property.hint_string = ",".join(names)


## Preset names in the library (file style_<name>.tres -> "<name>").
static func list_presets() -> PackedStringArray:
	var out := PackedStringArray()
	var dir := DirAccess.open(PRESET_DIR)
	if dir == null:
		return out
	for f in dir.get_files():
		f = f.trim_suffix(".remap")
		if f.begins_with("style_") and f.ends_with(".tres"):
			out.append(f.trim_prefix("style_").trim_suffix(".tres"))
	out.sort()
	return out


static func preset_path(name: String) -> String:
	return "%s/style_%s.tres" % [PRESET_DIR, name]


static func _preset_for(st: UtopiaGreebleStyle) -> String:
	if st == null:
		return NONE
	var path := st.resource_path
	if path.is_empty() or path.contains("::"):
		return LOCAL
	if path.get_base_dir() == PRESET_DIR and path.get_file().begins_with("style_"):
		return path.get_file().trim_prefix("style_").trim_suffix(".tres")
	return CUSTOM


## This zone gets its own copy of its style (rules included; the meshes stay
## shared), saved inside the scene.
func make_local_copy() -> void:
	if style == null:
		push_warning("%s: no style to copy" % name)
		return
	style = copy_style(style)
	notify_property_list_changed()


## Writes this zone's style to the library as style_<new_preset_name>.tres
## and points the zone at it.
func save_as_preset() -> void:
	if style == null:
		push_warning("%s: no style to save" % name)
		return
	var nm := new_preset_name.strip_edges().to_snake_case()
	if nm.is_empty():
		push_warning("%s: type a name in new_preset_name first" % name)
		return
	var path := preset_path(nm)
	if ResourceLoader.exists(path):
		push_warning("%s: preset '%s' already exists (edit it, or pick another name)" % [name, nm])
		return
	DirAccess.make_dir_recursive_absolute(PRESET_DIR)
	var st := copy_style(style)
	st.style_name = nm
	var err := ResourceSaver.save(st, path)
	if err != OK:
		push_warning("%s: couldn't save %s (%s)" % [name, path, error_string(err)])
		return
	# (EditorInterface by name: this script also loads in exported games.)
	if Engine.is_editor_hint() and Engine.has_singleton("EditorInterface"):
		var ei: Object = Engine.get_singleton("EditorInterface")
		ei.call("get_resource_filesystem").call("update_file", path)
	style = load(path) as UtopiaGreebleStyle
	new_preset_name = ""
	notify_property_list_changed()


## A style with copies of its rules (meshes shared).
static func copy_style(src: UtopiaGreebleStyle) -> UtopiaGreebleStyle:
	var st := UtopiaGreebleStyle.new()
	st.style_name = src.style_name
	st.bay_length = src.bay_length
	st.threshold_mesh = src.threshold_mesh
	var rules: Array[UtopiaGreebleRule] = []
	for r in src.rules:
		rules.append(r.duplicate() as UtopiaGreebleRule if r else null)
	st.rules = rules
	return st


func label_text() -> String:
	if style == null:
		return "GREEBLES none"
	var t := "GREEBLES %s" % (style.style_name if preset == LOCAL or preset == CUSTOM else preset)
	if preset == LOCAL:
		t += " (local)"
	if mirror:
		t += " ⇄"
	if not is_equal_approx(density, 1.0):
		t += " ×%.2f" % density
	return t


func _changed() -> void:
	if not Engine.is_editor_hint() or not is_inside_tree():
		return
	var b := builder()
	if b and b.has_method("mark_greebles_dirty"):
		b.mark_greebles_dirty()
