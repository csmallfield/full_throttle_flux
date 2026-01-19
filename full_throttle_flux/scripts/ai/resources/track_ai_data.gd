@tool
extends Resource
class_name TrackAIData

## Track AI Data
## Container for all recorded AI training data for a single track.
## Handles skill tier organization and sample interpolation.

# ============================================================================
# IDENTITY
# ============================================================================

## Track this data belongs to
@export var track_id: String = ""

## All recorded laps for this track
@export var recorded_laps: Array[AIRecordedLap] = []

# ============================================================================
# SKILL TIERS (computed on load)
# ============================================================================

## Top 20% fastest laps (Skill 0.8-1.0)
var fast_laps: Array[AIRecordedLap] = []

## 20-40% laps (Skill 0.6-0.8)
var good_laps: Array[AIRecordedLap] = []

## 40-60% laps (Skill 0.4-0.6)
var median_laps: Array[AIRecordedLap] = []

## 60-80% laps (Skill 0.2-0.4)
var slow_laps: Array[AIRecordedLap] = []

## Bottom 20% laps (Skill 0.0-0.2)
var safe_laps: Array[AIRecordedLap] = []

## Cached best/worst times for skill calculations
var best_lap_time: float = INF
var worst_lap_time: float = 0.0

# ============================================================================
# INITIALIZATION
# ============================================================================

func _init() -> void:
	# Compute tiers whenever resource is loaded
	call_deferred("_compute_skill_tiers")

func _compute_skill_tiers() -> void:
	if recorded_laps.is_empty():
		return
	
	# Sort laps by time (fastest first)
	var sorted_laps: Array[AIRecordedLap] = []
	sorted_laps.assign(recorded_laps.duplicate())
	sorted_laps.sort_custom(func(a: AIRecordedLap, b: AIRecordedLap) -> bool: return a.lap_time < b.lap_time)
	
	# Cache best/worst times
	best_lap_time = sorted_laps[0].lap_time
	worst_lap_time = sorted_laps[-1].lap_time
	
	# Clear existing tiers
	fast_laps.clear()
	good_laps.clear()
	median_laps.clear()
	slow_laps.clear()
	safe_laps.clear()
	
	# Distribute into tiers (20% each)
	var count: int = sorted_laps.size()
	for i in range(count):
		var percentile: float = float(i) / float(count)
		var lap: AIRecordedLap = sorted_laps[i]
		
		if percentile < 0.2:
			fast_laps.append(lap)
		elif percentile < 0.4:
			good_laps.append(lap)
		elif percentile < 0.6:
			median_laps.append(lap)
		elif percentile < 0.8:
			slow_laps.append(lap)
		else:
			safe_laps.append(lap)

## Force recomputation of tiers (call after adding/removing laps)
func refresh_tiers() -> void:
	_compute_skill_tiers()

# ============================================================================
# SAMPLE QUERIES
# ============================================================================

## Get interpolated sample based on position and skill level
func get_interpolated_sample(spline_offset: float, skill: float) -> AIRacingSample:
	skill = clamp(skill, 0.0, 1.0)
	
	# Determine which tiers to blend between
	var tier_a: Array[AIRecordedLap]
	var tier_b: Array[AIRecordedLap]
	var blend_factor: float
	
	if skill >= 0.8:
		tier_a = good_laps if not good_laps.is_empty() else fast_laps
		tier_b = fast_laps
		blend_factor = (skill - 0.8) / 0.2
	elif skill >= 0.6:
		tier_a = median_laps if not median_laps.is_empty() else good_laps
		tier_b = good_laps if not good_laps.is_empty() else fast_laps
		blend_factor = (skill - 0.6) / 0.2
	elif skill >= 0.4:
		tier_a = slow_laps if not slow_laps.is_empty() else median_laps
		tier_b = median_laps if not median_laps.is_empty() else good_laps
		blend_factor = (skill - 0.4) / 0.2
	elif skill >= 0.2:
		tier_a = safe_laps if not safe_laps.is_empty() else slow_laps
		tier_b = slow_laps if not slow_laps.is_empty() else median_laps
		blend_factor = (skill - 0.2) / 0.2
	else:
		tier_a = safe_laps
		tier_b = safe_laps if not safe_laps.is_empty() else slow_laps
		blend_factor = skill / 0.2
	
	# Fallback if tiers are empty
	if tier_a.is_empty() and tier_b.is_empty():
		if not recorded_laps.is_empty():
			return recorded_laps[0].get_interpolated_sample_at_offset(spline_offset)
		return null
	
	if tier_a.is_empty():
		tier_a = tier_b
	if tier_b.is_empty():
		tier_b = tier_a
	
	# Get samples from each tier (average if multiple laps in tier)
	var sample_a: AIRacingSample = _get_averaged_sample_from_tier(tier_a, spline_offset)
	var sample_b: AIRacingSample = _get_averaged_sample_from_tier(tier_b, spline_offset)
	
	if sample_a == null:
		return sample_b
	if sample_b == null:
		return sample_a
	
	# Blend between tiers
	return _blend_samples(sample_a, sample_b, blend_factor)

func _get_averaged_sample_from_tier(tier: Array[AIRecordedLap], spline_offset: float) -> AIRacingSample:
	if tier.is_empty():
		return null
	
	# For now, just use first lap in tier
	# TODO: Average across all laps in tier for smoother lines
	return tier[0].get_interpolated_sample_at_offset(spline_offset)

func _blend_samples(a: AIRacingSample, b: AIRacingSample, t: float) -> AIRacingSample:
	var result: AIRacingSample = AIRacingSample.new()
	result.spline_offset = lerp(a.spline_offset, b.spline_offset, t)
	result.lateral_offset = lerp(a.lateral_offset, b.lateral_offset, t)
	result.speed = lerp(a.speed, b.speed, t)
	result.heading = a.heading.lerp(b.heading, t).normalized()
	result.world_position = a.world_position.lerp(b.world_position, t)
	result.throttle = lerp(a.throttle, b.throttle, t)
	result.brake = lerp(a.brake, b.brake, t)
	result.airbrake_left = lerp(a.airbrake_left, b.airbrake_left, t)
	result.airbrake_right = lerp(a.airbrake_right, b.airbrake_right, t)
	result.is_grounded = a.is_grounded if t < 0.5 else b.is_grounded
	result.is_boosting = a.is_boosting if t < 0.5 else b.is_boosting
	return result

# ============================================================================
# DATA MANAGEMENT
# ============================================================================

func add_recorded_lap(lap: AIRecordedLap) -> void:
	recorded_laps.append(lap)
	refresh_tiers()

func remove_lap_at_index(index: int) -> void:
	if index >= 0 and index < recorded_laps.size():
		recorded_laps.remove_at(index)
		refresh_tiers()

func clear_all_laps() -> void:
	recorded_laps.clear()
	fast_laps.clear()
	good_laps.clear()
	median_laps.clear()
	slow_laps.clear()
	safe_laps.clear()

func has_recorded_data() -> bool:
	return not recorded_laps.is_empty()
