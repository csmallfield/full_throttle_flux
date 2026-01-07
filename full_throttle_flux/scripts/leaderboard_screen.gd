extends Control
class_name LeaderboardScreen

## Standalone leaderboard viewer (accessible from main menu)
## Music continues from main menu

var container: VBoxContainer
var back_button: Button

# Now Playing display instance
var now_playing_display: NowPlayingDisplay

func _ready() -> void:
	_create_ui()
	_setup_focus()
	_setup_now_playing_display()
	# Menu music should already be playing from main menu - no need to start it

func _setup_now_playing_display() -> void:
	# Add the NowPlayingDisplay to this scene (deferred to avoid busy parent error)
	var display_scene = preload("res://scenes/now_playing_display.tscn")
	now_playing_display = display_scene.instantiate()
	call_deferred("add_child", now_playing_display)

func _create_ui() -> void:
	# Main container
	if not has_node("Container"):
		container = VBoxContainer.new()
		container.name = "Container"
		add_child(container)
	
	container.position = Vector2(100, 100)
	container.size = Vector2(1720, 800)
	container.add_theme_constant_override("separation", 30)
	
	# Title
	var title = Label.new()
	title.text = "LEADERBOARDS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 64)
	title.add_theme_color_override("font_color", Color(0.3, 0.8, 1.0))
	container.add_child(title)
	
	# Two-column layout
	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 100)
	hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	container.add_child(hbox)
	
	# Total time leaderboard
	var total_vbox = VBoxContainer.new()
	total_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(total_vbox)
	
	var total_title = Label.new()
	total_title.text = "TOTAL TIME (3 Laps)"
	total_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	total_title.add_theme_font_size_override("font_size", 36)
	total_title.add_theme_color_override("font_color", Color(1, 0.8, 0.2))
	total_vbox.add_child(total_title)
	
	var spacer1 = Control.new()
	spacer1.custom_minimum_size = Vector2(0, 20)
	total_vbox.add_child(spacer1)
	
	_populate_leaderboard(total_vbox, RaceManager.total_time_leaderboard)
	
	# Best lap leaderboard
	var lap_vbox = VBoxContainer.new()
	lap_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(lap_vbox)
	
	var lap_title = Label.new()
	lap_title.text = "BEST LAP"
	lap_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lap_title.add_theme_font_size_override("font_size", 36)
	lap_title.add_theme_color_override("font_color", Color(1, 0.8, 0.2))
	lap_vbox.add_child(lap_title)
	
	var spacer2 = Control.new()
	spacer2.custom_minimum_size = Vector2(0, 20)
	lap_vbox.add_child(spacer2)
	
	_populate_leaderboard(lap_vbox, RaceManager.best_lap_leaderboard)
	
	# Back button
	if not has_node("BackButton"):
		back_button = Button.new()
		back_button.name = "BackButton"
		add_child(back_button)
	
	back_button.text = "BACK TO MENU"
	back_button.position = Vector2(1920/2 - 150, 950)
	back_button.custom_minimum_size = Vector2(300, 70)
	back_button.add_theme_font_size_override("font_size", 32)
	back_button.focus_mode = Control.FOCUS_ALL  # Enable focus for navigation
	back_button.pressed.connect(_on_back_pressed)
	back_button.focus_entered.connect(_on_button_focus)

func _setup_focus() -> void:
	# Set initial focus to back button
	if back_button:
		back_button.grab_focus()

func _populate_leaderboard(parent: VBoxContainer, leaderboard: Array[Dictionary]) -> void:
	if leaderboard.is_empty():
		var empty_label = Label.new()
		empty_label.text = "No records yet!"
		empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_label.add_theme_font_size_override("font_size", 28)
		empty_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		parent.add_child(empty_label)
		return
	
	for i in range(leaderboard.size()):
		var entry = leaderboard[i]
		var rank_text = "%2d.  %s  -  %s" % [
			i + 1,
			entry.initials,
			RaceManager.format_time(entry.time)
		]
		
		var entry_label = Label.new()
		entry_label.text = rank_text
		entry_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		entry_label.add_theme_font_size_override("font_size", 24)
		
		# Highlight top 3
		if i < 3:
			var colors = [
				Color(1, 0.8, 0.2),      # Gold
				Color(0.8, 0.8, 0.8),    # Silver
				Color(0.8, 0.5, 0.3)     # Bronze
			]
			entry_label.add_theme_color_override("font_color", colors[i])
		else:
			entry_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
		
		parent.add_child(entry_label)

func _on_button_focus() -> void:
	AudioManager.play_hover()

func _on_back_pressed() -> void:
	AudioManager.play_back()
	# Music keeps playing - main menu will pick it up
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
