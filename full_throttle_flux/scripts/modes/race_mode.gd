extends ModeBase
class_name RaceMode

## Race Mode
## Player races against AI opponents on a track.
## Spawns player + AI ships, manages race state, tracks positions.
##
## v2: Added ship-to-ship avoidance integration
## v3: Added random hull colors for AI ships (using find_child for robustness)
## v4: Bakes a shared BakedRacingLine (optimized line + speed profile) once
##     per race and hands it to every AI controller; skill ranges raised so
##     Hard actually reaches skill 1.0 (previously capped at 0.80, which
##     meant the expert tuning never ran in real races)

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
@export var easy_skill_range := Vector2(0.25, 0.45)

## Skill range for Medium difficulty
@export var medium_skill_range := Vector2(0.50, 0.72)

## Skill range for Hard difficulty (top AI now runs the full computed
## profile -- skill no longer acts as an artificial speed governor)
@export var hard_skill_range := Vector2(0.78, 1.0)

@export_group("AI Avoidance")

## Enable ship-to-ship avoidance for AI
@export var ai_avoidance_enabled: bool = true

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

## Shared baked racing line (baked once, used by every AI controller)
var baked_racing_line: BakedRacingLine

## Player's finishing position (1-indexed)
var player_finish_position: int = -1

## Keep flying after the finish instead of going dead.
##
## AI ships used to have ai_active cleared the instant they crossed the line,
## so they coasted and hit the nearest wall while the results were on screen.
## The player's ship was worse: lock_controls() zeroes every input and it just
## sat on the track. Both now keep racing, and the player's ship is taken over
## by an AI controller so the field stays in motion behind the results.
@export var keep_flying_after_finish: bool = true

## AI controller created for the player's ship at the finish, if any.
var player_takeover_ai: AIShipController

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
	
	# Load track (from parent)
	await _load_track()
	
	# Bake the shared AI racing line (cached after first run per track+ship)
	await _bake_racing_line()
	
	# Spawn all ships (player + AI)
	await _spawn_all_ships()
	
	# Initialize position tracker
	_setup_position_tracker()
	
	# Register ships with RaceManager
	var ships_array: Array[Node3D] = []
	ships_array.assign(all_ships)
	RaceManager.register_race_ships(ships_array, ship_instance)
	
	# Setup AI ship avoidance (NEW)
	if ai_avoidance_enabled:
		_setup_ai_avoidance()
	
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


func _bake_racing_line() -> void:
	"""Bake (or cache-load) the shared racing line + speed profile for this
	track + ship profile combo. All AI controllers receive the same line;
	NOTE: all AIs currently race the player's selected ship profile, so one
	bake covers everyone. If per-AI profiles are introduced later, bake once
	per unique profile (the cache makes repeats near-free)."""
	var ship_profile = GameManager.get_selected_ship()
	if not ship_profile or not track_instance:
		push_warning("RaceMode: cannot bake racing line (missing ship profile or track)")
		return
	
	# Every AI races the player's selected ship, and each AI loads a trained
	# line for its own profile when one exists (AIShipController.initialize).
	# The shared bake is then only a fallback nobody uses, so skip it.
	var trained_id := AILineTrainer.track_id_for(track_instance)
	if AILineTrainer.load_trained_line(trained_id, ship_profile.ship_id) != null:
		print("RaceMode: trained line available for %s on %s - AI will use it, skipping shared bake" % [
			ship_profile.ship_id, trained_id])
		return
	print("RaceMode: no trained line for %s on %s - baking an untrained fallback line" % [
		ship_profile.ship_id, trained_id])
	
	# CSG wall collision shapes build during the first physics frames after
	# the track loads; the baker raycasts against them to measure track width.
	await get_tree().physics_frame
	await get_tree().physics_frame
	
	var helper := TrackSplineHelper.new(track_instance)
	if not helper.is_valid:
		push_warning("RaceMode: no valid track spline - AI will use geometric fallback")
		return
	
	var track_profile = GameManager.get_selected_track()
	var track_id: String = track_profile.track_id if track_profile else String(track_instance.name)
	
	var baker := AIRacingLineBaker.new()
	baked_racing_line = baker.bake(helper, ship_profile, get_viewport().find_world_3d(), track_id)
	
	if baked_racing_line:
		print("RaceMode: Racing line ready - %s" % baked_racing_line.get_debug_info())
	else:
		push_warning("RaceMode: racing line bake failed - AI will use geometric fallback")

