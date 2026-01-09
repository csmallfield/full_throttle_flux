extends CanvasLayer
class_name ResultsScreen

## Post-race results screen with stats, initial entry, and leaderboards
## Also handles endless mode summary display
## Music continues from race until player returns to menu

enum State {
	SHOWING_STATS,
	ENTERING_INITIALS,
	SHOWING_LEADERBOARDS,
	SHOWING_ENDLESS_SUMMARY
}

var current_state: State = State.SHOWING_STATS
var qualification_info: Dictionary = {}
var current_initials: String = ""
var max_initials_length: int = 3

# Persistent storage for last entered initials
static var last_entered_initials: String = ""

# Input blocking to prevent accidental selection
var _input_blocked := false
var _input_block_timer := 0.0
const INPUT_BLOCK_DURATION := 0.5  # Seconds to block input after showing buttons

# UI References
var stats_container: VBoxContainer
var initials_container: VBoxContainer
var leaderboards_container: VBoxContainer
var endless_summary_container: VBoxContainer
var buttons_container: HBoxContainer

func _ready() -> void:
	visible = false
	_create_ui()
	
	# Connect to race finished signals
	RaceManager.race_finished.connect(_on_race_finished)
	RaceManager.endless_finished.connect(_on_endless_finished)

func _process(delta: float) -> void:
	# Handle input blocking timer
	if _input_blocked:
		_input_block_timer -= delta
		if _input_block_timer <= 0:
			_input_blocked = false

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
	
	# Endless summary container
	endless_summary_container = VBoxContainer.new()
	endless_summary_container.name = "EndlessSummaryContainer"
	endless_summary_container.position = Vector2(1920/2 - 350, 150)
	endless_summary_container.size = Vector2(700, 600)
	endless_summary_container.add_theme_constant_override("separation", 25)
	endless_summary_container.visible = false
	add_child(endless_summary_container)
	
	# Buttons container
	buttons_container = HBoxContainer.new()
	buttons_container.name = "ButtonsContainer"
	buttons_container.position = Vector2(1920/2 - 250, 900)
	buttons_container.size = Vector2(500, 80)
	buttons_container.add_theme_constant_override("separation", 30)
	buttons_container.visible = false
	add_child(buttons_container)

func _on_race_finished(total_time: float, best_lap: float) -> void:
	# Only handle time trial mode here
	if RaceManager.is_endless_mode():
		return
	
	# Play race finish sound (music keeps playing)
	AudioManager.play_race_finish()
	
	await get_tree().create_timer(2.0).timeout
	
	visible = true
	_show_stats(total_time, best_lap)

func _on_endless_finished(total_laps: int, total_time: float, best_lap: float) -> void:
	# Show endless summary
	visible = true
	_show_endless_summary(total_laps, total_time, best_lap)

func _show_stats(total_time: float, best_lap: float) -> void:
	current_state = State.SHOWING_STATS
	stats_container.visible = true
	initials_container.visible = false
	leaderboards_container.visible = false
	endless_summary_container.visible = false
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

