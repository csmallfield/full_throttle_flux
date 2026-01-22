extends Control
class_name DifficultySelect

## Difficulty Selection Screen for Race Mode
## Displays Easy/Medium/Hard options and stores selection in GameManager
## Flow: Main Menu → Difficulty Select → Track Select → Ship Select → Race

# ============================================================================
# UI REFERENCES
# ============================================================================

var title_label: Label
var button_container: VBoxContainer
var easy_button: Button
var medium_button: Button
var hard_button: Button
var back_button: Button
var description_label: Label

# ============================================================================
# DIFFICULTY DESCRIPTIONS
# ============================================================================

const DIFFICULTY_INFO := {
	0: {
		"name": "EASY",
		"description": "Relaxed AI opponents. Perfect for learning the tracks.",
		"color": Color(0.3, 0.8, 0.3)
	},
	1: {
		"name": "MEDIUM",
		"description": "Balanced challenge. AI provides good competition.",
		"color": Color(0.8, 0.7, 0.2)
	},
	2: {
		"name": "HARD",
		"description": "Aggressive AI opponents. Only for experienced pilots.",
		"color": Color(0.9, 0.3, 0.3)
	}
}

# ============================================================================
# INITIALIZATION
# ============================================================================

func _ready() -> void:
	_create_ui()
	_setup_focus()

func _create_ui() -> void:
	# Background
	var bg = ColorRect.new()
	bg.color = Color(0.05, 0.05, 0.1, 1.0)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	
	# Title
	title_label = Label.new()
	title_label.text = "SELECT DIFFICULTY"
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.position = Vector2(1920/2 - 400, 100)
	title_label.size = Vector2(800, 80)
	title_label.add_theme_font_size_override("font_size", 56)
	title_label.add_theme_color_override("font_color", Color(0.3, 0.8, 1.0))
	add_child(title_label)
	
	# Subtitle
	var subtitle = Label.new()
	subtitle.text = "RACE MODE - 7 Opponents"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.position = Vector2(1920/2 - 400, 170)
	subtitle.size = Vector2(800, 40)
	subtitle.add_theme_font_size_override("font_size", 24)
	subtitle.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	add_child(subtitle)
	
	# Button container
	button_container = VBoxContainer.new()
	button_container.position = Vector2(1920/2 - 200, 280)
	button_container.size = Vector2(400, 400)
	button_container.add_theme_constant_override("separation", 30)
	add_child(button_container)
	
	# Easy button
	easy_button = _create_difficulty_button("EASY", 0)
	button_container.add_child(easy_button)
	
	# Medium button
	medium_button = _create_difficulty_button("MEDIUM", 1)
	button_container.add_child(medium_button)
	
	# Hard button
	hard_button = _create_difficulty_button("HARD", 2)
	button_container.add_child(hard_button)
	
	# Description panel
	var desc_panel = PanelContainer.new()
	desc_panel.position = Vector2(1920/2 - 400, 680)
	desc_panel.size = Vector2(800, 100)
	add_child(desc_panel)
	
	description_label = Label.new()
	description_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	description_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	description_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description_label.add_theme_font_size_override("font_size", 24)
	description_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	desc_panel.add_child(description_label)
	
	# Back button
	back_button = Button.new()
	back_button.text = "← BACK"
	back_button.position = Vector2(100, 950)
	back_button.size = Vector2(200, 50)
	back_button.add_theme_font_size_override("font_size", 24)
	back_button.focus_mode = Control.FOCUS_ALL
	back_button.pressed.connect(_on_back_pressed)
	back_button.focus_entered.connect(_on_back_focus)
	add_child(back_button)

func _create_difficulty_button(text: String, difficulty: int) -> Button:
	var btn = Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(400, 80)
	btn.add_theme_font_size_override("font_size", 36)
	btn.focus_mode = Control.FOCUS_ALL
	btn.pressed.connect(_on_difficulty_selected.bind(difficulty))
	btn.focus_entered.connect(_on_difficulty_focused.bind(difficulty))
	return btn

func _setup_focus() -> void:
	# Vertical navigation
	easy_button.focus_neighbor_top = back_button.get_path()
	easy_button.focus_neighbor_bottom = medium_button.get_path()
	
	medium_button.focus_neighbor_top = easy_button.get_path()
	medium_button.focus_neighbor_bottom = hard_button.get_path()
	
	hard_button.focus_neighbor_top = medium_button.get_path()
	hard_button.focus_neighbor_bottom = back_button.get_path()
	
	back_button.focus_neighbor_top = hard_button.get_path()
	back_button.focus_neighbor_bottom = easy_button.get_path()
	
	# Initial focus on medium (sensible default)
	medium_button.grab_focus()

# ============================================================================
# CALLBACKS
# ============================================================================

func _on_difficulty_focused(difficulty: int) -> void:
	AudioManager.play_hover()
	var info = DIFFICULTY_INFO[difficulty]
	description_label.text = info.description
	description_label.add_theme_color_override("font_color", info.color)

func _on_difficulty_selected(difficulty: int) -> void:
	AudioManager.play_select()
	
	# Store difficulty in GameManager
	GameManager.selected_race_difficulty = difficulty
	
	print("DifficultySelect: Selected %s (difficulty %d)" % [DIFFICULTY_INFO[difficulty].name, difficulty])
	
	# Proceed to track selection
	await get_tree().create_timer(0.15).timeout
	get_tree().change_scene_to_file("res://scenes/ui/track_select.tscn")

func _on_back_pressed() -> void:
	AudioManager.play_back()
	await get_tree().create_timer(0.1).timeout
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")

func _on_back_focus() -> void:
	AudioManager.play_hover()
	description_label.text = ""

# ============================================================================
# INPUT
# ============================================================================

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_on_back_pressed()
		get_viewport().set_input_as_handled()
