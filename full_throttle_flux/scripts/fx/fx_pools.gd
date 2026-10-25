extends Node3D
class_name FxPools
## Race-wide particle pools for ship-kicked particles (v35 Phase 2).
##
## Per look (dust, spray, snow powder) two world-space GPUParticles3D:
##   carriers  invisible; ships emit them from script with emit() and the
##             wake velocity; they decelerate hard (carrier_damping) and, while
##             alive, spawn
##   puffs     on the GPU (sub-emitter, puff_rate per second each): small
##             textured puffs from the baked atlas, lit by the sun.
## So the whole grid costs one draw call per look, tens of thousands of puffs
## for a few hundred script calls a second, a global budget per quality tier,
## and ships can still spread carriers along the path they covered this frame.
##
## Godot details found by testing in the renderer: emit_particle() only spawns
## while `emitting` is false; per-particle scale and colour passed to it are
## overridden by the process material (position and velocity work); a
## sub-emitter fed by manually emitted carriers works; and constructing a
## GPUParticles3D draws from the global RNG the AI uses, so every emitter node
## is borrowed from the FxPrewarm autoload.
## Created on demand under the EnvironmentState: FxPools.for_env(env).

enum Kind { DUST, SPRAY, POWDER }

const NODE_NAME := "FxPools"
const PRESETS := [
	"res://resources/fx/particles_dust.tres",
	"res://resources/fx/particles_spray.tres",
	"res://resources/fx/particles_powder.tres",
]
const SHADER := "res://shaders/fx/dust_puff.gdshader"
const ATLAS := "res://assets/fx/dust_puffs.png"
const FLAGS := GPUParticles3D.EMIT_FLAG_POSITION | GPUParticles3D.EMIT_FLAG_VELOCITY
const HUGE_AABB := AABB(Vector3(-20000, -2000, -20000), Vector3(40000, 4000, 40000))

var env: EnvironmentState
var presets: Array[FxParticlePreset] = []
## One carrier emitter and one puff emitter per Kind.
var carriers: Array[GPUParticles3D] = []
var puffs: Array[GPUParticles3D] = []
var puff_materials: Array[ParticleProcessMaterial] = []
var draw_materials: Array[ShaderMaterial] = []
## Carriers requested since the race started / this frame, per Kind.
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
	var atlas := load(ATLAS) as Texture2D
	var quality := FxSettings.active()
	for path in PRESETS:
		var pr := load(path) as FxParticlePreset
		if pr == null:
			pr = FxParticlePreset.new()
		presets.append(pr)
		var tag := pr.display_name.replace(" ", "")

		# Puffs: what you see.
		var pm := _puff_material(pr)
		puff_materials.append(pm)
		var mat := ShaderMaterial.new()
		mat.shader = shader
		mat.set_shader_parameter("puffs", atlas)
		_apply_look(pr, mat)
		draw_materials.append(mat)
		var quad := QuadMesh.new()
		quad.material = mat
		var puff := FxPrewarm.take()
		puff.name = tag + "Puffs"
		puff.amount = int(quality.pick(pr.amount_low, pr.amount_medium, pr.amount_high))
		puff.lifetime = pr.lifetime
		puff.local_coords = false
		puff.emitting = false
		puff.process_material = pm
		puff.draw_pass_1 = quad
		puff.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		puff.visibility_aabb = HUGE_AABB
		add_child(puff)
		puffs.append(puff)

		# Carriers: invisible, emitted by ships, spawning puffs as they go.
		var car := FxPrewarm.take()
		car.name = tag + "Carriers"
		car.amount = int(quality.pick(pr.carrier_amount / 2, pr.carrier_amount * 3 / 4, pr.carrier_amount))
		car.lifetime = pr.carrier_lifetime
		car.local_coords = false
		car.emitting = false            # required for emit_particle() to spawn
		car.process_material = _carrier_material(pr)
		car.draw_pass_1 = null
		car.visibility_aabb = HUGE_AABB
		add_child(car)
		car.sub_emitter = car.get_path_to(puff)
		carriers.append(car)


## Spawns one carrier of `kind` at `pos` moving at `vel` (world space); it
## lays puffs along its path for carrier_lifetime seconds.
func emit(kind: int, pos: Vector3, vel: Vector3) -> void:
	var f := Engine.get_process_frames()
	if f != _frame:
		_frame = f
		emitted_frame.fill(0)
	carriers[kind].emit_particle(Transform3D(Basis.IDENTITY, pos), vel, Color.WHITE, Color(), FLAGS)
	emitted_total[kind] += 1
	emitted_frame[kind] += 1


