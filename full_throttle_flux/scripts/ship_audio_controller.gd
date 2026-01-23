extends Node3D
class_name ShipAudioController

## Dynamic Ship Audio System
## Handles layered engine sounds, boost effects, airbrakes, collisions, and wind
## Respects global SFX volume from AudioManager
## 
## Engine system uses 3 layers (idle, mid, high) with crossfading and pitch shifting
## Responds to both throttle input (immediate) and actual velocity (ceiling)

# ============================================================================
# SOUND PATHS
# ============================================================================

const SFX_ENGINE_IDLE := "res://sounds/ship/engine_idle.wav"
const SFX_ENGINE_MID := "res://sounds/ship/engine_mid.wav"
const SFX_ENGINE_HIGH := "res://sounds/ship/engine_high.wav"
const SFX_ENGINE_BOOST := "res://sounds/ship/engine_boost_layer.wav"
const SFX_BOOST_SURGE := "res://sounds/ship/boost_surge.wav"
const SFX_WALL_HIT := "res://sounds/ship/wall_hit.wav"
const SFX_WALL_SCRAPE := "res://sounds/ship/wall_scrape.wav"
const SFX_AIRBRAKE_HYDRAULIC := "res://sounds/ship/airbrake_hydraulic.wav"
const SFX_AIRBRAKE_WIND := "res://sounds/ship/airbrake_wind.wav"
const SFX_SHIP_LAND := "res://sounds/ship/ship_land.wav"
const SFX_WIND_LOOP := "res://sounds/ship/wind_loop.wav"

# ============================================================================
# CONFIGURATION
# ============================================================================

@export_group("Ship Reference")
@export var ship: CharacterBody3D

@export_group("Engine Sound Settings")
## Base volume for engine sounds (dB)
@export var engine_base_volume := -6.0
## Minimum pitch multiplier at idle
@export var engine_min_pitch := 0.7
## Maximum pitch multiplier at top speed
@export var engine_max_pitch := 1.8
## How much throttle affects pitch (0-1)
@export var throttle_pitch_influence := 0.3
## How quickly engine pitch responds to changes
@export var engine_pitch_smoothing := 8.0
## How quickly engine volume responds to changes
@export var engine_volume_smoothing := 6.0

@export_group("Layer Crossfade Settings")
## Speed ratio where idle layer starts fading out (0-1)
@export var idle_fade_start := 0.0
## Speed ratio where idle layer is silent
@export var idle_fade_end := 0.3
## Speed ratio where mid layer starts
@export var mid_fade_start := 0.1
## Speed ratio where mid layer is at full volume
@export var mid_fade_full := 0.4
## Speed ratio where mid layer starts fading
@export var mid_fade_end := 0.8
## Speed ratio where high layer starts
@export var high_fade_start := 0.6
## Speed ratio where high layer is at full volume
@export var high_fade_full := 0.9

@export_group("Boost Settings")
## How long the boost pitch effect lasts
@export var boost_pitch_duration := 1.5
## Extra pitch added during boost
@export var boost_pitch_bonus := 0.3
## Volume of boost layer when active (dB)
@export var boost_layer_volume := -3.0

@export_group("Airbrake Settings")
## Volume of airbrake hydraulic sound (dB)
@export var airbrake_hydraulic_volume := -6.0
## Volume of airbrake wind at full airbrake (dB)
@export var airbrake_wind_max_volume := -6.0
## Pitch reduction when airbraking (strain effect)
@export var airbrake_pitch_strain := 0.15

@export_group("Wind Settings")
## Minimum speed ratio for wind to be audible
@export var wind_min_speed_ratio := 0.2
## Volume of wind at max speed (dB)
@export var wind_max_volume := -9.0

@export_group("Collision Settings")
## Volume of wall hit sound (dB)
@export var wall_hit_volume := 0.0
## Volume of wall scrape loop (dB)
@export var wall_scrape_volume := -6.0
## Volume of landing sound (dB)
@export var land_volume := -3.0
## Minimum airborne time to trigger landing sound
@export var land_min_airtime := 0.3

# ============================================================================
# AUDIO PLAYERS
# ============================================================================

# Engine layers (looping)
var _engine_idle: AudioStreamPlayer3D
var _engine_mid: AudioStreamPlayer3D
var _engine_high: AudioStreamPlayer3D
var _engine_boost_layer: AudioStreamPlayer3D

# One-shot sounds
var _boost_surge: AudioStreamPlayer3D
var _wall_hit: AudioStreamPlayer3D
var _ship_land: AudioStreamPlayer3D
var _airbrake_hydraulic: AudioStreamPlayer3D

# Looping effects
var _wall_scrape: AudioStreamPlayer3D
var _airbrake_wind: AudioStreamPlayer3D
var _wind_loop: AudioStreamPlayer3D

