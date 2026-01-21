extends Node

## Race Mode Test Launcher
## Initializes GameManager with test selections then launches race mode.
## Run this scene from the editor to test race mode.

@export_group("Test Configuration")

## Track ID to use for testing
@export var test_track_id: String = "test_circuit_3_live"

## Ship ID to use for testing
@export var test_ship_id: String = "default_racer"

## Number of AI opponents
@export_range(1, 7) var num_ai_opponents: int = 3

## AI difficulty (0=Easy, 1=Medium, 2=Hard)
@export_range(0, 2) var ai_difficulty: int = 1

## Number of laps
@export var num_laps: int = 3

func _ready() -> void:
	print("========================================")
	print("RACE MODE TEST")
	print("========================================")
	print("Track: %s" % test_track_id)
	print("Ship: %s" % test_ship_id)
	print("AI Opponents: %d" % num_ai_opponents)
	print("Difficulty: %s" % ["Easy", "Medium", "Hard"][ai_difficulty])
	print("Laps: %d" % num_laps)
	print("========================================")
	
	# Wait for GameManager to initialize
	await get_tree().process_frame
	
	# Setup GameManager selections
	_setup_game_manager()
	
	# Create RaceLauncher with race mode
	_launch_race()

func _setup_game_manager() -> void:
	"""Configure GameManager with test selections."""
	# Select track
	if not GameManager.select_track_by_id(test_track_id):
		push_error("RaceModeTest: Track not found: %s" % test_track_id)
		# Try first available track
		if GameManager.available_tracks.size() > 0:
			GameManager.select_track(GameManager.available_tracks[0])
			print("RaceModeTest: Falling back to: %s" % GameManager.selected_track_profile.display_name)
	
	# Select ship
	if not GameManager.select_ship_by_id(test_ship_id):
		push_error("RaceModeTest: Ship not found: %s" % test_ship_id)
		# Try first available ship
		if GameManager.available_ships.size() > 0:
			GameManager.select_ship(GameManager.available_ships[0])
			print("RaceModeTest: Falling back to: %s" % GameManager.selected_ship_profile.display_name)
	
	# Select race mode
	GameManager.select_mode("race")
	
	print("RaceModeTest: GameManager configured")
	print("  Track: %s" % GameManager.selected_track_profile.display_name)
	print("  Ship: %s" % GameManager.selected_ship_profile.display_name)
	print("  Mode: %s" % GameManager.selected_mode)

func _launch_race() -> void:
	"""Create and configure the race launcher."""
	var launcher_script = load("res://scripts/race_launcher.gd")
	
	if not launcher_script:
		push_error("RaceModeTest: Could not load race_launcher.gd")
		return
	
	# Create launcher node
	var launcher = Node.new()
	launcher.name = "RaceLauncher"
	launcher.set_script(launcher_script)
	
	# Configure for race mode
	launcher.override_mode = true
	launcher.forced_mode = "race"
	launcher.num_ai_opponents = num_ai_opponents
	launcher.ai_difficulty = ai_difficulty
	
	# Remove this test node and add launcher
	var parent = get_parent()
	
	# Defer to avoid issues with tree modification during ready
	call_deferred("_finalize_launch", launcher, parent)

func _finalize_launch(launcher: Node, parent: Node) -> void:
	"""Final step: add launcher and remove self."""
	parent.add_child(launcher)
	queue_free()
