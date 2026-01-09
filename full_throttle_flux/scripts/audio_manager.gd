extends Node

## Global Audio Manager Singleton
## Handles UI sounds, sound effects, and global volume settings
## Volume settings persist between sessions
## NOTE: Music playback is handled by MusicPlaylistManager

# ============================================================================
# AUDIO BUS NAMES
# ============================================================================

const BUS_MASTER := "Master"
const BUS_MUSIC := "Music"
const BUS_SFX := "SFX"
const BUS_UI := "UI"

# ============================================================================
# SETTINGS PERSISTENCE
# ============================================================================

const SETTINGS_PATH := "user://audio_settings.json"

# ============================================================================
# UI SOUND PATHS
# ============================================================================

const SFX_UI_HOVER := "res://sounds/ui/ui_hover.wav"
const SFX_UI_SELECT := "res://sounds/ui/ui_select.wav"
const SFX_UI_BACK := "res://sounds/ui/ui_back.wav"
const SFX_UI_PAUSE := "res://sounds/ui/ui_pause.wav"
const SFX_UI_RESUME := "res://sounds/ui/ui_resume.wav"
const SFX_UI_KEYSTROKE := "res://sounds/ui/ui_keystroke.wav"

# ============================================================================
# RACE SOUND PATHS
# ============================================================================

const SFX_COUNTDOWN_BEEP := "res://sounds/race/countdown_beep.wav"
const SFX_COUNTDOWN_GO := "res://sounds/race/countdown_go.wav"
const SFX_LAP_COMPLETE := "res://sounds/race/lap_complete.wav"
const SFX_FINAL_LAP := "res://sounds/race/final_lap.wav"
const SFX_RACE_FINISH := "res://sounds/race/race_finish.wav"
const SFX_WRONG_WAY := "res://sounds/race/wrong_way.wav"
const SFX_NEW_RECORD := "res://sounds/race/new_record.wav"
const SFX_LINE_CROSS := "res://sounds/ambient/line_cross.wav"

# ============================================================================
# VOLUME SETTINGS (Linear scale: 0 = mute, 1 = normal, 2 = loud)
# ============================================================================

## Music volume on linear scale (0-2, where 1 is default)
var music_volume_linear := 1.0:
	set(value):
		music_volume_linear = clamp(value, 0.0, 2.0)
		_apply_music_volume()
		_save_settings()

## SFX volume on linear scale (0-2, where 1 is default)
var sfx_volume_linear := 1.0:
	set(value):
		sfx_volume_linear = clamp(value, 0.0, 2.0)
		_apply_sfx_volume()
		_save_settings()

# Internal base volumes (what "1.0" means in dB)
const _BASE_MUSIC_DB := -12.0
const _BASE_SFX_DB := 0.0

# Current calculated volume offsets
var _music_db_offset := 0.0
var _sfx_db_offset := 0.0

# ============================================================================
# LEGACY SETTINGS (kept for compatibility)
# ============================================================================

@export_group("Volume Settings")
@export_range(0.0, 1.0) var master_volume := 1.0:
	set(value):
		master_volume = value
		_update_bus_volume(BUS_MASTER, value)

@export_range(0.0, 1.0) var ui_volume := 0.8:
	set(value):
		ui_volume = value
		_update_bus_volume(BUS_UI, value)

# ============================================================================
# AUDIO PLAYERS
# ============================================================================

var _ui_player_pool: Array[AudioStreamPlayer] = []
var _sfx_player_pool: Array[AudioStreamPlayer] = []

const UI_POOL_SIZE := 4
const SFX_POOL_SIZE := 8

# Preloaded sounds cache
var _sound_cache: Dictionary = {}

# ============================================================================
# INITIALIZATION
# ============================================================================

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # Audio works even when paused
	_setup_audio_buses()
	_create_sound_pools()
	_preload_ui_sounds()
	_load_settings()

func _setup_audio_buses() -> void:
	# Create audio buses if they don't exist
	# Note: In production, you'd set these up in the Audio Bus Layout editor
	# For now, we'll work with the default Master bus
	pass

