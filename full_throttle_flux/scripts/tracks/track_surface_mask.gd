@tool
extends Resource
class_name TrackSurfaceMask
## A surface mask recipe: one or two tiling textures combined into one value,
## and how much that value moves roughness, metallic and specular. A
## TrackSurfaceVariation points at one (`mask`), so recipes form a library that
## tracks pick from. Each band scales it with its own `mask_amount`.
##
## Two textures at unrelated scales (say 7.3 m and 31 m) go a long way before
## they visibly repeat. Tiling along the path is snapped per path, so there's
## no jump at the start line.
##
## See shaders/track/modules/mask.gdshaderinc.

enum Mode {
	OFF,
	A_ONLY,
	A_TIMES_B,    ## Both layers multiplied.
	B_MASKS_A,    ## B scales how much of A shows.
}

const CHANNELS := [Vector4(1, 0, 0, 0), Vector4(0, 1, 0, 0), Vector4(0, 0, 1, 0), Vector4(0, 0, 0, 1)]
## Pixels read per axis when measuring a texture's average.
const MEAN_GRID := 64

@export var mode: Mode = Mode.A_ONLY
@export_group("Layer A")
@export var a_texture: Texture2D
@export_enum("R", "G", "B", "A") var a_channel: int = 0
## Metres per tile: across, along.
@export var a_tile := Vector2(7.3, 7.3)
## Metres: across, along.
@export var a_offset := Vector2.ZERO
@export_group("Layer B")
@export var b_texture: Texture2D
@export_enum("R", "G", "B", "A") var b_channel: int = 0
@export var b_tile := Vector2(31.0, 31.0)
@export var b_offset := Vector2.ZERO
@export_group("Shape")
@export_range(0.0, 8.0, 0.05) var contrast := 1.0
## Moves everything the mask touches by this much, near and far, on both tiers.
@export_range(-0.5, 0.5, 0.01) var bias := 0.0
@export_group("Response")
## Added to roughness, metallic and specular for a full mask.
@export_range(-2.0, 2.0, 0.01) var roughness := 0.5
@export_range(-2.0, 2.0, 0.01) var metallic := 0.0
@export_range(-2.0, 2.0, 0.01) var specular := 0.0

static var _means := {}


## Writes the recipe into a road material.
func apply(mat: ShaderMaterial) -> void:
	var usable := a_texture != null and (mode <= Mode.A_ONLY or b_texture != null)
	mat.set_shader_parameter("mask_mode", int(mode) if usable else 0)
	mat.set_shader_parameter("mask_a", a_texture)
	mat.set_shader_parameter("mask_b", b_texture)
	mat.set_shader_parameter("mask_a_channel", CHANNELS[a_channel])
	mat.set_shader_parameter("mask_b_channel", CHANNELS[b_channel])
	mat.set_shader_parameter("mask_a_tile", a_tile)
	mat.set_shader_parameter("mask_b_tile", b_tile)
	mat.set_shader_parameter("mask_a_offset", a_offset)
	mat.set_shader_parameter("mask_b_offset", b_offset)
	mat.set_shader_parameter("mask_a_mean", channel_mean(a_texture, a_channel))
	mat.set_shader_parameter("mask_b_mean", channel_mean(b_texture, b_channel))
	mat.set_shader_parameter("mask_contrast", contrast)
	mat.set_shader_parameter("mask_bias", bias)
	mat.set_shader_parameter("mask_rough", roughness)
	mat.set_shader_parameter("mask_metal", metallic)
	mat.set_shader_parameter("mask_spec", specular)


## A material with no mask: as the shader's defaults.
static func clear(mat: ShaderMaterial) -> void:
	mat.set_shader_parameter("mask_mode", 0)


## The average of one channel of `tex`, measured once per texture and channel.
static func channel_mean(tex: Texture2D, channel: int) -> float:
	if tex == null:
		return 0.5
	var key := "%d:%d" % [tex.get_instance_id(), channel]
	if _means.has(key):
		return _means[key]
	var img := tex.get_image()
	var mean := 0.5
	if img and not img.is_empty():
		if img.is_compressed():
			img = img.duplicate()
			img.decompress()
		var sum := 0.0
		for y in MEAN_GRID:
			for x in MEAN_GRID:
				var c := img.get_pixel(x * img.get_width() / MEAN_GRID, y * img.get_height() / MEAN_GRID)
				sum += c[channel]
		mean = sum / (MEAN_GRID * MEAN_GRID)
	_means[key] = mean
	return mean
