extends ModeBase
class_name RaceMode

## Race Mode
## Player races against AI opponents on a track.
## Spawns player + AI ships, manages race state, tracks positions.

# ============================================================================
# CONFIGURATION
# ============================================================================

@export_group("Race Settings")

## Number of laps to complete (hardcoded to 3)
@export var num_laps: int = 3

## Number of AI opponents (hardcoded to 7)
@export_range(1, 7) var num_ai_opponents: int = 7

## AI difficulty preset
enum Difficulty { EASY, MEDIUM, HARD }
@export var difficulty: Difficulty = Difficulty.MEDIUM

@export_group("AI Skill Ranges")

## Skill range for Easy difficulty
@export var easy_skill_range := Vector2(0.20, 0.40)

## Skill range for Medium difficulty
@export var medium_skill_range := Vector2(0.40, 0.60)

## Skill range for Hard difficulty
@export var hard_skill_range := Vector2(0.60, 0.80)

# ============================================================================
# RACE STATE
# ============================================================================

## All ships in the race (player + AI)
var all_ships: Array[Node3D] = []

## AI ships only
var ai_ships: Array[Node3D] = []

## AI controllers for each AI ship
var ai_controllers: Array[AIShipController] = []

## Position tracker
var position_tracker: RacePositionTracker

## Track AI data for AI opponents
var track_ai_data: TrackAIData

## Player's finishing position (1-indexed)
var player_finish_position: int = -1

# ============================================================================
# UI INSTANCES
# ============================================================================

var race_hud: CanvasLayer
var debug_hud: CanvasLayer
var pause_menu: CanvasLayer
var results_screen: CanvasLayer
var now_playing_display: Node

# ============================================================================
# SCRIPTS (loaded once)
# ============================================================================

var hud_race_script: Script
var debug_hud_script: Script
var pause_menu_script: Script
var results_screen_script: Script

# ============================================================================
# OVERRIDES
# ============================================================================

func get_mode_id() -> String:
	return "race"

func get_hud_config() -> Dictionary:
	return {
		"show_speedometer": true,
		"show_lap_timer": true,
		"show_lap_counter": true,
		"show_countdown": true,
		"show_position": true,  # Race-specific: show P1, P2, etc.
		"total_racers": num_ai_opponents + 1
	}

# ============================================================================
# SETUP
# ============================================================================

func _ready() -> void:
	_load_ui_scripts()

func _load_ui_scripts() -> void:
	hud_race_script = load("res://scripts/hud_race.gd")
	debug_hud_script = load("res://scripts/debug_hud.gd")
	pause_menu_script = load("res://scripts/pause_menu.gd")
	results_screen_script = load("res://scripts/results_screen.gd")

func setup_race() -> void:
	print("RaceMode: Setting up race with %d AI opponents..." % num_ai_opponents)
	
	# Configure RaceManager for race mode
	RaceManager.set_mode(RaceManager.RaceMode.RACE)
	RaceManager.total_laps = num_laps
	RaceManager.reset_race()
	
	# Load track AI data
	_load_track_ai_data()
	
	# Load track (from parent)
	await _load_track()
	
	# Spawn all ships (player + AI)
	await _spawn_all_ships()
	
	# Initialize position tracker
	_setup_position_tracker()
	
	# Register ships with RaceManager
	var ships_array: Array[Node3D] = []
	ships_array.assign(all_ships)
	RaceManager.register_race_ships(ships_array, ship_instance)
	
	# Setup camera (follows player)
	_setup_camera()
	
	# Setup UI
	_setup_race_hud()
	_setup_debug_hud()
	_setup_pause_menu()
	_setup_results_screen()
	_setup_now_playing()
	
	# Connect signals
	_connect_race_signals()
	
	mode_ready.emit()
	print("RaceMode: Setup complete - %d ships on grid" % all_ships.size())

func _load_track_ai_data() -> void:
	"""Load AI training data for the current track."""
	var track_profile = GameManager.get_selected_track()
	if not track_profile:
		push_warning("RaceMode: No track profile, AI will use geometric fallback")
		return
	
	track_ai_data = AIDataManager.load_track_ai_data(track_profile.track_id)
	
	if track_ai_data:
		print("RaceMode: Loaded AI data - %d recorded laps" % track_ai_data.recorded_laps.size())
	else:
		print("RaceMode: No AI data found, AI will use geometric fallback")

# ============================================================================
# SHIP SPAWNING
# ============================================================================

