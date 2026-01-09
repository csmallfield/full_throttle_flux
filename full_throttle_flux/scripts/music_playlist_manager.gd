extends Node

## Music Playlist Manager Singleton
## Handles auto-discovery of music tracks, shuffled playback, and crossfading
## Emits signals for UI updates (now playing display)
## Volume is controlled via AudioManager.music_volume_linear

# ============================================================================
# SIGNALS
# ============================================================================

## Emitted when a new track starts playing
signal track_started(track: MusicTrack)

## Emitted when music stops completely
signal music_stopped()

# ============================================================================
# CONFIGURATION
# ============================================================================

const MUSIC_FOLDER := "res://music/"

@export_group("Playback Settings")
## Time for crossfade between tracks (seconds)
@export var crossfade_duration := 2.0

## Base volume for music playback (dB) - modified by AudioManager
var music_volume_db := -12.0

## Time to wait before starting next track after one ends
@export var track_gap := 0.5

# ============================================================================
# STATE
# ============================================================================

enum Context { MENU, RACE }

var _current_context: Context = Context.MENU
var _all_tracks: Array[MusicTrack] = []
var _menu_tracks: Array[MusicTrack] = []
var _race_tracks: Array[MusicTrack] = []

# Shuffle queues (tracks waiting to be played)
var _menu_queue: Array[MusicTrack] = []
var _race_queue: Array[MusicTrack] = []

# Currently playing
var _current_track: MusicTrack = null
var _last_race_track: MusicTrack = null  # To avoid when returning to menu

# Audio players for crossfading
var _player_a: AudioStreamPlayer
var _player_b: AudioStreamPlayer
var _active_player: AudioStreamPlayer
var _is_playing := false

# Track if we're in a fade out (to prevent volume updates during fade)
var _is_fading_out := false

# ============================================================================
# INITIALIZATION
# ============================================================================

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_create_audio_players()
	_discover_tracks()
	_build_playlists()

func _create_audio_players() -> void:
	_player_a = AudioStreamPlayer.new()
	_player_a.name = "MusicPlayerA"
	_player_a.bus = "Master"
	_player_a.volume_db = music_volume_db
	_player_a.finished.connect(_on_track_finished)
	add_child(_player_a)
	
	_player_b = AudioStreamPlayer.new()
	_player_b.name = "MusicPlayerB"
	_player_b.bus = "Master"
	_player_b.volume_db = music_volume_db
	_player_b.finished.connect(_on_track_finished)
	add_child(_player_b)
	
	_active_player = _player_a

func _discover_tracks() -> void:
	_all_tracks.clear()
	
	var dir = DirAccess.open(MUSIC_FOLDER)
	if not dir:
		print("MusicPlaylistManager: Could not open music folder: ", MUSIC_FOLDER)
		return
	
	dir.list_dir_begin()
	var file_name = dir.get_next()
	
	while file_name != "":
		# Look for .tres files (our MusicTrack resources)
		if file_name.ends_with(".tres") or file_name.ends_with(".res"):
			var resource_path = MUSIC_FOLDER + file_name
			var resource = load(resource_path)
			
			if resource is MusicTrack:
				var track = resource as MusicTrack
				if track.is_valid():
					_all_tracks.append(track)
					print("MusicPlaylistManager: Discovered track: ", track.get_display_text())
				else:
					print("MusicPlaylistManager: Invalid track (no audio): ", file_name)
		
		file_name = dir.get_next()
	
	dir.list_dir_end()
	print("MusicPlaylistManager: Found %d valid tracks" % _all_tracks.size())

func _build_playlists() -> void:
	_menu_tracks.clear()
	_race_tracks.clear()
	
	for track in _all_tracks:
		if track.use_in_menu:
			_menu_tracks.append(track)
		if track.use_in_race:
			_race_tracks.append(track)
	
	print("MusicPlaylistManager: Menu tracks: %d, Race tracks: %d" % [_menu_tracks.size(), _race_tracks.size()])
	
	# Initialize shuffle queues
	_reshuffle_menu_queue()
	_reshuffle_race_queue()

# ============================================================================
# SHUFFLE QUEUE MANAGEMENT
# ============================================================================

func _reshuffle_menu_queue() -> void:
	_menu_queue = _menu_tracks.duplicate()
	_menu_queue.shuffle()
	print("MusicPlaylistManager: Reshuffled menu queue (%d tracks)" % _menu_queue.size())

func _reshuffle_race_queue() -> void:
	_race_queue = _race_tracks.duplicate()
	_race_queue.shuffle()
	print("MusicPlaylistManager: Reshuffled race queue (%d tracks)" % _race_queue.size())

func _get_next_menu_track() -> MusicTrack:
	# If queue is empty, reshuffle
	if _menu_queue.is_empty():
		_reshuffle_menu_queue()
	
	# If still empty, no tracks available
	if _menu_queue.is_empty():
		return null
	
	# Try to avoid the track that just played during race
	if _last_race_track != null and _menu_queue.size() > 1:
		var index = _menu_queue.find(_last_race_track)
		if index == 0:
			# Move it to the end
			var track = _menu_queue.pop_front()
			_menu_queue.append(track)
	
	return _menu_queue.pop_front()

