extends Node
class_name AILapRecorder

## AI Lap Recorder
## Records player/AI racing data for training AI opponents.
## Captures samples at configurable intervals during play.
## Saves completed laps to TrackAIData resources.
##
## Usage:
## - Add as child of race scene or attach to AIDebugTester
## - Press F4 to toggle recording
## - Complete laps in Endless mode to capture data
## - Data saves to user://ai_recordings/

# ============================================================================
# SIGNALS
# ============================================================================

signal recording_started()
signal recording_stopped()
signal sample_recorded(sample: AIRacingSample)
signal lap_recorded(lap: AIRecordedLap)
signal lap_discarded(reason: String)

# ============================================================================
# CONFIGURATION
# ============================================================================

@export_group("Recording Settings")

## Ship to record (auto-detected if not set)
@export var ship: ShipController

## Sample interval in seconds (0.05 = 20 samples/second)
@export var sample_interval: float = 0.05

## Toggle key for recording
@export var toggle_key: Key = KEY_F4

## Automatically start recording when race starts
@export var auto_record: bool = false

## Minimum lap time to consider valid (filters physics glitches)
@export var min_valid_lap_time: float = 30.0

## Maximum collision time per lap before discarding (seconds)
@export var max_collision_time: float = 5.0

@export_group("Storage")

## Base path for saving recordings
@export var save_path: String = "user://ai_recordings/"

## Auto-save after each lap
@export var auto_save: bool = true

# ============================================================================
# STATE
# ============================================================================

var is_recording: bool = false
var spline_helper: TrackSplineHelper
var track_ai_data: TrackAIData

# Current lap recording state
var current_lap_samples: Array[AIRacingSample] = []
var lap_start_time: float = 0.0
var sample_timer: float = 0.0
var collision_time_accumulated: float = 0.0
var recording_started_mid_lap: bool = false

# Track identification
var current_track_id: String = ""

# Debug overlay
var debug_label: Label

# ============================================================================
# INITIALIZATION
# ============================================================================

func _ready() -> void:
	# Wait for scene to stabilize
	await get_tree().process_frame
	await get_tree().process_frame
	
	_find_ship()
	_find_track()
	_setup_signals()
	_setup_debug_overlay()
	_ensure_save_directory()
	_load_existing_data()
	
	print("===========================================")
	print("AI Lap Recorder Ready!")
	print("  F4: Toggle recording (currently %s)" % ("ON" if is_recording else "OFF"))
	print("  Sample interval: %.3fs (%d samples/sec)" % [sample_interval, int(1.0 / sample_interval)])
	print("  Track: %s" % current_track_id)
	print("  Save path: %s" % save_path)
	if track_ai_data:
		print("  Existing laps: %d" % track_ai_data.recorded_laps.size())
	print("===========================================")

func _find_ship() -> void:
	if ship:
		return
	
	# Search for ShipController in scene
	ship = _find_node_of_type(get_tree().root, "ShipController") as ShipController
	
	if not ship:
		push_warning("AILapRecorder: No ship found! Set 'ship' export or ensure ShipController exists.")

func _find_track() -> void:
	# Find track root (node containing Path3D)
	var track_root := _find_track_root()
	
	if track_root:
		# Initialize spline helper
		spline_helper = TrackSplineHelper.new(track_root)
		
		if not spline_helper.is_valid:
			push_warning("AILapRecorder: Spline helper failed to initialize")
			spline_helper = null
	
	# Get track ID from GameManager
	if GameManager.selected_track_profile:
		current_track_id = GameManager.selected_track_profile.track_id
	else:
		current_track_id = "unknown_track"

func _find_track_root() -> Node:
	var root := get_tree().root
	return _find_node_with_path3d(root)

func _find_node_with_path3d(node: Node) -> Node:
	for child in node.get_children():
		if child is Path3D:
			return node
		var found := _find_node_with_path3d(child)
		if found:
			return found
	return null

func _find_node_of_type(node: Node, type_name: String) -> Node:
	if node.get_script() and node.get_script().get_global_name() == type_name:
		return node
	for child in node.get_children():
		var found := _find_node_of_type(child, type_name)
		if found:
			return found
	return null

