@tool
extends Resource
class_name TrackSurfaceProfile
## A track surface cross-section (v38 phase 3): the bands across the road,
## left to right, each with its module (TrackSurfaceBand). SurfaceZoneKeys
## pick one per stretch of track; presets live in PRESET_DIR.
##
## Fixed bands stack inward from each real edge of the driving surface; flex
## bands share what's left by weight, so a width key only changes the flex
## lanes. A road narrower than the fixed bands squeezes them all.
##
## With `mirror` on, `bands` runs from the left edge to the centre band and
## the right half is the same in reverse (the centre band isn't repeated).
##
## Rules the validator checks (problems()):
##   * at most MAX_BANDS bands after mirroring (the shader's limit)
##   * a channel between two different plate-like bands: a band switch
##     inside a pixel is otherwise a hard, unfiltered edge between patterns
##   * at least one flex band, or width keys squeeze everything

const MAX_BANDS := 16
const PRESET_DIR := "res://resources/track_surface/profiles"

@export var profile_name: String = ""
@export var bands: Array[TrackSurfaceBand] = []:
	set(v):
		bands = v
		emit_changed()
@export var mirror: bool = true:
	set(v):
		mirror = v
		emit_changed()


## Every band left to right, mirror applied.
func resolved() -> Array[TrackSurfaceBand]:
	var out: Array[TrackSurfaceBand] = []
	for b in bands:
		if b:
			out.append(b)
	if mirror:
		for i in range(out.size() - 2, -1, -1):
			out.append(out[i])
	return out


## The band table as the shader reads it, at most MAX_BANDS entries.
func packed() -> PackedVector4Array:
	var out := PackedVector4Array()
	for b in resolved():
		if out.size() >= MAX_BANDS:
			break
		out.append(b.packed())
	return out


## (sum of fixed widths, sum of flex weights).
func sums() -> Vector2:
	var s := Vector2.ZERO
	for v in packed():
		s += Vector2(v.x, v.y)
	return s


func problems() -> PackedStringArray:
	var out := PackedStringArray()
	var all := resolved()
	if all.is_empty():
		out.append("no bands")
		return out
	if all.size() > MAX_BANDS:
		out.append("%d bands after mirroring (max %d): the rest are dropped" % [all.size(), MAX_BANDS])
	var flex := false
	for i in all.size():
		flex = flex or all[i].flex > 0.0
		if i > 0:
			var a := all[i - 1]
			var b := all[i]
			if a.type != TrackSurfaceBand.Type.CHANNEL and b.type != TrackSurfaceBand.Type.CHANNEL \
					and a.type != b.type:
				out.append("bands %d and %d (%s, %s) meet without a channel between them" % [
						i - 1, i, TrackSurfaceBand.Type.keys()[a.type], TrackSurfaceBand.Type.keys()[b.type]])
	if not flex:
		out.append("no flex band: width keys squeeze every band")
	return out


## Preset names in the library (profile_<name>.tres -> "<name>").
static func list_presets() -> PackedStringArray:
	var out := PackedStringArray()
	var dir := DirAccess.open(PRESET_DIR)
	if dir == null:
		return out
	for f in dir.get_files():
		f = f.trim_suffix(".remap")
		if f.begins_with("profile_") and f.ends_with(".tres"):
			out.append(f.trim_prefix("profile_").trim_suffix(".tres"))
	out.sort()
	return out


static func preset_path(name: String) -> String:
	return "%s/profile_%s.tres" % [PRESET_DIR, name]
