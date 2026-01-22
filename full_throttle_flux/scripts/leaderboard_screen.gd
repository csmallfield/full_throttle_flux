extends Control
class_name LeaderboardScreen

## Standalone leaderboard viewer (accessible from main menu)
## Music continues from main menu
## Now supports browsing all track/mode combinations with left/right navigation
## Includes "Erase All Records" button with confirmation dialog
## Supports Time Trial, Endless, and Race modes

var container: VBoxContainer
var header_container: HBoxContainer
var content_container: HBoxContainer
var nav_label: Label
var back_button: Button
var erase_button: Button

# Now Playing display instance
var now_playing_display: NowPlayingDisplay

# Track/mode navigation
var leaderboard_combos: Array[Dictionary] = []
var current_combo_index: int = 0

# Confirmation dialog
var confirm_dialog: CanvasLayer
var confirm_visible: bool = false

func _ready() -> void:
	_build_combo_list()
	_create_ui()
	_setup_focus()
	_setup_now_playing_display()
	_update_display()
	# Menu music should already be playing from main menu - no need to start it

func _build_combo_list() -> void:
	leaderboard_combos = RaceManager.get_all_possible_leaderboard_combos()
	# If empty, add a placeholder
	if leaderboard_combos.is_empty():
		leaderboard_combos.append({
			"track_id": "none",
			"track_name": "No Tracks",
			"mode": "time_trial",
			"mode_name": "Time Trial"
		})

func _setup_now_playing_display() -> void:
	# Add the NowPlayingDisplay to this scene (deferred to avoid busy parent error)
	var display_scene = preload("res://scenes/now_playing_display.tscn")
	now_playing_display = display_scene.instantiate()
	call_deferred("add_child", now_playing_display)

func _create_ui() -> void:
	# Main container
	container = VBoxContainer.new()
	container.name = "Container"
	container.position = Vector2(100, 80)
	container.size = Vector2(1720, 850)
	container.add_theme_constant_override("separation", 20)
	add_child(container)
	
	# Title
	var title = Label.new()
	title.text = "LEADERBOARDS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 56)
	title.add_theme_color_override("font_color", Color(0.3, 0.8, 1.0))
	container.add_child(title)
	
	# Navigation header with arrows
	header_container = HBoxContainer.new()
	header_container.alignment = BoxContainer.ALIGNMENT_CENTER
	header_container.add_theme_constant_override("separation", 30)
	container.add_child(header_container)
	
	var left_arrow = Label.new()
	left_arrow.text = "◄"
	left_arrow.add_theme_font_size_override("font_size", 36)
	left_arrow.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	header_container.add_child(left_arrow)
	
	nav_label = Label.new()
	nav_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nav_label.custom_minimum_size = Vector2(600, 0)
	nav_label.add_theme_font_size_override("font_size", 32)
	nav_label.add_theme_color_override("font_color", Color(1, 0.8, 0.2))
	header_container.add_child(nav_label)
	
	var right_arrow = Label.new()
	right_arrow.text = "►"
	right_arrow.add_theme_font_size_override("font_size", 36)
	right_arrow.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	header_container.add_child(right_arrow)
	
	# Navigation hint
	var nav_hint = Label.new()
	nav_hint.text = "← / → to browse tracks"
	nav_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nav_hint.add_theme_font_size_override("font_size", 18)
	nav_hint.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	container.add_child(nav_hint)
	
	# Spacer
	var spacer1 = Control.new()
	spacer1.custom_minimum_size = Vector2(0, 10)
	container.add_child(spacer1)
	
	# Content container for leaderboards (two columns)
	content_container = HBoxContainer.new()
	content_container.name = "ContentContainer"
	content_container.add_theme_constant_override("separation", 100)
	content_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_container.alignment = BoxContainer.ALIGNMENT_CENTER
	container.add_child(content_container)
	
	# Button row
	var button_row = HBoxContainer.new()
	button_row.alignment = BoxContainer.ALIGNMENT_CENTER
	button_row.add_theme_constant_override("separation", 50)
	container.add_child(button_row)
	
	# Erase button
	erase_button = Button.new()
	erase_button.name = "EraseButton"
	erase_button.text = "ERASE ALL RECORDS"
	erase_button.custom_minimum_size = Vector2(280, 60)
	erase_button.add_theme_font_size_override("font_size", 24)
	erase_button.focus_mode = Control.FOCUS_ALL
	erase_button.pressed.connect(_on_erase_pressed)
	erase_button.focus_entered.connect(_on_button_focus)
	# Make it look more dangerous
	erase_button.add_theme_color_override("font_color", Color(1, 0.4, 0.4))
	button_row.add_child(erase_button)
	
	# Back button
	back_button = Button.new()
	back_button.name = "BackButton"
	back_button.text = "BACK TO MENU"
	back_button.custom_minimum_size = Vector2(280, 60)
	back_button.add_theme_font_size_override("font_size", 24)
	back_button.focus_mode = Control.FOCUS_ALL
	back_button.pressed.connect(_on_back_pressed)
	back_button.focus_entered.connect(_on_button_focus)
	button_row.add_child(back_button)
	
	# Set up button navigation
	erase_button.focus_neighbor_right = back_button.get_path()
	back_button.focus_neighbor_left = erase_button.get_path()
	
	# Create confirmation dialog (hidden initially)
	_create_confirm_dialog()

