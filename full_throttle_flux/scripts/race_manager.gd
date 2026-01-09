extends Node

## Central race management singleton
## Handles timing, lap tracking, leaderboards, and race state
## Supports both Time Trial and Endless modes
## NOTE: Music is now handled by MusicPlaylistManager, not here

# ============================================================================
# SIGNALS
# ============================================================================

signal countdown_tick(number: int)  # 3, 2, 1, 0 (GO)
signal race_started()
signal lap_completed(lap_number: int, lap_time: float)
signal race_finished(total_time: float, best_lap: float)
signal endless_finished(total_laps: int, total_time: float, best_lap: float)
signal wrong_way_warning()

# ============================================================================
# RACE MODE
# ============================================================================

enum RaceMode {
	TIME_TRIAL,
	ENDLESS
}

var current_mode: RaceMode = RaceMode.TIME_TRIAL

# ============================================================================
# RACE STATE
# ============================================================================

enum RaceState {
	NOT_STARTED,
	COUNTDOWN,
	RACING,
	FINISHED,
	PAUSED
}

var current_state: RaceState = RaceState.NOT_STARTED

# ============================================================================
# TIMING DATA
# ============================================================================

var current_lap: int = 0
var total_laps: int = 3
var race_start_time: float = 0.0
var lap_start_time: float = 0.0
var current_race_time: float = 0.0

# Lap times for current race
var lap_times: Array[float] = []
var best_lap_time: float = INF

# Endless mode specific - tracks all laps for summary
var endless_all_lap_times: Array[float] = []

# Pause tracking
var total_paused_time: float = 0.0
var pause_start_time: float = 0.0

# ============================================================================
# LEADERBOARD DATA
# ============================================================================

const LEADERBOARD_SIZE := 10
const SAVE_PATH := "user://leaderboards.json"

# Each entry: {initials: String, time: float}
var total_time_leaderboard: Array[Dictionary] = []
var best_lap_leaderboard: Array[Dictionary] = []

# ============================================================================
# INITIALIZATION
# ============================================================================

func _ready() -> void:
	load_leaderboards()

# ============================================================================
# MODE CONTROL
# ============================================================================

func set_mode(mode: RaceMode) -> void:
	current_mode = mode

func is_endless_mode() -> bool:
	return current_mode == RaceMode.ENDLESS

func is_time_trial_mode() -> bool:
	return current_mode == RaceMode.TIME_TRIAL

# ============================================================================
# RACE CONTROL
# ============================================================================

func start_countdown() -> void:
	if current_state != RaceState.NOT_STARTED:
		return
	
	current_state = RaceState.COUNTDOWN
	_run_countdown()

func _run_countdown() -> void:
	await get_tree().create_timer(1.0).timeout
	countdown_tick.emit(3)
	AudioManager.play_countdown_beep()
	
	await get_tree().create_timer(1.0).timeout
	countdown_tick.emit(2)
	AudioManager.play_countdown_beep()
	
	await get_tree().create_timer(1.0).timeout
	countdown_tick.emit(1)
	AudioManager.play_countdown_beep()
	
	await get_tree().create_timer(1.0).timeout
	countdown_tick.emit(0)  # GO!
	AudioManager.play_countdown_go()
	
	_start_race()

func _start_race() -> void:
	current_state = RaceState.RACING
	current_lap = 1
	lap_times.clear()
	endless_all_lap_times.clear()
	best_lap_time = INF
	total_paused_time = 0.0
	pause_start_time = 0.0
	
	race_start_time = Time.get_ticks_msec() / 1000.0
	lap_start_time = race_start_time
	
	# NOTE: Music is now started by race_controller.gd via MusicPlaylistManager
	# Do NOT call AudioManager.play_race_music() here
	
	race_started.emit()

func complete_lap() -> void:
	if current_state != RaceState.RACING:
		return
	
	var current_time = Time.get_ticks_msec() / 1000.0
	var lap_time = (current_time - lap_start_time) - total_paused_time
	
	if current_mode == RaceMode.ENDLESS:
		# Endless mode: keep rolling window of 5 laps for display
		endless_all_lap_times.append(lap_time)
		lap_times.append(lap_time)
		
		# Only keep last 5 for display
		while lap_times.size() > 5:
			lap_times.pop_front()
	else:
		# Time trial: keep all laps
		lap_times.append(lap_time)
	
	if lap_time < best_lap_time:
		best_lap_time = lap_time
	
	lap_completed.emit(current_lap, lap_time)
	
	current_lap += 1
	
	if current_mode == RaceMode.TIME_TRIAL and current_lap > total_laps:
		_finish_race()
	else:
		# Reset paused time for new lap
		lap_start_time = current_time
		total_paused_time = 0.0

func _finish_race() -> void:
	current_state = RaceState.FINISHED
	var current_time = Time.get_ticks_msec() / 1000.0
	current_race_time = (current_time - race_start_time) - total_paused_time
	
	race_finished.emit(current_race_time, best_lap_time)

func finish_endless() -> void:
	"""Called when player quits endless mode - emits summary data"""
	if current_mode != RaceMode.ENDLESS:
		return
	# Allow finishing from either RACING or PAUSED state
	if current_state != RaceState.RACING and current_state != RaceState.PAUSED:
		return
	
	current_state = RaceState.FINISHED
	var current_time = Time.get_ticks_msec() / 1000.0
	current_race_time = (current_time - race_start_time) - total_paused_time
	
	var completed_laps = endless_all_lap_times.size()
	endless_finished.emit(completed_laps, current_race_time, best_lap_time)

