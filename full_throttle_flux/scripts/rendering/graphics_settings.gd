extends Node
## Graphics settings (v37, autoload "GraphicsSettings").
##
## Saved in user://graphics.cfg; debug keys (DebugKeys, number row) switch them
## in game for side by side comparison:
##   5         FX quality     Low / Medium / High (FxSettings, saved in
##                            user://fx_settings.tres). Ship LOD, dust and SSR
##                            follow at once; particle counts on the next race.
##   6         motion blur    on / off (not saved)
##   Shift+6   blur debug     off / velocity / neighbour max / distance
##   7         anti-aliasing  MSAA 2x + SMAA (v36) / MSAA 4x + SMAA (default) /
##                            TAA / FSR 2 at native resolution
##   Shift+7   road grid      filtered (v37) / v36 fixed-pixel lines, for A/B
##                            only (not saved)
##   8         shadows        Low = v36 (4096 atlas, soft low) / High = 8192
##                            atlas, soft medium (default) / Ultra = 8192, soft high
##   Shift+8   render scale   the 3D view's height: Native / 1440 / 1080 (default)
##                            / 900 lines. A window taller than that renders 3D
##                            at that height and upscales (FSR 1 under the MSAA
##                            and TAA modes, FSR 2 under the FSR 2 mode); the
##                            HUD stays at window resolution. A 1080p window is
##                            unchanged; a 3440x1440 fullscreen renders 2580x1080,
##                            which is what a GTX 1080 Ti holds 60 fps at.
##   9         track surface  debug view: off / s,t / band ids / panel ids /
##                            filter level / zones / wear (not saved)
##   Shift+9   track surface  quality tier Low / High (default). v38 phase 1:
##                            both look the same; the hook later modules use
##
## Env overrides for tests and the benchmark: FTF_AA=0..3, FTF_SHADOWS=0..2,
## FTF_FX=0..2, FTF_BLUR=0|1, FTF_SURFACE_TIER=0|1, FTF_SCALE=0..3.
##
## Tracks: apply_track() puts the track's ShadowProfile (TrackProfile's own,
## else resources/rendering/shadow_profile_default.tres) on every shadow-casting
## DirectionalLight3D. ModeBase calls it after loading the track.
##
## The benchmark (tools/dev/gfx_bench.gd) sets modes directly with
## set_aa() / set_shadows() and doesn't save.
##
## Physics interpolation (v37.1): on in project.godot, but scoped to the ships.
## The scene root is set to OFF here and ShipController opts back in, so the
## ships (which move only on physics ticks) are drawn smoothly between ticks,
## while everything moved in _process (cameras, weather, greebles, FX) is
## drawn exactly where it is put, as before.

enum AA { MSAA2_SMAA, MSAA4_SMAA, TAA, FSR2_NATIVE }
enum Shadows { LOW, HIGH, ULTRA }
enum SurfaceTier { LOW, HIGH }
enum RenderScale { NATIVE, LINES_1440, LINES_1080, LINES_900 }

const AA_NAMES := ["MSAA 2x + SMAA (v36)", "MSAA 4x + SMAA", "TAA", "FSR 2 native"]
const SHADOW_NAMES := ["Low (v36: 4096, soft low)", "High (8192, soft medium)", "Ultra (8192, soft high)"]
const SCALE_NAMES := ["Native", "1440 lines", "1080 lines", "900 lines"]
## 3D render height per RenderScale (0 = the window's own).
const SCALE_LINES := [0, 1440, 1080, 900]
const FX_NAMES := ["Low", "Medium", "High"]
const BLUR_VIEWS := ["off", "velocity", "neighbour max", "distance"]
const SURFACE_TIER_NAMES := ["Low", "High"]
const SURFACE_VIEWS := ["off", "s / t", "band ids", "panel ids", "filter level", "zones", "wear"]
## Global shader uniforms the v38 track surface reads (project.godot).
const U_SURFACE_TIER := &"track_surface_tier"
const U_SURFACE_DEBUG := &"track_surface_debug"
const CONFIG := "user://graphics.cfg"
const DEFAULT_PROFILE := "res://resources/rendering/shadow_profile_default.tres"
const GRID_MATERIAL := "res://shaders/resources/grid_material.tres"
const GRID_V36 := "res://shaders/grid_shader_v36.gdshader"

var aa: AA = AA.MSAA4_SMAA
var shadows: Shadows = Shadows.HIGH
var surface_tier: SurfaceTier = SurfaceTier.HIGH
var render_scale: RenderScale = RenderScale.LINES_1080
var surface_view := 0
var grid_v36 := false
var _grid_v37: Shader = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().root.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_load()
	if OS.get_environment("FTF_AA") != "":
		aa = clampi(int(OS.get_environment("FTF_AA")), 0, 3) as AA
	if OS.get_environment("FTF_SHADOWS") != "":
		shadows = clampi(int(OS.get_environment("FTF_SHADOWS")), 0, 2) as Shadows
	if OS.get_environment("FTF_FX") != "":
		FxSettings.active().quality = clampi(int(OS.get_environment("FTF_FX")), 0, 2) as FxSettings.Quality
	if OS.get_environment("FTF_SURFACE_TIER") != "":
		surface_tier = clampi(int(OS.get_environment("FTF_SURFACE_TIER")), 0, 1) as SurfaceTier
	if OS.get_environment("FTF_BLUR") != "":
		MotionBlurEffect.set_user_settings(OS.get_environment("FTF_BLUR") != "0")
	if OS.get_environment("FTF_SCALE") != "":
		render_scale = clampi(int(OS.get_environment("FTF_SCALE")), 0, 3) as RenderScale
	apply_all()
	# The 3D scale depends on the window's height: fullscreen toggles, resizes.
	get_tree().root.size_changed.connect(_apply_scale)
	_bind_keys()


