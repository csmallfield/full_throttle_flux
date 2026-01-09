extends CanvasLayer
class_name PauseMenu

## In-game pause menu
## Coordinates with MusicPlaylistManager for pausing music
## Adapts based on race mode (hides restart in endless mode)
## Includes volume controls for Music and SFX

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

# Volume controls
var volume_container: VBoxContainer
var music_slider: HSlider
var sfx_slider: HSlider
var music_label: Label
var sfx_label: Label

# Controls popup
var controls_popup: PanelContainer
var controls_close_button: Button

# Track if we need to show endless summary
var _show_endless_summary := false

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
	
	panel.position = Vector2(1920/2 - 250, 1080/2 - 300)
	panel.size = Vector2(500, 600)
	
	# VBox for content
	var vbox: VBoxContainer
	if not panel.has_node("VBoxContainer"):
		vbox = VBoxContainer.new()
		vbox.name = "VBoxContainer"
		panel.add_child(vbox)
	else:
		vbox = panel.get_node("VBoxContainer")
	
	vbox.add_theme_constant_override("separation", 15)
	
	# Title
	title_label = Label.new()
	title_label.name = "TitleLabel"
	title_label.text = "PAUSED"
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", 48)
	vbox.add_child(title_label)
	
	# Spacer
	var spacer1 = Control.new()
	spacer1.custom_minimum_size = Vector2(0, 20)
	vbox.add_child(spacer1)
	
	# Buttons
	resume_button = _create_pause_button("RESUME", vbox)
	restart_button = _create_pause_button("RESTART", vbox)
	controls_button = _create_pause_button("CONTROLS", vbox)
	quit_button = _create_pause_button("QUIT TO MENU", vbox)
	
	# Spacer before volume controls
	var spacer2 = Control.new()
	spacer2.custom_minimum_size = Vector2(0, 15)
	vbox.add_child(spacer2)
	
	# Volume controls section
	_create_volume_controls(vbox)
	
	# Spacer before debug toggle
	var spacer3 = Control.new()
	spacer3.custom_minimum_size = Vector2(0, 15)
	vbox.add_child(spacer3)
	
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

func _create_volume_controls(parent: VBoxContainer) -> void:
	# Container for volume controls
	volume_container = VBoxContainer.new()
	volume_container.name = "VolumeContainer"
	volume_container.add_theme_constant_override("separation", 8)
	parent.add_child(volume_container)
	
	# Volume section title
	var volume_title = Label.new()
	volume_title.text = "VOLUME"
	volume_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	volume_title.add_theme_font_size_override("font_size", 20)
	volume_title.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	volume_container.add_child(volume_title)
	
	# Music volume
	var music_hbox = HBoxContainer.new()
	music_hbox.add_theme_constant_override("separation", 10)
	volume_container.add_child(music_hbox)
	
	var music_name = Label.new()
	music_name.text = "Music"
	music_name.custom_minimum_size = Vector2(80, 0)
	music_name.add_theme_font_size_override("font_size", 18)
	music_hbox.add_child(music_name)
	
	music_slider = HSlider.new()
	music_slider.name = "MusicSlider"
	music_slider.min_value = 0.0
	music_slider.max_value = 2.0
	music_slider.step = 0.1
	music_slider.value = 1.0
	music_slider.custom_minimum_size = Vector2(250, 20)
	music_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	music_slider.focus_mode = Control.FOCUS_ALL
	music_hbox.add_child(music_slider)
	
	music_label = Label.new()
	music_label.name = "MusicLabel"
	music_label.text = "100%"
	music_label.custom_minimum_size = Vector2(50, 0)
	music_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	music_label.add_theme_font_size_override("font_size", 18)
	music_hbox.add_child(music_label)
	
	# SFX volume
	var sfx_hbox = HBoxContainer.new()
	sfx_hbox.add_theme_constant_override("separation", 10)
	volume_container.add_child(sfx_hbox)
	
	var sfx_name = Label.new()
	sfx_name.text = "SFX"
	sfx_name.custom_minimum_size = Vector2(80, 0)
	sfx_name.add_theme_font_size_override("font_size", 18)
	sfx_hbox.add_child(sfx_name)
	
	sfx_slider = HSlider.new()
	sfx_slider.name = "SFXSlider"
	sfx_slider.min_value = 0.0
	sfx_slider.max_value = 2.0
	sfx_slider.step = 0.1
	sfx_slider.value = 1.0
	sfx_slider.custom_minimum_size = Vector2(250, 20)
	sfx_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sfx_slider.focus_mode = Control.FOCUS_ALL
	sfx_hbox.add_child(sfx_slider)
	
	sfx_label = Label.new()
	sfx_label.name = "SFXLabel"
	sfx_label.text = "100%"
	sfx_label.custom_minimum_size = Vector2(50, 0)
	sfx_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	sfx_label.add_theme_font_size_override("font_size", 18)
	sfx_hbox.add_child(sfx_label)

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
	controls_close_button.focus_entered.connect(_on_button_focus)
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
	resume_button.focus_entered.connect(_on_button_focus)
	
	restart_button.pressed.connect(_on_restart_pressed)
	restart_button.focus_entered.connect(_on_button_focus)
	
	controls_button.pressed.connect(_on_controls_pressed)
	controls_button.focus_entered.connect(_on_button_focus)
	
	quit_button.pressed.connect(_on_quit_pressed)
	quit_button.focus_entered.connect(_on_button_focus)
	
	debug_toggle_button.pressed.connect(_on_debug_toggle_pressed)
	debug_toggle_button.focus_entered.connect(_on_button_focus)
	
	# Volume slider signals
	music_slider.value_changed.connect(_on_music_volume_changed)
	music_slider.focus_entered.connect(_on_slider_focus)
	sfx_slider.value_changed.connect(_on_sfx_volume_changed)
	sfx_slider.focus_entered.connect(_on_slider_focus)