func _setup_signals() -> void:
	# Connect to RaceManager signals
	if RaceManager.race_started.is_connected(_on_race_started):
		return
	
	RaceManager.race_started.connect(_on_race_started)
	RaceManager.lap_completed.connect(_on_lap_completed)
	RaceManager.race_finished.connect(_on_race_finished)
	RaceManager.endless_finished.connect(_on_endless_finished)

func _setup_debug_overlay() -> void:
	# Create a simple label for recording status
	var canvas := CanvasLayer.new()
	canvas.name = "RecorderOverlay"
	canvas.layer = 100
	add_child(canvas)
	
	debug_label = Label.new()
	debug_label.name = "RecordingStatus"
	debug_label.position = Vector2(20, 100)
	debug_label.add_theme_font_size_override("font_size", 18)
	debug_label.add_theme_color_override("font_color", Color.WHITE)
	debug_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	debug_label.add_theme_constant_override("shadow_offset_x", 2)
	debug_label.add_theme_constant_override("shadow_offset_y", 2)
	canvas.add_child(debug_label)

func _ensure_save_directory() -> void:
	if not DirAccess.dir_exists_absolute(save_path):
		DirAccess.make_dir_recursive_absolute(save_path)
		print("AILapRecorder: Created save directory: %s" % save_path)

func _load_existing_data() -> void:
	var data_path := _get_track_data_path()
	
	if ResourceLoader.exists(data_path):
		track_ai_data = load(data_path) as TrackAIData
		if track_ai_data:
			print("AILapRecorder: Loaded existing data with %d laps" % track_ai_data.recorded_laps.size())
			return
	
	# Create new TrackAIData
	track_ai_data = TrackAIData.new()
	track_ai_data.track_id = current_track_id
	print("AILapRecorder: Created new TrackAIData for '%s'" % current_track_id)

func _get_track_data_path() -> String:
	return save_path + current_track_id + "_ai_data.tres"

# ============================================================================
# INPUT HANDLING
# ============================================================================

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == toggle_key:
			toggle_recording()

# ============================================================================
# RECORDING CONTROL
# ============================================================================

func toggle_recording() -> void:
	if is_recording:
		stop_recording()
	else:
		start_recording()

func start_recording() -> void:
	if is_recording:
		return
	
	if not ship:
		push_warning("AILapRecorder: Cannot start recording - no ship!")
		return
	
	if not spline_helper or not spline_helper.is_valid:
		push_warning("AILapRecorder: Cannot start recording - no valid spline!")
		return
	
	is_recording = true
	recording_started_mid_lap = RaceManager.is_racing() and RaceManager.current_lap > 0
	
	# If we're mid-lap, we'll start fresh on next lap
	if recording_started_mid_lap:
		print("AILapRecorder: Recording enabled - will start capturing on next lap")
	else:
		_reset_lap_recording()
	
	recording_started.emit()
	print(">>> RECORDING STARTED")

func stop_recording() -> void:
	if not is_recording:
		return
	
	is_recording = false
	
	# Discard current incomplete lap
	if current_lap_samples.size() > 0:
		print("AILapRecorder: Discarded %d samples from incomplete lap" % current_lap_samples.size())
		current_lap_samples.clear()
	
	recording_stopped.emit()
	print(">>> RECORDING STOPPED")

func _reset_lap_recording() -> void:
	current_lap_samples.clear()
	lap_start_time = Time.get_ticks_msec() / 1000.0
	sample_timer = 0.0
	collision_time_accumulated = 0.0
	recording_started_mid_lap = false

# ============================================================================
# SAMPLE CAPTURE
# ============================================================================

func _physics_process(delta: float) -> void:
	_update_debug_overlay()
	
	if not is_recording or not ship or not spline_helper:
		return
	
	if not RaceManager.is_racing():
		return
	
	# Don't record if we started mid-lap (wait for next lap)
	if recording_started_mid_lap:
		return
	
	# Sample timer
	sample_timer += delta
	
	if sample_timer >= sample_interval:
		sample_timer -= sample_interval
		_capture_sample()
	
	# Track collision time (for quality filtering)
	# Note: This is a simplified check - you might want to enhance based on actual collision detection
	if ship.velocity.length() < 5.0 and ship.is_grounded:
		# Ship is nearly stopped while grounded - possible stuck/collision state
		collision_time_accumulated += delta

