extends Node
class_name ModeBase

## Mode Base Class
## Abstract base for game modes. Handles loading track, spawning ship,
## setting up camera and HUD. Subclasses implement mode-specific logic.

# ============================================================================
# SIGNALS
# ============================================================================

signal mode_ready
signal race_started
signal race_finished(results: Dictionary)

# ============================================================================
# SCENE REFERENCES (set after assembly)
# ============================================================================

var track_instance: Node3D
var ship_instance: Node3D
var camera_instance: Node3D
var hud_instance: CanvasLayer
var starting_grid: StartingGrid
var respawn_manager: TrackRespawnManager

# ============================================================================
# STATE
# ============================================================================

var is_race_active := false
var race_time := 0.0

# ============================================================================
# PACKED SCENES (assign in subclass or inspector)
# ============================================================================

@export var camera_scene: PackedScene
@export var hud_scene: PackedScene

# ============================================================================
# VIRTUAL METHODS (override in subclasses)
# ============================================================================

## Return unique mode identifier
func get_mode_id() -> String:
	return "base"

## Return HUD configuration for this mode
func get_hud_config() -> Dictionary:
	return {
		"show_speedometer": true,
		"show_lap_timer": true,
		"show_lap_counter": true,
	}

## Called when race countdown finishes
func _on_race_start() -> void:
	pass

## Called every frame during active race
func _on_race_update(delta: float) -> void:
	pass

## Called when race ends
func _on_race_end() -> void:
	pass

# ============================================================================
# SETUP FLOW
# ============================================================================

func setup_race() -> void:
	"""Main setup entry point. Call after adding mode to scene tree."""
	print("ModeBase: Setting up race...")
	
	if not _validate_selections():
		push_error("ModeBase: Invalid selections, cannot setup race")
		return
	
	await _load_track()
	await _setup_respawn_manager()  # CHANGE: Add await
	await _spawn_ship()
	_setup_camera()
	_setup_hud()
	
	mode_ready.emit()
	print("ModeBase: Race setup complete")

func _validate_selections() -> bool:
	if not GameManager.has_valid_selection():
		push_error("ModeBase: GameManager missing selection")
		return false
	return true

# ============================================================================
# TRACK LOADING
# ============================================================================

func _load_track() -> void:
	var track_profile = GameManager.get_selected_track()
	
	# Check if track_scene is set in profile
	if track_profile.track_scene:
		track_instance = track_profile.track_scene.instantiate()
	else:
		# Fallback: try to load by convention
		var track_path = "res://scenes/tracks/%s.tscn" % track_profile.track_id
		if ResourceLoader.exists(track_path):
			var scene = load(track_path)
			track_instance = scene.instantiate()
		else:
			push_error("ModeBase: Could not find track scene for %s" % track_profile.track_id)
			return
	
	add_child(track_instance)
	
	# Find starting grid
	starting_grid = _find_starting_grid(track_instance)
	if not starting_grid:
		push_warning("ModeBase: No StartingGrid found in track")
	
	print("ModeBase: Loaded track - %s" % track_profile.display_name)

func _find_starting_grid(node: Node) -> StartingGrid:
	if node is StartingGrid:
		return node
	for child in node.get_children():
		var found = _find_starting_grid(child)
		if found:
			return found
	return null



# ============================================================================
# SHIP SPAWNING
# ============================================================================

func _setup_respawn_manager() -> void:
	"""Initialize the track respawn manager."""
	if not track_instance:
		return
	
	# Create respawn manager
	respawn_manager = TrackRespawnManager.new()
	respawn_manager.name = "RespawnManager"
	
	# Add as child of mode (will be cleaned up with mode)
	add_child(respawn_manager)
	
	# Initialize with track root (await because initialize is now async)
	if await respawn_manager.initialize(track_instance):
		print("ModeBase: Respawn manager initialized")
	else:
		push_warning("ModeBase: Failed to initialize respawn manager")