func _setup_focus() -> void:
	_update_focus_chain()

func _update_focus_chain() -> void:
	# Determine which buttons are visible
	var focusable_items: Array[Control] = []
	
	focusable_items.append(resume_button)
	
	if restart_button.visible:
		focusable_items.append(restart_button)
	
	focusable_items.append(controls_button)
	focusable_items.append(quit_button)
	focusable_items.append(music_slider)
	focusable_items.append(sfx_slider)
	focusable_items.append(debug_toggle_button)
	
	# Set up circular navigation
	for i in range(focusable_items.size()):
		var current = focusable_items[i]
		var prev_idx = (i - 1) if i > 0 else focusable_items.size() - 1
		var next_idx = (i + 1) if i < focusable_items.size() - 1 else 0
		
		current.focus_neighbor_top = focusable_items[prev_idx].get_path()
		current.focus_neighbor_bottom = focusable_items[next_idx].get_path()

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

func _on_button_focus() -> void:
	AudioManager.play_hover()

func _on_slider_focus() -> void:
	AudioManager.play_hover()

func show_pause() -> void:
	visible = true
	controls_popup.visible = false
	_update_debug_button_text()
	
	# Show/hide restart button based on mode
	restart_button.visible = RaceManager.is_time_trial_mode()
	_update_focus_chain()
	
	# Load current volume settings into sliders
	_load_volume_settings()
	
	RaceManager.pause_race()
	MusicPlaylistManager.pause_music()  # Pause the music
	AudioManager.play_pause()
	
	# Set focus to resume button when pause menu appears
	if resume_button:
		resume_button.grab_focus()

func hide_pause() -> void:
	visible = false
	controls_popup.visible = false
	RaceManager.resume_race()
	MusicPlaylistManager.resume_music()  # Resume the music

func _load_volume_settings() -> void:
	# Load current values from AudioManager
	music_slider.value = AudioManager.music_volume_linear
	sfx_slider.value = AudioManager.sfx_volume_linear
	_update_volume_labels()

func _update_volume_labels() -> void:
	# Display as percentage (0-200%)
	music_label.text = "%d%%" % int(music_slider.value * 100)
	sfx_label.text = "%d%%" % int(sfx_slider.value * 100)

func _on_music_volume_changed(value: float) -> void:
	AudioManager.music_volume_linear = value
	_update_volume_labels()

func _on_sfx_volume_changed(value: float) -> void:
	AudioManager.sfx_volume_linear = value
	_update_volume_labels()
	# Play a test sound so user can hear the change
	AudioManager.play_hover()

func _on_resume_pressed() -> void:
	AudioManager.play_resume()
	hide_pause()
	resume_requested.emit()

func _on_restart_pressed() -> void:
	# Only available in time trial mode
	if not RaceManager.is_time_trial_mode():
		return
	
	AudioManager.play_select()
	visible = false
	controls_popup.visible = false
	get_tree().paused = false
	RaceManager.reset_race()
	MusicPlaylistManager.stop_music(false)  # Stop music immediately
	restart_requested.emit()
	get_tree().reload_current_scene()

func _on_controls_pressed() -> void:
	AudioManager.play_select()
	# Hide main menu, show controls popup
	get_node("PanelContainer").visible = false
	controls_popup.visible = true
	
	# Set focus to close button
	if controls_close_button:
		controls_close_button.grab_focus()

func _on_controls_close_pressed() -> void:
	AudioManager.play_back()
	# Hide controls popup, show main menu
	controls_popup.visible = false
	get_node("PanelContainer").visible = true
	
	# Return focus to controls button
	if controls_button:
		controls_button.grab_focus()

func _on_quit_pressed() -> void:
	AudioManager.play_select()
	visible = false
	controls_popup.visible = false
	get_tree().paused = false
	
	if RaceManager.is_endless_mode():
		# Trigger endless mode finish (will show summary via results screen)
		RaceManager.finish_endless()
	else:
		# Time trial: just quit to menu
		RaceManager.reset_race()
		MusicPlaylistManager.stop_music(false)
		quit_requested.emit()
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn")

func _on_debug_toggle_pressed() -> void:
	AudioManager.play_select()
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
