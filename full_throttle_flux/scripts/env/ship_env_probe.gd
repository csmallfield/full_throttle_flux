extends Node
class_name ShipEnvProbe
## What the environment FX need to know about one ship, sampled once per
## physics tick after the ship has moved (v35).
##
## ShipController attaches one in _ready. It stays idle (no rays, no spline
## search) until the race has an EnvironmentState, so the AI trainer and the
## dev sims pay nothing.
##
## Read-only outputs:
##   ground    has_ground, ground_distance, ground_point, ground_normal
##   walls     wall_left / wall_right (metres, INF = none within SIDE_RAY_LENGTH)
##             plus their points and normals
##   track     spline_distance (metres along MainSpline, -1 = unknown), zone
##   surface   wetness, frost, dust, precipitation: the LOCAL values here
##             (global weather combined with the zone: dry under a roof, ...)
##   hits      last_hit_* and scraping, fed by ShipController.wall_hit/scrape
## FX connect to ShipController.wall_hit / wall_scrape directly for events.

const NODE_NAME := "ShipEnvProbe"
## Runs after every ship (default 0) and after ShipContactResolver (100).
const PHYSICS_PRIORITY := 110
const WALL_MASK := 4                 # same layer TrackCorridor measures
const SIDE_RAY_LENGTH := 12.0        # walls further away than this read as INF
## Side rays start this far above the ship origin along its up axis.
const SIDE_RAY_LIFT := 0.3
## Seconds between EnvironmentState lookups while idle.
const BIND_RETRY := 1.0
## v38.1: physics ticks between samples by the ship's FX LOD (ShipFx.lod):
## FULL (the camera's ship), NEAR, FAR, OFF. Everything here feeds visual FX
## only, so distant ships are sampled less often; the ground is copied from
## the controller every tick regardless (free).
const SAMPLE_EVERY := [1, 2, 4, 8]

var ship: ShipController
var env: EnvironmentState
var active: bool = false

# --- Ground ---------------------------------------------------------------
var has_ground: bool = false
var ground_distance: float = INF
var ground_point := Vector3.ZERO
var ground_normal := Vector3.UP

# --- Walls ----------------------------------------------------------------
var wall_left: float = INF
var wall_right: float = INF
var wall_left_point := Vector3.ZERO
var wall_right_point := Vector3.ZERO
var wall_left_normal := Vector3.ZERO
var wall_right_normal := Vector3.ZERO

# --- Track ----------------------------------------------------------------
var spline_distance: float = -1.0
var zone := TrackFxZones.Sample.new()

# --- Local surface --------------------------------------------------------
var wetness: float = 0.0
var frost: float = 0.0
var dust: float = 0.0
var precipitation: float = 0.0

# --- Wall hits ------------------------------------------------------------
var last_hit_time_ms: int = -1
var last_hit_point := Vector3.ZERO
var last_hit_speed: float = 0.0
var last_hit_closing: float = 0.0
## True while the ship is scraping along a wall (ticks after the first).
var scraping: bool = false

var _tracker: SplineTracker
var _ray: PhysicsRayQueryParameters3D
var _bind_timer: float = 0.0
var _scrape_seen_tick: int = -1
var _fx: ShipFx
## Staggers the ships' sampling ticks so a grid's work is spread evenly.
var _phase: int = 0


## Adds a probe to `p_ship` once; returns the existing one on a second call.
static func attach(p_ship: ShipController) -> ShipEnvProbe:
	var existing := of(p_ship)
	if existing:
		return existing
	var p := ShipEnvProbe.new()
	p.name = NODE_NAME
	p_ship.add_child(p)
	return p


static func of(p_ship: Node) -> ShipEnvProbe:
	if p_ship == null:
		return null
	return p_ship.get_node_or_null(NODE_NAME) as ShipEnvProbe


