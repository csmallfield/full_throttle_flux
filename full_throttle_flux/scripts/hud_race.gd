extends CanvasLayer
class_name HUDRace

## Racing HUD displaying countdown, lap progress, timing, and speed

@export var ship: AGShip2097

# UI References
var countdown_label: Label
var lap_info_label: Label
var lap_times_label: RichTextLabel
var current_time_label: Label
var speed_label: Label

func _ready() -> void:
	# Connect to RaceManager signals
	RaceManager.countdown_tick.connect(_on_countdown_tick)
	RaceManager.race_started.connect(_on_race_started)
	RaceManager.lap_completed.connect(_on_lap_completed)
	RaceManager.race_finished.connect(_on_race_finished)
	
	_create_ui_elements()
	_reset_display()

func _create_ui_elements() -> void:
	# Countdown (large, center screen)
	countdown_label = Label.new()
	countdown_label.name = "CountdownLabel"
	countdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	countdown_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	countdown_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	countdown_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	countdown_label.add_theme_font_size_override("font_size", 120)
	countdown_label.add_theme_color_override("font_color", Color.WHITE)
	countdown_label.add_theme_color_override("font_outline_color", Color.BLACK)
	countdown_label.add_theme_constant_override("outline_size", 8)
	countdown_label.visible = false
	add_child(countdown_label)
	
	# Lap info (top center)
	lap_info_label = Label.new()
	lap_info_label.name = "LapInfoLabel"
	lap_info_label.position = Vector2(1920/2 - 100, 20)
	lap_info_label.size = Vector2(200, 40)
	lap_info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lap_info_label.add_theme_font_size_override("font_size", 32)
	lap_info_label.add_theme_color_override("font_color", Color.WHITE)
	lap_info_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	lap_info_label.add_theme_constant_override("shadow_offset_x", 2)
	lap_info_label.add_theme_constant_override("shadow_offset_y", 2)
	lap_info_label.text = "LAP 1/3"
	add_child(lap_info_label)
	
	# Lap times (top left) - using RichTextLabel for BBCode support
	lap_times_label = RichTextLabel.new()
	lap_times_label.name = "LapTimesLabel"
	lap_times_label.position = Vector2(20, 80)
	lap_times_label.size = Vector2(300, 200)
	lap_times_label.bbcode_enabled = true
	lap_times_label.fit_content = true
	lap_times_label.scroll_active = false
	lap_times_label.add_theme_font_size_override("normal_font_size", 20)
	lap_times_label.add_theme_font_size_override("bold_font_size", 20)
	lap_times_label.add_theme_color_override("default_color", Color.WHITE)
	lap_times_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	lap_times_label.add_theme_constant_override("shadow_offset_x", 1)
	lap_times_label.add_theme_constant_override("shadow_offset_y", 1)
	lap_times_label.text = ""
	add_child(lap_times_label)
	
	# Current time (top right)
	current_time_label = Label.new()
	current_time_label.name = "CurrentTimeLabel"
	current_time_label.position = Vector2(1920 - 320, 20)
	current_time_label.size = Vector2(300, 40)
	current_time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	current_time_label.add_theme_font_size_override("font_size", 32)
	current_time_label.add_theme_color_override("font_color", Color(0.3, 1, 0.3))
	current_time_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	current_time_label.add_theme_constant_override("shadow_offset_x", 2)
	current_time_label.add_theme_constant_override("shadow_offset_y", 2)
	current_time_label.text = "00:00.000"
	add_child(current_time_label)
	
	# Speed (bottom center)
	speed_label = Label.new()
	speed_label.name = "SpeedLabel"
	speed_label.position = Vector2(1920/2 - 100, 1080 - 80)
	speed_label.size = Vector2(200, 60)
	speed_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	speed_label.add_theme_font_size_override("font_size", 48)
	speed_label.add_theme_color_override("font_color", Color(1, 0.8, 0))
	speed_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	speed_label.add_theme_constant_override("shadow_offset_x", 2)
	speed_label.add_theme_constant_override("shadow_offset_y", 2)
	speed_label.text = "0 km/h"
	add_child(speed_label)

func _process(_delta: float) -> void:
	_update_speed()
	_update_current_time()

func _update_speed() -> void:
	if not ship:
		speed_label.text = "0 km/h"
		return
	
	var speed_kmh = ship.velocity.length() * 3.6
	speed_label.text = "%d km/h" % int(speed_kmh)

func _update_current_time() -> void:
	if RaceManager.is_racing():
		var time = RaceManager.get_current_lap_time()
		current_time_label.text = RaceManager.format_time(time)

func _reset_display() -> void:
	lap_info_label.text = "LAP 1/3"
	lap_times_label.text = ""
	current_time_label.text = "00:00.000"
	speed_label.text = "0 km/h"
	countdown_label.visible = false

# ============================================================================
# SIGNAL HANDLERS
# ============================================================================

func _on_countdown_tick(number: int) -> void:
	countdown_label.visible = true
	
	if number == 0:
		countdown_label.text = "GO!"
		countdown_label.add_theme_color_override("font_color", Color(0.3, 1, 0.3))
	else:
		countdown_label.text = str(number)
		countdown_label.add_theme_color_override("font_color", Color.WHITE)
	
	# Fade out after a moment
	await get_tree().create_timer(0.8).timeout
	countdown_label.visible = false

func _on_race_started() -> void:
	_reset_display()

func _on_lap_completed(lap_number: int, lap_time: float) -> void:
	# Update lap counter
	if lap_number < RaceManager.total_laps:
		lap_info_label.text = "LAP %d/%d" % [lap_number + 1, RaceManager.total_laps]
	else:
		lap_info_label.text = "FINISHED"
	
	# Update lap times display
	_update_lap_times_display()

func _on_race_finished(_total_time: float, _best_lap: float) -> void:
	lap_info_label.text = "FINISHED"

func _update_lap_times_display() -> void:
	var lines: Array[String] = []
	
	# Find best lap time
	var best_time = INF
	for time in RaceManager.lap_times:
		if time < best_time:
			best_time = time
	
	# Display each lap
	for i in range(RaceManager.lap_times.size()):
		var time = RaceManager.lap_times[i]
		var time_str = RaceManager.format_time(time)
		
		# Bold best lap (using BBCode)
		if time == best_time:
			lines.append("[b]Lap %d: %s[/b]" % [i + 1, time_str])
		else:
			lines.append("Lap %d: %s" % [i + 1, time_str])
	
	lap_times_label.text = "\n".join(lines)