func _capture_sample() -> void:
	var sample := AIRacingSample.new()
	
	# Line data
	var world_pos := ship.global_position
	sample.world_position = world_pos
	sample.spline_offset = spline_helper.world_to_spline_offset(world_pos)
	sample.lateral_offset = spline_helper.calculate_lateral_offset(world_pos, sample.spline_offset)
	sample.speed = ship.velocity.length()
	sample.heading = -ship.global_transform.basis.z  # Forward direction
	
	# Control data
	sample.throttle = ship.throttle_input
	sample.brake = 0.0  # Ship controller doesn't have explicit brake
	sample.airbrake_left = ship.airbrake_left
	sample.airbrake_right = ship.airbrake_right
	sample.is_grounded = ship.is_grounded
	sample.is_boosting = false  # Would need to track this in ship controller
	
	current_lap_samples.append(sample)
	sample_recorded.emit(sample)

func _update_debug_overlay() -> void:
	if not debug_label:
		return
	
	var status_lines: Array[String] = []
	
	if is_recording:
		status_lines.append("[color=red]● REC[/color] AI Recording")
		
		if recording_started_mid_lap:
			status_lines.append("  Waiting for lap start...")
		else:
			status_lines.append("  Samples: %d" % current_lap_samples.size())
			status_lines.append("  Time: %.1fs" % ((Time.get_ticks_msec() / 1000.0) - lap_start_time))
		
		if track_ai_data:
			status_lines.append("  Saved laps: %d" % track_ai_data.recorded_laps.size())
	else:
		status_lines.append("[color=gray]○ OFF[/color] AI Recording (F4 to start)")
		if track_ai_data and track_ai_data.recorded_laps.size() > 0:
			status_lines.append("  Saved laps: %d" % track_ai_data.recorded_laps.size())
	
	debug_label.text = "\n".join(status_lines)

# ============================================================================
# LAP COMPLETION HANDLING
# ============================================================================

func _on_race_started() -> void:
	if is_recording:
		_reset_lap_recording()
		print("AILapRecorder: Race started - recording lap 1")
	elif auto_record:
		start_recording()

func _on_lap_completed(lap_number: int, lap_time: float) -> void:
	if not is_recording:
		return
	
	# If we started mid-lap, this is our cue to start fresh
	if recording_started_mid_lap:
		_reset_lap_recording()
		print("AILapRecorder: Now recording lap %d" % (lap_number + 1))
		return
	
	# Validate and save the completed lap
	_finalize_lap(lap_time)
	
	# Reset for next lap
	_reset_lap_recording()
	print("AILapRecorder: Now recording lap %d" % (lap_number + 1))

func _on_race_finished(_total_time: float, _best_lap: float) -> void:
	# Time trial finished - don't save incomplete lap
	if is_recording and current_lap_samples.size() > 0:
		print("AILapRecorder: Race finished - discarding incomplete lap")
		current_lap_samples.clear()

func _on_endless_finished(_total_laps: int, _total_time: float, _best_lap: float) -> void:
	# Endless mode finished - don't save incomplete lap
	if is_recording and current_lap_samples.size() > 0:
		print("AILapRecorder: Endless finished - discarding incomplete lap")
		current_lap_samples.clear()

