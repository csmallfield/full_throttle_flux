@tool
extends Resource
class_name AIRecordedLap

## AI Recorded Lap
## Contains all sample points from a single recorded lap.
## Used for skill-based AI interpolation.

# ============================================================================
# METADATA
# ============================================================================

## Track this lap was recorded on
@export var track_id: String = ""

## Total lap time in seconds
@export var lap_time: float = 0.0

## When this lap was recorded (ISO timestamp)
@export var recording_date: String = ""

## Format version for future migrations
@export var recording_version: int = 1

# ============================================================================
# SAMPLE DATA
# ============================================================================

## Ordered array of sample points along the lap
@export var samples: Array[AIRacingSample] = []

# ============================================================================
# UTILITY
# ============================================================================

## Get the sample closest to a given spline offset
func get_sample_at_offset(spline_offset: float) -> AIRacingSample:
	if samples.is_empty():
		return null
	
	# Wrap offset to 0-1 range
	spline_offset = fmod(spline_offset, 1.0)
	if spline_offset < 0:
		spline_offset += 1.0
	
	# Binary search for closest sample
	var low: int = 0
	var high: int = samples.size() - 1
	
	while low < high:
		var mid: int = (low + high) / 2
		if samples[mid].spline_offset < spline_offset:
			low = mid + 1
		else:
			high = mid
	
	# Check if we should return previous sample (closer)
	if low > 0:
		var prev_diff: float = abs(samples[low - 1].spline_offset - spline_offset)
		var curr_diff: float = abs(samples[low].spline_offset - spline_offset)
		if prev_diff < curr_diff:
			return samples[low - 1]
	
	return samples[low]

## Get interpolated sample between two nearest samples
func get_interpolated_sample_at_offset(spline_offset: float) -> AIRacingSample:
	if samples.is_empty():
		return null
	
	if samples.size() == 1:
		return samples[0]
	
	# Wrap offset to 0-1 range
	spline_offset = fmod(spline_offset, 1.0)
	if spline_offset < 0:
		spline_offset += 1.0
	
	# Find surrounding samples
	var idx_after: int = 0
	for i in range(samples.size()):
		if samples[i].spline_offset > spline_offset:
			idx_after = i
			break
		idx_after = i
	
	var idx_before: int = idx_after - 1
	if idx_before < 0:
		idx_before = samples.size() - 1
	
	var sample_before: AIRacingSample = samples[idx_before]
	var sample_after: AIRacingSample = samples[idx_after]
	
	# Calculate interpolation factor
	var range_start: float = sample_before.spline_offset
	var range_end: float = sample_after.spline_offset
	
	# Handle wrap-around at lap boundary
	if range_end < range_start:
		range_end += 1.0
		if spline_offset < range_start:
			spline_offset += 1.0
	
	var range_size: float = range_end - range_start
	var t: float = 0.5  # Default to midpoint
	if range_size > 0.0001:
		t = (spline_offset - range_start) / range_size
	
	# Interpolate all values
	var result: AIRacingSample = AIRacingSample.new()
	result.spline_offset = spline_offset
	result.lateral_offset = lerp(sample_before.lateral_offset, sample_after.lateral_offset, t)
	result.speed = lerp(sample_before.speed, sample_after.speed, t)
	result.heading = sample_before.heading.lerp(sample_after.heading, t).normalized()
	result.world_position = sample_before.world_position.lerp(sample_after.world_position, t)
	result.throttle = lerp(sample_before.throttle, sample_after.throttle, t)
	result.brake = lerp(sample_before.brake, sample_after.brake, t)
	result.airbrake_left = lerp(sample_before.airbrake_left, sample_after.airbrake_left, t)
	result.airbrake_right = lerp(sample_before.airbrake_right, sample_after.airbrake_right, t)
	result.is_grounded = sample_before.is_grounded if t < 0.5 else sample_after.is_grounded
	result.is_boosting = sample_before.is_boosting if t < 0.5 else sample_after.is_boosting
	
	return result

## Calculate skill rating based on reference lap times
func calculate_skill_rating(best_time: float, worst_time: float) -> float:
	if best_time >= worst_time:
		return 0.5  # No variance, return middle
	
	# Invert: faster time = higher skill
	var normalized = (worst_time - lap_time) / (worst_time - best_time)
	return clamp(normalized, 0.0, 1.0)
