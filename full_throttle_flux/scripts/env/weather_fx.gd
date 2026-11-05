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
## How it looks (null when nothing falls).
var look: PrecipLook
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
	# Snow reads denser than rain at the same rate: its look thins it.
	var density := shown * (look.density_scale if look else 1.0)
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
	if look:
		process_mat.set_shader_parameter("fall", look.fall(wind))
	var tint := _tint()
	draw_mat.set_shader_parameter("tint", tint)
	far_mat.set_shader_parameter("tint", tint)
	far_mat.set_shader_parameter("opacity", (look.far_opacity if look else 0.15) * shown)
	far.global_position = cp


## Per-kind look, from its PrecipLook (resources/weather/precip).
func _configure(k: int) -> void:
	look = PrecipLook.for_kind(k)
	if look:
		look.configure(process_mat, draw_mat, far_mat)


## After an edit to the current look (Sky Lab): applies it again.
func reconfigure() -> void:
	_configure(kind)


func _tint() -> Color:
	var base := Color(0.72, 0.74, 0.78)
	if env.sky:
		base = env.sky.fog_color
	return look.tint(base, env.dust_color) if look else base
