extends RefCounted
class_name RacePositionTracker

## Race Position Tracker
## Calculates real-time race positions for all ships based on:
## - Laps completed
## - Position along track (spline offset 0-1)
##
## Position = (laps_completed * 1.0) + spline_offset
## Higher progress = further ahead in race

# ============================================================================
# SIGNALS
# ============================================================================

signal positions_updated(positions: Array[Dictionary])
signal position_changed(ship: Node3D, old_position: int, new_position: int)

# ============================================================================
# CONFIGURATION
# ============================================================================

## How often to update positions (seconds)
var update_interval: float = 0.1

# ============================================================================
# STATE
# ============================================================================

var spline_helper: TrackSplineHelper
var tracked_ships: Array[Node3D] = []
var player_ship: Node3D = null

## Current positions: Array of { ship, position, progress, lap, spline_offset }
var current_positions: Array[Dictionary] = []

## Previous positions for change detection: ship -> position
var previous_positions: Dictionary = {}

var _update_timer: float = 0.0
var _is_initialized: bool = false

# ============================================================================
# INITIALIZATION
# ============================================================================

func initialize(track_root: Node, ships: Array[Node3D], player: Node3D = null) -> bool:
	"""Initialize the tracker with track and ships."""
	# Create spline helper for track position calculation
	spline_helper = TrackSplineHelper.new(track_root)
	
	if not spline_helper.is_valid:
		push_error("RacePositionTracker: Failed to initialize spline helper")
		return false
	
	tracked_ships = ships
	player_ship = player
	
	# Initialize position tracking
	current_positions.clear()
	previous_positions.clear()
	
	for i in range(ships.size()):
		var ship = ships[i]
		current_positions.append({
			"ship": ship,
			"position": i + 1,
			"progress": 0.0,
			"lap": 1,
			"spline_offset": 0.0
		})
		previous_positions[ship] = i + 1
	
	_is_initialized = true
	print("RacePositionTracker: Initialized with %d ships" % ships.size())
	return true

# ============================================================================
# UPDATE
# ============================================================================

func update(delta: float) -> void:
	"""Call this every frame to update positions."""
	if not _is_initialized:
		return
	
	_update_timer += delta
	
	if _update_timer >= update_interval:
		_update_timer = 0.0
		_calculate_positions()

func _calculate_positions() -> void:
	"""Recalculate all ship positions."""
	if not spline_helper or not spline_helper.is_valid:
		return
	
	# Calculate progress for each ship
	for entry in current_positions:
		var ship: Node3D = entry.ship
		
		if not is_instance_valid(ship):
			continue
		
		# Get lap count from RaceManager
		var lap_count: int = RaceManager.get_ship_lap_count(ship)
		
		# Check if ship has finished
		if RaceManager.has_ship_finished(ship):
			# Finished ships get maximum progress based on finish position
			# This keeps them sorted correctly at the top
			var finish_pos = RaceManager.get_ship_finish_position(ship)
			entry.progress = 1000.0 - finish_pos  # Finished ships always ahead
			entry.lap = RaceManager.total_laps
			entry.spline_offset = 1.0
		else:
			# Get spline offset (0-1 position along track)
			var spline_offset: float = spline_helper.world_to_spline_offset(ship.global_position)
			
			# Calculate total progress
			# Lap count starts at 1, so subtract 1 for the formula
			var progress: float = float(lap_count - 1) + spline_offset
			
			entry.progress = progress
			entry.lap = lap_count
			entry.spline_offset = spline_offset
	
	# Sort by progress (descending - highest progress = first place)
	current_positions.sort_custom(_compare_progress)
	
	# Assign positions and detect changes
	for i in range(current_positions.size()):
		var entry = current_positions[i]
		var new_position = i + 1
		var ship = entry.ship
		
		var old_position = previous_positions.get(ship, new_position)
		
		if new_position != old_position:
			entry.position = new_position
			position_changed.emit(ship, old_position, new_position)
			previous_positions[ship] = new_position
		else:
			entry.position = new_position
	
	positions_updated.emit(current_positions)

func _compare_progress(a: Dictionary, b: Dictionary) -> bool:
	"""Sort comparison - higher progress first."""
	return a.progress > b.progress

# ============================================================================
# QUERIES
# ============================================================================

func get_position(ship: Node3D) -> int:
	"""Get current race position for a ship (1-indexed)."""
	for entry in current_positions:
		if entry.ship == ship:
			return entry.position
	return -1

func get_player_position() -> int:
	"""Get current race position for the player."""
	if player_ship:
		return get_position(player_ship)
	return -1

func get_positions() -> Array[Dictionary]:
	"""Get all current positions."""
	return current_positions

func get_ship_at_position(position: int) -> Node3D:
	"""Get the ship at a given position (1-indexed)."""
	if position < 1 or position > current_positions.size():
		return null
	return current_positions[position - 1].ship

func get_ship_progress(ship: Node3D) -> Dictionary:
	"""Get detailed progress info for a ship."""
	for entry in current_positions:
		if entry.ship == ship:
			return entry
	return {}

func get_gap_to_leader(ship: Node3D) -> float:
	"""Get the progress gap between a ship and the leader."""
	if current_positions.is_empty():
		return 0.0
	
	var leader_progress = current_positions[0].progress
	
	for entry in current_positions:
		if entry.ship == ship:
			return leader_progress - entry.progress
	
	return 0.0

func get_gap_to_ship_ahead(ship: Node3D) -> float:
	"""Get the progress gap between a ship and the ship directly ahead."""
	var ship_position = get_position(ship)
	
	if ship_position <= 1:
		return 0.0  # Already in first
	
	var ahead_entry = current_positions[ship_position - 2]  # -1 for 0-index, -1 for ahead
	
	for entry in current_positions:
		if entry.ship == ship:
			return ahead_entry.progress - entry.progress
	
	return 0.0

# ============================================================================
# FORMATTING
# ============================================================================

func format_position(position: int) -> String:
	"""Format position with ordinal suffix (1st, 2nd, 3rd, etc.)."""
	if position < 1:
		return "?"
	
	var suffix: String
	
	if position == 1:
		suffix = "st"
	elif position == 2:
		suffix = "nd"
	elif position == 3:
		suffix = "rd"
	else:
		suffix = "th"
	
	return "%d%s" % [position, suffix]

func format_position_short(position: int) -> String:
	"""Format position as P1, P2, P3, etc."""
	if position < 1:
		return "P?"
	return "P%d" % position

# ============================================================================
# DEBUG
# ============================================================================

func get_debug_info() -> String:
	var lines: Array[String] = []
	lines.append("=== Race Positions ===")
	
	for entry in current_positions:
		var ship_name = entry.ship.name if is_instance_valid(entry.ship) else "INVALID"
		var is_player = " [PLAYER]" if entry.ship == player_ship else ""
		var finished = " FINISHED" if RaceManager.has_ship_finished(entry.ship) else ""
		
		lines.append("P%d: %s - Lap %d, Progress %.3f%s%s" % [
			entry.position,
			ship_name,
			entry.lap,
			entry.progress,
			is_player,
			finished
		])
	
	return "\n".join(lines)

func print_positions() -> void:
	print(get_debug_info())
