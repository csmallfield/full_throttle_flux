extends Node
## Graphics settings (v37, autoload "GraphicsSettings").
##
## Saved in user://graphics.cfg; debug keys (DebugKeys) switch them in game for
## side by side comparison:
##   F5        FX quality     Low / Medium / High (FxSettings, saved in
##                            user://fx_settings.tres). Ship LOD, dust and SSR
##                            follow at once; particle counts on the next race.
##   F6        motion blur    on / off (not saved)
##   Shift+F6  blur debug     off / velocity / neighbour max / distance
##   F7        anti-aliasing  MSAA 2x + SMAA (v36) / MSAA 4x + SMAA (default) /
##                            TAA / FSR 2 at native resolution
##   Shift+F7  road grid      filtered (v37) / v36 fixed-pixel lines, for A/B
##                            only (not saved)
##   F8        shadows        Low = v36 (4096 atlas, soft low) / High = 8192
##                            atlas, soft medium (default) / Ultra = 8192, soft high
##
## Env overrides for tests and the benchmark: FTF_AA=0..3, FTF_SHADOWS=0..2,
## FTF_FX=0..2, FTF_BLUR=0|1.
##
## Tracks: apply_track() puts the track's ShadowProfile (TrackProfile's own,
## else resources/rendering/shadow_profile_default.tres) on every shadow-casting
## DirectionalLight3D. ModeBase calls it after loading the track.
##
## The benchmark (tools/dev/gfx_bench.gd) sets modes directly with
## set_aa() / set_shadows() and doesn't save.

enum AA { MSAA2_SMAA, MSAA4_SMAA, TAA, FSR2_NATIVE }
enum Shadows { LOW, HIGH, ULTRA }

const AA_NAMES := ["MSAA 2x + SMAA (v36)", "MSAA 4x + SMAA", "TAA", "FSR 2 native"]
const SHADOW_NAMES := ["Low (v36: 4096, soft low)", "High (8192, soft medium)", "Ultra (8192, soft high)"]
const FX_NAMES := ["Low", "Medium", "High"]
const BLUR_VIEWS := ["off", "velocity", "neighbour max", "distance"]
const CONFIG := "user://graphics.cfg"
const DEFAULT_PROFILE := "res://resources/rendering/shadow_profile_default.tres"
const GRID_MATERIAL := "res://shaders/resources/grid_material.tres"
const GRID_V36 := "res://shaders/grid_shader_v36.gdshader"

var aa: AA = AA.MSAA4_SMAA
var shadows: Shadows = Shadows.HIGH
var grid_v36 := false
var _grid_v37: Shader = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load()
	if OS.get_environment("FTF_AA") != "":
		aa = clampi(int(OS.get_environment("FTF_AA")), 0, 3) as AA
	if OS.get_environment("FTF_SHADOWS") != "":
		shadows = clampi(int(OS.get_environment("FTF_SHADOWS")), 0, 2) as Shadows
	if OS.get_environment("FTF_FX") != "":
		FxSettings.active().quality = clampi(int(OS.get_environment("FTF_FX")), 0, 2) as FxSettings.Quality
	if OS.get_environment("FTF_BLUR") != "":
		MotionBlurEffect.set_user_settings(OS.get_environment("FTF_BLUR") != "0")
	apply_all()
	_bind_keys()


func _bind_keys() -> void:
	DebugKeys.bind(KEY_F5, "FX quality", _cycle_fx,
		func(): return FX_NAMES[FxSettings.active().quality] + "  (particle counts: next race)")
	DebugKeys.bind(KEY_F6, "Motion blur", _toggle_blur,
		func(): return "on" if MotionBlurEffect.user_enabled else "off")
	DebugKeys.bind(KEY_F6, "Motion blur debug view", _cycle_blur_view,
		func(): return BLUR_VIEWS[_blur_view()], null, DebugKeys.SHIFT)
	DebugKeys.bind(KEY_F7, "Anti-aliasing", _cycle_aa, func(): return AA_NAMES[aa])
	DebugKeys.bind(KEY_F7, "Road grid", func(): set_grid_v36(not grid_v36),
		func(): return "v36 (fixed-pixel lines)" if grid_v36 else "filtered (v37)", null, DebugKeys.SHIFT)
	DebugKeys.bind(KEY_F8, "Shadows", _cycle_shadows, func(): return SHADOW_NAMES[shadows])


