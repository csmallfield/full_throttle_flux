extends CanvasLayer
class_name HUDRace

## Racing HUD displaying countdown, lap progress, timing, speed, and race position
## Adapts display based on race mode (Time Trial vs Endless vs Race)

@export var ship: Node3D # Changed to Node3D for broader compatibility, cast as needed

@export_group("Speed Display")
## Multiplier to convert velocity units to displayed km/h
## 3.6 = treats 1 unit as 1 meter (realistic)
## Lower values (1.0-2.0) = if your track is scaled larger than real-world
## Adjust until displayed speed matches visual feel
@export var speed_display_multiplier := 3.6

## Minimum speed to display (hides tiny residual velocities)
@export var speed_display_threshold := 0.5
@export var max_gauge_speed := 1000.0

@export_group("Race Mode")
## Position tracker reference (set by RaceMode)
var position_tracker: RacePositionTracker

## Is this a race against opponents?
var is_race_mode: bool = false

## Total number of racers (for display like "P2/4")
var total_racers: int = 1

# UI References
var countdown_label: Label
var lap_info_label: Label
var lap_times_label: RichTextLabel
var current_time_label: Label
var fps_label: Label
var mode_label: Label
var speed_gauge: SpeedGauge

# Race position UI
var position_label: Label
var position_container: PanelContainer

# --------------------------------------------------------------------------------
# INTERNAL CLASS: SPEED GAUGE
# Handles drawing the arc, ticks, and needle using the CanvasItem API
# --------------------------------------------------------------------------------
class SpeedGauge extends Control:
	var current_speed: float = 0.0
	var max_speed: float = 1000.0
	var radius: float = 80.0
	var arc_color := Color(1, 1, 1, 0.2)
	var needle_color := Color(1, 0.2, 0.2)
	var text_color := Color(1, 0.8, 0)
	
	# Gauge angles (in degrees) - 135 to 405 gives a 270-degree dial starting bottom-left
	const START_ANGLE_DEG = 135.0
	const END_ANGLE_DEG = 405.0
	
	var _displayed_speed: float = 0.0
	var _speed_label: Label

	func _ready() -> void:
		# Add a label inside the gauge for the digital readout
		_speed_label = Label.new()
		_speed_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_speed_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_speed_label.add_theme_font_size_override("font_size", 24)
		_speed_label.add_theme_color_override("font_color", text_color)
		_speed_label.position = Vector2(-50, 20) # Offset slightly down from center
		_speed_label.size = Vector2(100, 30)
		add_child(_speed_label)

	func update_speed(target_speed: float, delta: float) -> void:
		# Smooth needle movement (Lerp)
		_displayed_speed = lerpf(_displayed_speed, target_speed, delta * 5.0)
		_speed_label.text = "%d" % int(target_speed) # Digital readout
		queue_redraw() # Trigger _draw()

	func _draw() -> void:
		var center = Vector2.ZERO # Draw relative to the control's center
		var start_rad = deg_to_rad(START_ANGLE_DEG)
		var end_rad = deg_to_rad(END_ANGLE_DEG)
		
		# 1. Draw Background Arc
		draw_arc(center, radius, start_rad, end_rad, 64, arc_color, 10.0, true)
		
		# 2. Draw Ticks (Major ticks every 100 units)
		var total_angle = end_rad - start_rad
		var major_step = 100.0
		var num_ticks = int(max_speed / major_step)
		
		for i in range(num_ticks + 1):
			var speed_val = i * major_step
			var t = speed_val / max_speed
			var angle = start_rad + (total_angle * t)
			var dir = Vector2(cos(angle), sin(angle))
			
			# Draw tick line
			draw_line(center + dir * (radius - 15), center + dir * radius, arc_color, 2.0)
		
		# 3. Draw Needle
		var speed_fraction = clamp(_displayed_speed / max_speed, 0.0, 1.0)
		var needle_angle = start_rad + (total_angle * speed_fraction)
		var needle_dir = Vector2(cos(needle_angle), sin(needle_angle))
		
		draw_line(center, center + needle_dir * (radius - 5), needle_color, 4.0, true)
		draw_circle(center, 5.0, needle_color) # Center cap

# --------------------------------------------------------------------------------
# MAIN HUD LOGIC
# --------------------------------------------------------------------------------

func _ready() -> void:
	# Connect to RaceManager signals
	if RaceManager:
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
	
	# Race position display (top right, prominent)
	_create_position_display()
	
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
	
	# Current time (top right, below position in race mode)
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
	
	# --- SPEED GAUGE SETUP ---
	speed_gauge = SpeedGauge.new()
	speed_gauge.name = "SpeedGauge"
	# Position at bottom center
	speed_gauge.position = Vector2(1920/2, 1080 - 120) 
	speed_gauge.max_speed = max_gauge_speed
	add_child(speed_gauge)
	
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

