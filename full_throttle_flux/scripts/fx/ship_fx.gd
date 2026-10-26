extends Node
class_name ShipFx
## Visual FX of one ship (v35): Phase 1 = thrust trails + wingtip air streams,
## Phase 2 = dust / spray / snow powder (ShipDust, into the race's FxPools).
##
## ShipController attaches one in _ready. Like ShipEnvProbe it stays idle
## until the race has an EnvironmentState (no trainer / sim cost). On bind it
## finds the model's FX sockets (FX_Thrust_*, FX_Wingtip_L/R under ShipMesh),
## or creates them from the ShipFxProfile fallbacks, and builds one
## TrailRibbon per socket. Every frame it drives the ribbons from the ship's
## state and the per-ship LOD from FxSettings:
##   FULL / NEAR   thrust + air streams
##   FAR           thrust only, coarser spline
##   OFF           nothing (ribbons age out)
## Purely visual: reads the ship, never writes to it.

const NODE_NAME := "ShipFx"
const DEFAULT_PROFILE := "res://resources/fx/default_ship_fx.tres"
const MAT_ENERGY := "res://resources/fx/trail_energy.tres"
const MAT_AIR := "res://resources/fx/trail_air.tres"
const BIND_RETRY := 1.0
## Smoothing rate (per second) for intensities, so throttle blips don't strobe.
const RESPONSE := 10.0

var ship: ShipController
var env: EnvironmentState
var probe: ShipEnvProbe
var profile: ShipFxProfile
var active: bool = false
var lod: FxSettings.Lod = FxSettings.Lod.NEAR

var thrust: Array[TrailRibbon] = []
var air_left: TrailRibbon
var air_right: TrailRibbon
var dust: ShipDust
var impacts: ShipImpacts

var _thrust_level: float = 0.0
var _boost_level: float = 0.0
var _air_l_level: float = 0.0
var _air_r_level: float = 0.0
var _bind_timer: float = 0.0
var _layer_timer: float = 0.0

## Profiling: microseconds spent in ShipFx._process (dust emission + driving)
## by ALL ships this frame. Ribbons add TrailRibbon.frame_usec on top.
static var frame_usec: int = 0
## Of which ShipDust.update (all ships).
static var dust_usec: int = 0
static var _frame_usec_frame: int = -1


static func attach(p_ship: ShipController) -> ShipFx:
	var existing := of(p_ship)
	if existing:
		return existing
	var fx := ShipFx.new()
	fx.name = NODE_NAME
	p_ship.add_child(fx)
	return fx


static func of(p_ship: Node) -> ShipFx:
	if p_ship == null:
		return null
	return p_ship.get_node_or_null(NODE_NAME) as ShipFx


func _ready() -> void:
	ship = get_parent() as ShipController
	if ship == null:
		set_process(false)
		return
	ship.ship_respawned.connect(clear)
	_try_bind()


func clear() -> void:
	for r in _all():
		r.clear()
	if dust:
		dust.reset()
	if impacts:
		impacts.reset()


func _process(delta: float) -> void:
	if not active:
		_bind_timer -= delta
		if _bind_timer <= 0.0:
			_try_bind()
		return
	if not is_instance_valid(env):
		_unbind()
		return
	var t0 := Time.get_ticks_usec()
	var fr := Engine.get_process_frames()
	if fr != _frame_usec_frame:
		_frame_usec_frame = fr
		frame_usec = 0
		dust_usec = 0
	var cam := get_viewport().get_camera_3d()
	lod = FxSettings.active().lod_for(ship, cam)
	_drive_thrust(delta)
	_drive_air(delta)
	# v38.1: no dust from a ship the camera can't see (behind it, in a chase
	# view half the pack): puffs live about a second and drift little. The
	# ribbons keep sampling so a trail is there when the ship comes into view.
	if dust and (lod == FxSettings.Lod.FULL or cam == null or _on_screen(cam)):
		var td := Time.get_ticks_usec()
		dust.update(delta, _dust_lod() * float(FxSettings.active().pick(0.4, 0.7, 1.0)))
		dust_usec += Time.get_ticks_usec() - td
	if impacts:
		impacts.sparks_enabled = lod != FxSettings.Lod.OFF
	_layer_timer -= delta
	if _layer_timer <= 0.0:
		_tag_ship_layers()
	frame_usec += Time.get_ticks_usec() - t0


