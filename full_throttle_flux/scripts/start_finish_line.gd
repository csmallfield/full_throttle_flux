extends Area3D
class_name StartFinishLine

## Detects when ships cross the start/finish line and triggers lap completion.
## Respects global SFX volume from AudioManager.
## Supports both single-ship and multi-ship (race) modes.
## 
## Anti-cheat features:
## - First crossing only "starts" lap timing, doesn't complete a lap
## - Wrong-way crossing activates penalty mode requiring extra valid crossing
## - Short cooldown prevents physics jitter double-triggers
## 
## Detection uses velocity direction only (more reliable than position checks)

@export_group("Visual Settings")

## Color of the start/finish line
@export var line_color := Color(1.0, 1.0, 1.0, 0.8)

## Emission intensity for the glowing effect
@export var glow_intensity := 2.0

@export_group("Detection Settings")

## Minimum time between crossing detections per ship (prevents physics jitter)
## Keep this short - just enough to prevent double-triggers from same crossing
@export var crossing_cooldown := 0.3

## Enable detailed debug output
@export var debug_enabled := true

# Audio player for line cross sound
var _audio_player: AudioStreamPlayer3D

# Base volume for line cross sound (before SFX offset)
var _base_volume := -3.0

# Internal state - now per-ship for race mode
var _race_started := false

# Per-ship tracking for multi-ship races
# ship -> { first_crossing_done: bool, penalty_mode: bool, last_crossing_time: float, inside: bool }
var _ship_states: Dictionary = {}

# Legacy single-ship state (for backwards compatibility)
var _first_crossing_done := false
var _penalty_mode := false
var _last_crossing_time := -999.0
var _ship_inside := false

func _ready() -> void:
	# Connect to race manager
	RaceManager.race_started.connect(_on_race_started)
	RaceManager.race_finished.connect(_on_race_finished)
	
	# Connect area signals
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	
	# Update visual material
	_update_visual_material()
	
	# Setup audio
	_setup_audio()

func _setup_audio() -> void:
	_audio_player = AudioStreamPlayer3D.new()
	_audio_player.name = "LineCrossPlayer"
	_audio_player.max_distance = 80.0
	_audio_player.volume_db = _base_volume
	add_child(_audio_player)
	
	# Load the sound
	if ResourceLoader.exists(AudioManager.SFX_LINE_CROSS):
		_audio_player.stream = load(AudioManager.SFX_LINE_CROSS)

func _on_race_started() -> void:
	_race_started = true
	
	# Reset legacy state
	_first_crossing_done = false
	_penalty_mode = false
	_last_crossing_time = -999.0
	_ship_inside = false
	
	# Reset per-ship states
	_ship_states.clear()
	
	if debug_enabled:
		print("StartFinishLine: Race started, state reset")

func _on_race_finished(_total_time: float, _best_lap: float) -> void:
	_race_started = false

func _get_ship_state(ship: Node3D) -> Dictionary:
	"""Get or create per-ship state for race mode."""
	if ship not in _ship_states:
		_ship_states[ship] = {
			"first_crossing_done": false,
			"penalty_mode": false,
			"last_crossing_time": -999.0,
			"inside": false
		}
	return _ship_states[ship]

func _on_body_entered(body: Node3D) -> void:
	if not body is ShipController:
		return
	
	if not _race_started:
		return
	
	var ship = body as ShipController
	
	# Use per-ship tracking for race mode
	if RaceManager.is_race_mode():
		_handle_ship_entry_race_mode(ship)
	else:
		_handle_ship_entry_legacy(ship)

