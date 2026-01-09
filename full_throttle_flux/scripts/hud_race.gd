extends CanvasLayer
class_name HUDRace

## Racing HUD displaying countdown, lap progress, timing, and speed
## Adapts display based on race mode (Time Trial vs Endless)

@export var ship: AGShip2097

@export_group("Speed Display")
## Multiplier to convert velocity units to displayed km/h
## 3.6 = treats 1 unit as 1 meter (realistic)
## Lower values (1.0-2.0) = if your track is scaled larger than real-world
## Adjust until displayed speed matches visual feel
@export var speed_display_multiplier := 3.6

## Minimum speed to display (hides tiny residual velocities)
@export var speed_display_threshold := 0.5

# UI References
var countdown_label: Label
var lap_info_label: Label
var lap_times_label: RichTextLabel
var current_time_label: Label
var speed_label: Label
var fps_label: Label
var mode_label: Label

func _ready() -> void:
	# Connect to RaceManager signals
	RaceManager.countdown_tick.connect(_on_countdown_tick)
	RaceManager.race_started.connect(_on_race_started)
	RaceManager.lap_completed.connect(_on_lap_completed)
	RaceManager.race_finished.connect(_on_race_finished)
	
	_create_ui_elements()
	_reset_display()

func _create_ui_elements() -> void:
	# Countdown (large, horizontally centered, upper-middle of screen)
	countdown_label = Label.new()
	countdown_label.name = "CountdownLabel"
	countdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	countdown_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	# Position: centered horizontally, in the middle of the upper half (below lap counter)
	countdown_label.position = Vector2(1920/2 - 150, 180)
	countdown_label.size = Vector2(300, 150)
	countdown_label.add_theme_font_size_override("font_size", 120)
	countdown_label.add_theme_color_override("font_color", Color.WHITE)
	countdown_label.add_theme_color_override("font_outline_color", Color.BLACK)
	countdown_label.add_theme_constant_override("outline_size", 8)
	countdown_label.visible = false
	add_child(countdown_label)
	
	# Mode indicator (top left, above lap times)
	mode_label = Label.new()
	mode_label.name = "ModeLabel"
	mode_label.position = Vector2(20, 50)
	mode_label.size = Vector2(200, 30)
	mode_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	mode_label.add_theme_font_size_override("font_size", 20)
	mode_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	mode_label.text = ""
	add_child(mode_label)
	
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
	
	# FPS counter (bottom right)
	fps_label = Label.new()
	fps_label.name = "FPSLabel"
	fps_label.position = Vector2(1920 - 150, 1080 - 60)
	fps_label.size = Vector2(130, 40)
	fps_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	fps_label.add_theme_font_size_override("font_size", 24)
	fps_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	fps_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	fps_label.add_theme_constant_override("shadow_offset_x", 1)
	fps_label.add_theme_constant_override("shadow_offset_y", 1)
	fps_label.text = "60 FPS"
	add_child(fps_label)

func _process(_delta: float) -> void:
	_update_speed()
	_update_current_time()
	_update_fps()

func _update_speed() -> void:
	if not ship:
		speed_label.text = "0 km/h"
		return
	
	var speed_raw = ship.velocity.length()
	
	# Apply threshold to avoid showing tiny residual velocities
	if speed_raw < speed_display_threshold:
		speed_label.text = "0 km/h"
		return
	
	var speed_kmh = speed_raw * speed_display_multiplier
	speed_label.text = "%d km/h" % int(speed_kmh)

func _update_fps() -> void:
	var fps = Engine.get_frames_per_second()
	fps_label.text = "%d FPS" % fps
	
	# Color code FPS for performance feedback
	if fps >= 55:
		fps_label.add_theme_color_override("font_color", Color(0.3, 1, 0.3))  # Green
	elif fps >= 30:
		fps_label.add_theme_color_override("font_color", Color(1, 1, 0.3))  # Yellow
	else:
		fps_label.add_theme_color_override("font_color", Color(1, 0.3, 0.3))  # Red

func _update_current_time() -> void:
	if RaceManager.is_racing():
		var time = RaceManager.get_current_lap_time()
		current_time_label.text = RaceManager.format_time(time)

func _reset_display() -> void:
	# Update mode label
	if RaceManager.is_endless_mode():
		mode_label.text = "ENDLESS"
		mode_label.add_theme_color_override("font_color", Color(1.0, 0.6, 0.2))
		lap_info_label.text = "LAP 1"
	else:
		mode_label.text = ""
		lap_info_label.text = "LAP 1/%d" % RaceManager.total_laps
	
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

func _on_lap_completed(lap_number: int, _lap_time: float) -> void:
	# Update lap counter based on mode
	if RaceManager.is_endless_mode():
		# Endless mode: just show current lap number
		lap_info_label.text = "LAP %d" % (lap_number + 1)
	else:
		# Time trial mode: show lap X of Y
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
	
	# Find best lap time among displayed laps
	var best_displayed_time = RaceManager.get_best_displayed_lap_time()
	
	if RaceManager.is_endless_mode():
		# Endless mode: show persistent best lap at the top
		if RaceManager.best_lap_time < INF:
			var best_time_str = RaceManager.format_time(RaceManager.best_lap_time)
			lines.append("[color=#ffcc00][b]Best: %s[/b][/color]" % best_time_str)
			lines.append("")  # Empty line for spacing
		
		# Endless mode: show last 5 laps with their actual lap numbers
		# lap_times contains the rolling window of last 5
		var total_completed = RaceManager.endless_all_lap_times.size()
		var displayed_count = RaceManager.lap_times.size()
		var first_displayed_lap = total_completed - displayed_count + 1
		
		for i in range(displayed_count):
			var time = RaceManager.lap_times[i]
			var lap_num = first_displayed_lap + i
			var time_str = RaceManager.format_time(time)
			
			# Bold if this is the overall best lap
			if time == RaceManager.best_lap_time:
				lines.append("[b]Lap %d: %s[/b]" % [lap_num, time_str])
			else:
				lines.append("Lap %d: %s" % [lap_num, time_str])
	else:
		# Time trial mode: show all laps
		for i in range(RaceManager.lap_times.size()):
			var time = RaceManager.lap_times[i]
			var time_str = RaceManager.format_time(time)
			
			# Bold best lap (using BBCode)
			if time == best_displayed_time:
				lines.append("[b]Lap %d: %s[/b]" % [i + 1, time_str])
			else:
				lines.append("Lap %d: %s" % [i + 1, time_str])
	
	lap_times_label.text = "\n".join(lines)
