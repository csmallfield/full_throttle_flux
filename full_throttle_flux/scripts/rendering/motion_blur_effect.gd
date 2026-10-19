@tool
extends CompositorEffect
class_name MotionBlurEffect
## Velocity-buffer motion blur (camera + per-object) as a CompositorEffect.
##
## needs_motion_vectors makes Forward+ render its velocity buffer; four compute
## passes then run in HDR, after transparents and before glow/tonemap:
##   1. prep        full res   colour + linear distance, scaled/clamped blur radius
##   2. tile max    1/tile     largest radius per tile
##   3. neighbour   1/tile     largest radius in the 3x3 tiles around
##   4. gather      full res   McGuire-style depth-aware reconstruction
## Put it BEFORE the god rays in the compositor so the rays stay crisp.
##
## Game code drives three statics (no reference to the effect needed):
##   MotionBlurEffect.speed_ratio      0..1 player speed, -1 = undriven (full)
##   MotionBlurEffect.set_user_settings(enabled, intensity)  settings menu
##   MotionBlurEffect.notify_camera_cut()  hard cut / teleport / respawn
## Off (or intensity 0) disables the effect outright, so Forward+ also stops
## rendering the velocity buffer.
##
## Profiling: MotionBlurEffect.profile_gpu = true captures RD timestamps
## ("MB ...") that show in the editor's Visual Profiler; MotionBlurProfiler and
## tools/dev/mb_profile.gd read them in game.

enum Timing {
	## Blur as if every frame lasted 1/reference_fps: same streak length at any
	## frame rate.
	NORMALISED,
	## Real shutter: exposure = shutter_angle/360 of the actual frame time, so
	## blur shrinks as fps rises (and grows on a hitch, up to max_blur_px).
	PHYSICAL,
}
enum DebugView { OFF, VELOCITY, NEIGHBOUR_MAX, DISTANCE }

## Authoring switch. The effect's built-in `enabled` is derived from this and
## the user settings; set this one, not `enabled`.
@export var blur_enabled := true:
	set(v):
		blur_enabled = v
		_sync_enabled()
## Overall strength, multiplies the streak length.
@export_range(0.0, 2.0, 0.01) var intensity := 1.0
## Exposure as a fraction of the frame: 180 = half the frame (film default),
## 360 = the whole frame.
@export_range(0.0, 360.0, 1.0) var shutter_angle := 180.0
@export var timing: Timing = Timing.NORMALISED
@export_range(24.0, 240.0, 1.0) var reference_fps := 60.0
## Longest streak, in pixels at 1080p (scales with the render height).
@export_range(4.0, 128.0, 1.0) var max_blur_px := 40.0
## Tile edge in pixels. Raised automatically to at least the max blur radius
## (half of max_blur_px at this resolution), which the filter requires.
@export_range(8, 64, 1) var tile_size := 20
## Gather taps per pixel (cost scales with this, only where something blurs).
@export_range(4, 32, 1) var samples := 12

@export_group("Speed fade")
## Blur fades in between these speed ratios (MotionBlurEffect.speed_ratio).
@export_range(0.0, 1.0, 0.01) var fade_start := 0.2
@export_range(0.0, 1.0, 0.01) var fade_full := 0.6

@export_group("Camera cuts")
## A camera jump bigger than this (units / degrees) in one frame is treated as
## a cut and that frame is not blurred.
@export var cut_distance := 30.0
@export var cut_angle_deg := 40.0

@export_group("Advanced")
## Reproject the sky (no velocity of its own) so it streaks with camera rotation.
@export var sky_velocity := true
## Depth softness as a fraction of distance (foreground/background separation).
@export_range(0.002, 0.2, 0.001) var depth_softness := 0.02
## With MSAA the resolved velocity/depth are sample averages; silhouette pixels
## then take their closest neighbour's motion instead (only active with MSAA).
@export var msaa_edge_fix := true
## Animate the tap jitter per frame (grain instead of a fixed pattern).
@export var animate_noise := false
## Run in the editor viewport too.
@export var editor_preview := false

@export_group("Debug")
@export var debug_view: DebugView = DebugView.OFF
## Read back per-frame stats into MotionBlurEffect.last_stats (stalls nothing,
## arrives a few frames late). Testing only.
@export var debug_stats := false
## > 0 overrides the measured frame time (offline test harness renders slower
## than real time, but its motion is authored per 1/60 s).
var debug_frame_dt := 0.0

static var speed_ratio := -1.0
static var user_enabled := true
static var user_intensity := 1.0
static var profile_gpu := false
static var last_stats := {}
static var _live: Array[WeakRef] = []
static var _cut_frames := 0

