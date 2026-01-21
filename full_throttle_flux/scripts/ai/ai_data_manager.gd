extends RefCounted
class_name AIDataManager

## AI Data Manager
## Utility class for loading and managing TrackAIData resources.
## Searches both user recordings and bundled data.

# ============================================================================
# PATHS
# ============================================================================

const USER_DATA_PATH := "user://ai_recordings/"
const BUNDLED_DATA_PATH := "res://resources/ai_data/"

# ============================================================================
# LOADING
# ============================================================================

static func load_track_ai_data(track_id: String) -> TrackAIData:
	"""
	Load TrackAIData for a track.
	Searches user recordings first, then bundled data.
	Returns null if no data exists.
	"""
	# Try user recordings first (development/player data)
	var user_path := USER_DATA_PATH + track_id + "_ai_data.tres"
	if ResourceLoader.exists(user_path):
		var data := load(user_path) as TrackAIData
		if data:
			print("AIDataManager: Loaded user AI data for '%s' (%d laps)" % [track_id, data.recorded_laps.size()])
			return data
	
	# Try bundled data (shipped with game)
	var bundled_path := BUNDLED_DATA_PATH + track_id + "_ai_data.tres"
	if ResourceLoader.exists(bundled_path):
		var data := load(bundled_path) as TrackAIData
		if data:
			print("AIDataManager: Loaded bundled AI data for '%s' (%d laps)" % [track_id, data.recorded_laps.size()])
			return data
	
	print("AIDataManager: No AI data found for '%s'" % track_id)
	return null

static func has_ai_data(track_id: String) -> bool:
	"""Check if any AI data exists for a track."""
	var user_path := USER_DATA_PATH + track_id + "_ai_data.tres"
	var bundled_path := BUNDLED_DATA_PATH + track_id + "_ai_data.tres"
	return ResourceLoader.exists(user_path) or ResourceLoader.exists(bundled_path)

static func get_data_source(track_id: String) -> String:
	"""Returns 'user', 'bundled', or 'none' indicating where data comes from."""
	var user_path := USER_DATA_PATH + track_id + "_ai_data.tres"
	if ResourceLoader.exists(user_path):
		return "user"
	
	var bundled_path := BUNDLED_DATA_PATH + track_id + "_ai_data.tres"
	if ResourceLoader.exists(bundled_path):
		return "bundled"
	
	return "none"

# ============================================================================
# BAKING / EXPORT
# ============================================================================

static func bake_to_bundled(track_id: String) -> bool:
	"""
	Copy user recordings to bundled data path for shipping.
	Used during development to finalize AI data.
	Returns true on success.
	"""
	var user_path := USER_DATA_PATH + track_id + "_ai_data.tres"
	
	if not ResourceLoader.exists(user_path):
		push_warning("AIDataManager: No user data to bake for '%s'" % track_id)
		return false
	
	var data := load(user_path) as TrackAIData
	if not data:
		push_error("AIDataManager: Failed to load user data for '%s'" % track_id)
		return false
	
	# Ensure bundled directory exists
	if not DirAccess.dir_exists_absolute(BUNDLED_DATA_PATH):
		DirAccess.make_dir_recursive_absolute(BUNDLED_DATA_PATH)
	
	var bundled_path := BUNDLED_DATA_PATH + track_id + "_ai_data.tres"
	var error := ResourceSaver.save(data, bundled_path)
	
	if error == OK:
		print("AIDataManager: Baked AI data to '%s'" % bundled_path)
		return true
	else:
		push_error("AIDataManager: Failed to bake - error %d" % error)
		return false

# ============================================================================
# ANALYSIS
# ============================================================================

static func get_data_summary(track_id: String) -> Dictionary:
	"""Get summary info about AI data for a track."""
	var data := load_track_ai_data(track_id)
	
	if not data:
		return {
			"exists": false,
			"track_id": track_id
		}
	
	data.refresh_tiers()
	
	var lap_times: Array[float] = []
	for lap in data.recorded_laps:
		lap_times.append(lap.lap_time)
	
	var best_time := INF
	var worst_time := 0.0
	var total_time := 0.0
	
	for time in lap_times:
		best_time = min(best_time, time)
		worst_time = max(worst_time, time)
		total_time += time
	
	var avg_time := total_time / lap_times.size() if lap_times.size() > 0 else 0.0
	
	return {
		"exists": true,
		"track_id": track_id,
		"source": get_data_source(track_id),
		"total_laps": data.recorded_laps.size(),
		"best_time": best_time,
		"worst_time": worst_time,
		"avg_time": avg_time,
		"tier_fast": data.fast_laps.size(),
		"tier_good": data.good_laps.size(),
		"tier_median": data.median_laps.size(),
		"tier_slow": data.slow_laps.size(),
		"tier_safe": data.safe_laps.size()
	}

static func print_all_track_summaries() -> void:
	"""Print AI data summary for all known tracks."""
	print("\n============================================================")
	print("AI DATA SUMMARY")
	print("============================================================")
	
	for track in GameManager.available_tracks:
		var summary := get_data_summary(track.track_id)
		
		print("\n%s (%s):" % [track.display_name, track.track_id])
		
		if not summary.exists:
			print("  No AI data")
			continue
		
		print("  Source: %s" % summary.source)
		print("  Laps: %d" % summary.total_laps)
		print("  Times: Best=%.2fs, Avg=%.2fs, Worst=%.2fs" % [
			summary.best_time,
			summary.avg_time,
			summary.worst_time
		])
		print("  Tiers: Fast=%d, Good=%d, Med=%d, Slow=%d, Safe=%d" % [
			summary.tier_fast,
			summary.tier_good,
			summary.tier_median,
			summary.tier_slow,
			summary.tier_safe
		])
	
	print("\n============================================================\n")
