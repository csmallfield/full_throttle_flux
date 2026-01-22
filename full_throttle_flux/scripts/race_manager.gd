extends Node

## Central race management singleton
## Handles timing, lap tracking, leaderboards, and race state
## Supports Time Trial, Endless, and Race modes
## Leaderboards are now per-track and per-mode
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

# Multi-ship signals (Race Mode)
signal ship_lap_completed(ship: Node3D, lap_number: int, lap_time: float)
signal ship_finished_race(ship: Node3D, position: int, total_time: float)
signal all_ships_finished()

# ============================================================================
# RACE MODE
# ============================================================================

enum RaceMode {
	TIME_TRIAL,
	ENDLESS,
	RACE  # Racing against AI
}

var current_mode: int = RaceMode.TIME_TRIAL

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
# TIMING DATA (Single-ship modes)
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
# MULTI-SHIP TRACKING (Race Mode)
# ============================================================================

## All ships participating in the race (including player)
var race_ships: Array[Node3D] = []

## The player's ship (for special handling)
var player_ship: Node3D = null

## Per-ship lap counts: ship -> lap_count
var ship_lap_counts: Dictionary = {}

## Per-ship lap start times: ship -> time
var ship_lap_start_times: Dictionary = {}

## Per-ship total race times (set when they finish): ship -> time
var ship_finish_times: Dictionary = {}

## Per-ship best lap times: ship -> time
var ship_best_laps: Dictionary = {}

## Per-ship all lap times: ship -> Array[float]
var ship_all_lap_times: Dictionary = {}

## Finish order (ships that have completed the race)
var finish_order: Array[Node3D] = []

## Number of ships that have finished
var ships_finished: int = 0

# ============================================================================
# LEADERBOARD DATA
# ============================================================================

const LEADERBOARD_SIZE := 10
const SAVE_PATH := "user://leaderboards_v2.json"

# Structure: { "track_id:mode": { "total_time": [...], "best_lap": [...] } }
# Each entry: { "initials": String, "time": float, "ship": String }
var leaderboards: Dictionary = {}

# ============================================================================
# INITIALIZATION
# ============================================================================

func _ready() -> void:
	load_leaderboards()

# ============================================================================
# MODE CONTROL
# ============================================================================

func set_mode(mode: int) -> void:
	current_mode = mode

func is_endless_mode() -> bool:
	return current_mode == RaceMode.ENDLESS

func is_time_trial_mode() -> bool:
	return current_mode == RaceMode.TIME_TRIAL

func is_race_mode() -> bool:
	return current_mode == RaceMode.RACE

# ============================================================================
# MULTI-SHIP REGISTRATION (Race Mode)
# ============================================================================

func register_race_ships(ships: Array[Node3D], player: Node3D = null) -> void:
	"""Register all ships participating in a race."""
	race_ships = ships
	player_ship = player
	
	# Initialize tracking dictionaries
	ship_lap_counts.clear()
	ship_lap_start_times.clear()
	ship_finish_times.clear()
	ship_best_laps.clear()
	ship_all_lap_times.clear()
	finish_order.clear()
	ships_finished = 0
	
	for ship in ships:
		ship_lap_counts[ship] = 0
		ship_lap_start_times[ship] = 0.0
		ship_best_laps[ship] = INF
		ship_all_lap_times[ship] = []
	
	print("RaceManager: Registered %d ships for race" % ships.size())

func get_ship_lap_count(ship: Node3D) -> int:
	"""Get current lap count for a ship."""
	return ship_lap_counts.get(ship, 0)

func get_ship_best_lap(ship: Node3D) -> float:
	"""Get best lap time for a ship."""
	return ship_best_laps.get(ship, INF)

func has_ship_finished(ship: Node3D) -> bool:
	"""Check if a ship has completed the race."""
	return ship in finish_order

