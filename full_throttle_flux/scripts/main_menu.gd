extends Control
class_name MainMenu

## Main menu for the racing game
## Uses MusicPlaylistManager for shuffled music playback

var title_label: Label
var start_button: Button
var endless_button: Button
var race_button: Button
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
	
	title_label.text = ""
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
	
	button_container.position = Vector2(1920/2 - 200, 320)
	button_container.size = Vector2(400, 500)
	button_container.add_theme_constant_override("separation", 25)
	
	# Create buttons
	start_button = _create_menu_button("TIME TRIAL", button_container)
	endless_button = _create_menu_button("ENDLESS MODE", button_container)
	race_button = _create_menu_button("RACE MODE", button_container)
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
	if endless_button:
		endless_button.pressed.connect(_on_endless_pressed)
		endless_button.focus_entered.connect(_on_button_focus)
	if race_button:
		race_button.pressed.connect(_on_race_pressed)
		race_button.focus_entered.connect(_on_button_focus)
	if leaderboard_button:
		leaderboard_button.pressed.connect(_on_leaderboard_pressed)
		leaderboard_button.focus_entered.connect(_on_button_focus)
	if quit_button:
		quit_button.pressed.connect(_on_quit_pressed)
		quit_button.focus_entered.connect(_on_button_focus)

func _setup_focus() -> void:
	# Set up focus navigation chain
	if start_button and endless_button and race_button and leaderboard_button and quit_button:
		start_button.focus_neighbor_top = quit_button.get_path()
		start_button.focus_neighbor_bottom = endless_button.get_path()
		
		endless_button.focus_neighbor_top = start_button.get_path()
		endless_button.focus_neighbor_bottom = race_button.get_path()
		
		race_button.focus_neighbor_top = endless_button.get_path()
		race_button.focus_neighbor_bottom = leaderboard_button.get_path()
		
		leaderboard_button.focus_neighbor_top = race_button.get_path()
		leaderboard_button.focus_neighbor_bottom = quit_button.get_path()
		
		quit_button.focus_neighbor_top = leaderboard_button.get_path()
		quit_button.focus_neighbor_bottom = start_button.get_path()
		
		# Set initial focus to start button
		start_button.grab_focus()

func _on_button_focus() -> void:
	AudioManager.play_hover()

func _on_start_pressed() -> void:
	AudioManager.play_select()
	
	# Set mode, then go to track selection
	GameManager.select_mode("time_trial")
	
	await get_tree().create_timer(0.15).timeout
	get_tree().change_scene_to_file("res://scenes/ui/track_select.tscn")

func _on_endless_pressed() -> void:
	AudioManager.play_select()
	
	# Set mode, then go to track selection
	GameManager.select_mode("endless")
	
	await get_tree().create_timer(0.15).timeout
	get_tree().change_scene_to_file("res://scenes/ui/track_select.tscn")

func _on_race_pressed() -> void:
	AudioManager.play_select()
	
	# Set mode, then go to difficulty selection
	GameManager.select_mode("race")
	
	await get_tree().create_timer(0.15).timeout
	get_tree().change_scene_to_file("res://scenes/ui/difficulty_select.tscn")

func _on_leaderboard_pressed() -> void:
	AudioManager.play_select()
	await get_tree().create_timer(0.1).timeout
	get_tree().change_scene_to_file("res://scenes/leaderboard_screen.tscn")

func _on_quit_pressed() -> void:
	AudioManager.play_select()
	await get_tree().create_timer(0.1).timeout
	get_tree().quit()
