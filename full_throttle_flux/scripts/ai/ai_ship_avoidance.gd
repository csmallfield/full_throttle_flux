extends RefCounted
class_name AIShipAvoidance

## AI Ship Avoidance System
## Provides steering/throttle adjustments to avoid collisions with other ships.
## Integrates with AIShipController - call after decide_controls() to modify outputs.
##
## Design Philosophy:
## - Balanced by default: Ships give space while maintaining racing lines
## - Position-aware: More aggressive when behind, defensive when leading
## - Difficulty scaling: Easy AI avoids more, Hard AI holds line better

# ============================================================================
# CONFIGURATION - AWARENESS
# ============================================================================

## Forward detection distance for ships ahead
var forward_awareness_distance: float = 25.0

## Side detection distance for ships alongside
var side_awareness_distance: float = 8.0

## Rear detection distance (for defensive awareness)
var rear_awareness_distance: float = 12.0

## Angle of forward detection cone (degrees from forward)
var forward_cone_angle: float = 45.0

# ============================================================================
# CONFIGURATION - AVOIDANCE BEHAVIOR
# ============================================================================

## Base avoidance strength (0 = ignore others, 1 = maximum avoidance)
var avoidance_strength: float = 0.6

## How much to prioritize racing line over avoidance (0 = always avoid, 1 = hold line)
var line_holding_strength: float = 0.5

## Distance at which avoidance starts to activate
var avoidance_start_distance: float = 15.0

## Distance at which avoidance is at maximum urgency
var avoidance_urgent_distance: float = 5.0

## Smoothing factor for avoidance steering changes
var steering_smoothing: float = 0.3

# ============================================================================
# CONFIGURATION - AGGRESSION (Position-Based)
# ============================================================================

## Base aggression level (0 = purely defensive, 1 = will make contact)
var aggression_base: float = 0.3

## Aggression increase when behind in race position
var aggression_when_behind: float = 0.5

## Aggression decrease when leading
var aggression_when_leading: float = 0.1

## Whether AI will intentionally block other ships
var allow_blocking: bool = true

# ============================================================================
# CONFIGURATION - DIFFICULTY SCALING
# ============================================================================

## Multiplier for awareness distances (lower = harder AI, reacts later)
var difficulty_awareness_scale: float = 1.0

## Multiplier for reaction smoothing (lower = faster reactions = harder)
var difficulty_reaction_scale: float = 1.0

## Scale aggression/avoidance by race position
var scale_by_position: bool = true

# ============================================================================
# STATE
# ============================================================================

var ship: ShipController
var skill_level: float = 1.0

## Current avoidance steering adjustment (-1 to 1, added to base steering)
var avoidance_steering: float = 0.0

## Current avoidance throttle adjustment (0 to 1, multiplier)
var avoidance_throttle: float = 1.0

## Smoothed steering for jitter prevention
var _smoothed_steering: float = 0.0

## Race position tracking
var race_position: int = 1
var total_racers: int = 1

## All ships in the race (set by AIShipController or RaceMode)
var all_race_ships: Array = []  # Array of ShipController, untyped for flexibility

# ============================================================================
# INITIALIZATION
# ============================================================================

func initialize(p_ship: ShipController, p_skill: float = 1.0) -> void:
	ship = p_ship
	skill_level = p_skill
	_update_difficulty_scaling()

func set_skill(skill: float) -> void:
	skill_level = clampf(skill, 0.0, 1.0)
	_update_difficulty_scaling()

func _update_difficulty_scaling() -> void:
	"""Adjust parameters based on skill level."""
	# Higher skill = less avoidance (more aggressive), faster reactions
	# Skill 0.0 (Easy): awareness_scale=1.3, reaction_scale=1.5 (slow, cautious)
	# Skill 1.0 (Hard): awareness_scale=0.8, reaction_scale=0.7 (fast, aggressive)
	difficulty_awareness_scale = lerpf(1.3, 0.8, skill_level)
	difficulty_reaction_scale = lerpf(1.5, 0.7, skill_level)
	
	# Aggression scales with skill
	aggression_base = lerpf(0.1, 0.4, skill_level)
	avoidance_strength = lerpf(0.8, 0.5, skill_level)
	line_holding_strength = lerpf(0.3, 0.7, skill_level)

func set_race_ships(ships: Array) -> void:
	"""Set all ships participating in the race."""
	all_race_ships = ships

func update_race_position(position: int, total: int) -> void:
	"""Update this ship's race position for aggression scaling."""
	race_position = position
	total_racers = total