func get_ship_finish_position(ship: Node3D) -> int:
	"""Get the finish position of a ship (1-indexed), or -1 if not finished."""
	var idx = finish_order.find(ship)
	return idx + 1 if idx >= 0 else -1

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
	
	# Initialize multi-ship lap start times
	if is_race_mode():
		for ship in race_ships:
			ship_lap_start_times[ship] = race_start_time
			ship_lap_counts[ship] = 1  # Starting lap 1
	
	race_started.emit()

func complete_lap(ship: Node3D = null) -> void:
	"""Complete a lap. In race mode, pass the ship that crossed the line."""
	if current_state != RaceState.RACING:
		return
	
	if is_race_mode() and ship != null:
		_complete_lap_for_ship(ship)
	else:
		_complete_lap_single_ship()

func _complete_lap_single_ship() -> void:
	"""Original single-ship lap completion logic."""
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

func _complete_lap_for_ship(ship: Node3D) -> void:
	"""Multi-ship lap completion for Race Mode."""
	if ship not in ship_lap_counts:
		push_warning("RaceManager: Unknown ship crossed finish line")
		return
	
	# Check if ship already finished
	if has_ship_finished(ship):
		return
	
	var current_time = Time.get_ticks_msec() / 1000.0
	var lap_start = ship_lap_start_times.get(ship, race_start_time)
	var lap_time = current_time - lap_start
	
	var current_ship_lap = ship_lap_counts[ship]
	
	# Store lap time
	var all_laps: Array = ship_all_lap_times.get(ship, [])
	all_laps.append(lap_time)
	ship_all_lap_times[ship] = all_laps
	
	# Update best lap
	if lap_time < ship_best_laps.get(ship, INF):
		ship_best_laps[ship] = lap_time
	
	# Emit per-ship lap completion
	ship_lap_completed.emit(ship, current_ship_lap, lap_time)
	
	# Also emit legacy signal for player ship (for HUD compatibility)
	# IMPORTANT: Update lap_times array BEFORE emitting signal, so HUD handlers
	# can read from the array if needed (matches Time Trial behavior)
	if ship == player_ship:
		lap_times.append(lap_time)
		if lap_time < best_lap_time:
			best_lap_time = lap_time
		current_lap = current_ship_lap + 1
		lap_completed.emit(current_ship_lap, lap_time)
	
	print("RaceManager: %s completed lap %d in %.3f" % [ship.name, current_ship_lap, lap_time])
	
	# Check if ship finished the race
	if current_ship_lap >= total_laps:
		_ship_finishes_race(ship, current_time)
	else:
		# Advance to next lap
		ship_lap_counts[ship] = current_ship_lap + 1
		ship_lap_start_times[ship] = current_time

func _ship_finishes_race(ship: Node3D, finish_time: float) -> void:
	"""Called when a ship completes all laps."""
	var total_time = finish_time - race_start_time
	ship_finish_times[ship] = total_time
	finish_order.append(ship)
	ships_finished += 1
	
	var position = ships_finished
	
	print("RaceManager: %s FINISHED in position %d with time %.3f" % [ship.name, position, total_time])
	
	ship_finished_race.emit(ship, position, total_time)
	
	# If player finished, emit legacy signal
	if ship == player_ship:
		current_race_time = total_time
		race_finished.emit(total_time, best_lap_time)
	
	# Check if all ships have finished
	if ships_finished >= race_ships.size():
		all_ships_finished.emit()
		current_state = RaceState.FINISHED

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
	
	# Reset multi-ship tracking
	race_ships.clear()
	player_ship = null
	ship_lap_counts.clear()
	ship_lap_start_times.clear()
	ship_finish_times.clear()
	ship_best_laps.clear()
	ship_all_lap_times.clear()
	finish_order.clear()
	ships_finished = 0

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
# RACE MODE QUERIES
# ============================================================================