var _rd: RenderingDevice
var _sh := {}
var _pl := {}
var _sampler := RID()
var _stats_buf := RID()
var _stats_pending := false
var _state := {}   # per render-buffers instance: last time, camera, view-projections
const CTX := &"ftf_motion_blur"
const PASSES := ["prep", "tile_max", "neighbor_max", "gather"]
const F_REPROJ := 1
const F_SKY := 2
const F_MSAA_FIX := 4
const F_STATS := 8
const F_ORTHO := 16


func _init() -> void:
	effect_callback_type = EFFECT_CALLBACK_TYPE_POST_TRANSPARENT
	needs_motion_vectors = true
	_live.append(weakref(self))
	_sync_enabled()
	RenderingServer.call_on_render_thread(_init_compute)


## Settings-menu hook. Off or 0 intensity disables every live instance (and with
## it the velocity pass).
static func set_user_settings(on: bool, strength: float = -1.0) -> void:
	user_enabled = on
	if strength >= 0.0:
		user_intensity = clampf(strength, 0.0, 1.0)
	var alive: Array[WeakRef] = []
	for w in _live:
		var e: MotionBlurEffect = w.get_ref()
		if e:
			e._sync_enabled()
			alive.append(w)
	_live = alive


## Call on a hard camera cut, respawn or teleport: the next frame(s) are not
## blurred (their velocity spans the jump). Big jumps are also caught
## automatically via cut_distance / cut_angle_deg.
static func notify_camera_cut(frames: int = 1) -> void:
	_cut_frames = maxi(_cut_frames, frames)


func _sync_enabled() -> void:
	enabled = blur_enabled and user_enabled and user_intensity > 0.0


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and _rd:
		for k in _pl:
			if _pl[k].is_valid():
				_rd.free_rid(_pl[k])
		for k in _sh:
			if _sh[k].is_valid():
				_rd.free_rid(_sh[k])
		for r in [_sampler, _stats_buf]:
			if r.is_valid():
				_rd.free_rid(r)


func _init_compute() -> void:
	_rd = RenderingServer.get_rendering_device()
	if _rd == null:
		return
	for pass_name in PASSES:
		var f: RDShaderFile = load("res://shaders/motion_blur/mb_%s.glsl" % pass_name)
		var spirv := f.get_spirv()
		if spirv.compile_error_compute != "":
			push_error("MotionBlurEffect: %s: %s" % [pass_name, spirv.compile_error_compute])
			return
		_sh[pass_name] = _rd.shader_create_from_spirv(spirv)
		_pl[pass_name] = _rd.compute_pipeline_create(_sh[pass_name])
	var ss := RDSamplerState.new()
	ss.min_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
	ss.mag_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
	ss.repeat_u = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
	ss.repeat_v = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
	_sampler = _rd.sampler_create(ss)
	_stats_buf = _rd.storage_buffer_create(32)


## The speed fade factor for the current speed_ratio.
func speed_fade() -> float:
	if speed_ratio < 0.0:
		return 1.0
	if fade_full <= fade_start:
		return 1.0 if speed_ratio >= fade_start else 0.0
	return smoothstep(fade_start, fade_full, speed_ratio)


func _uniform(type: RenderingDevice.UniformType, binding: int, ids: Array) -> RDUniform:
	var u := RDUniform.new()
	u.uniform_type = type
	u.binding = binding
	for id in ids:
		u.add_id(id)
	return u


func _ensure_texture(buffers: RenderSceneBuffersRD, tex_name: StringName, fmt: RenderingDevice.DataFormat, size: Vector2i) -> void:
	if buffers.has_texture(CTX, tex_name):
		var f := buffers.get_texture_format(CTX, tex_name)
		if f.width == size.x and f.height == size.y:
			return
		buffers.clear_context(CTX)   # resized: drop everything, recreated below
	var usage := RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_STORAGE_BIT
	buffers.create_texture(CTX, tex_name, fmt, usage, RenderingDevice.TEXTURE_SAMPLES_1, size, buffers.get_view_count(), 1, true, false)


func _ts(label: String) -> void:
	if profile_gpu:
		_rd.capture_timestamp(label)