func _spawn_all_ships() -> void:
	"""Spawn player ship and AI opponents."""
	all_ships.clear()
	ai_ships.clear()
	ai_controllers.clear()
	
	# Spawn player at pole position (grid slot 0)
	await _spawn_player_ship()
	
	# Spawn AI ships at remaining grid positions
	for i in range(num_ai_opponents):
		var grid_position = i + 1  # AI starts at position 1
		var skill = _calculate_ai_skill(i)
		await _spawn_ai_ship(grid_position, skill)
	
	print("RaceMode: Spawned %d total ships (1 player + %d AI)" % [all_ships.size(), ai_ships.size()])

func _spawn_player_ship() -> void:
	"""Spawn the player's ship at pole position."""
	var ship_profile = GameManager.get_selected_ship()
	
	# Load ship scene
	var ship_scene_path = "res://scenes/ships/%s.tscn" % ship_profile.ship_id
	if not ResourceLoader.exists(ship_scene_path):
		ship_scene_path = "res://scenes/ships/default_racer.tscn"
	
	var ship_scene = load(ship_scene_path)
	ship_instance = ship_scene.instantiate()
	ship_instance.name = "Player_Ship"
	
	# Apply profile
	if ship_instance is ShipController:
		ship_instance.profile = ship_profile
	
	add_child(ship_instance)
	
	# Position at pole
	if starting_grid:
		ship_instance.global_transform = starting_grid.get_start_transform(0)
	
	# Lock controls until race starts
	if ship_instance.has_method("lock_controls"):
		ship_instance.lock_controls()
	
	all_ships.append(ship_instance)
	print("RaceMode: Player ship spawned at pole position")

func _spawn_ai_ship(grid_position: int, skill: float) -> void:
	"""Spawn an AI-controlled ship at the given grid position."""
	var ship_profile = GameManager.get_selected_ship()  # Use same ship for now
	
	# Load ship scene
	var ship_scene_path = "res://scenes/ships/default_racer.tscn"
	var ship_scene = load(ship_scene_path)
	var ai_ship = ship_scene.instantiate()
	ai_ship.name = "AI_Ship_%d" % grid_position
	
	# Apply profile
	if ai_ship is ShipController:
		ai_ship.profile = ship_profile
		ai_ship.ai_controlled = true  # Mark as AI controlled
	
	add_child(ai_ship)
	
	# Position on grid
	if starting_grid:
		ai_ship.global_transform = starting_grid.get_start_transform(grid_position)
	
	# Lock controls until race starts
	if ai_ship.has_method("lock_controls"):
		ai_ship.lock_controls()
	
	# Create and attach AI controller
	var ai_controller = AIShipController.new()
	ai_controller.name = "AIController_%d" % grid_position
	ai_controller.ship = ai_ship
	ai_controller.skill_level = skill
	ai_controller.ai_active = false  # Activate after countdown
	ai_controller.debug_draw_enabled = false  # Disable debug visualization
	ai_ship.add_child(ai_controller)
	
	# Initialize AI with track data
	ai_controller.initialize(track_instance, track_ai_data)
	
	all_ships.append(ai_ship)
	ai_ships.append(ai_ship)
	ai_controllers.append(ai_controller)
	
	print("RaceMode: AI ship %d spawned at grid position %d (skill: %.2f)" % [
		grid_position, grid_position, skill
	])

func _calculate_ai_skill(ai_index: int) -> float:
	"""Calculate skill level for an AI based on difficulty and position."""
	var skill_range: Vector2
	
	match difficulty:
		Difficulty.EASY:
			skill_range = easy_skill_range
		Difficulty.MEDIUM:
			skill_range = medium_skill_range
		Difficulty.HARD:
			skill_range = hard_skill_range
	
	# Distribute skills across the range
	# First AI (index 0) gets top of range, last AI gets bottom
	if num_ai_opponents <= 1:
		return (skill_range.x + skill_range.y) / 2.0
	
	var t = float(ai_index) / float(num_ai_opponents - 1)
	
	# Invert t so first AI is fastest
	t = 1.0 - t
	
	return lerp(skill_range.x, skill_range.y, t)

# ============================================================================
# POSITION TRACKING
# ============================================================================

func _setup_position_tracker() -> void:
	"""Initialize the position tracking system."""
	position_tracker = RacePositionTracker.new()
	
	var ships_array: Array[Node3D] = []
	ships_array.assign(all_ships)
	
	if not position_tracker.initialize(track_instance, ships_array, ship_instance):
		push_error("RaceMode: Failed to initialize position tracker")
		return
	
	# Connect signals
	position_tracker.position_changed.connect(_on_position_changed)
	
	print("RaceMode: Position tracker initialized")