## Carriers of `kind` requested in the current frame (0 if none yet).
func frame_count(kind: int) -> int:
	return emitted_frame[kind] if _frame == Engine.get_process_frames() else 0


## Puffs a carrier of `kind` lays over its life.
func puffs_per_carrier(kind: int) -> float:
	return presets[kind].puff_rate * presets[kind].carrier_lifetime


func preset(kind: int) -> FxParticlePreset:
	return presets[kind]


func _notification(what: int) -> void:
	# Hand the emitter nodes back for the next race instead of freeing them.
	if what == NOTIFICATION_PREDELETE:
		for p in carriers + puffs:
			p.sub_emitter = NodePath()
			FxPrewarm.give_back(p)
		carriers.clear()
		puffs.clear()


func _process(_delta: float) -> void:
	if not is_instance_valid(env):
		return
	# Wind pushes every pool the same way the clouds and (later) rain go.
	var w := env.wind_direction * env.wind_speed
	for i in presets.size():
		var pr := presets[i]
		puff_materials[i].gravity = Vector3(w.x * pr.wind_influence, -pr.gravity, w.y * pr.wind_influence)
		if pr.use_track_dust_color:
			draw_materials[i].set_shader_parameter("tint", env.dust_color)


func _apply_look(pr: FxParticlePreset, mat: ShaderMaterial) -> void:
	mat.set_shader_parameter("tint", pr.color)
	mat.set_shader_parameter("opacity", pr.opacity)
	mat.set_shader_parameter("erosion", pr.erosion)
	mat.set_shader_parameter("core_darken", pr.core_darken)
	mat.set_shader_parameter("backlight", pr.backlight)
	mat.set_shader_parameter("emission_boost", pr.emission_boost)


static func _carrier_material(pr: FxParticlePreset) -> ParticleProcessMaterial:
	var pm := ParticleProcessMaterial.new()
	pm.gravity = Vector3.ZERO
	pm.damping_min = pr.carrier_damping
	pm.damping_max = pr.carrier_damping
	pm.sub_emitter_mode = ParticleProcessMaterial.SUB_EMITTER_CONSTANT
	pm.sub_emitter_frequency = pr.puff_rate
	# Puffs start with the carrier's (decaying) velocity: early puffs fly with
	# the wake, late ones hang back, and the plume stretches out naturally.
	pm.sub_emitter_keep_velocity = true
	return pm


static func _puff_material(pr: FxParticlePreset) -> ParticleProcessMaterial:
	var pm := ParticleProcessMaterial.new()
	pm.gravity = Vector3(0.0, -pr.gravity, 0.0)
	pm.damping_min = pr.damping
	pm.damping_max = pr.damping
	pm.lifetime_randomness = pr.lifetime_randomness
	pm.spread = 180.0
	pm.initial_velocity_min = pr.burst_min
	pm.initial_velocity_max = pr.burst_max
	var grow := maxf(pr.grow, 1.0)
	pm.scale_min = pr.scale_min * grow
	pm.scale_max = pr.scale_max * grow
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 1.0 / grow))
	curve.add_point(Vector2(0.3, lerpf(1.0 / grow, 1.0, 0.65)))
	curve.add_point(Vector2(1.0, 1.0))
	var ct := CurveTexture.new()
	ct.curve = curve
	pm.scale_curve = ct
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, maxf(pr.fade_in, 0.01), 0.45, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 0.7), Color(1, 1, 1, 0)])
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	# Brightness spread per puff.
	var bg := Gradient.new()
	var b := pr.brightness_min
	bg.offsets = PackedFloat32Array([0.0, 1.0])
	bg.colors = PackedColorArray([Color(b, b, b, 1), Color(1, 1, 1, 1)])
	var bt := GradientTexture1D.new()
	bt.gradient = bg
	pm.color_initial_ramp = bt
	pm.angle_min = -180.0
	pm.angle_max = 180.0
	pm.angular_velocity_min = -pr.spin
	pm.angular_velocity_max = pr.spin
	# A stable random per puff in CUSTOM.z: picks its atlas tile.
	pm.anim_offset_min = 0.0
	pm.anim_offset_max = 1.0
	pm.anim_speed_min = 0.0
	pm.anim_speed_max = 0.0
	if pr.turbulence_strength > 0.0:
		pm.turbulence_enabled = true
		pm.turbulence_noise_strength = pr.turbulence_strength
		pm.turbulence_noise_scale = pr.turbulence_scale
		pm.turbulence_influence_min = 0.05
		pm.turbulence_influence_max = 0.2
	return pm
