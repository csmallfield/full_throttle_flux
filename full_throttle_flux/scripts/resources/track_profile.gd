@tool
extends Resource
class_name TrackProfile

## Track Profile Resource
## Defines metadata and settings for a race track.
## Create .tres files from this in resources/tracks/

# ============================================================================
# IDENTITY
# ============================================================================

@export_group("Identity")

## Unique identifier for this track (used for save data, records, etc.)
@export var track_id: String = "test_circuit"

## Display name shown in menus
@export var display_name: String = "Test Circuit"

## Track description for selection screen
@export_multiline var description: String = ""

## Thumbnail image for selection UI
@export var thumbnail: Texture2D

## Track author/designer
@export var author: String = "Unknown"

# ============================================================================
# TRACK SCENE
# ============================================================================

@export_group("Track Scene")

## Reference to the track scene (geometry, boost pads, start line, starting grid)
@export var track_scene: PackedScene

# ============================================================================
# RACE SETTINGS
# ============================================================================

@export_group("Race Settings")

## Default number of laps for this track
@export var default_laps: int = 3

## Maximum ships on grid (for AI races)
@export var grid_size: int = 8

## Difficulty rating 1-5
@export_range(1, 5) var difficulty: int = 2

# ============================================================================
# MODE SUPPORT
# ============================================================================

@export_group("Mode Support")

## Track supports Time Trial mode
@export var supports_time_trial: bool = true

## Track supports Endless mode
@export var supports_endless: bool = true

## Track supports full Race mode (with AI)
@export var supports_race: bool = true

# ============================================================================
# AUDIO
# ============================================================================

@export_group("Audio")

## Optional music override for this track (null = use default playlist)
@export var music_override: Resource

# ============================================================================
# UTILITY
# ============================================================================

func get_supported_modes() -> Array[String]:
	var modes: Array[String] = []
	if supports_time_trial:
		modes.append("time_trial")
	if supports_endless:
		modes.append("endless")
	if supports_race:
		modes.append("race")
	return modes
