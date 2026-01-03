extends CanvasLayer
class_name ResultsScreen

## Post-race results screen with stats, initial entry, and leaderboards

enum State {
	SHOWING_STATS,
	ENTERING_INITIALS,
	SHOWING_LEADERBOARDS
}

var current_state: State = State.SHOWING_STATS
var qualification_info: Dictionary = {}
var current_initials: String = ""
var max_initials_length: int = 3

# UI References
var stats_container: VBoxContainer
var initials_container: VBoxContainer
var leaderboards_container: VBoxContainer
var buttons_container: HBoxContainer

func _ready() -> void:
	visible = false
	_create_ui()
	
	# Connect to race finished signal
	RaceManager.race_finished.connect(_on_race_finished)

func _create_ui() -> void:
	# Stats container
	stats_container = VBoxContainer.new()
	stats_container.name = "StatsContainer"
	stats_container.position = Vector2(1920/2 - 300, 150)
	stats_container.size = Vector2(600, 400)
	stats_container.add_theme_constant_override("separation", 20)
	add_child(stats_container)
	
	# Initials container
	initials_container = VBoxContainer.new()
	initials_container.name = "InitialsContainer"
	initials_container.position = Vector2(1920/2 - 300, 400)
	initials_container.size = Vector2(600, 200)
	initials_container.add_theme_constant_override("separation", 20)
	initials_container.visible = false
	add_child(initials_container)
	
	# Leaderboards container
	leaderboards_container = VBoxContainer.new()
	leaderboards_container.name = "LeaderboardsContainer"
	leaderboards_container.position = Vector2(100, 150)
	leaderboards_container.size = Vector2(1720, 700)
	leaderboards_container.add_theme_constant_override("separation", 30)
	leaderboards_container.visible = false
	add_child(leaderboards_container)
	
	# Buttons container
	buttons_container = HBoxContainer.new()
	buttons_container.name = "ButtonsContainer"
	buttons_container.position = Vector2(1920/2 - 250, 900)
	buttons_container.size = Vector2(500, 80)
	buttons_container.add_theme_constant_override("separation", 30)
	buttons_container.visible = false
	add_child(buttons_container)

func _on_race_finished(total_time: float, best_lap: float) -> void:
	await get_tree().create_timer(2.0).timeout
	
	visible = true
	_show_stats(total_time, best_lap)

func _show_stats(total_time: float, best_lap: float) -> void:
	current_state = State.SHOWING_STATS
	stats_container.visible = true
	initials_container.visible = false
	leaderboards_container.visible = false
	buttons_container.visible = false
	
	# Clear previous content
	for child in stats_container.get_children():
		child.queue_free()
	
	# Title
	var title = Label.new()
	title.text = "RACE COMPLETE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 56)
	title.add_theme_color_override("font_color", Color(0.3, 1, 0.3))
	stats_container.add_child(title)
	
	# Spacer
	var spacer1 = Control.new()
	spacer1.custom_minimum_size = Vector2(0, 30)
	stats_container.add_child(spacer1)
	
	# Total time
	var total_label = Label.new()
	total_label.text = "Total Time: " + RaceManager.format_time(total_time)
	total_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	total_label.add_theme_font_size_override("font_size", 36)
	stats_container.add_child(total_label)
	
	# Best lap
	var best_label = Label.new()
	best_label.text = "Best Lap: " + RaceManager.format_time(best_lap)
	best_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	best_label.add_theme_font_size_override("font_size", 36)
	stats_container.add_child(best_label)
	
	# Individual laps
	var spacer2 = Control.new()
	spacer2.custom_minimum_size = Vector2(0, 20)
	stats_container.add_child(spacer2)
	
	for i in range(RaceManager.lap_times.size()):
		var lap_time = RaceManager.lap_times[i]
		var lap_label = Label.new()
		lap_label.text = "  Lap %d: %s" % [i + 1, RaceManager.format_time(lap_time)]
		lap_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lap_label.add_theme_font_size_override("font_size", 24)
		
		if lap_time == best_lap:
			lap_label.add_theme_color_override("font_color", Color(1, 1, 0.3))
		
		stats_container.add_child(lap_label)
	
	# Check qualification
	qualification_info = RaceManager.check_leaderboard_qualification()
	
	await get_tree().create_timer(3.0).timeout
	
	if qualification_info.total_time_qualified or qualification_info.best_lap_qualified:
		_show_initials_entry()
	else:
		_show_leaderboards()

func _show_initials_entry() -> void:
	current_state = State.ENTERING_INITIALS
	stats_container.visible = false
	initials_container.visible = true
	current_initials = ""
	
	# Clear previous content
	for child in initials_container.get_children():
		child.queue_free()
	
	# Title
	var title = Label.new()
	title.text = "NEW RECORD!"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 48)
	title.add_theme_color_override("font_color", Color(1, 0.8, 0.3))
	initials_container.add_child(title)
	
	# Qualification info
	var qual_text = ""
	if qualification_info.total_time_qualified:
		qual_text += "Total Time Rank: #%d\n" % (qualification_info.total_time_rank + 1)
	if qualification_info.best_lap_qualified:
		qual_text += "Best Lap Rank: #%d\n" % (qualification_info.best_lap_rank + 1)
	
	var qual_label = Label.new()
	qual_label.text = qual_text
	qual_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	qual_label.add_theme_font_size_override("font_size", 28)
	initials_container.add_child(qual_label)
	
	# Prompt
	var prompt = Label.new()
	prompt.text = "Enter your initials (3 letters):"
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt.add_theme_font_size_override("font_size", 24)
	initials_container.add_child(prompt)
	
	# Initials display
	var initials_label = Label.new()
	initials_label.name = "InitialsLabel"
	initials_label.text = "___"
	initials_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	initials_label.add_theme_font_size_override("font_size", 64)
	initials_label.add_theme_color_override("font_color", Color(0.3, 0.8, 1))
	initials_container.add_child(initials_label)
	
	# Instructions
	var instructions = Label.new()
	instructions.text = "Press ENTER when done"
	instructions.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	instructions.add_theme_font_size_override("font_size", 20)
	instructions.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	initials_container.add_child(instructions)

