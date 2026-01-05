extends CanvasLayer
class_name PauseMenu

## In-game pause menu

signal resume_requested
signal restart_requested
signal quit_requested

@export var debug_hud: DebugHUD

var title_label: Label
var resume_button: Button
var restart_button: Button
var controls_button: Button
var quit_button: Button
var debug_toggle_button: Button

# Controls popup
var controls_popup: PanelContainer
var controls_close_button: Button

func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	_create_ui()
	_create_controls_popup()
	_connect_signals()
	_setup_focus()

func _create_ui() -> void:
	# Panel container
	var panel: PanelContainer
	if not has_node("PanelContainer"):
		panel = PanelContainer.new()
		panel.name = "PanelContainer"
		add_child(panel)
	else:
		panel = $PanelContainer
	
	panel.position = Vector2(1920/2 - 250, 1080/2 - 250)
	panel.size = Vector2(500, 500)
	
	# VBox for content
	var vbox: VBoxContainer
	if not panel.has_node("VBoxContainer"):
		vbox = VBoxContainer.new()
		vbox.name = "VBoxContainer"
		panel.add_child(vbox)
	else:
		vbox = panel.get_node("VBoxContainer")
	
	vbox.add_theme_constant_override("separation", 20)
	
	# Title
	title_label = Label.new()
	title_label.name = "TitleLabel"
	title_label.text = "PAUSED"
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", 48)
	vbox.add_child(title_label)
	
	# Spacer
	var spacer1 = Control.new()
	spacer1.custom_minimum_size = Vector2(0, 30)
	vbox.add_child(spacer1)
	
	# Buttons
	resume_button = _create_pause_button("RESUME", vbox)
	restart_button = _create_pause_button("RESTART", vbox)
	controls_button = _create_pause_button("CONTROLS", vbox)
	quit_button = _create_pause_button("QUIT TO MENU", vbox)
	
	# Spacer before debug toggle
	var spacer2 = Control.new()
	spacer2.custom_minimum_size = Vector2(0, 20)
	vbox.add_child(spacer2)
	
	# Debug toggle button
	debug_toggle_button = _create_pause_button("DEBUG HUD: OFF", vbox)
	_update_debug_button_text()

func _create_pause_button(text: String, parent: Control) -> Button:
	var button = Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(400, 50)
	button.add_theme_font_size_override("font_size", 24)
	button.focus_mode = Control.FOCUS_ALL  # Enable focus for navigation
	parent.add_child(button)
	return button