func _create_sound_pools() -> void:
	# UI sound pool
	for i in range(UI_POOL_SIZE):
		var player = AudioStreamPlayer.new()
		player.name = "UIPlayer_%d" % i
		player.bus = BUS_MASTER
		add_child(player)
		_ui_player_pool.append(player)
	
	# SFX sound pool (for non-positional sounds)
	for i in range(SFX_POOL_SIZE):
		var player = AudioStreamPlayer.new()
		player.name = "SFXPlayer_%d" % i
		player.bus = BUS_MASTER
		add_child(player)
		_sfx_player_pool.append(player)

func _preload_ui_sounds() -> void:
	# Preload commonly used UI sounds
	_preload_sound(SFX_UI_HOVER)
	_preload_sound(SFX_UI_SELECT)
	_preload_sound(SFX_UI_BACK)
	_preload_sound(SFX_UI_PAUSE)
	_preload_sound(SFX_UI_RESUME)
	_preload_sound(SFX_UI_KEYSTROKE)

func _preload_sound(path: String) -> void:
	if ResourceLoader.exists(path):
		_sound_cache[path] = load(path)

# ============================================================================
# VOLUME CONTROL SYSTEM
# ============================================================================

## Convert linear volume (0-2) to dB offset
## 0 = muted (-80dB), 1 = normal (0dB offset), 2 = loud (+10dB offset)
func _linear_to_db_offset(linear: float) -> float:
	if linear <= 0.001:
		return -80.0  # Effectively muted
	elif linear <= 1.0:
		# 0 to 1 maps to -80dB to 0dB (exponential feel)
		# Using a curve for more natural volume control
		return lerp(-40.0, 0.0, linear)
	else:
		# 1 to 2 maps to 0dB to +10dB (perceived doubling)
		return lerp(0.0, 10.0, linear - 1.0)

func _apply_music_volume() -> void:
	_music_db_offset = _linear_to_db_offset(music_volume_linear)
	
	# Tell MusicPlaylistManager to update its volume
	if MusicPlaylistManager:
		var final_db = _BASE_MUSIC_DB + _music_db_offset
		MusicPlaylistManager.set_volume(final_db)

func _apply_sfx_volume() -> void:
	_sfx_db_offset = _linear_to_db_offset(sfx_volume_linear)
	# SFX volume is applied when sounds are played

## Get the current SFX volume offset in dB (used by other systems)
func get_sfx_db_offset() -> float:
	return _sfx_db_offset

## Get the current music volume offset in dB
func get_music_db_offset() -> float:
	return _music_db_offset

# ============================================================================
# SETTINGS PERSISTENCE
# ============================================================================

func _save_settings() -> void:
	var settings := {
		"music_volume": music_volume_linear,
		"sfx_volume": sfx_volume_linear,
		"version": 1
	}
	
	var file = FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(settings, "\t"))
		file.close()

func _load_settings() -> void:
	if not FileAccess.file_exists(SETTINGS_PATH):
		# First run - apply defaults
		_apply_music_volume()
		_apply_sfx_volume()
		return
	
	var file = FileAccess.open(SETTINGS_PATH, FileAccess.READ)
	if not file:
		_apply_music_volume()
		_apply_sfx_volume()
		return
	
	var json_string = file.get_as_text()
	file.close()
	
	var json = JSON.new()
	var parse_result = json.parse(json_string)
	
	if parse_result != OK:
		print("AudioManager: Error parsing settings JSON")
		_apply_music_volume()
		_apply_sfx_volume()
		return
	
	var data = json.data
	
	# Load values without triggering setters (to avoid multiple saves)
	if data.has("music_volume"):
		music_volume_linear = clamp(float(data.music_volume), 0.0, 2.0)
	if data.has("sfx_volume"):
		sfx_volume_linear = clamp(float(data.sfx_volume), 0.0, 2.0)
	
	# Apply volumes
	_apply_music_volume()
	_apply_sfx_volume()
	
	print("AudioManager: Loaded settings - Music: %.2f, SFX: %.2f" % [music_volume_linear, sfx_volume_linear])

# ============================================================================
# SOUND EFFECTS
# ============================================================================

func play_ui_sound(path: String, volume_db := 0.0, pitch := 1.0) -> void:
	_play_from_pool(_ui_player_pool, path, volume_db + _sfx_db_offset, pitch)