# ============================================================================
# STATE
# ============================================================================

var _current_engine_pitch := 1.0
var _target_engine_pitch := 1.0
var _boost_pitch_timer := 0.0
var _was_airbraking := false
var _was_grounded := true
var _is_scraping := false
var _last_airborne_time := 0.0

# ============================================================================
# INITIALIZATION
# ============================================================================

func _ready() -> void:
	_create_audio_players()
	_load_sounds()
	_start_engine()

func _create_audio_players() -> void:
	# Engine layers
	_engine_idle = _create_player_3d("EngineIdle", true)
	_engine_mid = _create_player_3d("EngineMid", true)
	_engine_high = _create_player_3d("EngineHigh", true)
	_engine_boost_layer = _create_player_3d("EngineBoostLayer", true)
	
	# One-shots
	_boost_surge = _create_player_3d("BoostSurge", false)
	_wall_hit = _create_player_3d("WallHit", false)
	_ship_land = _create_player_3d("ShipLand", false)
	_airbrake_hydraulic = _create_player_3d("AirbrakeHydraulic", false)
	
	# Looping effects
	_wall_scrape = _create_player_3d("WallScrape", true)
	_airbrake_wind = _create_player_3d("AirbrakeWind", true)
	_wind_loop = _create_player_3d("WindLoop", true)

func _create_player_3d(player_name: String, looping: bool) -> AudioStreamPlayer3D:
	var player = AudioStreamPlayer3D.new()
	player.name = player_name
	player.max_distance = 100.0
	player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	add_child(player)
	return player

func _load_sounds() -> void:
	_load_stream(_engine_idle, SFX_ENGINE_IDLE)
	_load_stream(_engine_mid, SFX_ENGINE_MID)
	_load_stream(_engine_high, SFX_ENGINE_HIGH)
	_load_stream(_engine_boost_layer, SFX_ENGINE_BOOST)
	_load_stream(_boost_surge, SFX_BOOST_SURGE)
	_load_stream(_wall_hit, SFX_WALL_HIT)
	_load_stream(_wall_scrape, SFX_WALL_SCRAPE)
	_load_stream(_airbrake_hydraulic, SFX_AIRBRAKE_HYDRAULIC)
	_load_stream(_airbrake_wind, SFX_AIRBRAKE_WIND)
	_load_stream(_ship_land, SFX_SHIP_LAND)
	_load_stream(_wind_loop, SFX_WIND_LOOP)

func _load_stream(player: AudioStreamPlayer3D, path: String) -> void:
	if ResourceLoader.exists(path):
		player.stream = load(path)
	else:
		print("ShipAudioController: Sound not found (placeholder): ", path)

func _start_engine() -> void:
	# Start all engine layers (we'll control volume for crossfading)
	_engine_idle.volume_db = _apply_sfx_offset(engine_base_volume)
	_engine_mid.volume_db = -80.0
	_engine_high.volume_db = -80.0
	_engine_boost_layer.volume_db = -80.0
	
	_engine_idle.play()
	_engine_mid.play()
	_engine_high.play()
	_engine_boost_layer.play()
	
	# Start wind loop (silent initially)
	_wind_loop.volume_db = -80.0
	_wind_loop.play()
	
	# Start airbrake wind (silent initially)
	_airbrake_wind.volume_db = -80.0
	_airbrake_wind.play()
	
	# Start scrape loop (silent initially)
	_wall_scrape.volume_db = -80.0
	_wall_scrape.play()

# ============================================================================
# VOLUME HELPER
# ============================================================================

## Apply the global SFX volume offset to a base volume
func _apply_sfx_offset(base_db: float) -> float:
	return base_db + AudioManager.get_sfx_db_offset()

# ============================================================================
# MAIN UPDATE
# ============================================================================

func _process(delta: float) -> void:
	if not ship:
		return
	
	_update_engine_sound(delta)
	_update_boost_effect(delta)
	_update_airbrake_sound(delta)
	_update_wind_sound(delta)
	_update_landing_detection()

# ============================================================================
# ENGINE SOUND SYSTEM
# ============================================================================

