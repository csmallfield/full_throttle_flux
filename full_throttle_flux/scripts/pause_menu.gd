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
var quit_button: Button
var debug_toggle_button: Button

func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	_create_ui()
	_connect_signals()

func _create_ui() -> void:
	# Panel container
	var panel: PanelContainer
	if not has_node("PanelContainer"):
		panel = PanelContainer.new()
		panel.name = "PanelContainer"
		add_child(panel)
	else:
		panel = $PanelContainer
	
	panel.position = Vector2(1920/2 - 250, 1080/2 - 200)
	panel.size = Vector2(500, 400)
	
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
	parent.add_child(button)
	return button

func _connect_signals() -> void:
	resume_button.pressed.connect(_on_resume_pressed)
	restart_button.pressed.connect(_on_restart_pressed)
	quit_button.pressed.connect(_on_quit_pressed)
	debug_toggle_button.pressed.connect(_on_debug_toggle_pressed)

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):  # ESC key
		if visible:
			_on_resume_pressed()
		else:
			show_pause()

func show_pause() -> void:
	visible = true
	_update_debug_button_text()
	RaceManager.pause_race()

func hide_pause() -> void:
	visible = false
	RaceManager.resume_race()

func _on_resume_pressed() -> void:
	hide_pause()
	resume_requested.emit()

func _on_restart_pressed() -> void:
	visible = false
	get_tree().paused = false
	RaceManager.reset_race()
	restart_requested.emit()
	get_tree().reload_current_scene()

func _on_quit_pressed() -> void:
	visible = false
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
