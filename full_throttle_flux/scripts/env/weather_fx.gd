extends Node3D
class_name WeatherFx
## Falling weather around the camera (v35 Phase 4): rain, snow, dust-storm
## grit. Child of the EnvironmentState; one per race.
##
##   near  one GPUParticles3D (borrowed from FxPrewarm: its constructor eats
##         the global RNG the AI uses) with a custom process shader: every
##         particle falls forever from a fixed seed and is wrapped into a box
##         around the camera, so the box is full at any speed and streaks
##         lean and stretch with the camera's own motion
##   far   a cylinder around the camera with procedural streaks / flecks /
##         wind sheets for depth
## Both fade out while the camera's ship is in a covered zone (tunnels,
## buildings), the same zones that dry the road. Purely visual.

const PROCESS_SHADER := "res://shaders/env/precip_process.gdshader"
const DRAW_SHADER := "res://shaders/env/precip_draw.gdshader"
const FAR_SHADER := "res://shaders/env/precip_far.gdshader"
const HUGE_AABB := AABB(Vector3(-20000, -2000, -20000), Vector3(40000, 4000, 40000))
## Seconds for the cover cut-out to fade.
const COVER_FADE := 0.25

var env: EnvironmentState
var near: GPUParticles3D
var far: MeshInstance3D
var process_mat: ShaderMaterial
var draw_mat: ShaderMaterial
var far_mat: ShaderMaterial
## What is falling now (WeatherPreset.Kind; CLEAR / FOG = nothing).
var kind: int = WeatherPreset.Kind.CLEAR
## Shown share 0..1 after cover (for tests and the overlay).
var shown: float = 0.0
var covered: float = 0.0

var _cam_prev := Vector3.INF
var _cam_vel := Vector3.ZERO


static func of(p_env: EnvironmentState) -> WeatherFx:
	return p_env.get_node_or_null("WeatherFx") as WeatherFx if p_env else null


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	process_priority = 100   # after the cameras have moved
	process_mat = ShaderMaterial.new()
	process_mat.shader = load(PROCESS_SHADER)
	draw_mat = ShaderMaterial.new()
	draw_mat.shader = load(DRAW_SHADER)
	var quad := QuadMesh.new()
	quad.material = draw_mat
	near = FxPrewarm.take()
	near.name = "Near"
	near.local_coords = false
	near.amount = int(FxSettings.active().pick(5000, 10000, 18000))
	near.lifetime = 600.0
	near.explosiveness = 1.0
	near.fixed_fps = 0
	near.interpolate = false
	near.process_material = process_mat
	near.draw_pass_1 = quad
	near.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	near.visibility_aabb = HUGE_AABB
	near.emitting = false
	add_child(near)
	far_mat = ShaderMaterial.new()
	far_mat.shader = load(FAR_SHADER)
	var cyl := CylinderMesh.new()
	cyl.top_radius = 30.0
	cyl.bottom_radius = 30.0
	cyl.height = 50.0
	cyl.radial_segments = 32
	cyl.rings = 1
	cyl.cap_top = false
	cyl.cap_bottom = false
	cyl.material = far_mat
	far = MeshInstance3D.new()
	far.name = "Far"
	far.mesh = cyl
	far.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	far.custom_aabb = HUGE_AABB
	far.visible = false
	add_child(far)


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and near:
		FxPrewarm.give_back(near)
		near = null