func get_race_results() -> Array[Dictionary]:
	"""Get final race results sorted by finish position."""
	var results: Array[Dictionary] = []
	
	for i in range(finish_order.size()):
		var ship = finish_order[i]
		results.append({
			"position": i + 1,
			"ship": ship,
			"ship_name": ship.name,
			"is_player": ship == player_ship,
			"total_time": ship_finish_times.get(ship, INF),
			"best_lap": ship_best_laps.get(ship, INF),
			"all_laps": ship_all_lap_times.get(ship, [])
		})
	
	# Add DNF ships (didn't finish)
	for ship in race_ships:
		if ship not in finish_order:
			results.append({
				"position": -1,
				"ship": ship,
				"ship_name": ship.name,
				"is_player": ship == player_ship,
				"total_time": INF,
				"best_lap": ship_best_laps.get(ship, INF),
				"all_laps": ship_all_lap_times.get(ship, []),
				"dnf": true
			})
	
	return results

# ============================================================================
# LEADERBOARD KEY HELPERS
# ============================================================================

func _get_leaderboard_key(track_id: String, mode: String) -> String:
	return "%s:%s" % [track_id, mode]

func _get_current_leaderboard_key() -> String:
	var track_id = GameManager.selected_track_profile.track_id if GameManager.selected_track_profile else "unknown"
	var mode: String
	match current_mode:
		RaceMode.ENDLESS:
			mode = "endless"
		RaceMode.RACE:
			mode = "race"
		_:
			mode = "time_trial"
	return _get_leaderboard_key(track_id, mode)

func _ensure_leaderboard_exists(key: String) -> void:
	if not leaderboards.has(key):
		leaderboards[key] = {
			"total_time": [],
			"best_lap": []
		}

func _get_current_ship_name() -> String:
	if GameManager.selected_ship_profile:
		return GameManager.selected_ship_profile.display_name
	return "Unknown"

# ============================================================================
# LEADERBOARDS
# ============================================================================

func get_leaderboard(track_id: String, mode: String, category: String) -> Array:
	"""Get a specific leaderboard. category is 'total_time' or 'best_lap'"""
	var key = _get_leaderboard_key(track_id, mode)
	if not leaderboards.has(key):
		return []
	if not leaderboards[key].has(category):
		return []
	return leaderboards[key][category]

func get_all_leaderboard_keys() -> Array[String]:
	"""Get all track:mode combinations that have leaderboard data"""
	var keys: Array[String] = []
	for key in leaderboards.keys():
		keys.append(key)
	return keys

func get_all_possible_leaderboard_combos() -> Array[Dictionary]:
	"""Get all track/mode combinations from available tracks"""
	var combos: Array[Dictionary] = []
	for track in GameManager.available_tracks:
		var supported_modes = track.get_supported_modes()
		if "time_trial" in supported_modes:
			combos.append({
				"track_id": track.track_id,
				"track_name": track.display_name,
				"mode": "time_trial",
				"mode_name": "Time Trial"
			})
		if "endless" in supported_modes:
			combos.append({
				"track_id": track.track_id,
				"track_name": track.display_name,
				"mode": "endless",
				"mode_name": "Endless"
			})
		if "race" in supported_modes:
			combos.append({
				"track_id": track.track_id,
				"track_name": track.display_name,
				"mode": "race",
				"mode_name": "Race"
			})
	return combos

func check_leaderboard_qualification() -> Dictionary:
	"""Returns which leaderboards the current race qualifies for"""
	var result := {
		"total_time_qualified": false,
		"best_lap_qualified": false,
		"total_time_rank": -1,
		"best_lap_rank": -1
	}
	
	var key = _get_current_leaderboard_key()
	_ensure_leaderboard_exists(key)
	
	var total_time_board = leaderboards[key]["total_time"] as Array
	var best_lap_board = leaderboards[key]["best_lap"] as Array
	
	# Time trial and race mode: check both total time and best lap
	# Endless: only check best lap (and only if at least one lap completed)
	if current_mode == RaceMode.TIME_TRIAL or current_mode == RaceMode.RACE:
		# Check total time
		if total_time_board.size() < LEADERBOARD_SIZE:
			result.total_time_qualified = true
			result.total_time_rank = _get_insert_position(total_time_board, current_race_time)
		elif current_race_time < total_time_board[-1].time:
			result.total_time_qualified = true
			result.total_time_rank = _get_insert_position(total_time_board, current_race_time)
	
	# Check best lap (all modes, but endless needs at least one lap)
	if current_mode == RaceMode.ENDLESS and endless_all_lap_times.is_empty():
		return result
	
	if best_lap_board.size() < LEADERBOARD_SIZE:
		result.best_lap_qualified = true
		result.best_lap_rank = _get_insert_position(best_lap_board, best_lap_time)
	elif best_lap_time < best_lap_board[-1].time:
		result.best_lap_qualified = true
		result.best_lap_rank = _get_insert_position(best_lap_board, best_lap_time)
	
	return result