# ============================================================================
# MAIN UPDATE - Call each physics frame
# ============================================================================

func update(delta: float) -> void:
	"""Update avoidance calculations. Call before applying controls."""
	if not ship or all_race_ships.is_empty():
		avoidance_steering = 0.0
		avoidance_throttle = 1.0
		return
	
	var nearby_ships := _detect_nearby_ships()
	_calculate_avoidance(nearby_ships, delta)

# ============================================================================
# SHIP DETECTION
# ============================================================================

func _detect_nearby_ships() -> Array[Dictionary]:
	"""Find ships within awareness range and categorize them."""
	var detected: Array[Dictionary] = []
	
	if not ship:
		return detected
	
	var ship_pos := ship.global_position
	var ship_forward := -ship.global_transform.basis.z
	var ship_right := ship.global_transform.basis.x
	
	# Get scaled awareness distances
	var fwd_dist: float = forward_awareness_distance * difficulty_awareness_scale
	var side_dist: float = side_awareness_distance * difficulty_awareness_scale
	var rear_dist: float = rear_awareness_distance * difficulty_awareness_scale
	var max_dist: float = maxf(fwd_dist, maxf(side_dist, rear_dist))
	
	for i in range(all_race_ships.size()):
		var other: ShipController = all_race_ships[i] as ShipController
		if other == null or other == ship or not is_instance_valid(other):
			continue
		
		var to_other: Vector3 = other.global_position - ship_pos
		var distance: float = to_other.length()
		
		# Quick distance check
		if distance > max_dist or distance < 0.1:
			continue
		
		var direction: Vector3 = to_other.normalized()
		var forward_dot: float = direction.dot(ship_forward)
		var right_dot: float = direction.dot(ship_right)
		
		# Categorize position
		var is_ahead: bool = forward_dot > 0.3
		var is_behind: bool = forward_dot < -0.3
		var is_alongside: bool = absf(forward_dot) <= 0.3
		
		# Check if within relevant awareness zone
		var in_range: bool = false
		var zone: String = "none"
		
		if is_ahead:
			var angle: float = rad_to_deg(acos(clampf(forward_dot, 0.0, 1.0)))
			if angle < forward_cone_angle and distance < fwd_dist:
				in_range = true
				zone = "forward"
		elif is_alongside and distance < side_dist:
			in_range = true
			zone = "side"
		elif is_behind and distance < rear_dist:
			in_range = true
			zone = "rear"
		
		if in_range:
			detected.append({
				"ship": other,
				"distance": distance,
				"direction": direction,
				"forward_dot": forward_dot,
				"right_dot": right_dot,
				"zone": zone,
				"relative_speed": ship.velocity.length() - other.velocity.length()
			})
	
	return detected

# ============================================================================
# AVOIDANCE CALCULATION
# ============================================================================

