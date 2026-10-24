extends RefCounted
class_name AIFieldSense
## v34: where every ship is, in spline space, computed once per physics tick
## and shared by all AI controllers. An AI publishes its own state (its line
## follower already knows its spline offset); the player's ship, or any ship
## nobody published, is measured on first request each tick.
##
## State: {frame, offset (0..1), lat (m, +right, tilted frame), s_speed (u/s
## along the spline tangent), speed}

static var _states: Dictionary = {}

static func publish(ship: ShipController, offset: float, lat: float, helper: TrackSplineHelper) -> void:
	var tangent: Vector3 = helper.get_tangent_at_offset(offset)
	_states[ship.get_instance_id()] = {
		"frame": Engine.get_physics_frames(), "offset": offset, "lat": lat,
		"s_speed": ship.velocity.dot(tangent), "speed": ship.velocity.length()}

static func state_of(ship: ShipController, helper: TrackSplineHelper) -> Dictionary:
	var id := ship.get_instance_id()
	var frame := Engine.get_physics_frames()
	if _states.has(id) and _states[id].frame == frame:
		return _states[id]
	var offset: float = helper.world_to_spline_offset(ship.global_position)
	var lat: float = helper.calculate_lateral_offset(ship.global_position, offset, true)
	publish(ship, offset, lat, helper)
	return _states[id]

## Signed distance along the track from a to b in metres, on a closed lap.
static func along(from_offset: float, to_offset: float, track_length: float) -> float:
	var d: float = to_offset - from_offset
	if d > 0.5:
		d -= 1.0
	elif d < -0.5:
		d += 1.0
	return d * track_length