func _handle_ship_entry_race_mode(ship: ShipController) -> void:
	"""Handle ship entry in multi-ship race mode."""
	var state = _get_ship_state(ship)
	
	# Prevent processing if ship is already considered "inside"
	if state.inside:
		if debug_enabled:
			print("StartFinishLine: Ignoring entry for %s - ship already inside" % ship.name)
		return
	
	state.inside = true
	
	# Check cooldown
	var current_time = Time.get_ticks_msec() / 1000.0
	if current_time - state.last_crossing_time < crossing_cooldown:
		if debug_enabled:
			print("StartFinishLine: Ignoring %s - cooldown active" % ship.name)
		return
	
	# Get the line's forward direction (valid crossing direction)
	var line_forward = -global_transform.basis.z
	
	# Use velocity to determine crossing direction
	var velocity_dot = ship.velocity.dot(line_forward)
	var is_moving_forward = velocity_dot > 0
	
	if debug_enabled:
		print("StartFinishLine: === %s ENTRY ===" % ship.name)
		print("  Velocity dot: %.2f (forward=%s)" % [velocity_dot, is_moving_forward])
		print("  State: first_done=%s, penalty=%s" % [state.first_crossing_done, state.penalty_mode])
	
	state.last_crossing_time = current_time
	
	if is_moving_forward:
		_handle_forward_crossing_race_mode(ship, state)
	else:
		_handle_wrong_way_crossing_race_mode(ship, state)

func _handle_forward_crossing_race_mode(ship: ShipController, state: Dictionary) -> void:
	"""Handle valid forward crossing in race mode."""
	if not state.first_crossing_done:
		# First crossing - this "starts" lap 1, doesn't complete anything
		state.first_crossing_done = true
		_play_crossing_effect()
		_play_crossing_sound()
		print("StartFinishLine: *** %s First crossing - Lap 1 STARTED ***" % ship.name)
		return
	
	if state.penalty_mode:
		# Ship went wrong way earlier, this crossing just clears the penalty
		state.penalty_mode = false
		_play_crossing_sound()
		print("StartFinishLine: *** %s Penalty CLEARED ***" % ship.name)
		return
	
	# Valid lap completion!
	print("StartFinishLine: *** %s LAP COMPLETE! ***" % ship.name)
	RaceManager.complete_lap(ship)
	_play_crossing_effect()
	_play_crossing_sound()
	
	# Play lap complete sound via AudioManager (only for player)
	if ship == RaceManager.player_ship:
		AudioManager.play_lap_complete()
		
		# Check if this was the final lap warning (entering last lap)
		if RaceManager.current_lap == RaceManager.total_laps:
			AudioManager.play_final_lap()

func _handle_wrong_way_crossing_race_mode(ship: ShipController, state: Dictionary) -> void:
	"""Handle wrong-way crossing in race mode."""
	if not state.first_crossing_done:
		if debug_enabled:
			print("StartFinishLine: %s Wrong way ignored - race not started yet" % ship.name)
		return
	
	if not state.penalty_mode:
		state.penalty_mode = true
		
		# Only show warning for player
		if ship == RaceManager.player_ship:
			RaceManager.wrong_way_warning.emit()
			AudioManager.play_wrong_way()
		
		print("StartFinishLine: *** %s WRONG WAY - Penalty activated! ***" % ship.name)

func _handle_ship_entry_legacy(ship: ShipController) -> void:
	"""Legacy single-ship handling for Time Trial / Endless modes."""
	# Prevent processing if ship is already considered "inside"
	if _ship_inside:
		if debug_enabled:
			print("StartFinishLine: Ignoring entry - ship already inside")
		return
	
	_ship_inside = true
	
	# Check cooldown
	var current_time = Time.get_ticks_msec() / 1000.0
	if current_time - _last_crossing_time < crossing_cooldown:
		if debug_enabled:
			print("StartFinishLine: Ignoring - cooldown active (%.2f sec remaining)" % (crossing_cooldown - (current_time - _last_crossing_time)))
		return
	
	# Get the line's forward direction (valid crossing direction)
	var line_forward = -global_transform.basis.z
	
	# Use ONLY velocity to determine crossing direction
	var velocity_dot = ship.velocity.dot(line_forward)
	var is_moving_forward = velocity_dot > 0
	
	if debug_enabled:
		print("StartFinishLine: === ENTRY DETECTED ===")
		print("  Line forward: ", line_forward)
		print("  Ship velocity: ", ship.velocity)
		print("  Velocity dot: %.2f (forward=%s)" % [velocity_dot, is_moving_forward])
		print("  State: first_done=%s, penalty=%s" % [_first_crossing_done, _penalty_mode])
	
	_last_crossing_time = current_time
	
	if is_moving_forward:
		_handle_forward_crossing()
	else:
		_handle_wrong_way_crossing()