func play_sfx(path: String, volume_db := 0.0, pitch := 1.0) -> void:
	_play_from_pool(_sfx_player_pool, path, volume_db + _sfx_db_offset, pitch)

func _play_from_pool(pool: Array[AudioStreamPlayer], path: String, volume_db: float, pitch: float) -> void:
	var stream: AudioStream
	
	# Check cache first
	if path in _sound_cache:
		stream = _sound_cache[path]
	elif ResourceLoader.exists(path):
		stream = load(path)
		_sound_cache[path] = stream
	else:
		print("AudioManager: Sound file not found: ", path)
		return
	
	# Find available player in pool
	for player in pool:
		if not player.playing:
			player.stream = stream
			player.volume_db = volume_db
			player.pitch_scale = pitch
			player.play()
			return
	
	# All players busy, use first one (interrupting it)
	pool[0].stream = stream
	pool[0].volume_db = volume_db
	pool[0].pitch_scale = pitch
	pool[0].play()

# ============================================================================
# CONVENIENCE METHODS FOR UI SOUNDS
# ============================================================================

func play_hover() -> void:
	play_ui_sound(SFX_UI_HOVER, -6.0)

func play_select() -> void:
	play_ui_sound(SFX_UI_SELECT, -10.0)

func play_back() -> void:
	play_ui_sound(SFX_UI_BACK, -10.0)

func play_pause() -> void:
	play_ui_sound(SFX_UI_PAUSE, -10.0)

func play_resume() -> void:
	play_ui_sound(SFX_UI_RESUME, -10.0)

func play_keystroke() -> void:
	play_ui_sound(SFX_UI_KEYSTROKE, -3.0, randf_range(0.95, 1.05))

# ============================================================================
# CONVENIENCE METHODS FOR RACE SOUNDS
# ============================================================================

func play_countdown_beep() -> void:
	play_sfx(SFX_COUNTDOWN_BEEP, -6.0)

func play_countdown_go() -> void:
	play_sfx(SFX_COUNTDOWN_GO, -6.0)

func play_lap_complete() -> void:
	play_sfx(SFX_LAP_COMPLETE)

func play_final_lap() -> void:
	play_sfx(SFX_FINAL_LAP, 3.0)

func play_race_finish() -> void:
	play_sfx(SFX_RACE_FINISH)

func play_wrong_way() -> void:
	play_sfx(SFX_WRONG_WAY)

func play_new_record() -> void:
	play_sfx(SFX_NEW_RECORD)

func play_line_cross() -> void:
	play_sfx(SFX_LINE_CROSS, -3.0)

# ============================================================================
# VOLUME HELPERS
# ============================================================================

func _update_bus_volume(bus_name: String, linear_volume: float) -> void:
	var bus_idx = AudioServer.get_bus_index(bus_name)
	if bus_idx >= 0:
		var db = linear_to_db(linear_volume) if linear_volume > 0 else -80.0
		AudioServer.set_bus_volume_db(bus_idx, db)

func _linear_to_db(linear: float) -> float:
	if linear <= 0:
		return -80.0
	return 20.0 * log(linear) / log(10.0)

# ============================================================================
# DEPRECATED MUSIC SHORTCUTS
# Music is now handled by MusicPlaylistManager
# These functions are kept as no-ops for backward compatibility
# ============================================================================

func play_menu_music() -> void:
	# DEPRECATED: Use MusicPlaylistManager.start_menu_music() instead
	pass

func play_race_music() -> void:
	# DEPRECATED: Use MusicPlaylistManager.start_race_music() instead
	pass

func play_results_music() -> void:
	# DEPRECATED: Music continues from race via MusicPlaylistManager
	pass

func stop_music(_fade_out := true) -> void:
	# DEPRECATED: Use MusicPlaylistManager.stop_music() instead
	pass

func pause_music() -> void:
	# DEPRECATED: Use MusicPlaylistManager.pause_music() instead
	pass

func resume_music() -> void:
	# DEPRECATED: Use MusicPlaylistManager.resume_music() instead
	pass

func is_music_playing() -> bool:
	# DEPRECATED: Use MusicPlaylistManager.is_playing() instead
	return false