func _on_position_changed(ship: Node3D, old_pos: int, new_pos: int) -> void:
	"""Handle position changes."""
	if ship == ship_instance:
		print("RaceMode: Player moved from P%d to P%d" % [old_pos, new_pos])
		# Could play sound effect here

# ============================================================================
# UI SETUP
# ============================================================================

func _setup_race_hud() -> void:
	# Remove parent's HUD if it loaded one
	if hud_instance:
		hud_instance.queue_free()
		hud_instance = null
	
	# Create HUD CanvasLayer with script
	race_hud = CanvasLayer.new()
	race_hud.name = "HUD"
	
	if hud_race_script:
		race_hud.set_script(hud_race_script)
	
	add_child(race_hud)
	
	# Connect to ship
	if ship_instance and "ship" in race_hud:
		race_hud.ship = ship_instance
	
	# Pass position tracker reference if HUD supports it
	if "position_tracker" in race_hud:
		race_hud.position_tracker = position_tracker
	
	# Pass race mode flag
	if "is_race_mode" in race_hud:
		race_hud.is_race_mode = true
	
	if "total_racers" in race_hud:
		race_hud.total_racers = all_ships.size()
	
	print("RaceMode: Race HUD created")

func _setup_debug_hud() -> void:
	debug_hud = CanvasLayer.new()
	debug_hud.name = "DebugHUD"
	
	if debug_hud_script:
		debug_hud.set_script(debug_hud_script)
	
	add_child(debug_hud)
	
	if ship_instance and "ship" in debug_hud:
		debug_hud.ship = ship_instance
	
	print("RaceMode: Debug HUD created")

func _setup_pause_menu() -> void:
	pause_menu = CanvasLayer.new()
	pause_menu.name = "PauseMenu"
	
	if pause_menu_script:
		pause_menu.set_script(pause_menu_script)
	
	add_child(pause_menu)
	
	if debug_hud and "debug_hud" in pause_menu:
		pause_menu.debug_hud = debug_hud
	
	print("RaceMode: Pause menu created")

func _setup_results_screen() -> void:
	results_screen = CanvasLayer.new()
	results_screen.name = "ResultsScreen"
	
	if results_screen_script:
		results_screen.set_script(results_screen_script)
	
	add_child(results_screen)
	
	print("RaceMode: Results screen created")

func _setup_now_playing() -> void:
	var now_playing_path = "res://scenes/now_playing_display.tscn"
	if ResourceLoader.exists(now_playing_path):
		var scene = load(now_playing_path)
		now_playing_display = scene.instantiate()
		add_child(now_playing_display)
		print("RaceMode: Now playing display created")

# ============================================================================
# SIGNAL CONNECTIONS
# ============================================================================

func _connect_race_signals() -> void:
	# Disconnect existing
	_disconnect_race_signals()
	
	# Connect new
	RaceManager.race_started.connect(_on_race_manager_started)
	RaceManager.countdown_tick.connect(_on_countdown_tick)
	RaceManager.race_finished.connect(_on_race_manager_finished)
	RaceManager.ship_finished_race.connect(_on_ship_finished)
	RaceManager.all_ships_finished.connect(_on_all_ships_finished)
	RaceManager.lap_completed.connect(_on_lap_completed)

func _disconnect_race_signals() -> void:
	if RaceManager.race_started.is_connected(_on_race_manager_started):
		RaceManager.race_started.disconnect(_on_race_manager_started)
	if RaceManager.countdown_tick.is_connected(_on_countdown_tick):
		RaceManager.countdown_tick.disconnect(_on_countdown_tick)
	if RaceManager.race_finished.is_connected(_on_race_manager_finished):
		RaceManager.race_finished.disconnect(_on_race_manager_finished)
	if RaceManager.ship_finished_race.is_connected(_on_ship_finished):
		RaceManager.ship_finished_race.disconnect(_on_ship_finished)
	if RaceManager.all_ships_finished.is_connected(_on_all_ships_finished):
		RaceManager.all_ships_finished.disconnect(_on_all_ships_finished)
	if RaceManager.lap_completed.is_connected(_on_lap_completed):
		RaceManager.lap_completed.disconnect(_on_lap_completed)

# ============================================================================
# RACE FLOW
# ============================================================================

func start_countdown() -> void:
	print("RaceMode: Starting countdown via RaceManager")
	RaceManager.start_countdown()