# ============================================================================
# SHIP SPAWNING
# ============================================================================

func _spawn_all_ships() -> void:
	"""Spawn player ship and AI opponents."""
	all_ships.clear()
	ai_ships.clear()
	ai_controllers.clear()
	
	# NEW: Randomly select player's starting position (0-7)
	var total_slots = num_ai_opponents + 1  # Player + AI opponents
	var player_grid_position = randi() % total_slots
	
	print("RaceMode: Player will start in grid position %d" % player_grid_position)
	
	# Spawn player at random position
	await _spawn_player_ship(player_grid_position)
	
	# Spawn AI ships at remaining grid positions (skip player's slot)
	var ai_slot_index = 0
	for grid_position in range(total_slots):
		if grid_position == player_grid_position:
			continue  # Skip player's position
		
		var skill = _calculate_ai_skill(ai_slot_index)
		await _spawn_ai_ship(grid_position, skill)
		ai_slot_index += 1
	
	print("RaceMode: Spawned %d total ships (1 player + %d AI)" % [all_ships.size(), ai_ships.size()])

func _spawn_player_ship(grid_position: int = 0) -> void:
	"""Spawn the player's ship at the specified grid position."""
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
	
	# Position at specified grid slot (CHANGED from hardcoded 0)
	if starting_grid:
		ship_instance.global_transform = starting_grid.get_start_transform(grid_position)
	
	# Lock controls until race starts
	if ship_instance.has_method("lock_controls"):
		ship_instance.lock_controls()
	
	all_ships.append(ship_instance)
	print("RaceMode: Player ship spawned at grid position %d" % grid_position)
	
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
		ai_ship.respawn_manager = respawn_manager  # Assign respawn manager
	
	# NEW ORDER - position BEFORE adding to scene:
# Position on grid first (while not in scene tree)
	if starting_grid:
		ai_ship.global_transform = starting_grid.get_start_transform(grid_position)

	add_child(ai_ship)

	# Wait one frame for scene to be fully ready
	await get_tree().process_frame

	# Apply random hull color to AI ship
	_apply_random_hull_color(ai_ship)
	
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
	ai_controller.avoidance_enabled = ai_avoidance_enabled  # Set avoidance flag
	ai_ship.add_child(ai_controller)
	
	# Initialize AI with track data + shared baked racing line
	ai_controller.initialize(track_instance, baked_racing_line)
	
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
# SHIP APPEARANCE (UPDATED - using find_child)
# ============================================================================

func _apply_random_hull_color(ship: Node3D) -> void:
	"""Apply a random vibrant color to the ship's hull with maximum distinction."""
	# Get the ship's index to ensure distinct colors
	var ship_index = ai_ships.find(ship)
	if ship_index == -1:
		ship_index = ai_ships.size()  # Fallback for ships not yet in array
	
	# Evenly space hues around the color wheel for maximum distinction
	var hue = (float(ship_index) / float(num_ai_opponents)) + randf_range(-0.05, 0.05)
	hue = fmod(hue, 1.0)  # Wrap around if needed
	
	var saturation = randf_range(0.7, 0.95)  # High saturation
	var value = randf_range(0.6, 0.85)  # Good brightness
	
	var random_color = Color.from_hsv(hue, saturation, value)
	
	ship.set_meta("hull_color", random_color)
	_set_hull_color(ship, random_color)
	
	print("RaceMode: Applied hull color to %s: %s (hue: %.2f)" % [ship.name, random_color, hue])

