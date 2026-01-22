extends Node
class_name RaceLauncher

## Race Launcher
## Entry point for starting races. Creates the appropriate mode controller
## based on GameManager selections and sets up the race.
##
## LIGHTING: Tracks should include their own WorldEnvironment and DirectionalLight3D.
## RaceLauncher only creates fallback lighting if the track doesn't have its own.

# ============================================================================
# ENVIRONMENT (fallback only - tracks should define their own)
# ============================================================================

@export var default_environment: Environment
@export var default_sun_color: Color = Color(1, 0.95, 0.9)

## If true, always create environment even if track has one (not recommended)
@export var force_default_environment := false

# ============================================================================
# RACE MODE CONFIGURATION (for direct testing - normally read from GameManager)
# ============================================================================

@export_group("Race Mode Override")

## Override the GameManager mode selection (for testing)
@export var override_mode: bool = false

## Mode to use when override is enabled
@export_enum("time_trial", "endless", "race") var forced_mode: String = "time_trial"

## Number of AI opponents (race mode only) - used when override_mode is true
@export_range(1, 7) var num_ai_opponents: int = 7

## AI difficulty (race mode only) - used when override_mode is true
@export_enum("Easy", "Medium", "Hard") var ai_difficulty: int = 1

# ============================================================================
# MODE INSTANCES
# ============================================================================

var current_mode: ModeBase

# ============================================================================
# INITIALIZATION
# ============================================================================

func _ready() -> void:
	print("RaceLauncher: Starting...")
	
	# Verify we have valid selections
	if not GameManager.has_valid_selection():
		push_error("RaceLauncher: No valid selection in GameManager!")
		_return_to_menu()
		return
	
	# Create and setup the mode (which loads the track)
	await _create_mode()
	
	# Setup fallback environment AFTER track is loaded (so we can check what track has)
	_setup_fallback_environment()
	
	# Start the race after a brief delay
	await get_tree().create_timer(0.5).timeout
	
	if current_mode:
		current_mode.start_countdown()

func _setup_fallback_environment() -> void:
	"""Only create environment/lighting if the track doesn't have its own."""
	
	if force_default_environment:
		_create_full_environment()
		return
	
	# Check if track already has a WorldEnvironment
	var has_world_env := false
	var has_light := false
	
	if current_mode and current_mode.track_instance:
		has_world_env = _find_node_of_type(current_mode.track_instance, "WorldEnvironment") != null
		has_light = _find_node_of_type(current_mode.track_instance, "DirectionalLight3D") != null
	
	if has_world_env:
		print("RaceLauncher: Track has WorldEnvironment, skipping default")
	else:
		print("RaceLauncher: Track missing WorldEnvironment, creating fallback")
		_create_world_environment()
	
	if has_light:
		print("RaceLauncher: Track has DirectionalLight3D, skipping default")
	else:
		print("RaceLauncher: Track missing DirectionalLight3D, creating fallback")
		_create_directional_light()

func _find_node_of_type(node: Node, type_name: String) -> Node:
	"""Recursively search for a node of the given type."""
	if node.get_class() == type_name:
		return node
	
	for child in node.get_children():
		var found = _find_node_of_type(child, type_name)
		if found:
			return found
	
	return null

func _create_full_environment() -> void:
	"""Create both WorldEnvironment and DirectionalLight3D."""
	_create_world_environment()
	_create_directional_light()

