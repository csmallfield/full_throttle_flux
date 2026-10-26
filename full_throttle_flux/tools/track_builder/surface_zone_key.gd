@tool
extends ProfileKey
class_name SurfaceZoneKey
## Start of a track surface zone (v38 phase 3). Drop it anywhere near the
## BUILT road: from here to the next SurfaceZoneKey the road surface uses this
## key's cross-section profile (a lap wraps: the last key's zone runs on past
## the start line to the first key). Under a BranchFeature the key covers
## that branch; a branch with no key of its own carries on with the main
## track's profile at the fork.
##
## Pick a profile from the library (res://resources/track_surface/profiles),
## or drag any TrackSurfaceProfile .tres in. `blend_in` cross-fades from the
## zone before over that many metres; 0 is a hard seam (filtered, and marked
## with a seam line). A path can hold at most 4 different profiles.
##
## Surface keys never change the drivable track: moving one doesn't make the
## Build out of date. The surface updates live in the editor; Build writes it
## too. `distance` here is metres along the BUILT spline (MainSpline, or the
## branch's BranchSpline), as for GreebleZoneKey.

const CUSTOM := "(other file)"

## Profile from the preset library.
@export var preset: String = "industrial":
	set(v):
		if v == preset and profile != null:
			return
		preset = v
		if v != CUSTOM:
			var path := TrackSurfaceProfile.preset_path(v)
			if ResourceLoader.exists(path):
				profile = load(path) as TrackSurfaceProfile
		_changed()

## The profile this zone uses (set by `preset`, or drag a .tres here).
@export var profile: TrackSurfaceProfile:
	set(v):
		profile = v
		var p := _preset_for(v)
		if p != preset and p != "":
			preset = p
		_changed()

## Metres over which this zone cross-fades in from the zone before (0 = a
## hard seam). Inside a blend the shader draws both profiles.
@export_range(0.0, 200.0, 1.0, "suffix:m") var blend_in: float = 0.0:
	set(v):
		blend_in = v
		_changed()

## Reshuffles this zone's panel offsets, tints and vents.
@export var seed: int = 1:
	set(v):
		seed = v
		_changed()


func _validate_property(property: Dictionary) -> void:
	super(property)
	if property.name == "ease":
		property.usage = PROPERTY_USAGE_NO_EDITOR    # zones blend by blend_in instead
	elif property.name == "preset":
		var names := TrackSurfaceProfile.list_presets()
		if preset == CUSTOM:
			names.append(CUSTOM)
		property.hint = PROPERTY_HINT_ENUM
		property.hint_string = ",".join(names)


static func _preset_for(p: TrackSurfaceProfile) -> String:
	if p == null:
		return ""
	var path := p.resource_path
	if path.get_base_dir() == TrackSurfaceProfile.PRESET_DIR and path.get_file().begins_with("profile_"):
		return path.get_file().trim_prefix("profile_").trim_suffix(".tres")
	return CUSTOM


func label_text() -> String:
	var nm := preset if preset != CUSTOM else (profile.profile_name if profile else "none")
	var t := "SURFACE %s" % nm
	if blend_in > 0.0:
		t += " ⤳%.0f m" % blend_in
	return t


func _changed() -> void:
	if not Engine.is_editor_hint() or not is_inside_tree():
		return
	var b := builder()
	if b and b.has_method("mark_surface_dirty"):
		b.mark_surface_dirty()
