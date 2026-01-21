extends Node
class_name AIDebugTester

## AI Debug Tester
## Attach this to a race scene to test AI by pressing a key.
## Press F1 to toggle AI control of the player ship.
## Press F2 to cycle through skill levels.
## Press F3 to toggle debug visualization.
## Press F4 to toggle lap recording (handled by AILapRecorder).
## Press F5 to print AI data summary.

# ============================================================================
# CONFIGURATION
# ============================================================================

@export var ship: ShipController
@export var toggle_key: Key = KEY_F1
@export var skill_key: Key = KEY_F2
@export var debug_key: Key = KEY_F3
@export var summary_key: Key = KEY_F5

## Enable lap recording functionality
@export var enable_recording: bool = true

# ============================================================================
# STATE
# ============================================================================

var ai_controller: AIShipController
var lap_recorder: AILapRecorder
var track_ai_data: TrackAIData
var skill_levels: Array[float] = [0.0, 0.25, 0.5, 0.75, 1.0]
var current_skill_index := 2  # Start at 0.5

# ============================================================================
# INITIALIZATION
# ============================================================================

func _ready() -> void:
	# Wait for scene to be ready
	await get_tree().process_frame
	await get_tree().process_frame
	
	# Find ship if not set
	if not ship:
		ship = _find_ship()
	
	if not ship:
		push_warning("AIDebugTester: No ship found!")
		return
	
	# Load AI data for current track
	_load_ai_data()
	
	# Create AI controller
	_setup_ai_controller()
	
	# Setup lap recorder
	if enable_recording:
		_setup_lap_recorder()
	
	print("===========================================")
	print("AI Debug Tester Ready!")
	print("  F1: Toggle AI control")
	print("  F2: Cycle skill level (current: %.2f)" % skill_levels[current_skill_index])
	print("  F3: Toggle debug visualization")
	if enable_recording:
		print("  F4: Toggle lap recording")
	print("  F5: Print AI data summary")
	if track_ai_data:
		print("  AI Data: %d recorded laps loaded" % track_ai_data.recorded_laps.size())
	else:
		print("  AI Data: None (using geometric fallback)")
	print("===========================================")

func _find_ship() -> ShipController:
	"""Search for a ShipController in the scene."""
	return _find_node_of_type(get_tree().root, "ShipController") as ShipController

func _find_node_of_type(node: Node, type_name: String) -> Node:
	if node.get_class() == type_name or (node.get_script() and node.get_script().get_global_name() == type_name):
		return node
	for child in node.get_children():
		var found := _find_node_of_type(child, type_name)
		if found:
			return found
	return null

func _load_ai_data() -> void:
	"""Load recorded AI data for the current track."""
	var track_id := ""
	if GameManager.selected_track_profile:
		track_id = GameManager.selected_track_profile.track_id
	else:
		push_warning("AIDebugTester: No track profile selected")
		return
	
	track_ai_data = AIDataManager.load_track_ai_data(track_id)

func _setup_ai_controller() -> void:
	"""Create and configure the AI controller."""
	ai_controller = AIShipController.new()
	ai_controller.name = "AIDebugController"
	ai_controller.ship = ship
	ai_controller.skill_level = skill_levels[current_skill_index]
	ai_controller.ai_active = false  # Start disabled
	ai_controller.debug_draw_enabled = false
	ai_controller.debug_print_enabled = false
	
	add_child(ai_controller)
	
	# Wait a frame then initialize
	await get_tree().process_frame
	
	# Find track root (search for node containing Path3D)
	var track_root := _find_track_root()
	if track_root:
		# Pass the loaded AI data to the controller
		ai_controller.initialize(track_root, track_ai_data)
		print("AIDebugTester: AI controller initialized with track '%s'" % track_root.name)
		if track_ai_data:
			print("AIDebugTester: Using recorded data (%d laps)" % track_ai_data.recorded_laps.size())
		else:
			print("AIDebugTester: Using geometric fallback (no recorded data)")
	else:
		push_warning("AIDebugTester: Could not find track root for AI initialization")