func reset_race() -> void:
	current_state = RaceState.NOT_STARTED
	current_lap = 0
	lap_times.clear()
	endless_all_lap_times.clear()
	best_lap_time = INF
	race_start_time = 0.0
	lap_start_time = 0.0
	current_race_time = 0.0
	total_paused_time = 0.0
	pause_start_time = 0.0

func pause_race() -> void:
	if current_state == RaceState.RACING:
		current_state = RaceState.PAUSED
		pause_start_time = Time.get_ticks_msec() / 1000.0
		get_tree().paused = true

func resume_race() -> void:
	if current_state == RaceState.PAUSED:
		current_state = RaceState.RACING
		var current_time = Time.get_ticks_msec() / 1000.0
		var pause_duration = current_time - pause_start_time
		total_paused_time += pause_duration
		get_tree().paused = false

# ============================================================================
# TIMING QUERIES
# ============================================================================

func get_current_race_time() -> float:
	if current_state == RaceState.RACING:
		var current_time = Time.get_ticks_msec() / 1000.0
		return (current_time - race_start_time) - total_paused_time
	elif current_state == RaceState.PAUSED:
		# When paused, return time at moment of pause
		return (pause_start_time - race_start_time) - total_paused_time
	return current_race_time

func get_current_lap_time() -> float:
	if current_state == RaceState.RACING:
		var current_time = Time.get_ticks_msec() / 1000.0
		return (current_time - lap_start_time) - total_paused_time
	elif current_state == RaceState.PAUSED:
		# When paused, return time at moment of pause
		return (pause_start_time - lap_start_time) - total_paused_time
	return 0.0

func is_racing() -> bool:
	return current_state == RaceState.RACING

func is_countdown() -> bool:
	return current_state == RaceState.COUNTDOWN

func is_finished() -> bool:
	return current_state == RaceState.FINISHED

## Get the best lap time among the currently displayed laps (for highlighting)
func get_best_displayed_lap_time() -> float:
	if lap_times.is_empty():
		return INF
	
	var best = INF
	for time in lap_times:
		if time < best:
			best = time
	return best

# ============================================================================
# LEADERBOARDS
# ============================================================================

func check_leaderboard_qualification() -> Dictionary:
	"""Returns which leaderboards the current race qualifies for"""
	var result := {
		"total_time_qualified": false,
		"best_lap_qualified": false,
		"total_time_rank": -1,
		"best_lap_rank": -1
	}
	
	# No leaderboard qualification in endless mode
	if current_mode == RaceMode.ENDLESS:
		return result
	
	# Check total time
	if total_time_leaderboard.size() < LEADERBOARD_SIZE or current_race_time < total_time_leaderboard[-1].time:
		result.total_time_qualified = true
		result.total_time_rank = _get_insert_position(total_time_leaderboard, current_race_time)
	
	# Check best lap
	if best_lap_leaderboard.size() < LEADERBOARD_SIZE or best_lap_time < best_lap_leaderboard[-1].time:
		result.best_lap_qualified = true
		result.best_lap_rank = _get_insert_position(best_lap_leaderboard, best_lap_time)
	
	return result

func _get_insert_position(leaderboard: Array[Dictionary], time: float) -> int:
	for i in range(leaderboard.size()):
		if time < leaderboard[i].time:
			return i
	return leaderboard.size()

func add_to_leaderboard(initials: String, total_time_qualified: bool, best_lap_qualified: bool) -> void:
	initials = initials.to_upper().substr(0, 3)
	
	if total_time_qualified:
		var entry := {"initials": initials, "time": current_race_time}
		var pos = _get_insert_position(total_time_leaderboard, current_race_time)
		total_time_leaderboard.insert(pos, entry)
		
		if total_time_leaderboard.size() > LEADERBOARD_SIZE:
			total_time_leaderboard.resize(LEADERBOARD_SIZE)
	
	if best_lap_qualified:
		var entry := {"initials": initials, "time": best_lap_time}
		var pos = _get_insert_position(best_lap_leaderboard, best_lap_time)
		best_lap_leaderboard.insert(pos, entry)
		
		if best_lap_leaderboard.size() > LEADERBOARD_SIZE:
			best_lap_leaderboard.resize(LEADERBOARD_SIZE)
	
	save_leaderboards()

# ============================================================================
# PERSISTENCE
# ============================================================================

func save_leaderboards() -> void:
	var data := {
		"total_time": total_time_leaderboard,
		"best_lap": best_lap_leaderboard
	}
	
	var file = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data, "\t"))
		file.close()

func load_leaderboards() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		_create_default_leaderboards()
		return
	
	var file = FileAccess.open(SAVE_PATH, FileAccess.READ)
	if not file:
		_create_default_leaderboards()
		return
	
	var json_string = file.get_as_text()
	file.close()
	
	var json = JSON.new()
	var parse_result = json.parse(json_string)
	
	if parse_result != OK:
		print("Error parsing leaderboards JSON")
		_create_default_leaderboards()
		return
	
	var data = json.data
	total_time_leaderboard.clear()
	best_lap_leaderboard.clear()
	
	if data.has("total_time"):
		for entry in data.total_time:
			total_time_leaderboard.append(entry)
	
	if data.has("best_lap"):
		for entry in data.best_lap:
			best_lap_leaderboard.append(entry)

func _create_default_leaderboards() -> void:
	total_time_leaderboard.clear()
	best_lap_leaderboard.clear()
	# Start with empty leaderboards
	save_leaderboards()

# ============================================================================
# UTILITIES
# ============================================================================

static func format_time(time_seconds: float) -> String:
	"""Format time as MM:SS.mmm"""
	var minutes = int(time_seconds / 60.0)
	var seconds = int(time_seconds) % 60
	var milliseconds = int((time_seconds - int(time_seconds)) * 1000)
	
	return "%02d:%02d.%03d" % [minutes, seconds, milliseconds]
