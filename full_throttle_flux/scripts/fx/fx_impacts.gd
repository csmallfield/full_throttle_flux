extends Node3D
class_name FxImpacts
## Race-wide wall-hit FX (v35 Phase 3): sparks, scrape marks, hit flashes.
## Ships feed it through ShipImpacts; created on demand under the
## EnvironmentState with FxImpacts.for_env(env).
##
##   sparks   one world-space GPUParticles3D (borrowed from FxPrewarm, see
##            there for why) fed with emit_particle(): velocity-aligned
##            additive streaks, white-hot to dull red, falling under gravity
##   marks    a ring of Decals: dark scorch with bare-metal scratches
##            (tools/env/bake_scuff.py), glowing hot when fresh and cooling in
##            ~1 s, fading out over the last seconds of their life. Ships are
##            moved to their own render layer so a ship scraping the wall is
##            never painted by its own mark
##   flashes  a few pooled OmniLights for a short orange flash on hard hits

const NODE_NAME := "FxImpacts"
const SPARK_SHADER := "res://shaders/fx/spark.gdshader"
const SCUFF_ALBEDO := "res://assets/fx/scuff_albedo.png"
const SCUFF_EMISSION := "res://assets/fx/scuff_emission.png"
## Render layer for ship meshes (layer 19): decals skip it.
const SHIP_RENDER_LAYER := 1 << 18
const FLAGS := GPUParticles3D.EMIT_FLAG_POSITION | GPUParticles3D.EMIT_FLAG_VELOCITY
const HUGE_AABB := AABB(Vector3(-20000, -2000, -20000), Vector3(40000, 4000, 40000))

const MARKS := 96
const MARK_LIFE := 25.0        # seconds a mark stays
const MARK_FADE := 6.0         # ...the last of which it fades
const MARK_COOL := 1.2         # seconds the fresh-scrape glow takes to cool
const MARK_GLOW := 4.0         # emission energy of a fresh mark at full heat
const FLASHES := 6
const FLASH_TIME := 0.16

var env: EnvironmentState
var sparks: GPUParticles3D
var spark_material: ParticleProcessMaterial
var decals: Array[Decal] = []
var flashes: Array[OmniLight3D] = []
## Counters for tests and the overlay.
var sparks_total: int = 0
var marks_total: int = 0
var flashes_total: int = 0

var _mark_born := PackedFloat64Array()
var _mark_heat := PackedFloat32Array()
var _next_mark: int = 0
var _flash_age := PackedFloat32Array()
var _flash_energy := PackedFloat32Array()
var _next_flash: int = 0
var _clock: float = 0.0
## Own generator: the global one drives AI rolls (see FxPrewarm), so FX must
## never call randf() / _rng.randf_range() directly.
var _rng := RandomNumberGenerator.new()


static func for_env(p_env: EnvironmentState) -> FxImpacts:
	if p_env == null:
		return null
	var existing := p_env.get_node_or_null(NODE_NAME) as FxImpacts
	if existing:
		return existing
	var fx := FxImpacts.new()
	fx.name = NODE_NAME
	fx.env = p_env
	p_env.add_child(fx)
	return fx


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	_rng.seed = 35
	_build_sparks()
	_build_marks()
	_build_flashes()


# ============================================================================
# API
# ============================================================================

## `count` sparks at `pos`: `base_vel` (e.g. a share of the ship's velocity)
## plus a kick off the wall along `normal`, upward lift and random scatter.
func burst(pos: Vector3, normal: Vector3, base_vel: Vector3, count: int, kick: float, scatter: float) -> void:
	if sparks == null or count <= 0:
		return
	var up := Vector3.UP
	for i in count:
		var rnd := Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), _rng.randf_range(-1, 1))
		var v := base_vel + normal * kick * _rng.randf_range(0.3, 1.2) + up * _rng.randf_range(0.5, 1.0) * kick * 0.6 \
			+ rnd * scatter
		sparks.emit_particle(Transform3D(Basis.IDENTITY, pos + rnd * 0.15), v, Color.WHITE, Color(), FLAGS)
	sparks_total += count