func _input(event: InputEvent) -> void:
	if current_state != State.ENTERING_INITIALS:
		return
	
	if event is InputEventKey and event.pressed:
		var key = event.keycode
		
		if key == KEY_ENTER or key == KEY_KP_ENTER:
			if current_initials.length() >= 1:  # At least one letter
				_submit_initials()
		elif key == KEY_BACKSPACE:
			if current_initials.length() > 0:
				current_initials = current_initials.substr(0, current_initials.length() - 1)
				_update_initials_display()
		elif event.unicode >= 65 and event.unicode <= 90:  # A-Z
			if current_initials.length() < max_initials_length:
				current_initials += char(event.unicode)
				_update_initials_display()
		elif event.unicode >= 97 and event.unicode <= 122:  # a-z
			if current_initials.length() < max_initials_length:
				current_initials += char(event.unicode - 32)  # Convert to uppercase
				_update_initials_display()

func _update_initials_display() -> void:
	var label = initials_container.get_node_or_null("InitialsLabel")
	if label:
		var display = current_initials
		while display.length() < max_initials_length:
			display += "_"
		label.text = display

func _submit_initials() -> void:
	# Pad with spaces if needed
	while current_initials.length() < max_initials_length:
		current_initials += " "
	
	RaceManager.add_to_leaderboard(
		current_initials,
		qualification_info.total_time_qualified,
		qualification_info.best_lap_qualified
	)
	
	_show_leaderboards()

func _show_leaderboards() -> void:
	current_state = State.SHOWING_LEADERBOARDS
	stats_container.visible = false
	initials_container.visible = false
	leaderboards_container.visible = true
	buttons_container.visible = true
	
	# Clear previous content
	for child in leaderboards_container.get_children():
		child.queue_free()
	for child in buttons_container.get_children():
		child.queue_free()
	
	# Title
	var title = Label.new()
	title.text = "LEADERBOARDS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 48)
	leaderboards_container.add_child(title)
	
	# Create two-column layout
	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 100)
	leaderboards_container.add_child(hbox)
	
	# Total time leaderboard
	var total_vbox = VBoxContainer.new()
	total_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(total_vbox)
	
	var total_title = Label.new()
	total_title.text = "TOTAL TIME"
	total_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	total_title.add_theme_font_size_override("font_size", 32)
	total_vbox.add_child(total_title)
	
	_populate_leaderboard(total_vbox, RaceManager.total_time_leaderboard)
	
	# Best lap leaderboard
	var lap_vbox = VBoxContainer.new()
	lap_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(lap_vbox)
	
	var lap_title = Label.new()
	lap_title.text = "BEST LAP"
	lap_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lap_title.add_theme_font_size_override("font_size", 32)
	lap_vbox.add_child(lap_title)
	
	_populate_leaderboard(lap_vbox, RaceManager.best_lap_leaderboard)
	
	# Buttons
	var retry_button = Button.new()
	retry_button.text = "RETRY"
	retry_button.custom_minimum_size = Vector2(200, 60)
	retry_button.add_theme_font_size_override("font_size", 28)
	retry_button.pressed.connect(_on_retry_pressed)
	buttons_container.add_child(retry_button)
	
	var quit_button = Button.new()
	quit_button.text = "QUIT TO MENU"
	quit_button.custom_minimum_size = Vector2(200, 60)
	quit_button.add_theme_font_size_override("font_size", 28)
	quit_button.pressed.connect(_on_quit_pressed)
	buttons_container.add_child(quit_button)

func _populate_leaderboard(parent: VBoxContainer, leaderboard: Array[Dictionary]) -> void:
	if leaderboard.is_empty():
		var empty_label = Label.new()
		empty_label.text = "No records yet!"
		empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_label.add_theme_font_size_override("font_size", 20)
		empty_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
		parent.add_child(empty_label)
		return
	
	for i in range(leaderboard.size()):
		var entry = leaderboard[i]
		var rank_text = "%d. %s - %s" % [
			i + 1,
			entry.initials,
			RaceManager.format_time(entry.time)
		]
		
		var entry_label = Label.new()
		entry_label.text = rank_text
		entry_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		entry_label.add_theme_font_size_override("font_size", 20)
		
		if i < 3:  # Highlight top 3
			var colors = [Color(1, 0.8, 0.2), Color(0.8, 0.8, 0.8), Color(0.8, 0.5, 0.3)]
			entry_label.add_theme_color_override("font_color", colors[i])
		
		parent.add_child(entry_label)

func _on_retry_pressed() -> void:
	RaceManager.reset_race()
	get_tree().reload_current_scene()

func _on_quit_pressed() -> void:
	RaceManager.reset_race()
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