func _render_callback(type: int, render_data: RenderData) -> void:
	if _rd == null or not _pl.has("gather") or type != EFFECT_CALLBACK_TYPE_POST_TRANSPARENT:
		return
	if Engine.is_editor_hint() and not editor_preview:
		return
	var buffers := render_data.get_render_scene_buffers() as RenderSceneBuffersRD
	var scene := render_data.get_render_scene_data()
	if buffers == null or scene == null:
		return
	var size := buffers.get_internal_size()
	if size.x == 0 or size.y == 0:
		return

	# --- per-viewport bookkeeping: frame time, camera, last view-projection ---
	var key := buffers.get_instance_id()
	var st: Dictionary = _state.get(key, {})
	if st.is_empty():
		_state[key] = st
	var now := Time.get_ticks_usec()
	var dt := 1.0 / reference_fps
	if st.has("t"):
		dt = float(now - int(st["t"])) / 1000000.0
	st["t"] = now
	if debug_frame_dt > 0.0:
		dt = debug_frame_dt
	dt = clampf(dt, 0.001, 0.25)

	var cam := scene.get_cam_transform()
	var cut := false
	if st.has("cam"):
		var prev_cam: Transform3D = st["cam"]
		if cam.origin.distance_to(prev_cam.origin) > cut_distance:
			cut = true
		var q0 := prev_cam.basis.get_rotation_quaternion()
		var q1 := cam.basis.get_rotation_quaternion()
		if rad_to_deg(q0.angle_to(q1)) > cut_angle_deg:
			cut = true
	else:
		cut = true   # first frame for this viewport: no valid history yet
	st["cam"] = cam
	if _cut_frames > 0:
		_cut_frames -= 1
		cut = true

	var view_count := buffers.get_view_count()
	var vps: Array[Projection] = []
	var prev_vps: Array = st.get("vp", [])
	for view in range(view_count):
		var eye := Transform3D(Basis(), scene.get_view_eye_offset(view))
		vps.append(scene.get_view_projection(view) * Projection((cam * eye).affine_inverse()))
	st["vp"] = vps

	var fps_factor := 1.0
	if timing == Timing.NORMALISED:
		fps_factor = (1.0 / reference_fps) / dt
	var scale := 0.5 * (shutter_angle / 360.0) * intensity * user_intensity * speed_fade() * fps_factor
	if cut or scale <= 0.0001:
		return

	var res_scale := float(size.y) / 1080.0
	var max_radius := clampf(0.5 * max_blur_px * res_scale, 0.5, 64.0)
	var k := clampi(maxi(tile_size, ceili(max_radius)), 8, 64)
	var tiles := Vector2i((size.x + k - 1) / k, (size.y + k - 1) / k)
	_ensure_texture(buffers, &"color", RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT, size)
	_ensure_texture(buffers, &"vel", RenderingDevice.DATA_FORMAT_R16G16_SFLOAT, size)
	_ensure_texture(buffers, &"tile", RenderingDevice.DATA_FORMAT_R16G16_SFLOAT, tiles)
	_ensure_texture(buffers, &"neigh", RenderingDevice.DATA_FORMAT_R16G16_SFLOAT, tiles)

	var stats_on := debug_stats and not _stats_pending
	var flags := 0
	if sky_velocity:
		flags |= F_SKY
	if msaa_edge_fix and buffers.get_msaa_3d() != RenderingServer.VIEWPORT_MSAA_DISABLED:
		flags |= F_MSAA_FIX
	if stats_on:
		flags |= F_STATS
		_rd.buffer_clear(_stats_buf, 0, 32)
	var noise_offset := float(Engine.get_frames_drawn() % 64) * 7.0 if animate_noise else 0.0

	_rd.draw_command_begin_label("Motion Blur", Color(0.3, 0.7, 1.0))
	_ts("MB begin")
	for view in range(view_count):
		var proj := scene.get_view_projection(view)
		var vflags := flags
		var reproj := Projection.IDENTITY
		if view < prev_vps.size():
			reproj = (prev_vps[view] as Projection) * vps[view].inverse()
			vflags |= F_REPROJ
		if proj[2][3] == 0.0:
			vflags |= F_ORTHO
		var color := buffers.get_color_layer(view)
		var depth := buffers.get_depth_layer(view)
		var velocity := buffers.get_velocity_layer(view)
		var s_color := buffers.get_texture_slice(CTX, &"color", view, 0, 1, 1)
		var s_vel := buffers.get_texture_slice(CTX, &"vel", view, 0, 1, 1)
		var s_tile := buffers.get_texture_slice(CTX, &"tile", view, 0, 1, 1)
		var s_neigh := buffers.get_texture_slice(CTX, &"neigh", view, 0, 1, 1)
		var probe := Vector2(size.x / 2, size.y / 2)

		# 1. prep
		var set_p := UniformSetCacheRD.get_cache(_sh["prep"], 0, [
			_uniform(RenderingDevice.UNIFORM_TYPE_IMAGE, 0, [color]),
			_uniform(RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE, 1, [_sampler, depth]),
			_uniform(RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE, 2, [_sampler, velocity]),
			_uniform(RenderingDevice.UNIFORM_TYPE_IMAGE, 3, [s_color]),
			_uniform(RenderingDevice.UNIFORM_TYPE_IMAGE, 4, [s_vel]),
			_uniform(RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, 5, [_stats_buf]),
		])
		var pc := PackedFloat32Array()
		for c in range(4):
			var col: Vector4 = reproj[c]
			pc.append_array([col.x, col.y, col.z, col.w])
		pc.append_array([size.x, size.y, scale, max_radius,
			proj[2][2], proj[3][2], float(vflags), depth_softness,
			probe.x, probe.y, 0.0, 0.0])
		_dispatch("prep", set_p, pc, (size.x + 7) / 8, (size.y + 7) / 8)
		_ts("MB prep")

		# 2. tile max
		var set_t := UniformSetCacheRD.get_cache(_sh["tile_max"], 0, [
			_uniform(RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE, 0, [_sampler, s_vel]),
			_uniform(RenderingDevice.UNIFORM_TYPE_IMAGE, 1, [s_tile]),
			_uniform(RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, 2, [_stats_buf]),
		])
		_dispatch("tile_max", set_t, PackedFloat32Array([size.x, size.y, float(k), float(vflags)]), tiles.x, tiles.y)
		_ts("MB tile max")

		# 3. neighbour max
		var set_n := UniformSetCacheRD.get_cache(_sh["neighbor_max"], 0, [
			_uniform(RenderingDevice.UNIFORM_TYPE_IMAGE, 0, [s_tile]),
			_uniform(RenderingDevice.UNIFORM_TYPE_IMAGE, 1, [s_neigh]),
		])
		_dispatch("neighbor_max", set_n, PackedFloat32Array([tiles.x, tiles.y, 0.0, 0.0]), (tiles.x + 7) / 8, (tiles.y + 7) / 8)
		_ts("MB neighbour max")

		# 4. gather
		var set_g := UniformSetCacheRD.get_cache(_sh["gather"], 0, [
			_uniform(RenderingDevice.UNIFORM_TYPE_IMAGE, 0, [color]),
			_uniform(RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE, 1, [_sampler, s_color]),
			_uniform(RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE, 2, [_sampler, s_vel]),
			_uniform(RenderingDevice.UNIFORM_TYPE_IMAGE, 3, [s_neigh]),
		])
		_dispatch("gather", set_g, PackedFloat32Array([size.x, size.y, tiles.x, tiles.y,
			float(k), float(samples), depth_softness, float(debug_view),
			max_radius, noise_offset, 0.0, 0.0]), (size.x + 7) / 8, (size.y + 7) / 8)
		_ts("MB gather")
	_rd.draw_command_end_label()

	if stats_on:
		_stats_pending = true
		var info := {"scale": scale, "max_radius": max_radius, "tile": k, "tiles": tiles,
			"fps_factor": fps_factor, "fade": speed_fade(), "dt": dt, "size": size,
			"msaa_fix": (flags & F_MSAA_FIX) != 0}
		_rd.buffer_get_data_async(_stats_buf, _on_stats.bind(info), 0, 32)


func _dispatch(pass_name: String, uniform_set: RID, pc: PackedFloat32Array, gx: int, gy: int) -> void:
	var cl := _rd.compute_list_begin()
	_rd.compute_list_bind_compute_pipeline(cl, _pl[pass_name])
	_rd.compute_list_bind_uniform_set(cl, uniform_set, 0)
	_rd.compute_list_set_push_constant(cl, pc.to_byte_array(), pc.size() * 4)
	_rd.compute_list_dispatch(cl, maxi(gx, 1), maxi(gy, 1), 1)
	_rd.compute_list_end()


func _on_stats(data: PackedByteArray, info: Dictionary) -> void:
	_stats_pending = false
	var s := info.duplicate()
	s["max_radius_px"] = data.decode_float(0)
	s["active_tiles"] = data.decode_u32(4)
	s["probe_velocity_uv"] = Vector2(data.decode_float(8), data.decode_float(12))
	s["probe_distance"] = data.decode_float(16)
	s["probe_radius_px"] = data.decode_float(20)
	s["probe_depth"] = data.decode_float(24)
	s["frame"] = Engine.get_frames_drawn()
	last_stats = s