func _process(delta: float) -> void:
	if env == null or near == null:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var cp := cam.global_position
	if _cam_prev == Vector3.INF or cp.distance_to(_cam_prev) > 60.0 or delta <= 0.0:
		_cam_vel = Vector3.ZERO
	else:
		_cam_vel = _cam_vel.lerp((cp - _cam_prev) / delta, ShipController._smooth(20.0, delta))
	_cam_prev = cp

	var w: WeatherPreset = env.weather
	var k: int = w.kind if w else WeatherPreset.Kind.CLEAR
	if k != kind:
		kind = k
		_configure(kind)
	# Cover from the camera's ship (the chase camera exposes `ship`).
	var target_cover := 0.0
	var target_ship := cam.get("ship") as Node3D
	if target_ship is ShipController:
		var probe := ShipEnvProbe.of(target_ship)
		if probe and probe.active:
			target_cover = probe.zone.covered
	covered = move_toward(covered, target_cover, delta / COVER_FADE)
	var falling := kind == WeatherPreset.Kind.RAIN or kind == WeatherPreset.Kind.SNOW \
		or kind == WeatherPreset.Kind.DUST_STORM
	shown = env.precipitation * (1.0 - covered) if falling else 0.0
	# Snow reads denser than rain at the same rate: thin it.
	var density := shown * (0.55 if kind == WeatherPreset.Kind.SNOW else 1.0)
	var on := shown > 0.002
	if near.emitting != on:
		near.emitting = on
	near.visible = on
	far.visible = on
	if not on:
		return
	var wind := Vector3(env.wind_direction.x, 0.0, env.wind_direction.y) * env.wind_speed
	process_mat.set_shader_parameter("cam_pos", cp)
	process_mat.set_shader_parameter("cam_vel", _cam_vel)
	process_mat.set_shader_parameter("ratio", density)
	match kind:
		WeatherPreset.Kind.RAIN:
			process_mat.set_shader_parameter("fall", wind * 0.6 + Vector3(0, -11.0, 0))
		WeatherPreset.Kind.SNOW:
			process_mat.set_shader_parameter("fall", wind * 0.8 + Vector3(0, -1.4, 0))
		WeatherPreset.Kind.DUST_STORM:
			process_mat.set_shader_parameter("fall", wind * 1.1 + Vector3(0, -0.4, 0))
	var tint := _tint()
	draw_mat.set_shader_parameter("tint", tint)
	far_mat.set_shader_parameter("tint", tint)
	far_mat.set_shader_parameter("opacity", float(far.get_meta("opacity", 0.15)) * shown)
	far.global_position = cp


## Per-kind look.
func _configure(k: int) -> void:
	var d := draw_mat
	var p := process_mat
	match k:
		WeatherPreset.Kind.RAIN:
			p.set_shader_parameter("fall_spread", 0.15)
			p.set_shader_parameter("sway", 0.0)
			d.set_shader_parameter("width", 0.012)
			d.set_shader_parameter("min_length", 0.25)
			d.set_shader_parameter("max_length", 3.5)
			d.set_shader_parameter("shutter", 0.025)
			d.set_shader_parameter("roundness", 0.0)
			d.set_shader_parameter("opacity", 0.32)
			d.set_shader_parameter("near_fade", 0.6)
			far_mat.set_shader_parameter("cells", Vector2(1.4, 0.06))
			far_mat.set_shader_parameter("scroll", Vector2(0.0, 11.0))
			far_mat.set_shader_parameter("threshold", 0.62)
			far_mat.set_shader_parameter("sharpness", 0.08)
			far.set_meta("opacity", 0.08)
		WeatherPreset.Kind.SNOW:
			p.set_shader_parameter("fall_spread", 0.35)
			p.set_shader_parameter("sway", 0.6)
			d.set_shader_parameter("width", 0.035)
			d.set_shader_parameter("min_length", 0.035)
			d.set_shader_parameter("max_length", 0.6)
			d.set_shader_parameter("shutter", 0.01)
			d.set_shader_parameter("roundness", 1.0)
			d.set_shader_parameter("opacity", 0.6)
			d.set_shader_parameter("near_fade", 1.5)
			far_mat.set_shader_parameter("cells", Vector2(0.9, 0.5))
			far_mat.set_shader_parameter("scroll", Vector2(0.3, 1.4))
			far_mat.set_shader_parameter("threshold", 0.72)
			far_mat.set_shader_parameter("sharpness", 0.08)
			far.set_meta("opacity", 0.22)
		WeatherPreset.Kind.DUST_STORM:
			p.set_shader_parameter("fall_spread", 0.3)
			p.set_shader_parameter("sway", 0.3)
			d.set_shader_parameter("width", 0.02)
			d.set_shader_parameter("min_length", 0.05)
			d.set_shader_parameter("max_length", 1.2)
			d.set_shader_parameter("shutter", 0.02)
			d.set_shader_parameter("roundness", 0.4)
			d.set_shader_parameter("opacity", 0.45)
			d.set_shader_parameter("near_fade", 1.0)
			far_mat.set_shader_parameter("cells", Vector2(0.05, 0.12))
			far_mat.set_shader_parameter("scroll", Vector2(14.0, 0.0))
			far_mat.set_shader_parameter("threshold", 0.45)
			far_mat.set_shader_parameter("sharpness", 0.4)
			far.set_meta("opacity", 0.4)


func _tint() -> Color:
	var base := Color(0.72, 0.74, 0.78)
	if env.sky:
		base = env.sky.fog_color
	match kind:
		WeatherPreset.Kind.SNOW:
			return base.lerp(Color(0.95, 0.96, 1.0), 0.6)
		WeatherPreset.Kind.DUST_STORM:
			return env.dust_color.lerp(base, 0.3)
	return base.lerp(Color(0.85, 0.88, 0.92), 0.3)