func _update_engine_sound(delta: float) -> void:
	var speed_ratio = ship.get_speed_ratio()
	var throttle = ship.throttle_input
	
	# Calculate target pitch based on both speed and throttle
	# Speed determines the "ceiling" - you can't rev higher than your speed allows
	# Throttle provides immediate responsiveness within that ceiling
	var speed_pitch = lerp(engine_min_pitch, engine_max_pitch, speed_ratio)
	var throttle_pitch = lerp(0.0, throttle_pitch_influence, throttle)
	
	_target_engine_pitch = speed_pitch + throttle_pitch
	
	# Add boost pitch bonus
	if _boost_pitch_timer > 0:
		var boost_factor = _boost_pitch_timer / boost_pitch_duration
		_target_engine_pitch += boost_pitch_bonus * boost_factor
	
	# Apply airbrake strain (reduces pitch slightly)
	if ship.is_airbraking:
		var brake_amount = max(ship.airbrake_left, ship.airbrake_right)
		_target_engine_pitch -= airbrake_pitch_strain * brake_amount
	
	# Smooth pitch transition
	_current_engine_pitch = lerp(_current_engine_pitch, _target_engine_pitch, engine_pitch_smoothing * delta)
	
	# Apply pitch to all engine layers
	_engine_idle.pitch_scale = _current_engine_pitch
	_engine_mid.pitch_scale = _current_engine_pitch
	_engine_high.pitch_scale = _current_engine_pitch
	_engine_boost_layer.pitch_scale = _current_engine_pitch * 1.2  # Boost layer slightly higher
	
	# Calculate layer volumes (crossfading)
	var idle_vol = _calculate_layer_volume(speed_ratio, idle_fade_start, idle_fade_end, true)
	var mid_vol = _calculate_mid_layer_volume(speed_ratio)
	var high_vol = _calculate_layer_volume(speed_ratio, high_fade_start, high_fade_full, false)
	
	# Apply volumes with smoothing and global SFX offset
	var sfx_offset = AudioManager.get_sfx_db_offset()
	_engine_idle.volume_db = lerp(_engine_idle.volume_db, _linear_to_db(idle_vol) + engine_base_volume + sfx_offset, engine_volume_smoothing * delta)
	_engine_mid.volume_db = lerp(_engine_mid.volume_db, _linear_to_db(mid_vol) + engine_base_volume + sfx_offset, engine_volume_smoothing * delta)
	_engine_high.volume_db = lerp(_engine_high.volume_db, _linear_to_db(high_vol) + engine_base_volume + sfx_offset, engine_volume_smoothing * delta)

func _calculate_layer_volume(speed_ratio: float, start: float, end: float, fade_out: bool) -> float:
	if fade_out:
		# Fades from 1 to 0 as speed increases
		if speed_ratio <= start:
			return 1.0
		elif speed_ratio >= end:
			return 0.0
		else:
			return 1.0 - (speed_ratio - start) / (end - start)
	else:
		# Fades from 0 to 1 as speed increases
		if speed_ratio <= start:
			return 0.0
		elif speed_ratio >= end:
			return 1.0
		else:
			return (speed_ratio - start) / (end - start)

func _calculate_mid_layer_volume(speed_ratio: float) -> float:
	# Mid layer fades in, holds, then fades out
	if speed_ratio < mid_fade_start:
		return 0.0
	elif speed_ratio < mid_fade_full:
		return (speed_ratio - mid_fade_start) / (mid_fade_full - mid_fade_start)
	elif speed_ratio < mid_fade_end:
		return 1.0
	elif speed_ratio < 1.0:
		return 1.0 - (speed_ratio - mid_fade_end) / (1.0 - mid_fade_end)
	else:
		return 0.0

# ============================================================================
# BOOST EFFECT
# ============================================================================

func _update_boost_effect(delta: float) -> void:
	var sfx_offset = AudioManager.get_sfx_db_offset()
	
	if _boost_pitch_timer > 0:
		_boost_pitch_timer -= delta
		
		# Boost layer volume based on remaining time
		var boost_factor = _boost_pitch_timer / boost_pitch_duration
		var target_boost_vol = lerp(-80.0, boost_layer_volume + sfx_offset, boost_factor)
		_engine_boost_layer.volume_db = lerp(_engine_boost_layer.volume_db, target_boost_vol, 10.0 * delta)
	else:
		# Fade out boost layer
		_engine_boost_layer.volume_db = lerp(_engine_boost_layer.volume_db, -80.0, 5.0 * delta)

## Called externally when ship hits a boost pad
func trigger_boost() -> void:
	_boost_pitch_timer = boost_pitch_duration
	
	# Play boost surge one-shot
	if _boost_surge.stream:
		_boost_surge.volume_db = _apply_sfx_offset(0.0)
		_boost_surge.pitch_scale = randf_range(0.95, 1.05)
		_boost_surge.play()

# ============================================================================
# AIRBRAKE SOUND
# ============================================================================