func _calculate_avoidance(nearby_ships: Array[Dictionary], delta: float) -> void:
	"""Calculate steering and throttle adjustments to avoid nearby ships."""
	
	if nearby_ships.is_empty():
		# Smoothly return to neutral
		_smoothed_steering = lerpf(_smoothed_steering, 0.0, 10.0 * delta)
		avoidance_steering = _smoothed_steering
		avoidance_throttle = 1.0
		return
	
	var total_steer_adjustment := 0.0
	var should_slow := false
	var max_urgency := 0.0
	
	# Get effective aggression based on race position
	var effective_aggression := _get_effective_aggression()
	
	for ship_data in nearby_ships:
		var distance: float = ship_data.distance
		var right_dot: float = ship_data.right_dot
		var forward_dot: float = ship_data.forward_dot
		var zone: String = ship_data.zone
		var relative_speed: float = ship_data.relative_speed
		
		# Calculate urgency (0-1) based on distance
		var urgency := 0.0
		
		match zone:
			"forward":
				# Ships ahead - highest priority
				if distance < avoidance_start_distance:
					urgency = 1.0 - (distance / avoidance_start_distance)
					urgency = urgency * urgency  # Quadratic - more urgent when close
					
					# Extra urgency if closing fast
					if relative_speed > 5.0:
						urgency = minf(urgency * 1.3, 1.0)
			
			"side":
				# Ships alongside - moderate priority
				urgency = 1.0 - (distance / side_awareness_distance)
				urgency *= 0.7  # Less urgent than forward
			
			"rear":
				# Ships behind - low priority (defensive only)
				urgency = (1.0 - (distance / rear_awareness_distance)) * 0.3
		
		max_urgency = maxf(max_urgency, urgency)
		
		# Determine avoidance direction
		var avoid_direction: float
		if absf(right_dot) < 0.15:
			# Ship directly ahead/behind - pick a side
			# Prefer the side we're already leaning toward, or use a consistent bias
			avoid_direction = sign(ship.steer_input) if absf(ship.steer_input) > 0.1 else 1.0
		else:
			# Steer away from the other ship
			avoid_direction = -sign(right_dot)
		
		# Modify based on line holding and aggression
		var avoidance_modifier := 1.0
		
		# Line holding reduces avoidance when not urgent
		avoidance_modifier *= 1.0 - (line_holding_strength * (1.0 - urgency))
		
		# Aggression reduces avoidance overall
		avoidance_modifier *= 1.0 - (effective_aggression * 0.5)
		
		# Accumulate steering adjustment
		total_steer_adjustment += avoid_direction * urgency * avoidance_modifier
		
		# Check if we should slow down (ship very close ahead)
		if zone == "forward" and distance < avoidance_urgent_distance:
			should_slow = true
	
	# Apply avoidance strength and clamp
	var target_steering: float = clampf(total_steer_adjustment * avoidance_strength, -0.5, 0.5)
	
	# Smooth the steering adjustment
	var smoothing_factor := steering_smoothing * difficulty_reaction_scale
	_smoothed_steering = lerpf(_smoothed_steering, target_steering, (1.0 - smoothing_factor) * 10.0 * delta)
	avoidance_steering = _smoothed_steering
	
	# Calculate throttle adjustment
	if should_slow and max_urgency > 0.7:
		# Reduce throttle when very close to ship ahead
		avoidance_throttle = lerpf(1.0, 0.75, (max_urgency - 0.7) / 0.3)
	else:
		avoidance_throttle = 1.0

func _get_effective_aggression() -> float:
	"""Get aggression level adjusted for race position."""
	if not scale_by_position or total_racers <= 1:
		return aggression_base
	
	# Position ratio: 0 = first place, 1 = last place
	var position_ratio := float(race_position - 1) / float(total_racers - 1)
	
	if position_ratio < 0.5:
		# Leading half - reduce aggression (protect position)
		var lead_factor := 1.0 - (position_ratio * 2.0)
		return lerpf(aggression_base, aggression_when_leading, lead_factor)
	else:
		# Trailing half - increase aggression (need to overtake)
		var trail_factor := (position_ratio - 0.5) * 2.0
		return lerpf(aggression_base, aggression_when_behind, trail_factor)

# ============================================================================
# CONTROL ADJUSTMENT API
# ============================================================================

func adjust_controls(controls: Dictionary) -> Dictionary:
	"""
	Adjust control outputs from AIControlDecider.
	Call this after decide_controls() returns.
	
	Returns modified controls dictionary.
	"""
	var adjusted := controls.duplicate()
	
	# Add avoidance steering (clamped to valid range)
	adjusted.steer = clampf(controls.steer + avoidance_steering, -1.0, 1.0)
	
	# Multiply throttle by avoidance factor
	adjusted.throttle = controls.throttle * avoidance_throttle
	
	return adjusted

func get_adjusted_steering(base_steering: float) -> float:
	"""Get steering with avoidance adjustment applied."""
	return clampf(base_steering + avoidance_steering, -1.0, 1.0)

func get_adjusted_throttle(base_throttle: float) -> float:
	"""Get throttle with avoidance adjustment applied."""
	return base_throttle * avoidance_throttle

# ============================================================================
# QUERIES
# ============================================================================

func is_avoiding() -> bool:
	"""Check if currently making avoidance adjustments."""
	return absf(avoidance_steering) > 0.05 or avoidance_throttle < 0.95

func get_nearest_ship_distance() -> float:
	"""Get distance to nearest other ship."""
	var min_dist: float = INF
	
	if not ship:
		return min_dist
	
	for i in range(all_race_ships.size()):
		var other: ShipController = all_race_ships[i] as ShipController
		if other == null or other == ship or not is_instance_valid(other):
			continue
		var dist: float = ship.global_position.distance_to(other.global_position)
		min_dist = minf(min_dist, dist)
	
	return min_dist

# ============================================================================
# DEBUG
# ============================================================================

func get_debug_info() -> String:
	return "Avoid: steer=%.2f thr=%.0f%% pos=%d/%d aggr=%.0f%%" % [
		avoidance_steering,
		avoidance_throttle * 100.0,
		race_position,
		total_racers,
		_get_effective_aggression() * 100.0
	]