func _create_controls_popup() -> void:
	# Create popup panel
	controls_popup = PanelContainer.new()
	controls_popup.name = "ControlsPopup"
	controls_popup.position = Vector2(1920/2 - 400, 1080/2 - 350)
	controls_popup.size = Vector2(800, 700)
	controls_popup.visible = false
	add_child(controls_popup)
	
	# Main container
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 20)
	controls_popup.add_child(vbox)
	
	# Title
	var title = Label.new()
	title.text = "CONTROLS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 42)
	title.add_theme_color_override("font_color", Color(0.3, 0.8, 1.0))
	vbox.add_child(title)
	
	# Spacer
	var spacer1 = Control.new()
	spacer1.custom_minimum_size = Vector2(0, 10)
	vbox.add_child(spacer1)
	
	# Racing controls section
	var racing_title = Label.new()
	racing_title.text = "RACING"
	racing_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	racing_title.add_theme_font_size_override("font_size", 28)
	racing_title.add_theme_color_override("font_color", Color(1, 0.8, 0.3))
	vbox.add_child(racing_title)
	
	# Create two-column layout for racing controls
	var racing_hbox = HBoxContainer.new()
	racing_hbox.add_theme_constant_override("separation", 50)
	vbox.add_child(racing_hbox)
	
	# Keyboard column
	var kb_vbox = VBoxContainer.new()
	kb_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	racing_hbox.add_child(kb_vbox)
	
	var kb_label = Label.new()
	kb_label.text = "KEYBOARD"
	kb_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	kb_label.add_theme_font_size_override("font_size", 20)
	kb_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	kb_vbox.add_child(kb_label)
	
	_add_control_line(kb_vbox, "W", "Accelerate")
	_add_control_line(kb_vbox, "S", "Brake")
	_add_control_line(kb_vbox, "A / D", "Steer")
	_add_control_line(kb_vbox, "Q / E", "Airbrakes")
	
	# Gamepad column
	var gp_vbox = VBoxContainer.new()
	gp_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	racing_hbox.add_child(gp_vbox)
	
	var gp_label = Label.new()
	gp_label.text = "GAMEPAD"
	gp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	gp_label.add_theme_font_size_override("font_size", 20)
	gp_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	gp_vbox.add_child(gp_label)
	
	_add_control_line(gp_vbox, "A Button", "Accelerate")
	_add_control_line(gp_vbox, "B Button", "Brake")
	_add_control_line(gp_vbox, "Left Stick", "Steer")
	_add_control_line(gp_vbox, "L2 / R2", "Airbrakes")
	
	# Spacer
	var spacer2 = Control.new()
	spacer2.custom_minimum_size = Vector2(0, 15)
	vbox.add_child(spacer2)
	
	# Menu controls section
	var menu_title = Label.new()
	menu_title.text = "MENU NAVIGATION"
	menu_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	menu_title.add_theme_font_size_override("font_size", 28)
	menu_title.add_theme_color_override("font_color", Color(1, 0.8, 0.3))
	vbox.add_child(menu_title)
	
	# Create two-column layout for menu controls
	var menu_hbox = HBoxContainer.new()
	menu_hbox.add_theme_constant_override("separation", 50)
	vbox.add_child(menu_hbox)
	
	# Keyboard column
	var kb_menu_vbox = VBoxContainer.new()
	kb_menu_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	menu_hbox.add_child(kb_menu_vbox)
	
	var kb_menu_label = Label.new()
	kb_menu_label.text = "KEYBOARD"
	kb_menu_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	kb_menu_label.add_theme_font_size_override("font_size", 20)
	kb_menu_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	kb_menu_vbox.add_child(kb_menu_label)
	
	_add_control_line(kb_menu_vbox, "W / S", "Navigate")
	_add_control_line(kb_menu_vbox, "ENTER", "Select")
	_add_control_line(kb_menu_vbox, "ESC", "Back / Pause")
	
	# Gamepad column
	var gp_menu_vbox = VBoxContainer.new()
	gp_menu_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	menu_hbox.add_child(gp_menu_vbox)
	
	var gp_menu_label = Label.new()
	gp_menu_label.text = "GAMEPAD"
	gp_menu_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	gp_menu_label.add_theme_font_size_override("font_size", 20)
	gp_menu_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	gp_menu_vbox.add_child(gp_menu_label)
	
	_add_control_line(gp_menu_vbox, "D-Pad / Stick", "Navigate")
	_add_control_line(gp_menu_vbox, "A Button", "Select")
	_add_control_line(gp_menu_vbox, "Start / B", "Back / Pause")
	
	# Spacer before close button
	var spacer3 = Control.new()
	spacer3.custom_minimum_size = Vector2(0, 20)
	vbox.add_child(spacer3)
	
	# Close button
	controls_close_button = Button.new()
	controls_close_button.text = "CLOSE"
	controls_close_button.custom_minimum_size = Vector2(200, 50)
	controls_close_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	controls_close_button.add_theme_font_size_override("font_size", 24)
	controls_close_button.focus_mode = Control.FOCUS_ALL
	controls_close_button.pressed.connect(_on_controls_close_pressed)
	vbox.add_child(controls_close_button)