func _create_position_display() -> void:
	"""Create the race position display (P1, P2, etc.)."""
	# Container panel for position
	position_container = PanelContainer.new()
	position_container.name = "PositionContainer"
	position_container.position = Vector2(1920 - 180, 70)
	position_container.size = Vector2(160, 80)
	
	# Style the panel
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.0, 0.0, 0.0, 0.7)
	style.corner_radius_top_left = 10
	style.corner_radius_top_right = 10
	style.corner_radius_bottom_left = 10
	style.corner_radius_bottom_right = 10
	style.border_width_left = 3
	style.border_width_right = 3
	style.border_width_top = 3
	style.border_width_bottom = 3
	style.border_color = Color(1.0, 0.8, 0.0)  # Gold border
	position_container.add_theme_stylebox_override("panel", style)
	
	add_child(position_container)
	
	# Position label inside container
	position_label = Label.new()
	position_label.name = "PositionLabel"
	position_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	position_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	position_label.add_theme_font_size_override("font_size", 48)
	position_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3))  # Gold text
	position_label.text = "P1"
	position_container.add_child(position_label)
	
	# Initially hidden (shown only in race mode)
	position_container.visible = false

func _process(delta: float) -> void:
	_update_speed(delta)
	_update_current_time()
	_update_fps()
	_update_position_display()

func _update_speed(delta: float) -> void:
	if not is_instance_valid(ship):
		speed_gauge.update_speed(0.0, delta)
		return
	
	var speed_raw = ship.velocity.length()
	var speed_kmh = speed_raw * speed_display_multiplier
	
	# Pass data to gauge (it handles its own visual smoothing)
	speed_gauge.update_speed(speed_kmh, delta)

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

func _update_position_display() -> void:
	"""Update the race position indicator."""
	if not is_race_mode:
		position_container.visible = false
		return
	
	position_container.visible = true
	
	var current_position: int = -1
	
	# Get position from tracker if available
	if position_tracker:
		current_position = position_tracker.get_player_position()
	
	if current_position < 1:
		position_label.text = "P?"
		return
	
	# Format as "P1" or "P1/4" 
	if total_racers > 1:
		position_label.text = "P%d/%d" % [current_position, total_racers]
	else:
		position_label.text = "P%d" % current_position
	
	# Color code by position
	var style = position_container.get_theme_stylebox("panel") as StyleBoxFlat
	
	match current_position:
		1:
			# Gold for 1st place
			position_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3))
			if style:
				style.border_color = Color(1.0, 0.8, 0.0)
		2:
			# Silver for 2nd
			position_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
			if style:
				style.border_color = Color(0.6, 0.6, 0.6)
		3:
			# Bronze for 3rd
			position_label.add_theme_color_override("font_color", Color(0.8, 0.5, 0.2))
			if style:
				style.border_color = Color(0.7, 0.4, 0.1)
		_:
			# White for other positions
			position_label.add_theme_color_override("font_color", Color.WHITE)
			if style:
				style.border_color = Color(0.4, 0.4, 0.4)

func _reset_display() -> void:
	# Update mode label
	if RaceManager.is_race_mode():
		mode_label.text = "RACE"
		mode_label.add_theme_color_override("font_color", Color(0.3, 0.8, 1.0))
		lap_info_label.text = "LAP 1/%d" % RaceManager.total_laps
		is_race_mode = true
	elif RaceManager.is_endless_mode():
		mode_label.text = "ENDLESS"
		mode_label.add_theme_color_override("font_color", Color(1.0, 0.6, 0.2))
		lap_info_label.text = "LAP 1"
		is_race_mode = false
	else:
		mode_label.text = ""
		lap_info_label.text = "LAP 1/%d" % RaceManager.total_laps
		is_race_mode = false
	
	# Adjust time label position based on mode
	if is_race_mode:
		current_time_label.position = Vector2(1920 - 320, 160)  # Below position display
	else:
		current_time_label.position = Vector2(1920 - 320, 20)
	
	lap_times_label.text = ""
	current_time_label.text = "00:00.000"
	countdown_label.visible = false
	
	# Reset gauge
	if speed_gauge:
		speed_gauge.update_speed(0.0, 1.0)

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
	if RaceManager.is_race_mode():
		if lap_number < RaceManager.total_laps:
			lap_info_label.text = "LAP %d/%d" % [lap_number + 1, RaceManager.total_laps]
		else:
			lap_info_label.text = "FINISHED"
	elif RaceManager.is_endless_mode():
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
	
	# Show final position in race mode
	if is_race_mode and position_tracker:
		var final_pos = position_tracker.get_player_position()
		position_label.text = _format_position_ordinal(final_pos)

func _format_position_ordinal(position: int) -> String:
	"""Format position with ordinal suffix (1st, 2nd, 3rd, etc.)."""
	if position < 1:
		return "?"
	
	var suffix: String
	match position:
		1:
			suffix = "st"
		2:
			suffix = "nd"
		3:
			suffix = "rd"
		_:
			suffix = "th"
	
	return "%d%s" % [position, suffix]

func _update_lap_times_display() -> void:
	var lines: Array[String] = []
	
	# Find best lap time among displayed laps
	var best_displayed_time = RaceManager.get_best_displayed_lap_time()
	
	if RaceManager.is_race_mode():
		# Race mode: show lap times similar to time trial
		if RaceManager.best_lap_time < INF:
			var best_time_str = RaceManager.format_time(RaceManager.best_lap_time)
			lines.append("[color=#ffcc00][b]Best: %s[/b][/color]" % best_time_str)
			lines.append("")
		
		for i in range(RaceManager.lap_times.size()):
			var time = RaceManager.lap_times[i]
			var time_str = RaceManager.format_time(time)
			
			if time == RaceManager.best_lap_time:
				lines.append("[b]Lap %d: %s[/b]" % [i + 1, time_str])
			else:
				lines.append("Lap %d: %s" % [i + 1, time_str])
	
	elif RaceManager.is_endless_mode():
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