func _do_countdown() -> void:
	# Override to do nothing - RaceManager handles countdown
	pass

func _on_countdown_tick(number: int) -> void:
	print("RaceMode: Countdown %d" % number)
	
	# Keep all ships locked during countdown
	if number > 0:
		for ship in all_ships:
			if ship.has_method("lock_controls"):
				ship.lock_controls()
			ship.velocity = Vector3.ZERO

func _on_race_manager_started() -> void:
	print("RaceMode: Race started!")
	is_race_active = true
	
	# Unlock player ship
	if ship_instance and ship_instance.has_method("unlock_controls"):
		ship_instance.unlock_controls()
	
	# Activate AI controllers
	for controller in ai_controllers:
		controller.ai_active = true
		controller.enable_ai()
	
	# Start music
	MusicPlaylistManager.start_race_music()
	
	race_started.emit()

func _on_lap_completed(lap_number: int, lap_time: float) -> void:
	"""Handle player lap completion."""
	print("RaceMode: Player completed lap %d in %.3f" % [lap_number, lap_time])
	
	# Play lap complete sound (already handled in StartFinishLine for player)
	
	# Final lap warning
	if lap_number == num_laps - 1:
		AudioManager.play_final_lap()

func _on_ship_finished(ship: Node3D, position: int, total_time: float) -> void:
	"""Handle any ship finishing the race."""
	print("RaceMode: %s finished in position %d (%.3f)" % [ship.name, position, total_time])
	
	# Track player's finishing position
	if ship == ship_instance:
		player_finish_position = position
	
	# If an AI ship finished, disable its controller
	if ship != ship_instance:
		for i in range(ai_ships.size()):
			if ai_ships[i] == ship:
				ai_controllers[i].ai_active = false
				break

func _on_race_manager_finished(total_time: float, best_lap: float) -> void:
	"""Handle player finishing the race."""
	print("RaceMode: Player finished in P%d! Total: %.3f, Best lap: %.3f" % [player_finish_position, total_time, best_lap])
	
	# Lock player ship
	if ship_instance and ship_instance.has_method("lock_controls"):
		ship_instance.lock_controls()
	
	# Play finish sound
	AudioManager.play_race_finish()

func _on_all_ships_finished() -> void:
	"""Handle all ships completing the race."""
	print("RaceMode: All ships finished!")
	is_race_active = false
	
	# Disable all AI
	for controller in ai_controllers:
		controller.ai_active = false
	
	# Fade out music
	MusicPlaylistManager.stop_music(true)
	
	# Get final results
	var results = RaceManager.get_race_results()
	
	race_finished.emit({
		"results": results,
		"player_position": player_finish_position,
		"total_time": RaceManager.current_race_time,
		"best_lap": RaceManager.best_lap_time
	})

# ============================================================================
# PROCESS
# ============================================================================

func _process(delta: float) -> void:
	super._process(delta)
	
	# Update position tracker
	if position_tracker and is_race_active:
		position_tracker.update(delta)
	
	# Debug: Print positions periodically
	if is_race_active and Engine.get_process_frames() % 300 == 0:
		if position_tracker:
			position_tracker.print_positions()

# ============================================================================
# INPUT
# ============================================================================

func _input(event: InputEvent) -> void:
	if not is_race_active:
		return
	
	# Handle pause
	if event.is_action_pressed("ui_cancel"):
		if RaceManager.is_racing() and pause_menu:
			if pause_menu.has_method("show_pause"):
				pause_menu.show_pause()
			get_viewport().set_input_as_handled()

# ============================================================================
# CLEANUP
# ============================================================================

func cleanup() -> void:
	# Disconnect signals
	_disconnect_race_signals()
	
	# Cleanup AI controllers
	for controller in ai_controllers:
		if is_instance_valid(controller):
			controller.queue_free()
	ai_controllers.clear()
	
	# Cleanup AI ships
	for ship in ai_ships:
		if is_instance_valid(ship):
			ship.queue_free()
	ai_ships.clear()
	all_ships.clear()
	
	# Cleanup UI
	if race_hud:
		race_hud.queue_free()
	if debug_hud:
		debug_hud.queue_free()
	if pause_menu:
		pause_menu.queue_free()
	if results_screen:
		results_screen.queue_free()
	if now_playing_display:
		now_playing_display.queue_free()
	
	# Cleanup position tracker
	position_tracker = null
	
	# Call parent cleanup
	super.cleanup()