func _show_endless_summary(total_laps: int, total_time: float, best_lap: float) -> void:
	current_state = State.SHOWING_ENDLESS_SUMMARY
	stats_container.visible = false
	initials_container.visible = false
	leaderboards_container.visible = false
	endless_summary_container.visible = true
	buttons_container.visible = true
	
	# Block input briefly to prevent accidental selection
	_block_input()
	
	# Clear previous content
	for child in endless_summary_container.get_children():
		child.queue_free()
	for child in buttons_container.get_children():
		child.queue_free()
	
	# Title
	var title = Label.new()
	title.text = "ENDLESS MODE COMPLETE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 52)
	title.add_theme_color_override("font_color", Color(1.0, 0.6, 0.2))
	endless_summary_container.add_child(title)
	
	# Spacer
	var spacer1 = Control.new()
	spacer1.custom_minimum_size = Vector2(0, 40)
	endless_summary_container.add_child(spacer1)
	
	# Total laps
	var laps_label = Label.new()
	laps_label.text = "TOTAL LAPS COMPLETED"
	laps_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	laps_label.add_theme_font_size_override("font_size", 24)
	laps_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	endless_summary_container.add_child(laps_label)
	
	var laps_value = Label.new()
	laps_value.text = str(total_laps)
	laps_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	laps_value.add_theme_font_size_override("font_size", 64)
	laps_value.add_theme_color_override("font_color", Color(0.3, 1.0, 0.3))
	endless_summary_container.add_child(laps_value)
	
	# Spacer
	var spacer2 = Control.new()
	spacer2.custom_minimum_size = Vector2(0, 30)
	endless_summary_container.add_child(spacer2)
	
	# Total time
	var time_header = Label.new()
	time_header.text = "TOTAL TIME"
	time_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	time_header.add_theme_font_size_override("font_size", 24)
	time_header.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	endless_summary_container.add_child(time_header)
	
	var time_value = Label.new()
	time_value.text = RaceManager.format_time(total_time)
	time_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	time_value.add_theme_font_size_override("font_size", 42)
	time_value.add_theme_color_override("font_color", Color.WHITE)
	endless_summary_container.add_child(time_value)
	
	# Spacer
	var spacer3 = Control.new()
	spacer3.custom_minimum_size = Vector2(0, 30)
	endless_summary_container.add_child(spacer3)
	
	# Best lap
	var best_header = Label.new()
	best_header.text = "BEST LAP"
	best_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	best_header.add_theme_font_size_override("font_size", 24)
	best_header.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	endless_summary_container.add_child(best_header)
	
	var best_value = Label.new()
	if total_laps > 0:
		best_value.text = RaceManager.format_time(best_lap)
		best_value.add_theme_color_override("font_color", Color(1, 1, 0.3))
	else:
		best_value.text = "--:--.---"
		best_value.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	best_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	best_value.add_theme_font_size_override("font_size", 42)
	endless_summary_container.add_child(best_value)
	
	# Note about leaderboards
	var spacer4 = Control.new()
	spacer4.custom_minimum_size = Vector2(0, 40)
	endless_summary_container.add_child(spacer4)
	
	var note_label = Label.new()
	note_label.text = "(Endless mode times are not recorded to leaderboards)"
	note_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note_label.add_theme_font_size_override("font_size", 18)
	note_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	endless_summary_container.add_child(note_label)
	
	# Create back to menu button
	var menu_button = Button.new()
	menu_button.text = "BACK TO MENU"
	menu_button.custom_minimum_size = Vector2(300, 60)
	menu_button.add_theme_font_size_override("font_size", 28)
	menu_button.focus_mode = Control.FOCUS_ALL
	menu_button.pressed.connect(_on_endless_quit_pressed)
	menu_button.focus_entered.connect(_on_button_focus)
	buttons_container.add_child(menu_button)
	
	# Set focus after a brief delay to prevent accidental activation
	await get_tree().create_timer(INPUT_BLOCK_DURATION).timeout
	menu_button.grab_focus()

func _show_initials_entry() -> void:
	current_state = State.ENTERING_INITIALS
	stats_container.visible = false
	initials_container.visible = true
	
	# Pre-populate with last entered initials (Item 4)
	current_initials = last_entered_initials
	
	# Play new record fanfare
	AudioManager.play_new_record()
	
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
	initials_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	initials_label.add_theme_font_size_override("font_size", 64)
	initials_label.add_theme_color_override("font_color", Color(0.3, 0.8, 1))
	initials_container.add_child(initials_label)
	
	# Update display with pre-populated initials
	_update_initials_display()
	
	# Instructions
	var instructions = Label.new()
	instructions.text = "Press ENTER when done | Gamepad A to submit | BACKSPACE to delete"
	instructions.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	instructions.add_theme_font_size_override("font_size", 20)
	instructions.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	initials_container.add_child(instructions)

func _block_input() -> void:
	_input_blocked = true
	_input_block_timer = INPUT_BLOCK_DURATION