func _create_confirm_dialog() -> void:
	confirm_dialog = CanvasLayer.new()
	confirm_dialog.name = "ConfirmDialog"
	confirm_dialog.visible = false
	add_child(confirm_dialog)
	
	# Dark overlay
	var overlay = ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.8)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	confirm_dialog.add_child(overlay)
	
	# Dialog box
	var dialog_box = VBoxContainer.new()
	dialog_box.position = Vector2(1920/2 - 300, 1080/2 - 150)
	dialog_box.size = Vector2(600, 300)
	dialog_box.add_theme_constant_override("separation", 30)
	confirm_dialog.add_child(dialog_box)
	
	# Warning title
	var warning_title = Label.new()
	warning_title.text = "⚠ WARNING ⚠"
	warning_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	warning_title.add_theme_font_size_override("font_size", 48)
	warning_title.add_theme_color_override("font_color", Color(1, 0.3, 0.3))
	dialog_box.add_child(warning_title)
	
	# Warning message
	var warning_msg = Label.new()
	warning_msg.text = "This will permanently delete ALL leaderboard\nrecords across ALL tracks and modes.\n\nThis cannot be undone!"
	warning_msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	warning_msg.add_theme_font_size_override("font_size", 24)
	warning_msg.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
	dialog_box.add_child(warning_msg)
	
	# Button container
	var btn_container = HBoxContainer.new()
	btn_container.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_container.add_theme_constant_override("separation", 50)
	dialog_box.add_child(btn_container)
	
	# Cancel button
	var cancel_btn = Button.new()
	cancel_btn.name = "CancelButton"
	cancel_btn.text = "CANCEL"
	cancel_btn.custom_minimum_size = Vector2(200, 60)
	cancel_btn.add_theme_font_size_override("font_size", 28)
	cancel_btn.focus_mode = Control.FOCUS_ALL
	cancel_btn.pressed.connect(_on_confirm_cancel)
	cancel_btn.focus_entered.connect(_on_button_focus)
	btn_container.add_child(cancel_btn)
	
	# Confirm button
	var confirm_btn = Button.new()
	confirm_btn.name = "ConfirmButton"
	confirm_btn.text = "ERASE ALL"
	confirm_btn.custom_minimum_size = Vector2(200, 60)
	confirm_btn.add_theme_font_size_override("font_size", 28)
	confirm_btn.add_theme_color_override("font_color", Color(1, 0.3, 0.3))
	confirm_btn.focus_mode = Control.FOCUS_ALL
	confirm_btn.pressed.connect(_on_confirm_erase)
	confirm_btn.focus_entered.connect(_on_button_focus)
	btn_container.add_child(confirm_btn)
	
	# Set up dialog button navigation
	cancel_btn.focus_neighbor_right = confirm_btn.get_path()
	confirm_btn.focus_neighbor_left = cancel_btn.get_path()

func _setup_focus() -> void:
	# Set initial focus to back button
	if back_button:
		back_button.grab_focus()