## A scrape mark on the wall at `pos`, facing `normal`, stretched along `dir`.
## `heat` 0..1 sets how brightly it glows while fresh.
func mark(pos: Vector3, normal: Vector3, dir: Vector3, mark_length: float, heat: float) -> void:
	var n := normal.normalized()
	var x := (dir - n * dir.dot(n))
	if x.length_squared() < 1e-6:
		x = n.cross(Vector3.UP)
	x = x.normalized()
	var z := x.cross(n).normalized()
	var d := decals[_next_mark]
	d.global_transform = Transform3D(Basis(x, n, z), pos)
	d.size = Vector3(mark_length, 0.6, _rng.randf_range(0.45, 0.75))
	d.modulate = Color(1, 1, 1, 1)
	d.emission_energy = MARK_GLOW * heat
	d.visible = true
	_mark_born[_next_mark] = _clock
	_mark_heat[_next_mark] = heat
	_next_mark = (_next_mark + 1) % MARKS
	marks_total += 1


## Short orange flash at `pos` (hard hits).
func flash(pos: Vector3, energy: float) -> void:
	var l := flashes[_next_flash]
	l.global_position = pos
	l.light_energy = energy
	l.visible = true
	_flash_age[_next_flash] = 0.0
	_flash_energy[_next_flash] = energy
	_next_flash = (_next_flash + 1) % FLASHES
	flashes_total += 1


# ============================================================================
# UPDATE
# ============================================================================

func _process(delta: float) -> void:
	_clock += delta
	for i in MARKS:
		var d := decals[i]
		if not d.visible:
			continue
		var age := _clock - _mark_born[i]
		if age > MARK_LIFE:
			d.visible = false
			continue
		d.emission_energy = MARK_GLOW * _mark_heat[i] * maxf(0.0, 1.0 - age / MARK_COOL)
		d.modulate.a = clampf((MARK_LIFE - age) / MARK_FADE, 0.0, 1.0)
	for i in FLASHES:
		var l := flashes[i]
		if not l.visible:
			continue
		_flash_age[i] += delta
		var t := _flash_age[i] / FLASH_TIME
		if t >= 1.0:
			l.visible = false
		else:
			l.light_energy = _flash_energy[i] * (1.0 - t) * (1.0 - t)


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and sparks:
		FxPrewarm.give_back(sparks)
		sparks = null


# ============================================================================
# BUILD
# ============================================================================

func _build_sparks() -> void:
	var pm := ParticleProcessMaterial.new()
	pm.gravity = Vector3(0, -9.8, 0)
	pm.damping_min = 1.0
	pm.damping_max = 2.5
	pm.lifetime_randomness = 0.6
	pm.particle_flag_align_y = true
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.15, 0.5, 1.0])
	g.colors = PackedColorArray([Color(1.0, 0.95, 0.8, 1), Color(1.0, 0.7, 0.3, 1),
		Color(1.0, 0.35, 0.08, 0.8), Color(0.5, 0.08, 0.02, 0)])
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	spark_material = pm
	var mat := ShaderMaterial.new()
	mat.shader = load(SPARK_SHADER)
	var quad := QuadMesh.new()
	quad.material = mat
	sparks = FxPrewarm.take()
	sparks.name = "Sparks"
	sparks.amount = int(FxSettings.active().pick(800, 1600, 3000))
	sparks.lifetime = 0.7
	sparks.local_coords = false
	sparks.emitting = false
	sparks.fixed_fps = 60
	sparks.process_material = pm
	sparks.draw_pass_1 = quad
	sparks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sparks.visibility_aabb = HUGE_AABB
	add_child(sparks)


func _build_marks() -> void:
	var albedo := load(SCUFF_ALBEDO) as Texture2D
	var emission := load(SCUFF_EMISSION) as Texture2D
	_mark_born.resize(MARKS)
	_mark_heat.resize(MARKS)
	for i in MARKS:
		var d := Decal.new()
		d.name = "Mark%d" % i
		d.texture_albedo = albedo
		d.texture_emission = emission
		d.emission_energy = 0.0
		d.albedo_mix = 1.0
		# Not on ships; and fade where the surface turns away from the wall
		# so a mark low on the wall doesn't smear onto the road.
		d.cull_mask = 0xFFFFF & ~SHIP_RENDER_LAYER
		d.normal_fade = 0.5
		d.upper_fade = 0.2
		d.lower_fade = 0.2
		d.distance_fade_enabled = true
		d.distance_fade_begin = 180.0
		d.distance_fade_length = 60.0
		d.visible = false
		add_child(d)
		decals.append(d)


func _build_flashes() -> void:
	_flash_age.resize(FLASHES)
	_flash_energy.resize(FLASHES)
	for i in FLASHES:
		var l := OmniLight3D.new()
		l.name = "Flash%d" % i
		l.light_color = Color(1.0, 0.6, 0.25)
		l.omni_range = 9.0
		l.omni_attenuation = 1.5
		l.shadow_enabled = false
		l.visible = false
		add_child(l)
		flashes.append(l)
