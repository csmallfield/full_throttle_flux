@tool
extends CompositorEffect
class_name UtopiaGodRays
## Screen-space god rays (crepuscular rays) as a CompositorEffect.
## Pass 1 builds a half-res mask of bright sky around the sun (clouds and
## buildings occlude simply by not being bright sky), pass 2 radially blurs it
## toward the sun and adds it to the HDR buffer before tonemapping.
## Cost: 1 half-res + 1 full-res compute pass, `samples` taps per pixel.
## sun_direction / tint / intensity are driven by UtopiaSkyController.

@export_range(0.0, 4.0) var intensity := 0.45
@export var tint := Color(1.0, 0.85, 0.65)
## Sky luminance (HDR) above which a pixel emits rays.
@export_range(0.0, 8.0) var threshold := 0.6
@export_range(0.8, 1.0) var decay := 0.965
## How far toward the sun each pixel gathers, as a fraction of the distance.
@export_range(0.1, 1.0) var ray_length := 0.65
@export_range(8, 128) var samples := 64
## Emission falloff radius around the sun, in screen heights.
@export_range(0.05, 2.0) var sun_radius := 0.7
@export var weight := 2.2
## Only pixels whose view ray is at least this far above the world horizon
## (sine of the elevation angle) may emit. Guarantees track lights never cast
## rays, independent of the depth buffer.
@export_range(-0.2, 0.3) var horizon_cutoff := 0.0
## Show the emission mask instead of the scene (to see what is casting rays).
@export var debug_mask := false
var debug_depth := false
var sun_direction := Vector3(-0.5, 0.39, 0.7)

var _rd: RenderingDevice
var _sh_mask := RID()
var _sh_blur := RID()
var _pl_mask := RID()
var _pl_blur := RID()
var _sampler := RID()
const CTX := &"utopia_godrays"

func _init() -> void:
	effect_callback_type = EFFECT_CALLBACK_TYPE_POST_TRANSPARENT
	# Only SKY pixels may emit. Sky = reverse-Z depth 0. With MSAA (this
	# project uses 2x) Forward+ resolves depth into an R32F texture right before
	# post-transparent effects; the mask reads it with texelFetch (R32F linear
	# filtering is optional in Vulkan). A second, depth-free gate (horizon_cutoff)
	# guarantees track lights below the horizon can never emit even if a driver
	# hands us an empty depth buffer.
	RenderingServer.call_on_render_thread(_init_compute)

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and _rd:
		for r in [_pl_mask, _pl_blur, _sh_mask, _sh_blur, _sampler]:
			if r.is_valid():
				_rd.free_rid(r)

func _init_compute() -> void:
	_rd = RenderingServer.get_rendering_device()
	if _rd == null:
		return
	var fm: RDShaderFile = load("res://tools/utopia/godrays_mask.glsl")
	var fb: RDShaderFile = load("res://tools/utopia/godrays_blur.glsl")
	_sh_mask = _rd.shader_create_from_spirv(fm.get_spirv())
	_sh_blur = _rd.shader_create_from_spirv(fb.get_spirv())
	_pl_mask = _rd.compute_pipeline_create(_sh_mask)
	_pl_blur = _rd.compute_pipeline_create(_sh_blur)
	var ss := RDSamplerState.new()
	ss.min_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	ss.mag_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	ss.repeat_u = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
	ss.repeat_v = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
	_sampler = _rd.sampler_create(ss)

