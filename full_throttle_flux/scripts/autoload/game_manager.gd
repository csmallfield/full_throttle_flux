extends Node

## GameManager Autoload
## Central manager for game state: selected ship, track, mode.
## Uses manifest resources for exported builds (required).
## Falls back to directory scanning in editor for convenience.
## Add to Project Settings → Autoload as "GameManager"

# ============================================================================
# SIGNALS
# ============================================================================

signal ship_selected(profile: ShipProfile)
signal track_selected(profile: TrackProfile)
signal mode_selected(mode_id: String)

# ============================================================================
# CURRENT SELECTIONS
# ============================================================================

var selected_ship_profile: ShipProfile
var selected_track_profile: TrackProfile
var selected_mode: String = "time_trial"

## Race mode difficulty: 0=Easy, 1=Medium, 2=Hard
var selected_race_difficulty: int = 1

# ============================================================================
# AVAILABLE OPTIONS (loaded from manifests)
# ============================================================================

var available_ships: Array[ShipProfile] = []
var available_tracks: Array[TrackProfile] = []
var available_modes: Array[String] = ["time_trial", "endless", "race"]

# ============================================================================
# MANIFEST PATHS
# ============================================================================

const SHIP_MANIFEST_PATH := "res://resources/ships/ship_manifest.tres"
const TRACK_MANIFEST_PATH := "res://resources/tracks/track_manifest.tres"

# Legacy paths for editor fallback
const SHIPS_PATH := "res://resources/ships/"
const TRACKS_PATH := "res://resources/tracks/"

# ============================================================================
# INITIALIZATION
# ============================================================================

func _ready() -> void:
	_load_profiles()
	_set_defaults()
	print("GameManager: Initialized with %d ships, %d tracks" % [available_ships.size(), available_tracks.size()])

func _load_profiles() -> void:
	_load_ship_profiles()
	_load_track_profiles()

func _load_ship_profiles() -> void:
	available_ships.clear()
	
	# Try to load from manifest first (required for exports)
	if ResourceLoader.exists(SHIP_MANIFEST_PATH):
		var manifest = load(SHIP_MANIFEST_PATH) as ShipManifest
		if manifest:
			available_ships = manifest.get_all_ships()
			print("GameManager: Loaded %d ships from manifest" % available_ships.size())
			return
	
	# Fallback to directory scanning (editor only - won't work in exports)
	if OS.has_feature("editor"):
		print("GameManager: No ship manifest found, falling back to directory scan (editor only)")
		_discover_ship_profiles_legacy()
	else:
		push_error("GameManager: Ship manifest not found at %s - create it for exports to work!" % SHIP_MANIFEST_PATH)

func _load_track_profiles() -> void:
	available_tracks.clear()
	
	# Try to load from manifest first (required for exports)
	if ResourceLoader.exists(TRACK_MANIFEST_PATH):
		var manifest = load(TRACK_MANIFEST_PATH) as TrackManifest
		if manifest:
			available_tracks = manifest.get_all_tracks()
			print("GameManager: Loaded %d tracks from manifest" % available_tracks.size())
			return
	
	# Fallback to directory scanning (editor only - won't work in exports)
	if OS.has_feature("editor"):
		print("GameManager: No track manifest found, falling back to directory scan (editor only)")
		_discover_track_profiles_legacy()
	else:
		push_error("GameManager: Track manifest not found at %s - create it for exports to work!" % TRACK_MANIFEST_PATH)

# ============================================================================
# LEGACY DIRECTORY SCANNING (Editor Fallback)
# ============================================================================

func _discover_ship_profiles_legacy() -> void:
	var dir = DirAccess.open(SHIPS_PATH)
	if not dir:
		push_warning("GameManager: Could not open ships directory: %s" % SHIPS_PATH)
		return
	
	dir.list_dir_begin()
	var file_name = dir.get_next()
	while file_name != "":
		# Skip manifest file and subdirectories
		if not dir.current_is_dir() and (file_name.ends_with(".tres") or file_name.ends_with(".res")):
			if file_name != "ship_manifest.tres":
				var profile = load(SHIPS_PATH + file_name) as ShipProfile
				if profile:
					available_ships.append(profile)
					print("GameManager: Discovered ship - %s" % profile.display_name)
		file_name = dir.get_next()
	dir.list_dir_end()

