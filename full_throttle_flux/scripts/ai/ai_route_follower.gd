extends AILineFollower
class_name AIRouteFollower

## v32: an AILineFollower over several ROUTE LAPS (TrackGraph routes): one
## inner follower per route, each with its own lap spline, racing line and
## speed profile. Exactly one is active; switching blends the steering target,
## speed target and line curvature from the old route to the new one over
## `blend_distance` metres of travel, so there's no snap in the lateral target.
##
## Everything else that reads a follower (the decider's tracking error, style
## gains, the trainer, the spectator, debug drawing) sees the ACTIVE route's
## spline_helper, baked_line and current_spline_offset, mirrored onto this
## object each tick, so the base class methods work unchanged.
##
## Used only on tracks whose TrackGraph has route laps; elsewhere the AI keeps
## its single AILineFollower.

var views: Array[AILineFollower] = []
var routes: PackedInt32Array = PackedInt32Array()   # route id per view (-1 = main)
var active: int = 0

## Metres of travel over which a route switch blends.
var blend_distance: float = 120.0

var _from: int = -1
var _blend: float = 1.0
var _last_pos := Vector3.INF

func add_view(route: int, follower: AILineFollower) -> void:
	views.append(follower)
	routes.append(route)
	if views.size() == 1:
		_mirror()

func view_for_route(route: int) -> int:
	for i in routes.size():
		if routes[i] == route:
			return i
	return 0

func active_route() -> int:
	return routes[active] if active < routes.size() else -1

func is_blending() -> bool:
	return _from >= 0

## Switch to the view for `route`. `blend` false = snap (after a respawn).
func set_route(route: int, blend: bool = true) -> void:
	var i := view_for_route(route)
	if i == active:
		return
	if blend:
		_from = active
		_blend = 0.0
	else:
		_from = -1
		_blend = 1.0
	active = i
	_mirror()

func set_skill(skill: float) -> void:
	super.set_skill(skill)
	for v in views:
		v.set_skill(skill)

func update_position(world_position: Vector3) -> void:
	if _from >= 0 and _last_pos != Vector3.INF:
		_blend += world_position.distance_to(_last_pos) / maxf(blend_distance, 1.0)
		if _blend >= 1.0:
			_from = -1
			_blend = 1.0
	_last_pos = world_position
	views[active].update_position(world_position)
	if _from >= 0:
		views[_from].update_position(world_position)
	_mirror()

func _mirror() -> void:
	var v: AILineFollower = views[active]
	spline_helper = v.spline_helper
	baked_line = v.baked_line
	perf_model = v.perf_model
	current_spline_offset = v.current_spline_offset
	current_world_position = v.current_world_position
	cached_max_upcoming_curvature = v.cached_max_upcoming_curvature
	cached_max_curvature_signed = v.cached_max_curvature_signed
	cached_corner_distance = v.cached_corner_distance
	cached_immediate_curvature = v.cached_immediate_curvature
	cached_immediate_curvature_signed = v.cached_immediate_curvature_signed
	cached_target_lateral_offset = v.cached_target_lateral_offset
	cached_apex_world_position = v.cached_apex_world_position
	cached_apex_spline_offset = v.cached_apex_spline_offset
	baked_steer_lookahead_max = v.baked_steer_lookahead_max

func get_target_position(ship_speed: float, max_speed: float) -> Dictionary:
	# Style gains are written to this object; pass them on to the active view.
	views[active].baked_steer_lookahead_max = baked_steer_lookahead_max
	var a: Dictionary = views[active].get_target_position(ship_speed, max_speed)
	if _from < 0:
		return a
	var b: Dictionary = views[_from].get_target_position(ship_speed, max_speed)
	var w := _blend * _blend * (3.0 - 2.0 * _blend)
	a.world_position = (b.world_position as Vector3).lerp(a.world_position, w)
	a.suggested_speed = lerpf(b.suggested_speed, a.suggested_speed, w)
	a.lateral_offset = lerpf(b.get("lateral_offset", 0.0), a.get("lateral_offset", 0.0), w)
	a.line_curvature_signed = lerpf(b.get("line_curvature_signed", 0.0), a.get("line_curvature_signed", 0.0), w)
	return a

func get_debug_info() -> String:
	return "[route %d%s] %s" % [active_route(), " blending %.0f%%" % (_blend * 100.0) if _from >= 0 else "",
			views[active].get_debug_info()]