func _setup_lap_recorder() -> void:
	"""Create and configure the lap recorder."""
	lap_recorder = AILapRecorder.new()
	lap_recorder.name = "AILapRecorder"
	lap_recorder.ship = ship
	lap_recorder.auto_record = false  # Manual toggle with F4
	
	add_child(lap_recorder)
	
	# Connect signals for feedback
	lap_recorder.lap_recorded.connect(_on_lap_recorded)
	lap_recorder.lap_discarded.connect(_on_lap_discarded)

func _find_track_root() -> Node:
	"""Find the track scene root."""
	# Search for common track parent patterns
	var root := get_tree().root
	
	# Look for nodes with Path3D children
	return _find_node_with_path3d(root)

func _find_node_with_path3d(node: Node) -> Node:
	for child in node.get_children():
		if child is Path3D:
			return node
		var found := _find_node_with_path3d(child)
		if found:
			return found
	return null

# ============================================================================
# INPUT HANDLING
# ============================================================================

func _input(event: InputEvent) -> void:
	if not ai_controller:
		return
	
	if event is InputEventKey and event.pressed:
		match event.keycode:
			toggle_key:
				_toggle_ai()
			skill_key:
				_cycle_skill()
			debug_key:
				_toggle_debug()
			summary_key:
				_print_summary()

func _toggle_ai() -> void:
	"""Toggle AI control on/off."""
	ai_controller.toggle_ai()
	
	if ai_controller.ai_active:
		print(">>> AI ENABLED (Skill: %.2f)" % ai_controller.skill_level)
	else:
		print(">>> AI DISABLED - Player control restored")

func _cycle_skill() -> void:
	"""Cycle through skill levels."""
	current_skill_index = (current_skill_index + 1) % skill_levels.size()
	var new_skill := skill_levels[current_skill_index]
	ai_controller.set_skill(new_skill)
	print(">>> AI Skill: %.2f" % new_skill)

func _toggle_debug() -> void:
	"""Toggle debug visualization."""
	ai_controller.debug_draw_enabled = not ai_controller.debug_draw_enabled
	ai_controller.debug_print_enabled = ai_controller.debug_draw_enabled
	
	if ai_controller.debug_draw_enabled:
		print(">>> Debug visualization ENABLED")
		# Re-setup debug visuals
		ai_controller._setup_debug_visualization()
	else:
		print(">>> Debug visualization DISABLED")

func _print_summary() -> void:
	"""Print AI data summary for current track."""
	if lap_recorder:
		lap_recorder.print_lap_summary()
	else:
		var track_id := ""
		if GameManager.selected_track_profile:
			track_id = GameManager.selected_track_profile.track_id
		var summary := AIDataManager.get_data_summary(track_id)
		
		print("\n=== AI Data Summary ===")
		if summary.exists:
			print("Track: %s" % summary.track_id)
			print("Source: %s" % summary.source)
			print("Laps: %d" % summary.total_laps)
			print("Best: %.2fs, Avg: %.2fs, Worst: %.2fs" % [
				summary.best_time, summary.avg_time, summary.worst_time
			])
		else:
			print("No AI data for track")
		print("======================\n")

# ============================================================================
# RECORDING CALLBACKS
# ============================================================================

func _on_lap_recorded(lap: AIRecordedLap) -> void:
	"""Called when a lap is successfully recorded."""
	print(">>> LAP RECORDED: %.2fs (%d samples)" % [lap.lap_time, lap.samples.size()])
	
	# Reload AI data so the controller can use the new lap
	_reload_ai_data()

func _on_lap_discarded(reason: String) -> void:
	"""Called when a lap is discarded."""
	print(">>> LAP DISCARDED: %s" % reason)

func _reload_ai_data() -> void:
	"""Reload AI data after new recordings."""
	_load_ai_data()
	
	# Update the AI controller with new data
	if ai_controller and ai_controller.line_follower and track_ai_data:
		ai_controller.line_follower.track_ai_data = track_ai_data
		ai_controller.line_follower.has_recorded_data = track_ai_data.has_recorded_data()
		print("AIDebugTester: Reloaded AI data (%d laps)" % track_ai_data.recorded_laps.size())

# ============================================================================
# HUD OVERLAY
# ============================================================================

func _process(_delta: float) -> void:
	# Could add a HUD overlay here showing AI status
	pass