func _ready() -> void:
	ship = get_parent() as ShipController
	if ship == null:
		push_warning("ShipEnvProbe: parent is not a ShipController")
		set_physics_process(false)
		return
	process_physics_priority = PHYSICS_PRIORITY
	ship.wall_hit.connect(_on_wall_hit)
	ship.wall_scrape.connect(_on_wall_scrape)
	ship.ship_respawned.connect(_on_respawned)
	_ray = PhysicsRayQueryParameters3D.new()
	_ray.collision_mask = WALL_MASK
	_ray.collide_with_areas = false
	_ray.exclude = [ship.get_rid()]
	_phase = get_instance_id() % 8
	_try_bind()


func _physics_process(delta: float) -> void:
	if not active:
		_bind_timer -= delta
		if _bind_timer <= 0.0:
			_try_bind()
		if not active:
			return
	if not is_instance_valid(env):
		active = false
		env = null
		return
	_sample_ground()
	if _fx == null:
		_fx = ShipFx.of(ship)
	# No camera (tests, sims): nothing to save, and they steer by these values.
	var every: int = 1
	if _fx and _fx.active and get_viewport().get_camera_3d() != null:
		every = SAMPLE_EVERY[int(_fx.lod)]
	if every == 1 or (Engine.get_physics_frames() + _phase) % every == 0:
		_sample_walls()
		_sample_track()
		_sample_surface()
	if scraping and Engine.get_physics_frames() - _scrape_seen_tick > 6:
		scraping = false


func _try_bind() -> void:
	_bind_timer = BIND_RETRY
	env = EnvironmentState.find(get_tree())
	active = env != null
	if active:
		_tracker = env.make_spline_tracker()


# ============================================================================
# SAMPLING
# ============================================================================

func _sample_ground() -> void:
	has_ground = ship.is_grounded
	if has_ground:
		ground_distance = ship.ground_distance
		ground_normal = ship.current_track_normal.normalized()
		# The controller keeps the distance, not the hit point; the smoothed
		# track normal puts this within a few cm of the real hit on any road a
		# ship can stay grounded on.
		ground_point = ship.global_position - ground_normal * ground_distance
	else:
		ground_distance = INF


func _sample_walls() -> void:
	var space := ship.get_world_3d().direct_space_state
	var basis := ship.global_transform.basis
	var right := basis.x.normalized()
	var origin := ship.global_position + basis.y.normalized() * SIDE_RAY_LIFT
	_ray.from = origin
	_ray.to = origin - right * SIDE_RAY_LENGTH
	var hit := space.intersect_ray(_ray)
	if hit.is_empty():
		wall_left = INF
	else:
		wall_left_point = hit.position
		wall_left_normal = hit.normal
		wall_left = origin.distance_to(hit.position)
	_ray.to = origin + right * SIDE_RAY_LENGTH
	hit = space.intersect_ray(_ray)
	if hit.is_empty():
		wall_right = INF
	else:
		wall_right_point = hit.position
		wall_right_normal = hit.normal
		wall_right = origin.distance_to(hit.position)


func _sample_track() -> void:
	if _tracker == null:
		spline_distance = -1.0
		zone.reset()
		return
	spline_distance = _tracker.update(ship.global_position)
	env.sample_zones(spline_distance, zone)


func _sample_surface() -> void:
	wetness = env.local_wetness(zone)
	frost = env.local_frost(zone)
	dust = env.local_dust(zone)
	precipitation = env.local_precipitation(zone)


# ============================================================================
# EVENTS
# ============================================================================

func _on_wall_hit(point: Vector3, _normal: Vector3, speed: float, closing: float) -> void:
	last_hit_time_ms = Time.get_ticks_msec()
	last_hit_point = point
	last_hit_speed = speed
	last_hit_closing = closing
	scraping = false


func _on_wall_scrape(point: Vector3, _normal: Vector3, speed: float, _closing: float) -> void:
	scraping = true
	_scrape_seen_tick = Engine.get_physics_frames()
	last_hit_point = point
	last_hit_speed = speed


func _on_respawned() -> void:
	if _tracker:
		_tracker.reset()
	scraping = false


## Seconds since the last wall hit, INF if none yet.
func seconds_since_hit() -> float:
	if last_hit_time_ms < 0:
		return INF
	return (Time.get_ticks_msec() - last_hit_time_ms) / 1000.0
