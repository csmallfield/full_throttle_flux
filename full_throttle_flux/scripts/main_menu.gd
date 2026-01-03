extends Control
class_name MainMenu

## Main menu for the racing game

var title_label: Label
var start_button: Button
var leaderboard_button: Button
var quit_button: Button

func _ready() -> void:
	_create_ui()
	_connect_signals()

func _create_ui() -> void:
	# Title
	if not has_node("TitleLabel"):
		title_label = Label.new()
		title_label.name = "TitleLabel"
		add_child(title_label)
	
	title_label.text = "ANTI-GRAV RACING 2097"
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
	parent.add_child(button)
	return button

func _connect_signals() -> void:
	if start_button:
		start_button.pressed.connect(_on_start_pressed)
	if leaderboard_button:
		leaderboard_button.pressed.connect(_on_leaderboard_pressed)
	if quit_button:
		quit_button.pressed.connect(_on_quit_pressed)

func _on_start_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/time_trial_01.tscn")

func _on_leaderboard_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/leaderboard_screen.tscn")

func _on_quit_pressed() -> void:
	get_tree().quit()