func _try_bind() -> void:
	_bind_timer = BIND_RETRY
	env = EnvironmentState.find(get_tree())
	if env == null:
		return
	probe = ShipEnvProbe.of(ship)
	profile = _find_profile()
	_build()
	active = true


func _unbind() -> void:
	active = false
	env = null
	for r in _all():
		r.queue_free()
	thrust.clear()
	dust = null
	if impacts:
		impacts.disconnect_ship()
	impacts = null
	air_left = null
	air_right = null


# ============================================================================
# DRIVING
# ============================================================================

func _drive_thrust(delta: float) -> void:
	var p := profile
	var throttle := clampf(absf(ship.throttle_input), 0.0, 1.0)
	var target := lerpf(p.thrust_idle, 1.0, throttle)
	_thrust_level = lerpf(_thrust_level, target, ShipController._smooth(RESPONSE, delta))
	var boost_target := 1.0 if ship.get_boost_overspeed() > 0.5 else 0.0
	_boost_level = lerpf(_boost_level, boost_target, ShipController._smooth(4.0, delta))
	var on := lod != FxSettings.Lod.OFF
	var far := lod == FxSettings.Lod.FAR
	var tint := p.thrust_color.lerp(p.boost_color, _boost_level)
	for r in thrust:
		r.emitting = on
		r.intensity = _thrust_level * lerpf(1.0, p.boost_intensity_mult, _boost_level)
		r.length_scale = lerpf(1.0, p.boost_length_mult, _boost_level)
		r.width_scale = lerpf(1.0, p.boost_width_mult, _boost_level)
		r.tint = tint
		r.subdivisions = 1 if far else 2


func _drive_air(delta: float) -> void:
	var p := profile
	var on := lod == FxSettings.Lod.FULL or lod == FxSettings.Lod.NEAR
	var speed_ratio := ship.get_speed_ratio()
	var speed_t := smoothstep(p.air_speed_start, maxf(p.air_speed_full, p.air_speed_start + 0.01), speed_ratio)
	var turn_load := absf(ship.measured_yaw_rate) * ship.get_speed() / maxf(p.air_load_full, 1.0)
	var humid := lerpf(p.air_dry_visibility, 1.0, clampf(env.humidity, 0.0, 1.0))
	# Turning loads the OUTSIDE tip more; the airbrake on a side loads that side.
	# measured_yaw_rate > 0 = turning left, so the right tip is outside.
	var turn := clampf(ship.measured_yaw_rate * 0.5 + 0.5, 0.0, 1.0)
	var load_l := clampf(p.air_base_load + turn_load * lerpf(1.4, 0.6, turn) + ship.airbrake_left * 0.6, 0.0, 1.0)
	var load_r := clampf(p.air_base_load + turn_load * lerpf(0.6, 1.4, turn) + ship.airbrake_right * 0.6, 0.0, 1.0)
	var k := ShipController._smooth(RESPONSE * 0.5, delta)
	_air_l_level = lerpf(_air_l_level, p.air_opacity * speed_t * load_l * humid, k)
	_air_r_level = lerpf(_air_r_level, p.air_opacity * speed_t * load_r * humid, k)
	for pair in [[air_left, _air_l_level], [air_right, _air_r_level]]:
		var r: TrailRibbon = pair[0]
		if r == null:
			continue
		r.emitting = on and float(pair[1]) > 0.005
		r.intensity = 1.0 if r.emitting else 0.0
		r.tint = Color(p.air_color, float(pair[1]))


# ============================================================================
# SETUP
# ============================================================================

func _find_profile() -> ShipFxProfile:
	var root := ship.ship_mesh
	if root:
		for n in [root] + root.get_children():
			if n.has_meta("fx_profile"):
				var pr := n.get_meta("fx_profile") as ShipFxProfile
				if pr:
					return pr
	var d := load(DEFAULT_PROFILE) as ShipFxProfile
	return d if d else ShipFxProfile.new()


