extends RefCounted
class_name ShipDust
## What one ship kicks up from the road (v35 Phase 2). Owned by ShipFx.
##
## Five emitters feed the race's FxPools:
##   ground          under the belly, on the probe's ground point
##   wall_l, wall_r  at the wall, when one is within dust_wall_range
##   brake_l, brake_r  under each airbrake, scaled by that brake's input
## Every emitter's rate is
##   surface x speed x (ground / wall / airbrake term) x LOD x quality
## where `surface` is the LOCAL surface from the ShipEnvProbe (so a covered zone
## stays dusty in the rain, and dust_scale zones raise it). Which pool a
## particle goes to follows the surface: dust when dry, spray above
## dust_wet_switch, snow powder above dust_frost_switch.
## Spawns are spread along the path each emitter covered since last frame, so
## a plume at 120 u/s is a ribbon of puffs, not clumps 2 m apart.

const EMITTERS := ["ground", "wall_l", "wall_r", "brake_l", "brake_r"]
const TELEPORT := 30.0

var ship: ShipController
var probe: ShipEnvProbe
var env: EnvironmentState
var pools: FxPools
var profile: ShipFxProfile
var brake_l: Node3D
var brake_r: Node3D
var belly: Node3D

## Current pool (FxPools.Kind) and per-emitter rates in particles/s, for the
## overlay and tests.
var kind: int = FxPools.Kind.DUST
var rates := {}

var _acc := {}
var _prev := {}
var _rng := RandomNumberGenerator.new()


func _init(p_ship: ShipController, p_probe: ShipEnvProbe, p_env: EnvironmentState,
		p_profile: ShipFxProfile, p_belly: Node3D, p_brake_l: Node3D, p_brake_r: Node3D) -> void:
	ship = p_ship
	probe = p_probe
	env = p_env
	profile = p_profile
	belly = p_belly
	brake_l = p_brake_l
	brake_r = p_brake_r
	pools = FxPools.for_env(env)
	_rng.seed = ship.get_instance_id()
	for e in EMITTERS:
		_acc[e] = 0.0
		rates[e] = 0.0


func reset() -> void:
	_prev.clear()
	for e in EMITTERS:
		_acc[e] = 0.0


## `lod_mult` 0..1 from ShipFx (FxSettings LOD and quality).
func update(delta: float, lod_mult: float) -> void:
	if probe == null or not probe.active or pools == null:
		return
	var p := profile
	var amount := surface_amount()
	var speed := ship.get_speed()
	var speed_t := smoothstep(p.dust_speed_start, maxf(p.dust_speed_full, p.dust_speed_start + 1.0), speed)
	var base := amount * speed_t * lod_mult
	var g := _ground_term()

	# Ground, under the belly.
	var ground_origin := Vector3.INF
	if probe.has_ground:
		# v37.1: where the ship is drawn (interpolated), not its physics pose
		# up to a tick ahead.
		var under: Node3D = belly if belly else ship
		ground_origin = _on_ground(under.get_global_transform_interpolated().origin)
	_run("ground", p.dust_ground_rate * base * g, delta, ground_origin, Vector3.ZERO)

	# Walls: closer = more, pushed away from the wall.
	_run("wall_l", p.dust_wall_rate * base * _wall_term(probe.wall_left), delta,
		probe.wall_left_point if probe.wall_left != INF else Vector3.INF, probe.wall_left_normal)
	_run("wall_r", p.dust_wall_rate * base * _wall_term(probe.wall_right), delta,
		probe.wall_right_point if probe.wall_right != INF else Vector3.INF, probe.wall_right_normal)

	# Airbrakes: on the ground under each brake, thrown outward.
	var right := ship.global_transform.basis.x.normalized()
	for side in [["brake_l", ship.airbrake_left, brake_l, -right], ["brake_r", ship.airbrake_right, brake_r, right]]:
		var input: float = side[1]
		var origin := Vector3.INF
		if probe.has_ground and side[2] != null:
			origin = _on_ground((side[2] as Node3D).get_global_transform_interpolated().origin)
		_run(side[0], p.dust_airbrake_rate * base * g * input, delta, origin, side[3])


## Strength of the CURRENT kind's surface, picking the kind first (also used
## by ShipImpacts for wall puffs).
func surface_amount() -> float:
	var p := profile
	if probe.frost > p.dust_frost_switch:
		kind = FxPools.Kind.POWDER
		return probe.frost * p.powder_strength
	if probe.wetness > p.dust_wet_switch:
		kind = FxPools.Kind.SPRAY
		return probe.wetness * p.spray_strength
	kind = FxPools.Kind.DUST
	# Damp dust doesn't fly.
	return probe.dust * (1.0 - probe.wetness / maxf(p.dust_wet_switch, 0.01))


## 1 at hover height, 0 at dust_ground_reach hover heights, a little more when
## the hull dips below hover height.
func _ground_term() -> float:
	if not probe.has_ground:
		return 0.0
	var h := maxf(ship._hover_height, 0.1)
	var d := probe.ground_distance
	var t := 1.0 - smoothstep(h, h * profile.dust_ground_reach, d)
	if d < h:
		t += profile.dust_ground_low_bonus * (1.0 - d / h)
	return t


func _wall_term(dist: float) -> float:
	if dist == INF:
		return 0.0
	var t := 1.0 - clampf(dist / maxf(profile.dust_wall_range, 0.1), 0.0, 1.0)
	return t * t


## Projects `p` onto the road plane under the ship.
func _on_ground(p: Vector3) -> Vector3:
	var n := probe.ground_normal
	# 0.6 m up: puffs are laid IN the air, not half-buried in the road (where
	# the soft-particle blend would erase them).
	return p - n * (p - probe.ground_point).dot(n) + n * 0.6


func _run(emitter: String, rate: float, delta: float, origin: Vector3, push: Vector3) -> void:
	rates[emitter] = rate
	if origin == Vector3.INF or rate <= 0.0:
		_prev.erase(emitter)
		_acc[emitter] = 0.0
		return
	var prev: Vector3 = _prev.get(emitter, origin)
	if prev.distance_squared_to(origin) > TELEPORT * TELEPORT:
		prev = origin
	_prev[emitter] = origin
	var acc: float = _acc[emitter] + rate * delta
	var n := int(acc)
	_acc[emitter] = acc - n
	if n <= 0:
		return
	var p := profile
	var up := probe.ground_normal if probe.has_ground else ship.global_transform.basis.y
	var right := ship.global_transform.basis.x.normalized()
	var inherit := ship.velocity * p.dust_inherit
	for i in n:
		var pos := prev.lerp(origin, _rng.randf()) + right * _rng.randf_range(-1.5, 1.5)
		var v := inherit + up * p.dust_rise * _rng.randf_range(0.5, 1.0) \
			+ right * _rng.randf_range(-p.dust_spread, p.dust_spread)
		if push != Vector3.ZERO:
			v += push.normalized() * p.dust_spread * _rng.randf_range(0.6, 1.4)
		pools.emit(kind, pos, v)