func _get_insert_position(leaderboard: Array, time: float) -> int:
	for i in range(leaderboard.size()):
		if time < leaderboard[i].time:
			return i
	return leaderboard.size()

func add_to_leaderboard(initials: String, total_time_qualified: bool, best_lap_qualified: bool) -> void:
	initials = initials.to_upper().substr(0, 3)
	var ship_name = _get_current_ship_name()
	var key = _get_current_leaderboard_key()
	_ensure_leaderboard_exists(key)
	
	if total_time_qualified:
		var entry := {"initials": initials, "time": current_race_time, "ship": ship_name}
		var board = leaderboards[key]["total_time"] as Array
		var pos = _get_insert_position(board, current_race_time)
		board.insert(pos, entry)
		
		if board.size() > LEADERBOARD_SIZE:
			board.resize(LEADERBOARD_SIZE)
	
	if best_lap_qualified:
		var entry := {"initials": initials, "time": best_lap_time, "ship": ship_name}
		var board = leaderboards[key]["best_lap"] as Array
		var pos = _get_insert_position(board, best_lap_time)
		board.insert(pos, entry)
		
		if board.size() > LEADERBOARD_SIZE:
			board.resize(LEADERBOARD_SIZE)
	
	save_leaderboards()

func erase_all_leaderboards() -> void:
	"""Nuclear option - clears ALL leaderboard data"""
	leaderboards.clear()
	save_leaderboards()
	print("RaceManager: All leaderboards erased")

# ============================================================================
# PERSISTENCE
# ============================================================================

func save_leaderboards() -> void:
	var file = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(leaderboards, "\t"))
		file.close()

func load_leaderboards() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		leaderboards = {}
		return
	
	var file = FileAccess.open(SAVE_PATH, FileAccess.READ)
	if not file:
		leaderboards = {}
		return
	
	var json_string = file.get_as_text()
	file.close()
	
	var json = JSON.new()
	var parse_result = json.parse(json_string)
	
	if parse_result != OK:
		print("RaceManager: Error parsing leaderboards JSON")
		leaderboards = {}
		return
	
	leaderboards = json.data if json.data is Dictionary else {}

# ============================================================================
# LEGACY COMPATIBILITY - Remove these if not needed elsewhere
# ============================================================================

# These provide backwards compatibility if anything still references the old arrays
var total_time_leaderboard: Array[Dictionary]:
	get:
		var key = _get_current_leaderboard_key()
		_ensure_leaderboard_exists(key)
		var result: Array[Dictionary] = []
		for entry in leaderboards[key]["total_time"]:
			result.append(entry)
		return result

var best_lap_leaderboard: Array[Dictionary]:
	get:
		var key = _get_current_leaderboard_key()
		_ensure_leaderboard_exists(key)
		var result: Array[Dictionary] = []
		for entry in leaderboards[key]["best_lap"]:
			result.append(entry)
		return result

# ============================================================================
# UTILITIES
# ============================================================================

static func format_time(time_seconds: float) -> String:
	"""Format time as MM:SS.mmm"""
	var minutes = int(time_seconds / 60.0)
	var seconds = int(time_seconds) % 60
	var milliseconds = int((time_seconds - int(time_seconds)) * 1000)
	
	return "%02d:%02d.%03d" % [minutes, seconds, milliseconds]