func _spawn_ship() -> void:
	var ship_profile = GameManager.get_selected_ship()
	
	# Load ship scene
	var ship_scene_path = "res://scenes/ships/%s.tscn" % ship_profile.ship_id
	if not ResourceLoader.exists(ship_scene_path):
		push_warning("ModeBase: Ship scene not found at %s, trying default" % ship_scene_path)
		ship_scene_path = "res://scenes/ships/default_racer.tscn"
	
	if not ResourceLoader.exists(ship_scene_path):
		push_error("ModeBase: Could not find any ship scene!")
		return
	
	var ship_scene = load(ship_scene_path)
	ship_instance = ship_scene.instantiate()
	
	# Ensure ship has the correct profile (override what's in scene)
	if ship_instance is ShipController:
		ship_instance.profile = ship_profile
		ship_instance.respawn_manager = respawn_manager  # ADD THIS LINE
	elif ship_instance.has_method("initialize_with_profile"):
		ship_instance.initialize_with_profile(ship_profile)
	
	add_child(ship_instance)
	
	# Position at starting grid
	if starting_grid:
		var start_transform = starting_grid.get_pole_position()
		ship_instance.global_transform = start_transform
		print("ModeBase: Ship placed at starting grid")
	else:
		push_warning("ModeBase: No starting grid, ship at default position")
	
	# Lock controls until race starts
	if ship_instance.has_method("lock_controls"):
		ship_instance.lock_controls()
	
	print("ModeBase: Spawned ship - %s" % ship_profile.display_name)

# ============================================================================
# CAMERA SETUP
# ============================================================================

func _setup_camera() -> void:
	if camera_scene:
		camera_instance = camera_scene.instantiate()
		add_child(camera_instance)
	else:
		# Load the AG camera script
		var cam_script = load("res://scripts/ag_camera_2097.gd")
		
		if cam_script:
			# Create camera and set script BEFORE adding to tree
			camera_instance = Camera3D.new()
			camera_instance.set_script(cam_script)
			add_child(camera_instance)
		else:
			# Fallback: create basic follow camera
			push_warning("ModeBase: AG camera script not found, using basic camera")
			camera_instance = Camera3D.new()
			add_child(camera_instance)
			camera_instance.global_position = Vector3(0, 10, 20)
	
	# Point camera at ship
	if ship_instance and camera_instance:
		if "ship" in camera_instance:
			camera_instance.ship = ship_instance
			print("ModeBase: Camera assigned to ship")
		else:
			push_warning("ModeBase: Camera has no 'ship' property")
		
		# Give ship reference to camera for shake effects
		if ship_instance is ShipController:
			ship_instance.camera = camera_instance
	
	print("ModeBase: Camera setup complete")

# ============================================================================
# HUD SETUP
# ============================================================================

func _setup_hud() -> void:
	if hud_scene:
		hud_instance = hud_scene.instantiate()
		add_child(hud_instance)
	else:
		# Try to load default HUD
		var hud_path = "res://scenes/hud_race.tscn"
		if ResourceLoader.exists(hud_path):
			var scene = load(hud_path)
			hud_instance = scene.instantiate()
			add_child(hud_instance)
		else:
			push_warning("ModeBase: HUD scene not found at %s" % hud_path)
	
	# Connect HUD to ship
	if hud_instance and ship_instance:
		if "ship" in hud_instance:
			hud_instance.ship = ship_instance
	
	print("ModeBase: HUD setup complete")

# ============================================================================
# RACE FLOW
# ============================================================================

func start_countdown() -> void:
	"""Begin pre-race countdown."""
	print("ModeBase: Starting countdown...")
	# Subclass implements countdown logic
	await _do_countdown()
	_begin_race()

func _do_countdown() -> void:
	"""Override in subclass for countdown implementation."""
	# Default: 3 second countdown
	for i in range(3, 0, -1):
		print("ModeBase: %d..." % i)
		await get_tree().create_timer(1.0).timeout
	print("ModeBase: GO!")

func _begin_race() -> void:
	"""Called after countdown, starts the race."""
	is_race_active = true
	race_time = 0.0
	
	# Unlock ship controls
	if ship_instance and ship_instance.has_method("unlock_controls"):
		ship_instance.unlock_controls()
	
	race_started.emit()
	_on_race_start()
	print("ModeBase: Race started!")

func end_race(results: Dictionary = {}) -> void:
	"""End the race and show results."""
	is_race_active = false
	
	# Lock ship controls
	if ship_instance and ship_instance.has_method("lock_controls"):
		ship_instance.lock_controls()
	
	_on_race_end()
	race_finished.emit(results)
	print("ModeBase: Race finished!")

# ============================================================================
# PROCESS
# ============================================================================

func _process(delta: float) -> void:
	if is_race_active:
		race_time += delta
		_on_race_update(delta)

# ============================================================================
# CLEANUP
# ============================================================================

func cleanup() -> void:
	"""Clean up mode resources before switching."""
	if track_instance:
		track_instance.queue_free()
	if ship_instance:
		ship_instance.queue_free()
	if camera_instance:
		camera_instance.queue_free()
	if hud_instance:
		hud_instance.queue_free()
	
	track_instance = null
	ship_instance = null
	camera_instance = null
	hud_instance = null
	starting_grid = null