func _create_world_environment() -> void:
	"""Create the WorldEnvironment with sky and effects."""
	var env: Environment
	
	if default_environment:
		env = default_environment
	else:
		# Create environment matching original time_trial_01.tscn
		env = Environment.new()
		env.background_mode = Environment.BG_SKY
		
		var sky_material = ProceduralSkyMaterial.new()
		sky_material.sky_top_color = Color(0.05, 0.05, 0.15)
		sky_material.sky_horizon_color = Color(0.2, 0.15, 0.3)
		sky_material.ground_bottom_color = Color(0.02, 0.02, 0.05)
		sky_material.ground_horizon_color = Color(0.2, 0.15, 0.3)
		
		var sky = Sky.new()
		sky.sky_material = sky_material
		env.sky = sky
		
		# Ambient light from sky
		env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
		env.ambient_light_color = Color(0.25, 0.25, 0.35)
		env.ambient_light_energy = 0.4
		
		# Tonemapping and glow
		env.tonemap_mode = Environment.TONE_MAPPER_ACES
		env.glow_enabled = true
		env.glow_intensity = 0.6
		env.glow_bloom = 0.2
	
	var world_env = WorldEnvironment.new()
	world_env.name = "FallbackWorldEnvironment"
	world_env.environment = env
	add_child(world_env)

func _create_directional_light() -> void:
	"""Create DirectionalLight3D matching original time_trial_01.tscn."""
	var sun = DirectionalLight3D.new()
	sun.name = "FallbackDirectionalLight"
	sun.light_color = default_sun_color
	sun.shadow_enabled = true
	sun.shadow_blur = 2.0
	
	# Match the original time_trial_01.tscn transform exactly
	# Original: Transform3D(-0.866023, -0.433016, 0.250001, 0, 0.499998, 0.866027, -0.500003, 0.749999, -0.43301, 0, 50, 0)
	sun.transform = Transform3D(
		Basis(
			Vector3(-0.866023, -0.433016, 0.250001),
			Vector3(0, 0.499998, 0.866027),
			Vector3(-0.500003, 0.749999, -0.43301)
		),
		Vector3(0, 50, 0)
	)
	
	add_child(sun)

func _create_mode() -> void:
	var mode_id: String
	
	# Check for mode override (for testing)
	if override_mode:
		mode_id = forced_mode
		print("RaceLauncher: Using forced mode: %s" % mode_id)
	else:
		mode_id = GameManager.get_selected_mode()
	
	match mode_id:
		"time_trial":
			current_mode = TimeTrialMode.new()
			print("RaceLauncher: Created TimeTrialMode")
		"endless":
			current_mode = EndlessMode.new()
			print("RaceLauncher: Created EndlessMode")
		"race":
			var race_mode = RaceMode.new()
			# Always 7 opponents, 3 laps (hardcoded per requirements)
			race_mode.num_ai_opponents = 7
			race_mode.num_laps = 3
			# Get difficulty from GameManager (or use override)
			if override_mode:
				race_mode.difficulty = ai_difficulty as RaceMode.Difficulty
			else:
				race_mode.difficulty = GameManager.selected_race_difficulty as RaceMode.Difficulty
			current_mode = race_mode
			print("RaceLauncher: Created RaceMode with %d AI opponents (difficulty: %s)" % [
				race_mode.num_ai_opponents,
				GameManager.get_race_difficulty_name() if not override_mode else ["Easy", "Medium", "Hard"][ai_difficulty]
			])
		_:
			push_error("RaceLauncher: Unknown mode: %s" % mode_id)
			_return_to_menu()
			return
	
	add_child(current_mode)
	
	# Setup the race (async)
	await current_mode.setup_race()
	
	print("RaceLauncher: Mode created and setup complete")

# ============================================================================
# NAVIGATION
# ============================================================================

func _return_to_menu() -> void:
	print("RaceLauncher: Returning to main menu")
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")

func restart_race() -> void:
	"""Restart current race with same selections."""
	print("RaceLauncher: Restarting race...")
	if current_mode:
		current_mode.cleanup()
		current_mode.queue_free()
		current_mode = null
	
	RaceManager.reset_race()
	
	await get_tree().create_timer(0.1).timeout
	await _create_mode()
	_setup_fallback_environment()
	
	await get_tree().create_timer(0.5).timeout
	if current_mode:
		current_mode.start_countdown()

func quit_to_menu() -> void:
	"""Clean up and return to main menu."""
	if current_mode:
		current_mode.cleanup()
	_return_to_menu()