func _on_body_exited(body: Node3D) -> void:
	if not body is ShipController:
		return
	
	var ship = body as ShipController
	
	if RaceManager.is_race_mode():
		var state = _get_ship_state(ship)
		state.inside = false
		if debug_enabled:
			print("StartFinishLine: %s exited trigger area" % ship.name)
	else:
		_ship_inside = false
		if debug_enabled:
			print("StartFinishLine: Ship exited trigger area")

func _handle_forward_crossing() -> void:
	"""Legacy forward crossing for single-ship modes."""
	if not _first_crossing_done:
		# First crossing - this "starts" lap 1, doesn't complete anything
		_first_crossing_done = true
		_play_crossing_effect()
		_play_crossing_sound()
		print("StartFinishLine: *** First crossing - Lap 1 STARTED ***")
		return
	
	if _penalty_mode:
		# Ship went wrong way earlier, this crossing just clears the penalty
		_penalty_mode = false
		_play_crossing_sound()
		print("StartFinishLine: *** Penalty CLEARED - complete another lap to count ***")
		return
	
	# Valid lap completion!
	print("StartFinishLine: *** LAP COMPLETE! ***")
	RaceManager.complete_lap()
	_play_crossing_effect()
	_play_crossing_sound()
	
	# Play lap complete sound via AudioManager
	AudioManager.play_lap_complete()
	
	# Check if this was the final lap warning (entering last lap)
	if RaceManager.current_lap == RaceManager.total_laps:
		AudioManager.play_final_lap()

func _handle_wrong_way_crossing() -> void:
	"""Legacy wrong-way crossing for single-ship modes."""
	if not _first_crossing_done:
		# Haven't even started yet, ignore
		if debug_enabled:
			print("StartFinishLine: Wrong way ignored - race not started yet")
		return
	
	# Only activate penalty if not already in penalty mode
	if not _penalty_mode:
		_penalty_mode = true
		RaceManager.wrong_way_warning.emit()
		AudioManager.play_wrong_way()
		print("StartFinishLine: *** WRONG WAY - Penalty activated! ***")
	else:
		if debug_enabled:
			print("StartFinishLine: Wrong way (already in penalty mode)")

func _play_crossing_sound() -> void:
	if _audio_player and _audio_player.stream:
		# Apply global SFX volume offset
		_audio_player.volume_db = _base_volume + AudioManager.get_sfx_db_offset()
		_audio_player.pitch_scale = randf_range(0.98, 1.02)
		_audio_player.play()

func _play_crossing_effect() -> void:
	var line_mesh = get_node_or_null("LineMesh")
	if line_mesh and line_mesh is CSGBox3D:
		var material = line_mesh.material as StandardMaterial3D
		if material:
			var tween = create_tween()
			tween.tween_property(material, "emission_energy_multiplier", glow_intensity * 2.0, 0.1)
			tween.tween_property(material, "emission_energy_multiplier", glow_intensity, 0.3)

func _update_visual_material() -> void:
	var line_mesh = get_node_or_null("LineMesh")
	if not line_mesh or not line_mesh is CSGBox3D:
		return
	
	var mat = StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = line_color
	mat.emission_enabled = true
	mat.emission = Color(line_color.r, line_color.g, line_color.b, 1.0)
	mat.emission_energy_multiplier = glow_intensity
	
	line_mesh.material = mat