func _update_airbrake_sound(delta: float) -> void:
	var is_airbraking = ship.is_airbraking
	var brake_amount = max(ship.airbrake_left, ship.airbrake_right)
	var sfx_offset = AudioManager.get_sfx_db_offset()
	
	# Detect airbrake engage
	if is_airbraking and not _was_airbraking:
		_play_airbrake_engage()
	
	_was_airbraking = is_airbraking
	
	# Update airbrake wind volume based on brake amount and speed
	if is_airbraking:
		var speed_factor = ship.get_speed_ratio()
		var target_wind_vol = lerp(-80.0, airbrake_wind_max_volume + sfx_offset, brake_amount * speed_factor)
		_airbrake_wind.volume_db = lerp(_airbrake_wind.volume_db, target_wind_vol, 8.0 * delta)
		
		# Pitch increases slightly with speed
		_airbrake_wind.pitch_scale = lerp(0.8, 1.2, speed_factor)
	else:
		_airbrake_wind.volume_db = lerp(_airbrake_wind.volume_db, -80.0, 10.0 * delta)

func _play_airbrake_engage() -> void:
	if _airbrake_hydraulic.stream:
		_airbrake_hydraulic.volume_db = _apply_sfx_offset(airbrake_hydraulic_volume)
		_airbrake_hydraulic.pitch_scale = randf_range(0.95, 1.05)
		_airbrake_hydraulic.play()

# ============================================================================
# WIND SOUND
# ============================================================================

func _update_wind_sound(delta: float) -> void:
	var speed_ratio = ship.get_speed_ratio()
	var sfx_offset = AudioManager.get_sfx_db_offset()
	
	if speed_ratio > wind_min_speed_ratio:
		var wind_factor = (speed_ratio - wind_min_speed_ratio) / (1.0 - wind_min_speed_ratio)
		var target_vol = lerp(-80.0, wind_max_volume + sfx_offset, wind_factor)
		_wind_loop.volume_db = lerp(_wind_loop.volume_db, target_vol, 5.0 * delta)
		_wind_loop.pitch_scale = lerp(0.8, 1.3, wind_factor)
	else:
		_wind_loop.volume_db = lerp(_wind_loop.volume_db, -80.0, 5.0 * delta)

# ============================================================================
# LANDING DETECTION
# ============================================================================

func _update_landing_detection() -> void:
	var is_grounded = ship.is_grounded
	
	# Track airborne time
	if not is_grounded:
		_last_airborne_time = ship.time_since_grounded
	
	# Detect landing
	if is_grounded and not _was_grounded:
		if _last_airborne_time > land_min_airtime:
			_play_landing()
	
	_was_grounded = is_grounded

func _play_landing() -> void:
	if _ship_land.stream:
		# Louder landing for longer airtime
		var volume_bonus = clamp((_last_airborne_time - land_min_airtime) * 3.0, 0.0, 6.0)
		_ship_land.volume_db = _apply_sfx_offset(land_volume + volume_bonus)
		_ship_land.pitch_scale = randf_range(0.9, 1.1)
		_ship_land.play()

# ============================================================================
# COLLISION SOUNDS (Called externally from ship)
# ============================================================================

func play_wall_hit(impact_speed: float) -> void:
	if _wall_hit.stream:
		# Volume and pitch based on impact speed
		var speed_factor = clamp(impact_speed / ship.max_speed, 0.0, 1.0)
		_wall_hit.volume_db = _apply_sfx_offset(wall_hit_volume + (speed_factor * 6.0))
		_wall_hit.pitch_scale = lerp(-1.0, -0.5, speed_factor)
		_wall_hit.play()

func start_wall_scrape() -> void:
	if _is_scraping:
		return
	_is_scraping = true
	
	if _wall_scrape.stream:
		_wall_scrape.volume_db = _apply_sfx_offset(wall_scrape_volume)
		# Don't restart if already playing
		if not _wall_scrape.playing:
			_wall_scrape.play()

func stop_wall_scrape() -> void:
	_is_scraping = false
	# Fade out quickly
	var tween = create_tween()
	tween.tween_property(_wall_scrape, "volume_db", -80.0, 0.1)

func update_wall_scrape_intensity(speed: float) -> void:
	if _is_scraping and _wall_scrape.stream:
		var speed_factor = clamp(speed / ship.max_speed, 0.0, 1.0)
		_wall_scrape.volume_db = _apply_sfx_offset(wall_scrape_volume + (speed_factor * 6.0))
		_wall_scrape.pitch_scale = lerp(0.7, 1.3, speed_factor)

# ============================================================================
# UTILITY
# ============================================================================

func _linear_to_db(linear: float) -> float:
	if linear <= 0.001:
		return -80.0
	return 20.0 * log(linear) / log(10.0)

## Stop all audio (for cleanup or pause)
func stop_all() -> void:
	for child in get_children():
		if child is AudioStreamPlayer3D:
			child.stop()

## Resume engine sounds after pause
func resume_engine() -> void:
	if not _engine_idle.playing:
		_start_engine()