func _set_hull_color(ship: Node3D, color: Color) -> void:
	"""Set the hull color on a ship's mesh using find_child (robust for inherited scenes)."""
	# Use find_child to recursively search for the hull node
	# This works better with inherited scenes and GLB imports
	var hull = ship.find_child("hull", true, false)  # recursive=true, owned=false
	
	if not hull:
		push_warning("RaceMode: hull node not found on %s" % ship.name)
		print("RaceMode: Could not find 'hull' node in scene tree")
		return
	
	if not hull is MeshInstance3D:
		push_warning("RaceMode: hull found but is not a MeshInstance3D (it's a %s)" % hull.get_class())
		return
	
	print("RaceMode: Found hull at path: %s" % hull.get_path())
	
	# Get the current material or create a new one
	var material: StandardMaterial3D
	
	# Try multiple sources for the material
	if hull.material_override and hull.material_override is StandardMaterial3D:
		# Duplicate the material_override
		material = hull.material_override.duplicate()
		print("  Duplicating material_override")
	elif hull.get_surface_override_material(0) and hull.get_surface_override_material(0) is StandardMaterial3D:
		# Try surface override
		material = hull.get_surface_override_material(0).duplicate()
		print("  Duplicating surface material")
	else:
		# Create a new StandardMaterial3D with default ship values
		material = StandardMaterial3D.new()
		material.metallic = 0.73
		material.roughness = 0.52
		print("  Creating new material")
	
	print("  Material albedo before: %s" % material.albedo_color)
	
	# Apply the new color
	material.albedo_color = color
	
	print("  Material albedo after: %s" % material.albedo_color)
	
	# Assign the modified material to the hull (try both methods)
	hull.material_override = material
	hull.set_surface_override_material(0, material)
	
	print("  Material applied to hull!")
	print("  Verification - hull.material_override.albedo_color: %s" % hull.material_override.albedo_color)

func restore_hull_color_on_respawn(ship: Node3D) -> void:
	"""Restore the ship's hull color after respawning (if needed)."""
	if ship.has_meta("hull_color"):
		var stored_color = ship.get_meta("hull_color")
		_set_hull_color(ship, stored_color)
		print("RaceMode: Restored hull color for %s" % ship.name)

# ============================================================================
# AI AVOIDANCE SETUP
# ============================================================================

func _setup_ai_avoidance() -> void:
	"""Initialize ship avoidance for all AI controllers."""
	if ai_controllers.is_empty():
		return
	
	# Collect all ShipController references
	var all_ship_controllers: Array[ShipController] = []
	
	# Add player ship
	if ship_instance and ship_instance is ShipController:
		all_ship_controllers.append(ship_instance as ShipController)
	
	# Add AI ships
	for ai_ship in ai_ships:
		if ai_ship is ShipController:
			all_ship_controllers.append(ai_ship as ShipController)
	
	# Tell each AI controller about all ships
	for ai_controller in ai_controllers:
		ai_controller.set_race_ships(all_ship_controllers)
		
		# Set initial race position based on grid position
		var grid_pos = ai_controllers.find(ai_controller) + 2  # +2 because player is #1
		ai_controller.update_race_position(grid_pos, all_ship_controllers.size())
	
	print("RaceMode: AI avoidance initialized for %d AI ships (tracking %d total ships)" % [
		ai_controllers.size(), all_ship_controllers.size()
	])

