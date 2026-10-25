extends Node3D
class_name FxPools
## Race-wide particle pools for ship-kicked particles (v35 Phase 2).
##
## One GPUParticles3D per look (dust, spray, snow powder), world space, fed by
## every ship through emit(): the whole grid costs one draw call per look, the
## budget is global (FxParticlePreset.amount_* per quality tier), and ships can
## spread their spawns along the path they covered this frame instead of
## clumping at 120 u/s.
##
## Godot details: emit_particle() only spawns while `emitting` is false; the
## process material overrides per-particle scale and colour (size variety
## comes from the preset, colour from the draw material); and the emitter nodes
## are borrowed from the FxPrewarm autoload, because constructing a
## GPUParticles3D mid-race draws from the global RNG the AI uses.
## Created on demand under the EnvironmentState: FxPools.for_env(env).

enum Kind { DUST, SPRAY, POWDER }

const NODE_NAME := "FxPools"
const PRESETS := [
	"res://resources/fx/particles_dust.tres",
	"res://resources/fx/particles_spray.tres",
	"res://resources/fx/particles_powder.tres",
]
const SHADER := "res://shaders/fx/dust_puff.gdshader"
const FLAGS := GPUParticles3D.EMIT_FLAG_POSITION | GPUParticles3D.EMIT_FLAG_VELOCITY

var env: EnvironmentState
var presets: Array[FxParticlePreset] = []
var emitters: Array[GPUParticles3D] = []
var process_materials: Array[ParticleProcessMaterial] = []
var draw_materials: Array[ShaderMaterial] = []
## Particles requested since the race started / this frame, per Kind.
var emitted_total := PackedInt64Array([0, 0, 0])
var emitted_frame := PackedInt32Array([0, 0, 0])
var _frame: int = -1


static func for_env(p_env: EnvironmentState) -> FxPools:
	if p_env == null:
		return null
	var existing := p_env.get_node_or_null(NODE_NAME) as FxPools
	if existing:
		return existing
	var pools := FxPools.new()
	pools.name = NODE_NAME
	pools.env = p_env
	p_env.add_child(pools)
	return pools


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	var shader := load(SHADER) as Shader
	var quality := FxSettings.active()
	for path in PRESETS:
		var pr := load(path) as FxParticlePreset
		if pr == null:
			pr = FxParticlePreset.new()
		presets.append(pr)
		var pm := _process_material(pr)
		process_materials.append(pm)
		var mat := ShaderMaterial.new()
		mat.shader = shader
		mat.render_priority = 0
		draw_materials.append(mat)
		_apply_look(pr, mat)
		var quad := QuadMesh.new()
		quad.material = mat
		var p := FxPrewarm.take()
		p.name = pr.display_name.replace(" ", "")
		p.amount = int(quality.pick(pr.amount_low, pr.amount_medium, pr.amount_high))
		p.lifetime = pr.lifetime
		p.local_coords = false
		p.emitting = false            # required for emit_particle() to spawn
		p.process_material = pm
		p.draw_pass_1 = quad
		p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		p.visibility_aabb = AABB(Vector3(-20000, -2000, -20000), Vector3(40000, 4000, 40000))
		add_child(p)
		emitters.append(p)


## Spawns one particle of `kind` at `pos` moving at `vel` (world space).
func emit(kind: int, pos: Vector3, vel: Vector3) -> void:
	var f := Engine.get_process_frames()
	if f != _frame:
		_frame = f
		emitted_frame.fill(0)
	emitters[kind].emit_particle(Transform3D(Basis.IDENTITY, pos), vel, Color.WHITE, Color(), FLAGS)
	emitted_total[kind] += 1
	emitted_frame[kind] += 1


## Particles of `kind` requested in the current frame (0 if none yet).
func frame_count(kind: int) -> int:
	return emitted_frame[kind] if _frame == Engine.get_process_frames() else 0


func preset(kind: int) -> FxParticlePreset:
	return presets[kind]


func _notification(what: int) -> void:
	# Hand the emitter nodes back for the next race instead of freeing them.
	if what == NOTIFICATION_PREDELETE:
		for p in emitters:
			FxPrewarm.give_back(p)
		emitters.clear()


func _process(_delta: float) -> void:
	if not is_instance_valid(env):
		return
	# Wind pushes every pool the same way the clouds and (later) rain go.
	var w := env.wind_direction * env.wind_speed
	for i in presets.size():
		var pr := presets[i]
		process_materials[i].gravity = Vector3(w.x * pr.wind_influence, -pr.gravity, w.y * pr.wind_influence)
		if pr.use_track_dust_color:
			draw_materials[i].set_shader_parameter("tint", env.dust_color)


func _apply_look(pr: FxParticlePreset, mat: ShaderMaterial) -> void:
	mat.set_shader_parameter("tint", pr.color)
	mat.set_shader_parameter("opacity", pr.opacity)
	mat.set_shader_parameter("softness", pr.softness)
	mat.set_shader_parameter("erosion", pr.erosion)
	mat.set_shader_parameter("emission_boost", pr.emission_boost)


static func _process_material(pr: FxParticlePreset) -> ParticleProcessMaterial:
	var pm := ParticleProcessMaterial.new()
	pm.gravity = Vector3(0.0, -pr.gravity, 0.0)
	pm.damping_min = pr.damping
	pm.damping_max = pr.damping
	var grow := maxf(pr.grow, 1.0)
	pm.scale_min = pr.scale_min * grow
	pm.scale_max = pr.scale_max * grow
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 1.0 / grow))
	curve.add_point(Vector2(1.0, 1.0))
	var ct := CurveTexture.new()
	ct.curve = curve
	pm.scale_curve = ct
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, maxf(pr.fade_in, 0.01), 0.55, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 0.65), Color(1, 1, 1, 0)])
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	pm.angle_min = -180.0
	pm.angle_max = 180.0
	pm.angular_velocity_min = -pr.spin
	pm.angular_velocity_max = pr.spin
	if pr.turbulence_strength > 0.0:
		pm.turbulence_enabled = true
		pm.turbulence_noise_strength = pr.turbulence_strength
		pm.turbulence_noise_scale = pr.turbulence_scale
		pm.turbulence_influence_min = 0.03
		pm.turbulence_influence_max = 0.12
	return pm