func _build() -> void:
	var p := profile
	var energy_mat := load(MAT_ENERGY) as Material
	var air_mat := load(MAT_AIR) as Material
	var sockets := _thrust_sockets()
	for s in sockets:
		var r := _ribbon("Thrust_" + s.name, s, energy_mat)
		r.max_length = p.thrust_max_length
		r.lifetime = p.thrust_lifetime
		r.sample_spacing = p.thrust_spacing
		r.width_head = p.thrust_width_head
		r.width_tail = p.thrust_width_tail
		r.fade_power = 3.0   # bright at the nozzle, gone well before the tail
		thrust.append(r)
	air_left = _air_ribbon("AirL", _socket("FX_Wingtip_L", p.fallback_wingtip_l), air_mat)
	air_right = _air_ribbon("AirR", _socket("FX_Wingtip_R", p.fallback_wingtip_r), air_mat)
	if probe:
		dust = ShipDust.new(ship, probe, env, p,
			_socket("FX_Belly", p.fallback_belly),
			_socket("FX_Airbrake_L", p.fallback_airbrake_l),
			_socket("FX_Airbrake_R", p.fallback_airbrake_r))
		impacts = ShipImpacts.new(ship, probe, env, p, dust)
	_tag_ship_layers()


func _air_ribbon(n: String, s: Node3D, mat: Material) -> TrailRibbon:
	var p := profile
	var r := _ribbon(n, s, mat)
	r.max_length = p.air_max_length
	r.lifetime = p.air_lifetime
	r.sample_spacing = p.air_spacing
	r.width_head = p.air_width_head
	r.width_tail = p.air_width_tail
	r.fade_power = 1.0
	r.head_fade = 2.0
	r.subdivisions = 1   # thin and long: spline detail doesn't show, halves the cost
	return r


func _ribbon(n: String, s: Node3D, mat: Material) -> TrailRibbon:
	var r := TrailRibbon.new()
	r.name = n
	r.socket = s
	r.material_override = mat
	add_child(r)
	return r


func _thrust_sockets() -> Array[Node3D]:
	var out: Array[Node3D] = []
	if ship.ship_mesh:
		for n in ship.ship_mesh.find_children("FX_Thrust*", "Node3D", true, false):
			out.append(n as Node3D)
	out.sort_custom(func(a, b): return String(a.name) < String(b.name))
	if out.is_empty():
		var i := 0
		for off in profile.fallback_thrust:
			out.append(_make_socket("FX_Thrust_%d" % i, off))
			i += 1
	return out


## Named socket under ShipMesh, created from `fallback` if the model has none.
func _socket(socket_name: String, fallback: Vector3) -> Node3D:
	if ship.ship_mesh:
		var found := ship.ship_mesh.find_child(socket_name, true, false) as Node3D
		if found:
			return found
	return _make_socket(socket_name, fallback)


func _make_socket(socket_name: String, offset: Vector3) -> Node3D:
	var m := Marker3D.new()
	m.name = socket_name
	var parent: Node3D = ship.ship_mesh if ship.ship_mesh else ship
	# Offsets are in ship space. default_racer.tscn's own ShipMesh carries the
	# model's 1.808 scale (pool variants keep it on a child), so undo it.
	var sc := parent.scale if parent != ship else Vector3.ONE
	m.position = Vector3(offset.x / sc.x, offset.y / sc.y, offset.z / sc.z)
	parent.add_child(m)
	return m


## Ship meshes live on their own render layer so wall scrape marks (Decals,
## see FxImpacts) never paint the ship that made them. Re-run now and then:
## the visual pool can swap the mesh in mid-race.
func _tag_ship_layers() -> void:
	_layer_timer = 1.0
	_tag_layers(ship)


func _tag_layers(n: Node) -> void:
	for c in n.get_children():
		if c is VisualInstance3D and not c is Decal and not c is Light3D \
				and not c is GPUParticles3D:
			(c as VisualInstance3D).layers = FxImpacts.SHIP_RENDER_LAYER
		_tag_layers(c)


## The ship, or a few metres around it, is in the camera's view.
func _on_screen(cam: Camera3D) -> bool:
	var p := ship.global_position
	if cam.is_position_in_frustum(p):
		return true
	# A ship just off the edge can still throw dust into frame.
	var r := cam.global_transform.basis.x * 6.0
	return cam.is_position_in_frustum(p + r) or cam.is_position_in_frustum(p - r)


## Dust strength per LOD: the camera ship gets it all, distant ships a hint.
func _dust_lod() -> float:
	match lod:
		FxSettings.Lod.FULL:
			return 1.0
		FxSettings.Lod.NEAR:
			return 0.6
		FxSettings.Lod.FAR:
			return 0.2
	return 0.0


func _all() -> Array[TrailRibbon]:
	var out: Array[TrailRibbon] = []
	out.append_array(thrust)
	if air_left:
		out.append(air_left)
	if air_right:
		out.append(air_right)
	return out