func _update_ai_race_positions() -> void:
	"""Update AI controllers with current race positions for aggression scaling."""
	if not position_tracker or ai_controllers.is_empty():
		return
	
	var positions = position_tracker.get_positions()
	var total_ships = positions.size()
	
	for entry in positions:
		var ship = entry.ship
		var position = entry.position
		
		# Skip player ship
		if ship == ship_instance:
			continue
		
		# Find the AI controller for this ship
		for ai_controller in ai_controllers:
			if ai_controller.ship == ship:
				ai_controller.update_race_position(position, total_ships)
				break

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
	
	# Update the AI's aggression based on new position
	if ai_avoidance_enabled and ship != ship_instance:
		for ai_controller in ai_controllers:
			if ai_controller.ship == ship:
				ai_controller.update_race_position(new_pos, all_ships.size())
				break

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
	
	# A finished AI keeps driving its line unless we are told otherwise.
	if keep_flying_after_finish:
		return
	if ship != ship_instance:
		for i in range(ai_ships.size()):
			if ai_ships[i] == ship:
				ai_controllers[i].ai_active = false
				break

func _on_race_manager_finished(total_time: float, best_lap: float) -> void:
	"""Handle player finishing the race."""
	print("RaceMode: Player finished in P%d! Total: %.3f, Best lap: %.3f" % [player_finish_position, total_time, best_lap])
	
	# Hand the player's ship to an AI so it flies a cool-down lap instead of
	# stopping dead. lock_controls() is still applied: _read_input() returns
	# early on ai_controlled before it ever reaches the lock, so the AI's
	# inputs stand, and the lock is there if the handover fails.
	if ship_instance and ship_instance.has_method("lock_controls"):
		ship_instance.lock_controls()
	if keep_flying_after_finish:
		_hand_player_to_ai()
	
	# Play finish sound
	AudioManager.play_race_finish()

## Attach an AI to the player's ship once they have finished.
func _hand_player_to_ai() -> void:
	if player_takeover_ai != null or not (ship_instance is ShipController):
		return
	
	# Stop recording first: everything from here is the AI driving, and it
	# must never be filed as a player lap.
	var recorder := get_node_or_null("LapRecorder")
	if recorder and recorder.has_method("stop"):
		recorder.stop()
	
	player_takeover_ai = AIShipController.new()
	player_takeover_ai.name = "AIController_PlayerTakeover"
	player_takeover_ai.ship = ship_instance
	player_takeover_ai.skill_level = 1.0
	player_takeover_ai.debug_draw_enabled = false
	player_takeover_ai.avoidance_enabled = ai_avoidance_enabled
	ship_instance.add_child(player_takeover_ai)
	player_takeover_ai.initialize(track_instance, baked_racing_line)
	
	if not player_takeover_ai.is_initialized:
		push_warning("RaceMode: player takeover AI failed to initialize")
		player_takeover_ai.queue_free()
		player_takeover_ai = null
		return
	
	# Only now stop reading the pad: _read_input() returns early on this.
	ship_instance.ai_controlled = true
	player_takeover_ai.ai_active = true
	
	# Everyone avoids everyone, including the newly AI-driven player ship.
	var field: Array[ShipController] = []
	for s in all_ships:
		if s is ShipController:
			field.append(s)
	for c in ai_controllers:
		c.set_race_ships(field)
	player_takeover_ai.set_race_ships(field)
	print("RaceMode: player ship handed over to AI for the cool-down")

func _on_all_ships_finished() -> void:
	"""Handle all ships completing the race."""
	print("RaceMode: All ships finished!")
	is_race_active = false
	
	if not keep_flying_after_finish:
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
	
	# Update AI race positions periodically for avoidance aggression scaling
	if ai_avoidance_enabled and is_race_active and Engine.get_process_frames() % 15 == 0:
		_update_ai_race_positions()
	
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
	
	# Release the player's takeover AI and give control back, in case the
	# ship outlives the mode (restart without respawning).
	if is_instance_valid(player_takeover_ai):
		player_takeover_ai.ai_active = false
		player_takeover_ai.queue_free()
	player_takeover_ai = null
	if is_instance_valid(ship_instance) and ship_instance is ShipController:
		ship_instance.ai_controlled = false
	
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