func _add_control_line(parent: VBoxContainer, key: String, action: String) -> void:
	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 10)
	parent.add_child(hbox)
	
	var key_label = Label.new()
	key_label.text = key
	key_label.add_theme_font_size_override("font_size", 18)
	key_label.add_theme_color_override("font_color", Color(0.3, 0.8, 1.0))
	key_label.custom_minimum_size = Vector2(120, 0)
	hbox.add_child(key_label)
	
	var dash_label = Label.new()
	dash_label.text = "→"
	dash_label.add_theme_font_size_override("font_size", 18)
	hbox.add_child(dash_label)
	
	var action_label = Label.new()
	action_label.text = action
	action_label.add_theme_font_size_override("font_size", 18)
	hbox.add_child(action_label)

func _connect_signals() -> void:
	resume_button.pressed.connect(_on_resume_pressed)
	restart_button.pressed.connect(_on_restart_pressed)
	controls_button.pressed.connect(_on_controls_pressed)
	quit_button.pressed.connect(_on_quit_pressed)
	debug_toggle_button.pressed.connect(_on_debug_toggle_pressed)

func _setup_focus() -> void:
	# Set up focus navigation chain
	if resume_button and restart_button and controls_button and quit_button and debug_toggle_button:
		resume_button.focus_neighbor_top = debug_toggle_button.get_path()
		resume_button.focus_neighbor_bottom = restart_button.get_path()
		
		restart_button.focus_neighbor_top = resume_button.get_path()
		restart_button.focus_neighbor_bottom = controls_button.get_path()
		
		controls_button.focus_neighbor_top = restart_button.get_path()
		controls_button.focus_neighbor_bottom = quit_button.get_path()
		
		quit_button.focus_neighbor_top = controls_button.get_path()
		quit_button.focus_neighbor_bottom = debug_toggle_button.get_path()
		
		debug_toggle_button.focus_neighbor_top = quit_button.get_path()
		debug_toggle_button.focus_neighbor_bottom = resume_button.get_path()

func _input(event: InputEvent) -> void:
	# Handle closing controls popup with ESC or gamepad B
	if controls_popup and controls_popup.visible:
		if event.is_action_pressed("ui_cancel"):
			_on_controls_close_pressed()
			get_viewport().set_input_as_handled()
			return
	
	# Handle pause menu toggle
	if event.is_action_pressed("ui_cancel"):  # ESC key
		if visible and not controls_popup.visible:
			_on_resume_pressed()
		else:
			show_pause()

func show_pause() -> void:
	visible = true
	controls_popup.visible = false
	_update_debug_button_text()
	RaceManager.pause_race()
	
	# Set focus to resume button when pause menu appears
	if resume_button:
		resume_button.grab_focus()

func hide_pause() -> void:
	visible = false
	controls_popup.visible = false
	RaceManager.resume_race()

func _on_resume_pressed() -> void:
	hide_pause()
	resume_requested.emit()

func _on_restart_pressed() -> void:
	visible = false
	controls_popup.visible = false
	get_tree().paused = false
	RaceManager.reset_race()
	restart_requested.emit()
	get_tree().reload_current_scene()

func _on_controls_pressed() -> void:
	# Hide main menu, show controls popup
	get_node("PanelContainer").visible = false
	controls_popup.visible = true
	
	# Set focus to close button
	if controls_close_button:
		controls_close_button.grab_focus()

func _on_controls_close_pressed() -> void:
	# Hide controls popup, show main menu
	controls_popup.visible = false
	get_node("PanelContainer").visible = true
	
	# Return focus to controls button
	if controls_button:
		controls_button.grab_focus()

func _on_quit_pressed() -> void:
	visible = false
	controls_popup.visible = false
	get_tree().paused = false
	RaceManager.reset_race()
	quit_requested.emit()
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")

func _on_debug_toggle_pressed() -> void:
	if debug_hud:
		debug_hud.toggle_visibility()
		_update_debug_button_text()

func _update_debug_button_text() -> void:
	if not debug_toggle_button:
		return
	
	if debug_hud and debug_hud.is_showing():
		debug_toggle_button.text = "DEBUG HUD: ON"
	else:
		debug_toggle_button.text = "DEBUG HUD: OFF"