func _render_callback(type: int, render_data: RenderData) -> void:
	if _rd == null or not _pl_blur.is_valid() or type != EFFECT_CALLBACK_TYPE_POST_TRANSPARENT or intensity <= 0.0:
		return
	var buffers := render_data.get_render_scene_buffers() as RenderSceneBuffersRD
	var scene := render_data.get_render_scene_data()
	if buffers == null or scene == null:
		return
	var size := buffers.get_internal_size()
	if size.x == 0 or size.y == 0:
		return
	var msize := Vector2i(maxi(size.x / 2, 1), maxi(size.y / 2, 1))
	if buffers.has_texture(CTX, &"mask"):
		var fmt := buffers.get_texture_format(CTX, &"mask")
		if fmt.width != msize.x or fmt.height != msize.y:
			buffers.clear_context(CTX)
	if not buffers.has_texture(CTX, &"mask"):
		var usage := RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_STORAGE_BIT
		buffers.create_texture(CTX, &"mask", RenderingDevice.DATA_FORMAT_R16_SFLOAT, usage, RenderingDevice.TEXTURE_SAMPLES_1, msize, buffers.get_view_count(), 1, true, false)
	var cam := scene.get_cam_transform()
	var sun_view := cam.basis.inverse() * sun_direction.normalized()
	for view in range(buffers.get_view_count()):
		var proj := scene.get_view_projection(view)
		var clip := proj * Vector4(sun_view.x, sun_view.y, sun_view.z, 0.0)
		if clip.w <= 0.001:
			continue  # sun behind the camera
		var ndc := Vector2(clip.x / clip.w, clip.y / clip.w)
		var sun_uv := Vector2(ndc.x * 0.5 + 0.5, 0.5 + ndc.y * 0.5)  # RD projection is already Y-flipped for Vulkan
		# fade out as the sun leaves the frame
		var off := maxf(maxf(-sun_uv.x, sun_uv.x - 1.0), maxf(-sun_uv.y, sun_uv.y - 1.0))
		var facing := 1.0 - smoothstep(0.0, 0.6, off)
		if facing <= 0.0:
			continue
		var color := buffers.get_color_layer(view)
		var depth := buffers.get_depth_layer(view)
		var mask := buffers.get_texture_slice(CTX, &"mask", view, 0, 1, 1)
		var aspect := float(size.x) / float(size.y)
		# pass 1: mask
		var u0 := RDUniform.new()
		u0.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
		u0.binding = 0
		u0.add_id(color)
		var u1 := RDUniform.new()
		u1.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
		u1.binding = 1
		u1.add_id(_sampler)
		u1.add_id(depth)
		var u2 := RDUniform.new()
		u2.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
		u2.binding = 2
		u2.add_id(mask)
		var set_m := UniformSetCacheRD.get_cache(_sh_mask, 0, [u0, u1, u2])
		var up_view := cam.basis.inverse() * Vector3.UP
		var pc_m := PackedFloat32Array([sun_uv.x, sun_uv.y, size.x, size.y, msize.x, msize.y,
			threshold, sun_radius, aspect, facing, 1.0 if debug_depth else 0.0, horizon_cutoff,
			up_view.x, up_view.y, up_view.z, 0.0,
			proj[0][0], proj[1][1], 0.0, 0.0])
		var cl := _rd.compute_list_begin()
		_rd.compute_list_bind_compute_pipeline(cl, _pl_mask)
		_rd.compute_list_bind_uniform_set(cl, set_m, 0)
		_rd.compute_list_set_push_constant(cl, pc_m.to_byte_array(), pc_m.size() * 4)
		_rd.compute_list_dispatch(cl, (msize.x + 7) / 8, (msize.y + 7) / 8, 1)
		_rd.compute_list_end()
		# pass 2: radial blur, additive into colour
		var b0 := RDUniform.new()
		b0.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
		b0.binding = 0
		b0.add_id(color)
		var b1 := RDUniform.new()
		b1.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
		b1.binding = 1
		b1.add_id(_sampler)
		b1.add_id(mask)
		var set_b := UniformSetCacheRD.get_cache(_sh_blur, 0, [b0, b1])
		var pc_b := PackedFloat32Array([sun_uv.x, sun_uv.y, size.x, size.y,
			tint.r, tint.g, tint.b, intensity, decay, ray_length, float(samples), -1.0 if debug_mask else weight])
		cl = _rd.compute_list_begin()
		_rd.compute_list_bind_compute_pipeline(cl, _pl_blur)
		_rd.compute_list_bind_uniform_set(cl, set_b, 0)
		_rd.compute_list_set_push_constant(cl, pc_b.to_byte_array(), pc_b.size() * 4)
		_rd.compute_list_dispatch(cl, (size.x + 7) / 8, (size.y + 7) / 8, 1)
		_rd.compute_list_end()
