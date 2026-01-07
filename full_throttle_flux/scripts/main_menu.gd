extends Control
class_name MainMenu

## Main menu for the racing game
## Uses MusicPlaylistManager for shuffled music playback

var title_label: Label
var start_button: Button
var leaderboard_button: Button
var quit_button: Button

# Now Playing display instance
var now_playing_display: NowPlayingDisplay

func _ready() -> void:
	_create_ui()
	_connect_signals()
	_setup_focus()
	_setup_now_playing_display()
	_start_music()

func _start_music() -> void:
	# Delay slightly to let NowPlayingDisplay connect its signals first
	await get_tree().process_frame
	await get_tree().process_frame
	
	# Only start music if not already playing (e.g., coming from leaderboard screen)
	print("MainMenu: _start_music called, is_playing=", MusicPlaylistManager.is_playing())
	if not MusicPlaylistManager.is_playing():
		MusicPlaylistManager.start_menu_music()

func _setup_now_playing_display() -> void:
	# Add the NowPlayingDisplay to this scene (deferred to avoid busy parent error)
	print("MainMenu: Setting up NowPlayingDisplay")
	var display_scene = preload("res://scenes/now_playing_display.tscn")
	now_playing_display = display_scene.instantiate()
	call_deferred("add_child", now_playing_display)

func _create_ui() -> void:
	# Title
	if not has_node("TitleLabel"):
		title_label = Label.new()
		title_label.name = "TitleLabel"
		add_child(title_label)
	
	title_label.text = "FULL THROTTLE FLUX"
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.position = Vector2(1920/2 - 400, 200)
	title_label.size = Vector2(800, 100)
	title_label.add_theme_font_size_override("font_size", 64)
	title_label.add_theme_color_override("font_color", Color(0.3, 0.8, 1.0))
	
	# Button container
	var button_container: VBoxContainer
	if not has_node("MenuButtons"):
		button_container = VBoxContainer.new()
		button_container.name = "MenuButtons"
		add_child(button_container)
	else:
		button_container = $MenuButtons
	
	button_container.position = Vector2(1920/2 - 200, 400)
	button_container.size = Vector2(400, 300)
	button_container.add_theme_constant_override("separation", 30)
	
	# Create buttons
	start_button = _create_menu_button("START TIME TRIAL", button_container)
	leaderboard_button = _create_menu_button("LEADERBOARDS", button_container)
	quit_button = _create_menu_button("QUIT", button_container)

func _create_menu_button(text: String, parent: Control) -> Button:
	var button = Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(400, 60)
	button.add_theme_font_size_override("font_size", 28)
	button.focus_mode = Control.FOCUS_ALL  # Enable focus for navigation
	parent.add_child(button)
	return button

func _connect_signals() -> void:
	if start_button:
		start_button.pressed.connect(_on_start_pressed)
		start_button.focus_entered.connect(_on_button_focus)
	if leaderboard_button:
		leaderboard_button.pressed.connect(_on_leaderboard_pressed)
		leaderboard_button.focus_entered.connect(_on_button_focus)
	if quit_button:
		quit_button.pressed.connect(_on_quit_pressed)
		quit_button.focus_entered.connect(_on_button_focus)

func _setup_focus() -> void:
	# Set up focus navigation chain
	if start_button and leaderboard_button and quit_button:
		start_button.focus_neighbor_top = quit_button.get_path()
		start_button.focus_neighbor_bottom = leaderboard_button.get_path()
		
		leaderboard_button.focus_neighbor_top = start_button.get_path()
		leaderboard_button.focus_neighbor_bottom = quit_button.get_path()
		
		quit_button.focus_neighbor_top = leaderboard_button.get_path()
		quit_button.focus_neighbor_bottom = start_button.get_path()
		
		# Set initial focus to start button
		start_button.grab_focus()

func _on_button_focus() -> void:
	AudioManager.play_hover()

func _on_start_pressed() -> void:
	AudioManager.play_select()
	
	# Fade out menu music before transitioning to race
	MusicPlaylistManager.fade_out_for_race()
	
	# Small delay to let sound play and music fade before scene change
	await get_tree().create_timer(0.3).timeout
	get_tree().change_scene_to_file("res://scenes/time_trial_01.tscn")

func _on_leaderboard_pressed() -> void:
	AudioManager.play_select()
	await get_tree().create_timer(0.1).timeout
	get_tree().change_scene_to_file("res://scenes/leaderboard_screen.tscn")

func _on_quit_pressed() -> void:
	AudioManager.play_select()
	await get_tree().create_timer(0.1).timeout
	get_tree().quit()
