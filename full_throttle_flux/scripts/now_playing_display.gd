extends CanvasLayer
class_name NowPlayingDisplay

## UI component that displays "Now Playing" information when a track starts
## Shows track name and artist in the lower-left corner with fade in/out

@export_group("Display Settings")
## How long the display stays visible (seconds)
@export var display_duration := 5.0

## Fade in duration (seconds)
@export var fade_in_time := 0.5

## Fade out duration (seconds)
@export var fade_out_time := 1.0

@export_group("Position")
## Margin from left edge of screen
@export var margin_left := 20

## Margin from bottom edge of screen
@export var margin_bottom := 40

@export_group("Appearance")
## Font size for track name
@export var track_name_size := 20

## Font size for artist
@export var artist_size := 16

## Color for track name
@export var track_name_color := Color(1.0, 1.0, 1.0, 1.0)

## Color for artist name
@export var artist_color := Color(0.7, 0.7, 0.7, 1.0)

## Color for "NOW PLAYING" label
@export var label_color := Color(0.3, 0.8, 1.0, 1.0)

# UI Elements
var _container: VBoxContainer
var _now_playing_label: Label
var _track_name_label: Label
var _artist_label: Label

var _display_timer: float = 0.0
var _is_showing := false
var _current_tween: Tween = null

func _ready() -> void:
	print("NowPlayingDisplay: _ready() called")
	# Process even when game is paused
	process_mode = Node.PROCESS_MODE_ALWAYS
	
	_create_ui()
	_hide_immediately()
	
	# Connect to playlist manager signal
	# We need to wait a frame for autoloads to be ready
	call_deferred("_connect_signals")

func _connect_signals() -> void:
	if MusicPlaylistManager:
		MusicPlaylistManager.track_started.connect(_on_track_started)
		MusicPlaylistManager.music_stopped.connect(_on_music_stopped)
		print("NowPlayingDisplay: Connected to MusicPlaylistManager signals")
		
		# Check if a track is already playing (we may have missed the signal)
		if MusicPlaylistManager.is_playing():
			var current = MusicPlaylistManager.get_current_track()
			print("NowPlayingDisplay: Music already playing, current track: ", current)
			if current:
				_show_track_info(current)
		else:
			print("NowPlayingDisplay: No music currently playing")
	else:
		print("NowPlayingDisplay: MusicPlaylistManager not found!")

func _create_ui() -> void:
	# Create a Control node to hold everything (needed for proper positioning in CanvasLayer)
	var anchor_control = Control.new()
	anchor_control.name = "AnchorControl"
	anchor_control.set_anchors_preset(Control.PRESET_FULL_RECT)
	anchor_control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(anchor_control)
	
	# Create container positioned at bottom-left
	_container = VBoxContainer.new()
	_container.name = "NowPlayingContainer"
	_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor_control.add_child(_container)
	
	# Position in lower-left - we'll set this after the viewport is ready
	_container.add_theme_constant_override("separation", 2)
	
	# "NOW PLAYING" label
	_now_playing_label = Label.new()
	_now_playing_label.name = "NowPlayingLabel"
	_now_playing_label.text = "♪ NOW PLAYING"
	_now_playing_label.add_theme_font_size_override("font_size", 12)
	_now_playing_label.add_theme_color_override("font_color", label_color)
	_container.add_child(_now_playing_label)
	
	# Track name
	_track_name_label = Label.new()
	_track_name_label.name = "TrackNameLabel"
	_track_name_label.text = "Track Name"
	_track_name_label.add_theme_font_size_override("font_size", track_name_size)
	_track_name_label.add_theme_color_override("font_color", track_name_color)
	_track_name_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_track_name_label.add_theme_constant_override("shadow_offset_x", 1)
	_track_name_label.add_theme_constant_override("shadow_offset_y", 1)
	_container.add_child(_track_name_label)
	
	# Artist
	_artist_label = Label.new()
	_artist_label.name = "ArtistLabel"
	_artist_label.text = "Artist"
	_artist_label.add_theme_font_size_override("font_size", artist_size)
	_artist_label.add_theme_color_override("font_color", artist_color)
	_artist_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	_artist_label.add_theme_constant_override("shadow_offset_x", 1)
	_artist_label.add_theme_constant_override("shadow_offset_y", 1)
	_container.add_child(_artist_label)
	
	# Position after layout is calculated
	call_deferred("_update_position")

func _update_position() -> void:
	var viewport_size = get_viewport().get_visible_rect().size
	_container.position = Vector2(margin_left, viewport_size.y - margin_bottom - 80)
	print("NowPlayingDisplay: Positioned at ", _container.position, " (viewport: ", viewport_size, ")")

func _process(delta: float) -> void:
	if _is_showing:
		_display_timer -= delta
		if _display_timer <= 0:
			_fade_out()

func _on_track_started(track: MusicTrack) -> void:
	if track == null:
		return
	
	_show_track_info(track)

func _on_music_stopped() -> void:
	_fade_out()

func _show_track_info(track: MusicTrack) -> void:
	print("NowPlayingDisplay: Showing track - ", track.track_name, " by ", track.artist)
	
	# Update text
	_track_name_label.text = track.track_name
	_artist_label.text = track.artist
	
	# Reset timer
	_display_timer = display_duration
	_is_showing = true
	
	# Cancel any existing tween
	if _current_tween and _current_tween.is_valid():
		_current_tween.kill()
	
	# Fade in
	_container.modulate.a = 0.0
	_container.visible = true
	
	_current_tween = create_tween()
	_current_tween.tween_property(_container, "modulate:a", 1.0, fade_in_time)

func _fade_out() -> void:
	if not _is_showing:
		return
	
	_is_showing = false
	
	# Cancel any existing tween
	if _current_tween and _current_tween.is_valid():
		_current_tween.kill()
	
	_current_tween = create_tween()
	_current_tween.tween_property(_container, "modulate:a", 0.0, fade_out_time)
	_current_tween.tween_callback(func(): _container.visible = false)

func _hide_immediately() -> void:
	_container.visible = false
	_container.modulate.a = 0.0
	_is_showing = false

## Manually show track info (for testing or manual triggers)
func show_track(track: MusicTrack) -> void:
	_show_track_info(track)

## Force hide the display
func hide_display() -> void:
	_fade_out()