func _bind_keys() -> void:
	DebugKeys.bind(KEY_5, "FX quality", _cycle_fx,
		func(): return FX_NAMES[FxSettings.active().quality] + "  (particle counts: next race)")
	DebugKeys.bind(KEY_6, "Motion blur", _toggle_blur,
		func(): return "on" if MotionBlurEffect.user_enabled else "off")
	DebugKeys.bind(KEY_6, "Motion blur debug view", _cycle_blur_view,
		func(): return BLUR_VIEWS[_blur_view()], null, DebugKeys.SHIFT)
	DebugKeys.bind(KEY_7, "Anti-aliasing", _cycle_aa, func(): return AA_NAMES[aa])
	DebugKeys.bind(KEY_7, "Road grid", func(): set_grid_v36(not grid_v36),
		func(): return "v36 (fixed-pixel lines)" if grid_v36 else "filtered (v37)", null, DebugKeys.SHIFT)
	DebugKeys.bind(KEY_8, "Shadows", _cycle_shadows, func(): return SHADOW_NAMES[shadows])
	DebugKeys.bind(KEY_8, "Render scale", _cycle_render_scale, render_scale_label, null, DebugKeys.SHIFT)
	DebugKeys.bind(KEY_9, "Track surface debug view",
		func(): set_surface_view((surface_view + 1) % SURFACE_VIEWS.size()),
		func(): return SURFACE_VIEWS[surface_view])
	DebugKeys.bind(KEY_9, "Track surface quality", _cycle_surface_tier,
		func(): return SURFACE_TIER_NAMES[surface_tier], null, DebugKeys.SHIFT)


func _cycle_aa() -> void:
	set_aa(((aa + 1) % AA.size()) as AA)
	_save()


func _cycle_shadows() -> void:
	set_shadows(((shadows + 1) % Shadows.size()) as Shadows)
	_save()


func _cycle_surface_tier() -> void:
	set_surface_tier(((surface_tier + 1) % SurfaceTier.size()) as SurfaceTier)
	_save()


func _cycle_render_scale() -> void:
	set_render_scale(((render_scale + 1) % RenderScale.size()) as RenderScale)
	_save()


## "1080 lines (2580x1080 of 3440x1440)", or "Native (1920x1080)".
func render_scale_label() -> String:
	var win := get_window().size
	var s := scale_for_height(win.y)
	if s >= 1.0:
		return "%s (%dx%d)" % [SCALE_NAMES[render_scale], win.x, win.y]
	return "%s (%dx%d of %dx%d)" % [SCALE_NAMES[render_scale],
			roundi(win.x * s), roundi(win.y * s), win.x, win.y]


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
	set_surface_tier(surface_tier)
	set_surface_view(surface_view)


## The 3D render height the window gets: 3D renders at min(window height,
## SCALE_LINES[render_scale]) and is upscaled to the window.
func set_render_scale(s: RenderScale) -> void:
	render_scale = s
	_apply_scale()


## The viewport's 3D scale for a window `height` pixels tall under the current
## render_scale: 1.0 at or under the target height, else target / height.
func scale_for_height(height: int) -> float:
	var lines: int = SCALE_LINES[render_scale]
	if lines <= 0 or height <= lines:
		return 1.0
	return clampf(float(lines) / float(height), 0.5, 1.0)


## Sets scaling_3d_mode and scaling_3d_scale for the current AA mode, render
## scale and window height. The FSR 2 mode upscales with FSR 2; the others keep
## their own AA and upscale with FSR 1 (bilinear at scale 1.0).
func _apply_scale() -> void:
	var vp := get_viewport()
	if vp == null:
		return
	var s := scale_for_height(get_window().size.y)
	vp.scaling_3d_scale = s
	if aa == AA.FSR2_NATIVE:
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR2
	elif s < 1.0:
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR
	else:
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR


## v38 track surface quality tier (global track_surface_tier).
func set_surface_tier(tier: SurfaceTier) -> void:
	surface_tier = tier
	RenderingServer.global_shader_parameter_set(U_SURFACE_TIER, int(tier))


## v38 track surface debug view, an index into SURFACE_VIEWS (0 = off).
func set_surface_view(view: int) -> void:
	surface_view = view
	RenderingServer.global_shader_parameter_set(U_SURFACE_DEBUG, view)


func set_aa(mode: AA) -> void:
	aa = mode
	var vp := get_viewport()
	if vp == null:
		return
	# Reset everything the modes touch, then set this one. The scaling mode
	# and scale are _apply_scale()'s, below.
	vp.use_taa = false
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
			# FSR 2 at scale 1.0 is a temporal AA with its own sharpening; under
			# a render scale it is the upscaler too.
			vp.msaa_3d = Viewport.MSAA_DISABLED
			vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	_apply_scale()


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
	surface_tier = clampi(int(cf.get_value("graphics", "surface_tier", surface_tier)), 0, 1) as SurfaceTier
	render_scale = clampi(int(cf.get_value("graphics", "render_scale", render_scale)), 0, 3) as RenderScale


func _save() -> void:
	var cf := ConfigFile.new()
	cf.set_value("graphics", "aa", int(aa))
	cf.set_value("graphics", "shadows", int(shadows))
	cf.set_value("graphics", "surface_tier", int(surface_tier))
	cf.set_value("graphics", "render_scale", int(render_scale))
	cf.save(CONFIG)
