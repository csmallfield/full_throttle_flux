@tool
extends Resource
class_name TrackSurfaceVariation
## A track's own deviations from the shared surface style (v38 phase 3).
## The style is the material shaders/track/track_surface_material.tres (its
## shader parameters); a variation overrides a few of them for one track,
## so every track reads as the same world with its own accents. Set it on
## the TrackBuilder; Build writes it into the TrackSurface node.
##
## A colour with alpha 0, or a number below 0, keeps the style's value.
## Keep clear of the boost pads' orange (about 20-40 degrees hue).

@export_group("Lights")
@export var light_blue := Color(0, 0, 0, 0)
@export var light_red := Color(0, 0, 0, 0)
@export var light_white := Color(0, 0, 0, 0)
@export_range(-1.0, 16.0, 0.05) var light_energy: float = -1.0
@export_group("Plates")
@export var plate_color := Color(0, 0, 0, 0)
@export var edge_color := Color(0, 0, 0, 0)
@export_range(-1.0, 0.5, 0.01) var panel_tint_var: float = -1.0
@export_group("Hazard and edges")
@export var hazard_yellow := Color(0, 0, 0, 0)
@export var hazard_black := Color(0, 0, 0, 0)
@export var edge_line_color := Color(0, 0, 0, 0)
@export_group("Grates and vents")
@export var grate_glow := Color(0, 0, 0, 0)
@export_range(-1.0, 4.0, 0.05) var grate_glow_energy: float = -1.0
@export var vent_glow := Color(0, 0, 0, 0)
@export_range(-1.0, 1.0, 0.05) var vent_chance: float = -1.0
@export_group("Wear")
## How used the whole track looks (phase 4): 0 = factory new, 1 = old.
@export_range(-1.0, 1.0, 0.05) var wear_age: float = -1.0
@export var grime_color := Color(0, 0, 0, 0)
@export var scorch_color := Color(0, 0, 0, 0)

## Shader parameter -> exported property, for the overrides above.
const PARAMS := ["light_blue", "light_red", "light_white", "light_energy", "plate_color",
		"edge_color", "panel_tint_var", "hazard_yellow", "hazard_black", "edge_line_color",
		"grate_glow", "grate_glow_energy", "vent_glow", "vent_chance", "wear_age", "grime_color",
		"scorch_color"]


## Writes the overridden values into `mat` (colours as vec3).
func apply(mat: ShaderMaterial) -> int:
	var n := 0
	for p in PARAMS:
		var v: Variant = get(p)
		if v is Color:
			var c: Color = v
			if c.a <= 0.0:
				continue
			mat.set_shader_parameter(p, Vector3(c.r, c.g, c.b))
		elif float(v) < 0.0:
			continue
		else:
			mat.set_shader_parameter(p, v)
		n += 1
	return n