func _get_next_race_track() -> MusicTrack:
	# If queue is empty, reshuffle
	if _race_queue.is_empty():
		_reshuffle_race_queue()
	
	# If still empty, no tracks available
	if _race_queue.is_empty():
		return null
	
	return _race_queue.pop_front()

# ============================================================================
# PLAYBACK CONTROL
# ============================================================================

## Start playing music for menu context
func start_menu_music() -> void:
	_current_context = Context.MENU
	_last_race_track = null  # Clear if coming fresh to menu
	_is_fading_out = false
	var track = _get_next_menu_track()
	if track:
		_play_track(track, true)

## Start playing music for race context
func start_race_music() -> void:
	_current_context = Context.RACE
	_is_fading_out = false
	var track = _get_next_race_track()
	if track:
		_last_race_track = track  # Remember for when returning to menu
		_play_track(track, true)

## Continue playing music when returning to menu from race
## Avoids the track that was just playing in race
func continue_to_menu_music() -> void:
	# Remember what was playing in race before switching context
	if _current_context == Context.RACE and _current_track != null:
		_last_race_track = _current_track
	
	_current_context = Context.MENU
	_is_fading_out = false
	var track = _get_next_menu_track()
	if track:
		_play_track(track, true)

## Fade out and stop all music
func stop_music(fade_out := true) -> void:
	if not _is_playing:
		return
	
	_is_playing = false
	_is_fading_out = true
	
	if fade_out:
		var tween = create_tween()
		tween.tween_property(_active_player, "volume_db", -80.0, crossfade_duration)
		tween.tween_callback(func():
			_active_player.stop()
			_active_player.volume_db = music_volume_db
			_is_fading_out = false
		)
	else:
		_active_player.stop()
		_is_fading_out = false
	
	music_stopped.emit()

## Fade out music (used when transitioning from menu to race countdown)
func fade_out_for_race() -> void:
	if not _is_playing:
		return
	
	_is_fading_out = true
	
	var tween = create_tween()
	tween.tween_property(_active_player, "volume_db", -80.0, crossfade_duration)
	tween.tween_callback(func():
		_active_player.stop()
		_active_player.volume_db = music_volume_db
		_is_playing = false
		_is_fading_out = false
	)

## Pause music playback
func pause_music() -> void:
	_player_a.stream_paused = true
	_player_b.stream_paused = true

## Resume music playback
func resume_music() -> void:
	_player_a.stream_paused = false
	_player_b.stream_paused = false

## Check if music is currently playing
func is_playing() -> bool:
	return _is_playing and (_player_a.playing or _player_b.playing)

## Get currently playing track
func get_current_track() -> MusicTrack:
	return _current_track

# ============================================================================
# INTERNAL PLAYBACK
# ============================================================================

func _play_track(track: MusicTrack, crossfade := true) -> void:
	if track == null or track.audio_stream == null:
		print("MusicPlaylistManager: Cannot play null track")
		return
	
	print("MusicPlaylistManager: Playing: ", track.get_display_text())
	
	var old_player = _active_player
	var new_player = _player_b if _active_player == _player_a else _player_a
	
	# Set up new player
	new_player.stream = track.audio_stream
	new_player.volume_db = -80.0 if crossfade and _is_playing else music_volume_db
	new_player.play()
	
	if crossfade and _is_playing:
		# Crossfade from old to new
		var tween = create_tween()
		tween.set_parallel(true)
		tween.tween_property(old_player, "volume_db", -80.0, crossfade_duration)
		tween.tween_property(new_player, "volume_db", music_volume_db, crossfade_duration)
		tween.set_parallel(false)
		tween.tween_callback(func(): old_player.stop())
	elif _is_playing:
		old_player.stop()
	
	_active_player = new_player
	_current_track = track
	_is_playing = true
	
	print("MusicPlaylistManager: Emitting track_started signal for: ", track.track_name)
	track_started.emit(track)

func _on_track_finished() -> void:
	# Only respond if this was the active player
	if not _is_playing:
		return
	
	# Small delay before next track
	await get_tree().create_timer(track_gap).timeout
	
	# Check we're still supposed to be playing
	if not _is_playing:
		return
	
	# Play next track based on context
	var next_track: MusicTrack = null
	
	match _current_context:
		Context.MENU:
			next_track = _get_next_menu_track()
		Context.RACE:
			next_track = _get_next_race_track()
	
	if next_track:
		_play_track(next_track, false)  # No crossfade for natural track end
	else:
		_is_playing = false
		music_stopped.emit()

# ============================================================================
# VOLUME CONTROL
# ============================================================================

## Set the music volume in dB (called by AudioManager)
func set_volume(volume_db: float) -> void:
	music_volume_db = volume_db
	
	# Don't update player volumes if we're in a fade out
	if _is_fading_out:
		return
	
	# Check if players exist (may be called before _ready)
	if not _player_a or not _player_b:
		return
	
	# Update active player volume immediately if playing
	if _is_playing and _active_player:
		_active_player.volume_db = volume_db
	
	# Also update the inactive player in case it's used next
	_player_a.volume_db = volume_db
	_player_b.volume_db = volume_db