func _update_display() -> void:
	# Clear content
	for child in content_container.get_children():
		child.queue_free()
	
	if leaderboard_combos.is_empty():
		return
	
	var combo = leaderboard_combos[current_combo_index]
	var track_name = combo.track_name
	var mode_name = combo.mode_name
	var track_id = combo.track_id
	var mode_key = combo.mode
	
	# Update navigation label
	nav_label.text = "%s - %s" % [track_name, mode_name]
	
	# Show appropriate leaderboards based on mode
	if mode_key == "time_trial" or mode_key == "race":
		# Time trial and race: show both total time and best lap
		var total_vbox = VBoxContainer.new()
		total_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		total_vbox.custom_minimum_size = Vector2(400, 0)
		content_container.add_child(total_vbox)
		
		var total_title = Label.new()
		total_title.text = "TOTAL TIME (3 Laps)"
		total_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		total_title.add_theme_font_size_override("font_size", 32)
		total_title.add_theme_color_override("font_color", Color(1, 0.8, 0.2))
		total_vbox.add_child(total_title)
		
		var spacer1 = Control.new()
		spacer1.custom_minimum_size = Vector2(0, 15)
		total_vbox.add_child(spacer1)
		
		var total_board = RaceManager.get_leaderboard(track_id, mode_key, "total_time")
		_populate_leaderboard(total_vbox, total_board)
		
		var lap_vbox = VBoxContainer.new()
		lap_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lap_vbox.custom_minimum_size = Vector2(400, 0)
		content_container.add_child(lap_vbox)
		
		var lap_title = Label.new()
		lap_title.text = "BEST LAP"
		lap_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lap_title.add_theme_font_size_override("font_size", 32)
		lap_title.add_theme_color_override("font_color", Color(1, 0.8, 0.2))
		lap_vbox.add_child(lap_title)
		
		var spacer2 = Control.new()
		spacer2.custom_minimum_size = Vector2(0, 15)
		lap_vbox.add_child(spacer2)
		
		var lap_board = RaceManager.get_leaderboard(track_id, mode_key, "best_lap")
		_populate_leaderboard(lap_vbox, lap_board)
	else:
		# Endless: show only best lap
		var lap_vbox = VBoxContainer.new()
		lap_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lap_vbox.custom_minimum_size = Vector2(500, 0)
		content_container.add_child(lap_vbox)
		
		var lap_title = Label.new()
		lap_title.text = "BEST LAP"
		lap_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lap_title.add_theme_font_size_override("font_size", 32)
		lap_title.add_theme_color_override("font_color", Color(1, 0.8, 0.2))
		lap_vbox.add_child(lap_title)
		
		var spacer = Control.new()
		spacer.custom_minimum_size = Vector2(0, 15)
		lap_vbox.add_child(spacer)
		
		var lap_board = RaceManager.get_leaderboard(track_id, mode_key, "best_lap")
		_populate_leaderboard(lap_vbox, lap_board)

func _populate_leaderboard(parent: VBoxContainer, leaderboard: Array) -> void:
	if leaderboard.is_empty():
		var empty_label = Label.new()
		empty_label.text = "No records yet!"
		empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_label.add_theme_font_size_override("font_size", 24)
		empty_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		parent.add_child(empty_label)
		return
	
	for i in range(leaderboard.size()):
		var entry = leaderboard[i]
		var ship_name = entry.get("ship", "???")
		var rank_text = "%2d.  %s  %s  [%s]" % [
			i + 1,
			entry.initials,
			RaceManager.format_time(entry.time),
			ship_name
		]
		
		var entry_label = Label.new()
		entry_label.text = rank_text
		entry_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		entry_label.add_theme_font_size_override("font_size", 22)
		
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

func _input(event: InputEvent) -> void:
	# Don't process navigation if confirm dialog is open
	if confirm_visible:
		# Handle cancel on escape/B button
		if event.is_action_pressed("ui_cancel"):
			_on_confirm_cancel()
			get_viewport().set_input_as_handled()
		return
	
	# Left/right navigation for leaderboards
	if event.is_action_pressed("ui_left"):
		_navigate(-1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_right"):
		_navigate(1)
		get_viewport().set_input_as_handled()

func _navigate(direction: int) -> void:
	if leaderboard_combos.size() <= 1:
		return
	
	current_combo_index += direction
	
	# Wrap around
	if current_combo_index < 0:
		current_combo_index = leaderboard_combos.size() - 1
	elif current_combo_index >= leaderboard_combos.size():
		current_combo_index = 0
	
	AudioManager.play_hover()
	_update_display()

func _on_button_focus() -> void:
	AudioManager.play_hover()

func _on_erase_pressed() -> void:
	AudioManager.play_select()
	_show_confirm_dialog()

func _show_confirm_dialog() -> void:
	confirm_visible = true
	confirm_dialog.visible = true
	
	# Focus the cancel button (safer default)
	var cancel_btn = confirm_dialog.get_node("CancelButton") if confirm_dialog.has_node("CancelButton") else null
	if not cancel_btn:
		# Find it in the hierarchy
		for child in confirm_dialog.get_children():
			if child is Control:
				var btn = child.find_child("CancelButton", true, false)
				if btn:
					btn.grab_focus()
					return
	else:
		cancel_btn.grab_focus()

func _on_confirm_cancel() -> void:
	AudioManager.play_back()
	confirm_visible = false
	confirm_dialog.visible = false
	back_button.grab_focus()

func _on_confirm_erase() -> void:
	AudioManager.play_select()
	RaceManager.erase_all_leaderboards()
	confirm_visible = false
	confirm_dialog.visible = false
	_update_display()
	back_button.grab_focus()

func _on_back_pressed() -> void:
	AudioManager.play_back()
	# Music keeps playing - main menu will pick it up
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