func _discover_track_profiles_legacy() -> void:
	var dir = DirAccess.open(TRACKS_PATH)
	if not dir:
		push_warning("GameManager: Could not open tracks directory: %s" % TRACKS_PATH)
		return
	
	dir.list_dir_begin()
	var file_name = dir.get_next()
	while file_name != "":
		# Skip manifest file and subdirectories
		if not dir.current_is_dir() and (file_name.ends_with(".tres") or file_name.ends_with(".res")):
			if file_name != "track_manifest.tres":
				var profile = load(TRACKS_PATH + file_name) as TrackProfile
				if profile:
					available_tracks.append(profile)
					print("GameManager: Discovered track - %s" % profile.display_name)
		file_name = dir.get_next()
	dir.list_dir_end()

func _set_defaults() -> void:
	# Select first available ship and track as defaults
	if available_ships.size() > 0:
		selected_ship_profile = available_ships[0]
	if available_tracks.size() > 0:
		selected_track_profile = available_tracks[0]

# ============================================================================
# SELECTION API
# ============================================================================

func select_ship(profile: ShipProfile) -> void:
	selected_ship_profile = profile
	ship_selected.emit(profile)
	print("GameManager: Selected ship - %s" % profile.display_name)

func select_ship_by_id(ship_id: String) -> bool:
	for profile in available_ships:
		if profile.ship_id == ship_id:
			select_ship(profile)
			return true
	push_warning("GameManager: Ship not found - %s" % ship_id)
	return false

func select_track(profile: TrackProfile) -> void:
	selected_track_profile = profile
	track_selected.emit(profile)
	print("GameManager: Selected track - %s" % profile.display_name)

func select_track_by_id(track_id: String) -> bool:
	for profile in available_tracks:
		if profile.track_id == track_id:
			select_track(profile)
			return true
	push_warning("GameManager: Track not found - %s" % track_id)
	return false

func select_mode(mode_id: String) -> void:
	if mode_id in available_modes:
		selected_mode = mode_id
		mode_selected.emit(mode_id)
		print("GameManager: Selected mode - %s" % mode_id)
	else:
		push_warning("GameManager: Unknown mode - %s" % mode_id)

func select_race_difficulty(difficulty: int) -> void:
	selected_race_difficulty = clampi(difficulty, 0, 2)
	print("GameManager: Selected race difficulty - %d" % selected_race_difficulty)

# ============================================================================
# GETTERS
# ============================================================================

func get_selected_ship() -> ShipProfile:
	return selected_ship_profile

func get_selected_track() -> TrackProfile:
	return selected_track_profile

func get_selected_mode() -> String:
	return selected_mode

func get_race_difficulty() -> int:
	return selected_race_difficulty

func get_race_difficulty_name() -> String:
	match selected_race_difficulty:
		0: return "Easy"
		1: return "Medium"
		2: return "Hard"
		_: return "Unknown"

func get_ships_for_mode(mode_id: String) -> Array[ShipProfile]:
	# For now, all ships work with all modes
	return available_ships

func get_tracks_for_mode(mode_id: String) -> Array[TrackProfile]:
	var compatible: Array[TrackProfile] = []
	for track in available_tracks:
		var supported = track.get_supported_modes()
		if mode_id in supported:
			compatible.append(track)
	return compatible

# ============================================================================
# UTILITY
# ============================================================================

func refresh_profiles() -> void:
	"""Re-load profiles from manifests (or rescan in editor)."""
	_load_profiles()

func has_valid_selection() -> bool:
	"""Check if we have everything needed to start a race."""
	return selected_ship_profile != null and selected_track_profile != null and selected_mode != ""