func _input(event: InputEvent) -> void:
	if current_state != State.ENTERING_INITIALS:
		return
	
	# Handle accept action (ENTER or gamepad A)
	if event.is_action_pressed("ui_accept"):
		if current_initials.length() >= 1:  # At least one letter
			AudioManager.play_select()
			_submit_initials()
		return
	
	if event is InputEventKey and event.pressed:
		var key = event.keycode
		
		if key == KEY_BACKSPACE:
			if current_initials.length() > 0:
				current_initials = current_initials.substr(0, current_initials.length() - 1)
				AudioManager.play_keystroke()
				_update_initials_display()
		elif event.unicode >= 65 and event.unicode <= 90:  # A-Z
			if current_initials.length() < max_initials_length:
				current_initials += char(event.unicode)
				AudioManager.play_keystroke()
				_update_initials_display()
		elif event.unicode >= 97 and event.unicode <= 122:  # a-z
			if current_initials.length() < max_initials_length:
				current_initials += char(event.unicode - 32)  # Convert to uppercase
				AudioManager.play_keystroke()
				_update_initials_display()

func _update_initials_display() -> void:
	var label = initials_container.get_node_or_null("InitialsLabel")
	if label:
		var display = current_initials
		while display.length() < max_initials_length:
			display += "_"
		label.text = display

func _submit_initials() -> void:
	# Store for next time (Item 4)
	last_entered_initials = current_initials
	
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
	endless_summary_container.visible = false
	buttons_container.visible = true
	
	# Block input briefly to prevent accidental selection (Item 3)
	_block_input()
	
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
	
	# Buttons - create but don't set focus yet
	var retry_button = Button.new()
	retry_button.name = "RetryButton"
	retry_button.text = "RETRY"
	retry_button.custom_minimum_size = Vector2(200, 60)
	retry_button.add_theme_font_size_override("font_size", 28)
	retry_button.focus_mode = Control.FOCUS_ALL
	retry_button.pressed.connect(_on_retry_pressed)
	retry_button.focus_entered.connect(_on_button_focus)
	buttons_container.add_child(retry_button)
	
	var quit_button = Button.new()
	quit_button.name = "QuitButton"
	quit_button.text = "QUIT TO MENU"
	quit_button.custom_minimum_size = Vector2(200, 60)
	quit_button.add_theme_font_size_override("font_size", 28)
	quit_button.focus_mode = Control.FOCUS_ALL
	quit_button.pressed.connect(_on_quit_pressed)
	quit_button.focus_entered.connect(_on_button_focus)
	buttons_container.add_child(quit_button)
	
	# Set up button navigation
	retry_button.focus_neighbor_left = quit_button.get_path()
	retry_button.focus_neighbor_right = quit_button.get_path()
	quit_button.focus_neighbor_left = retry_button.get_path()
	quit_button.focus_neighbor_right = retry_button.get_path()
	
	# Set focus after a delay to prevent accidental selection (Item 3)
	await get_tree().create_timer(INPUT_BLOCK_DURATION).timeout
	retry_button.grab_focus()

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

func _on_button_focus() -> void:
	# Only play sound if input is not blocked
	if not _input_blocked:
		AudioManager.play_hover()

func _on_retry_pressed() -> void:
	# Check if input is blocked
	if _input_blocked:
		return
	
	AudioManager.play_select()
	RaceManager.reset_race()
	MusicPlaylistManager.stop_music(false)  # Stop race music
	get_tree().reload_current_scene()

func _on_quit_pressed() -> void:
	# Check if input is blocked
	if _input_blocked:
		return
	
	AudioManager.play_select()
	RaceManager.reset_race()
	# Stop race music - menu will start its own shuffled music
	MusicPlaylistManager.stop_music(false)
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")

func _on_endless_quit_pressed() -> void:
	# Check if input is blocked
	if _input_blocked:
		return
	
	AudioManager.play_select()
	RaceManager.reset_race()
	MusicPlaylistManager.stop_music(false)
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
