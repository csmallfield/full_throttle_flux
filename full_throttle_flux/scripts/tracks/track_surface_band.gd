@tool
extends Resource
class_name TrackSurfaceBand
## One band of a track surface cross-section (v38 phase 3): a strip across
## the road with a width in metres, or a flex weight that shares the space
## the fixed bands leave, and the module that draws it. See
## TrackSurfaceProfile.

## Same order as the shader's BT_* constants.
enum Type {
	PLATE,    ## Smooth plate (vents optional).
	CHANNEL,  ## Narrow recess between lanes; lights live here.
	EDGE,     ## Painted edge band: edge line and LED row on its outer side.
	RIBBED,   ## Ribbed plate: longitudinal grooves.
	GRATE,    ## Hex grate, recessed.
}

## Same order as the shader's LIGHT_* constants.
enum Light {
	NONE,
	RED_DOTS,
	BLUE,
}

@export var type: Type = Type.PLATE:
	set(v):
		type = v
		emit_changed()
		notify_property_list_changed()
## Metres across. Ignored where flex > 0 (a flex band is only its share).
@export_range(0.0, 40.0, 0.05, "suffix:m") var width: float = 1.0:
	set(v):
		width = v
		emit_changed()
## > 0: this band takes this share of what the fixed bands leave (several
## flex bands split it by weight). The road's width keys only change these.
@export_range(0.0, 10.0, 0.1) var flex: float = 0.0:
	set(v):
		flex = v
		emit_changed()
## Channels: the light in it.
@export var light: Light = Light.NONE:
	set(v):
		light = v
		emit_changed()
## Plates: vent boxes (placed by a hash, see the vents module).
@export var vents: bool = false:
	set(v):
		vents = v
		emit_changed()


func _validate_property(property: Dictionary) -> void:
	if property.name == "light" and type != Type.CHANNEL:
		property.usage = PROPERTY_USAGE_NO_EDITOR
	elif property.name == "vents" and type != Type.PLATE:
		property.usage = PROPERTY_USAGE_NO_EDITOR
	elif property.name == "width" and flex > 0.0:
		property.usage |= PROPERTY_USAGE_READ_ONLY


## The shader's per-band param: light kind for channels, 1 = vents for plates.
func param() -> int:
	match type:
		Type.CHANNEL:
			return int(light)
		Type.PLATE:
			return 1 if vents else 0
	return 0


## (width, flex, type, param), as the shader reads it.
func packed() -> Vector4:
	return Vector4(0.0 if flex > 0.0 else width, flex, float(type), float(param()))
