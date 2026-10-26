extends RefCounted
class_name ShipImpacts
## One ship's wall-hit FX (v35 Phase 3). Owned by ShipFx; listens to
## ShipController.wall_hit / wall_scrape and feeds FxImpacts (sparks, marks,
## flashes) and FxPools (dust, spray or powder off the wall).
##
##   hit      a burst of sparks scaled by the closing speed, a flash on hard
##            hits, a puff of whatever the surface throws (dust, spray,
##            powder), and a scrape mark
##   scrape   a spark stream (rate x speed) at the moving contact point, the
##            sparks carrying on with most of the ship's speed so they trail
##            behind it, and wall dust
## Marks: contact that keeps coming back (a scrape, or the rapid glancing
## hits a ship riding a wall really produces) is drawn as one unbroken line:
## each new mark spans from the previous one to the new contact point. Marks
## are laid every `spacing` metres (grows with speed) so the decal ring lasts.
## Wet surfaces quench: fewer sparks. Purely visual.

var ship: ShipController
var probe: ShipEnvProbe
var env: EnvironmentState
var profile: ShipFxProfile
var dust: ShipDust
var impacts: FxImpacts
var pools: FxPools
## Set by ShipFx each frame: false at FxSettings LOD OFF (marks still land).
var sparks_enabled: bool = true

var _last_mark := Vector3.INF
var _last_contact_tick: int = -100000
var _spark_acc: float = 0.0
var _dust_acc: float = 0.0
var _rng := RandomNumberGenerator.new()


func _init(p_ship: ShipController, p_probe: ShipEnvProbe, p_env: EnvironmentState,
		p_profile: ShipFxProfile, p_dust: ShipDust) -> void:
	ship = p_ship
	probe = p_probe
	env = p_env
	profile = p_profile
	dust = p_dust
	impacts = FxImpacts.for_env(env)
	pools = FxPools.for_env(env)
	_rng.seed = ship.get_instance_id() + 7
	ship.wall_hit.connect(_on_hit)
	ship.wall_scrape.connect(_on_scrape)


func disconnect_ship() -> void:
	if is_instance_valid(ship):
		if ship.wall_hit.is_connected(_on_hit):
			ship.wall_hit.disconnect(_on_hit)
		if ship.wall_scrape.is_connected(_on_scrape):
			ship.wall_scrape.disconnect(_on_scrape)


func reset() -> void:
	_last_mark = Vector3.INF
	_last_contact_tick = -100000
	_spark_acc = 0.0
	_dust_acc = 0.0


func _on_hit(point: Vector3, normal: Vector3, speed: float, closing: float) -> void:
	if impacts == null:
		return
	var p := profile
	var heat := clampf(closing / maxf(p.hit_full_closing, 1.0), 0.0, 1.0)
	if sparks_enabled:
		var n := int(lerpf(p.hit_sparks_min, p.hit_sparks_max, heat) * _quench())
		impacts.burst(point, normal, ship.velocity * p.hit_spark_inherit, n,
			p.hit_spark_kick * (0.5 + heat), p.hit_spark_scatter)
		if heat >= p.flash_min_heat:
			impacts.flash(point + normal * 0.5, p.flash_energy * heat)
	_puff(point, normal, p.hit_dust_carriers * (0.3 + 0.7 * heat), 1.0 + heat)
	_contact_mark(point, normal, speed, maxf(heat, 0.2), p.mark_min_length + heat * 1.5)


func _on_scrape(point: Vector3, normal: Vector3, speed: float, _closing: float) -> void:
	if impacts == null:
		return
	var p := profile
	var dt := ship.get_physics_process_delta_time()
	if sparks_enabled:
		_spark_acc += p.scrape_sparks_per_speed * speed * dt * _quench()
		var n := int(_spark_acc)
		_spark_acc -= n
		if n > 0:
			impacts.burst(point, normal, ship.velocity * p.scrape_spark_inherit, n,
				p.hit_spark_kick * 0.6, p.hit_spark_scatter * 0.7)
	_dust_acc += p.scrape_dust_rate * dt
	var c := int(_dust_acc)
	_dust_acc -= c
	if c > 0:
		_puff(point, normal, c, 0.6)
	var heat := clampf(speed / maxf(ship.get_max_speed(), 1.0), 0.2, 1.0) * 0.7
	_contact_mark(point, normal, speed, heat, p.mark_min_length)


## Lays the next mark of a contact line. Continuing contact (within
## CONTACT_GAP seconds of the last, and close by) bridges from the previous mark,
## so the line has no gaps; a fresh contact gets a standalone mark.
const CONTACT_GAP := 0.3
const MAX_BRIDGE := 9.0

func _contact_mark(point: Vector3, normal: Vector3, speed: float, heat: float, fresh_length: float) -> void:
	# Physics ticks, not wall time: contact comes from the physics step.
	var now := Engine.get_physics_frames()
	var continuing := _last_mark != Vector3.INF \
		and now - _last_contact_tick <= int(CONTACT_GAP * Engine.physics_ticks_per_second)
	_last_contact_tick = now
	if continuing:
		var gap := point.distance_to(_last_mark)
		if gap > MAX_BRIDGE:
			continuing = false
		elif gap < maxf(profile.mark_min_length, speed * profile.mark_spacing_time):
			return   # not far enough along yet
		else:
			impacts.mark((point + _last_mark) * 0.5, normal, point - _last_mark, gap + 0.6, heat)
			_last_mark = point
			return
	impacts.mark(point, normal, ship.velocity, fresh_length, heat)
	_last_mark = point


## Carriers of the current surface kind off the wall at `point`.
func _puff(point: Vector3, normal: Vector3, carriers: float, strength: float) -> void:
	if pools == null or dust == null:
		return
	var amount := dust.surface_amount()
	var n := int(carriers * amount)
	if n <= 0:
		return
	var up := probe.ground_normal if probe and probe.has_ground else Vector3.UP
	for i in n:
		var v := ship.velocity * profile.dust_inherit * 0.6 \
			+ normal * _rng.randf_range(2.0, 6.0) * strength \
			+ up * _rng.randf_range(0.5, 3.0) \
			+ Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), _rng.randf_range(-1, 1)) * 2.0
		pools.emit(dust.kind, point + normal * 0.4, v)


## Wet walls and roads quench sparks.
func _quench() -> float:
	return 1.0 - profile.spark_wet_quench * (probe.wetness if probe else 0.0)