func _finalize_lap(lap_time: float) -> void:
	# Validation checks
	if current_lap_samples.size() < 10:
		lap_discarded.emit("Too few samples (%d)" % current_lap_samples.size())
		print("AILapRecorder: Discarded lap - too few samples (%d)" % current_lap_samples.size())
		return
	
	if lap_time < min_valid_lap_time:
		lap_discarded.emit("Lap time too short (%.2fs)" % lap_time)
		print("AILapRecorder: Discarded lap - too short (%.2fs)" % lap_time)
		return
	
	if collision_time_accumulated > max_collision_time:
		lap_discarded.emit("Too much collision time (%.2fs)" % collision_time_accumulated)
		print("AILapRecorder: Discarded lap - too much collision (%.2fs)" % collision_time_accumulated)
		return
	
	# Create the recorded lap
	var recorded_lap := AIRecordedLap.new()
	recorded_lap.track_id = current_track_id
	recorded_lap.lap_time = lap_time
	recorded_lap.recording_date = Time.get_datetime_string_from_system()
	recorded_lap.recording_version = 1
	
	# Copy samples (create new array to avoid reference issues)
	recorded_lap.samples.assign(current_lap_samples)
	
	# Add to track data
	track_ai_data.add_recorded_lap(recorded_lap)
	
	lap_recorded.emit(recorded_lap)
	print("AILapRecorder: ✓ Recorded lap %.2fs (%d samples) - Total: %d laps" % [
		lap_time,
		recorded_lap.samples.size(),
		track_ai_data.recorded_laps.size()
	])
	
	# Auto-save
	if auto_save:
		save_data()

# ============================================================================
# DATA PERSISTENCE
# ============================================================================

func save_data() -> void:
	if not track_ai_data:
		push_warning("AILapRecorder: No data to save")
		return
	
	var path := _get_track_data_path()
	var error := ResourceSaver.save(track_ai_data, path)
	
	if error == OK:
		print("AILapRecorder: Saved to %s" % path)
	else:
		push_error("AILapRecorder: Failed to save - error %d" % error)

func load_data() -> void:
	_load_existing_data()

func clear_all_data() -> void:
	"""Nuclear option - clears all recorded data for current track."""
	if track_ai_data:
		track_ai_data.clear_all_laps()
		save_data()
		print("AILapRecorder: Cleared all data for '%s'" % current_track_id)

func remove_lap(index: int) -> void:
	"""Remove a specific lap by index."""
	if track_ai_data and index >= 0 and index < track_ai_data.recorded_laps.size():
		var lap := track_ai_data.recorded_laps[index]
		track_ai_data.remove_lap_at_index(index)
		print("AILapRecorder: Removed lap %d (%.2fs)" % [index, lap.lap_time])
		if auto_save:
			save_data()

# ============================================================================
# UTILITY
# ============================================================================

func get_lap_summary() -> Array[Dictionary]:
	"""Get summary of all recorded laps for UI display."""
	var summary: Array[Dictionary] = []
	
	if not track_ai_data:
		return summary
	
	for i in range(track_ai_data.recorded_laps.size()):
		var lap := track_ai_data.recorded_laps[i]
		summary.append({
			"index": i,
			"time": lap.lap_time,
			"time_formatted": RaceManager.format_time(lap.lap_time),
			"samples": lap.samples.size(),
			"date": lap.recording_date
		})
	
	return summary

func get_tier_distribution() -> Dictionary:
	"""Get count of laps in each skill tier."""
	if not track_ai_data:
		return {}
	
	track_ai_data.refresh_tiers()
	
	return {
		"fast": track_ai_data.fast_laps.size(),
		"good": track_ai_data.good_laps.size(),
		"median": track_ai_data.median_laps.size(),
		"slow": track_ai_data.slow_laps.size(),
		"safe": track_ai_data.safe_laps.size(),
		"total": track_ai_data.recorded_laps.size()
	}

func print_lap_summary() -> void:
	"""Print a formatted summary of all recorded laps."""
	var summary := get_lap_summary()
	var tiers := get_tier_distribution()
	
	print("\n=== AI Recording Summary: %s ===" % current_track_id)
	print("Total laps: %d" % tiers.get("total", 0))
	print("Tier distribution: Fast=%d, Good=%d, Median=%d, Slow=%d, Safe=%d" % [
		tiers.get("fast", 0),
		tiers.get("good", 0),
		tiers.get("median", 0),
		tiers.get("slow", 0),
		tiers.get("safe", 0)
	])
	print("\nAll laps:")
	for lap_info in summary:
		print("  #%d: %s (%d samples) - %s" % [
			lap_info.index,
			lap_info.time_formatted,
			lap_info.samples,
			lap_info.date
		])
	print("=============================================\n")