func _cycle_aa() -> void:
	set_aa(((aa + 1) % AA.size()) as AA)
	_save()


func _cycle_shadows() -> void:
	set_shadows(((shadows + 1) % Shadows.size()) as Shadows)
	_save()


func _cycle_fx() -> void:
	var fx := FxSettings.active()
	fx.quality = ((fx.quality + 1) % FxSettings.Quality.size()) as FxSettings.Quality
	fx.save()


func _toggle_blur() -> void:
	MotionBlurEffect.set_user_settings(not MotionBlurEffect.user_enabled)


func _cycle_blur_view() -> void:
	for e in blur_effects():
		e.debug_view = (e.debug_view + 1) % BLUR_VIEWS.size()


func _blur_view() -> int:
	var effects := blur_effects()
	return int(effects[0].debug_view) if not effects.is_empty() else 0


## The MotionBlurEffects on the current WorldEnvironment's compositor.
func blur_effects() -> Array:
	var out := []
	for n in get_tree().root.find_children("*", "WorldEnvironment", true, false):
		var env := n as WorldEnvironment
		if env.compositor:
			for e in env.compositor.compositor_effects:
				if e is MotionBlurEffect:
					out.append(e)
	return out


func apply_all() -> void:
	set_aa(aa)
	set_shadows(shadows)


func set_aa(mode: AA) -> void:
	aa = mode
	var vp := get_viewport()
	if vp == null:
		return
	# Reset everything the modes touch, then set this one.
	vp.use_taa = false
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	vp.scaling_3d_scale = 1.0
	match mode:
		AA.MSAA2_SMAA:
			vp.msaa_3d = Viewport.MSAA_2X
			vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_SMAA
		AA.MSAA4_SMAA:
			vp.msaa_3d = Viewport.MSAA_4X
			vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_SMAA
		AA.TAA:
			# TAA resolves the edges itself; MSAA and SMAA on top only cost.
			vp.msaa_3d = Viewport.MSAA_DISABLED
			vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
			vp.use_taa = true
		AA.FSR2_NATIVE:
			# FSR 2 at scale 1.0 is a temporal AA with its own sharpening.
			vp.msaa_3d = Viewport.MSAA_DISABLED
			vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
			vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR2
			vp.scaling_3d_scale = 1.0


func set_shadows(q: Shadows) -> void:
	shadows = q
	match q:
		Shadows.LOW:
			RenderingServer.directional_shadow_atlas_set_size(4096, true)
			RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_LOW)
		Shadows.HIGH:
			RenderingServer.directional_shadow_atlas_set_size(8192, true)
			RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM)
		Shadows.ULTRA:
			RenderingServer.directional_shadow_atlas_set_size(8192, true)
			RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_HIGH)


## A/B only: swaps the shared grid material back to the v36 shader (every
## road and wall using it changes at once).
func set_grid_v36(on: bool) -> void:
	grid_v36 = on
	var mat := load(GRID_MATERIAL) as ShaderMaterial
	if mat == null:
		return
	if _grid_v37 == null:
		_grid_v37 = mat.shader
	if on:
		mat.shader = load(GRID_V36) as Shader
		mat.set_shader_parameter("grid_size", 2.0)
		mat.set_shader_parameter("line_width", 0.5)
		mat.set_shader_parameter("major_grid_every", 2.0)
		mat.set_shader_parameter("major_line_width", 1.0)
	else:
		mat.shader = _grid_v37


## Puts the track's shadow profile on its lights. `profile` = the
## TrackProfile's own (may be null: the default).
func apply_track(track_root: Node, profile: ShadowProfile = null) -> int:
	if profile == null and ResourceLoader.exists(DEFAULT_PROFILE):
		profile = load(DEFAULT_PROFILE) as ShadowProfile
	if profile == null or track_root == null:
		return 0
	return profile.apply_tree(track_root)


func _load() -> void:
	var cf := ConfigFile.new()
	if cf.load(CONFIG) != OK:
		return
	aa = clampi(int(cf.get_value("graphics", "aa", aa)), 0, 3) as AA
	shadows = clampi(int(cf.get_value("graphics", "shadows", shadows)), 0, 2) as Shadows


func _save() -> void:
	var cf := ConfigFile.new()
	cf.set_value("graphics", "aa", int(aa))
	cf.set_value("graphics", "shadows", int(shadows))
	cf.save(CONFIG)
