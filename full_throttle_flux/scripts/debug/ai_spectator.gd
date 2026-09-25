extends Node
class_name AISpectator

## Debug "watch" mode: point the chase camera at any ship in the race,
## including the AI ones, and read out what its controller is doing.
##
## Built for watching how the AI actually races -- lines, airbrake use, how it
## behaves in traffic -- rather than trying to keep up with it as a player.
##
## Deliberately self-discovering: it scans the tree for ShipController and
## AIShipController nodes rather than being handed a list by the race mode, so
## it works in any mode (race, time trial, a bare test scene) without those
## modes needing to know it exists.
##
## Keys (raw scancodes, so no project input map changes are needed):
##   F9          toggle spectator on/off
##   [  and  ]   previous / next ship
##   \           jump back to the player's ship
##   Y           cycle cinematic cameras (shift+Y goes back)
##   H           hide every HUD and overlay for a clean view
##   F10         cycle overlay detail: off -> basic -> full
##   F11         freeze the AI's inputs readout (useful for reading a moment)

## Set false to compile the spectator out of a build.
@export var enabled: bool = true

## Start spectating immediately rather than waiting for F9.
@export var auto_start: bool = false

var camera: Node3D
var _ships: Array[ShipController] = []
var _ais: Dictionary = {}          ## ShipController -> AIShipController
var _index: int = 0
var _player_ship: ShipController
var _active: bool = false
var _detail: int = 1               ## 0 off, 1 basic, 2 full
var _frozen: bool = false
var _layer: CanvasLayer
var _label: Label
var _refresh: float = 0.0

## Cinematic cameras, ported from MotorRig. Built on first use.
var _rig: CinematicCameraRig
## 0 = the game's chase camera, 1..n = rig cameras.
var _cam_index: int = 0

## Clean view: every CanvasLayer hidden, including this overlay.
var _clean: bool = false
var _hidden_layers: Array[CanvasLayer] = []

const REFRESH_INTERVAL := 0.1
const MAX_LAPS_SHOWN := 8

## Fallback lap timing for ships RaceManager is not tracking (time trial, bare
## test scenes). Timed wrap to wrap on the spline, for every ship all the time,
## so the history already exists when you switch to a ship.
var _timers: Dictionary = {}         ## ShipController -> Dictionary
var _helper: TrackSplineHelper
var _clock: float = 0.0

func _ready() -> void:
	if not enabled:
		set_process(false)
		set_process_unhandled_input(false)
		return
	_build_overlay()
	# Let the mode finish spawning before we look for ships.
	await get_tree().process_frame
	await get_tree().process_frame
	_rescan()
	if auto_start and _ships.size() > 0:
		_activate(true)

# ============================================================================
# DISCOVERY
# ============================================================================

func _rescan() -> void:
	_ships.clear()
	_ais.clear()
	_collect(get_tree().root)
	if _player_ship == null:
		for s in _ships:
			if not s.ai_controlled:
				_player_ship = s
				break
	if camera == null:
		camera = _find_camera(get_tree().root)

func _collect(n: Node) -> void:
	if n is ShipController:
		_ships.append(n)
	elif n is AIShipController and n.ship:
		_ais[n.ship] = n
		if _helper == null and n.spline_helper and n.spline_helper.is_valid:
			_helper = n.spline_helper
	for c in n.get_children():
		_collect(c)

func _find_camera(n: Node) -> Node3D:
	if n is Camera3D and "ship" in n and n.has_method("reset_to_ship"):
		return n
	for c in n.get_children():
		var r := _find_camera(c)
		if r:
			return r
	return null

# ============================================================================
# INPUT
# ============================================================================

## Uses _input rather than _unhandled_input so a focused Control (the HUD, a
## results screen) cannot swallow these. Only events we actually act on are
## marked handled, so nothing else changes.
func _input(event: InputEvent) -> void:
	if not enabled:
		return
	if event is InputEventKey:
		var key := event as InputEventKey
		if not key.pressed or key.echo:
			return
		# Match BOTH codes. `keycode` follows the keyboard layout and
		# `physical_keycode` follows US positions, and on a German QWERTZ
		# layout they disagree for exactly the keys used here: Y/Z swap, and
		# the brackets are not where US layouts put them at all.
		if _is_key(key, KEY_F9):
			_activate(not _active)
		elif _is_key(key, KEY_Y) or _is_key(key, KEY_Z) or _is_key(key, KEY_C):
			_cycle_camera(-1 if key.shift_pressed else 1)
		elif _is_key(key, KEY_BRACKETLEFT) or _is_key(key, KEY_COMMA):
			_step(-1)
		elif _is_key(key, KEY_BRACKETRIGHT) or _is_key(key, KEY_PERIOD):
			_step(1)
		elif _is_key(key, KEY_BACKSLASH):
			_to_player()
		elif _is_key(key, KEY_H):
			_set_clean_view(not _clean)
		elif _is_key(key, KEY_F10):
			_detail = (_detail + 1) % 3
			_layer.visible = _detail > 0
		elif _is_key(key, KEY_F11):
			_frozen = not _frozen
		else:
			return
		get_viewport().set_input_as_handled()
		return
	
	# Gamepad, while spectating only, so gameplay controls are untouched.
	# MotorRig cycled cameras on gamepad Y, which is the habit to match.
	if _active and event is InputEventJoypadButton:
		var pad := event as InputEventJoypadButton
		if not pad.pressed:
			return
		match pad.button_index:
			JOY_BUTTON_Y:
				_cycle_camera(1)
			JOY_BUTTON_X:
				_cycle_camera(-1)
			JOY_BUTTON_LEFT_SHOULDER:
				_step(-1)
			JOY_BUTTON_RIGHT_SHOULDER:
				_step(1)
			_:
				return
		get_viewport().set_input_as_handled()

## True if either the layout-mapped or the physical code matches.
func _is_key(key: InputEventKey, code: Key) -> bool:
	return key.keycode == code or key.physical_keycode == code

func _activate(on: bool) -> void:
	if on and _ships.is_empty():
		_rescan()
		if _ships.is_empty():
			push_warning("AISpectator: no ships found")
			return
	_active = on
	_layer.visible = on and _detail > 0
	print("AISpectator: %s (%d ships). Y or gamepad Y cycles cameras." % [
		"ON" if on else "off", _ships.size()])
	if on:
		# Prefer starting on an AI ship -- watching the player from here is
		# what the normal camera already does.
		for i in range(_ships.size()):
			if _ships[i].ai_controlled:
				_index = i
				break
		_attach(_ships[_index])
	else:
		_to_player()
		_cam_index = 0
		_apply_camera()

# ============================================================================
# CINEMATIC CAMERAS
# ============================================================================

## Cycle chase -> cockpit -> heli -> ... -> orbit -> chase.
func _cycle_camera(step: int) -> void:
	if not _active:
		return
	if _rig == null:
		_rig = CinematicCameraRig.new()
		_rig.name = "CinematicCameraRig"
		add_child(_rig)
		# Several cameras need the track, not just the ship: clamping plants to
		# the corridor, sitting on the racing surface, flying the kamikaze camera
		# along the spline through corners.
		_rig.spline = _helper
		if _index < _ships.size():
			_rig.follow(_ships[_index])
	_cam_index = wrapi(_cam_index + step, 0, _rig.cameras.size() + 1)
	_apply_camera()
	print("AISpectator: camera -> %s" % camera_label())

func _apply_camera() -> void:
	if _cam_index == 0 or _rig == null:
		if _rig:
			_rig.release()
		if camera is Camera3D:
			(camera as Camera3D).make_current()
	else:
		_rig.select_index(_cam_index - 1)

## Hide every CanvasLayer in the tree -- race HUD, debug HUD, now-playing
## display and this overlay -- so the cinematic cameras give a clean frame.
##
## Only layers that were visible get restored, so anything already hidden (a
## pause menu, the results screen) is not switched on by turning clean view
## off again.
func _set_clean_view(on: bool) -> void:
	_clean = on
	if on:
		_hidden_layers.clear()
		_collect_layers(get_tree().root)
		for layer in _hidden_layers:
			layer.visible = false
	else:
		for layer in _hidden_layers:
			if is_instance_valid(layer):
				layer.visible = true
		_hidden_layers.clear()
		_layer.visible = _active and _detail > 0

func _collect_layers(n: Node) -> void:
	if n is CanvasLayer and (n as CanvasLayer).visible:
		_hidden_layers.append(n)
	for c in n.get_children():
		_collect_layers(c)

func camera_label() -> String:
	if _cam_index == 0 or _rig == null:
		return "chase"
	return _rig.active_name()

func _step(dir: int) -> void:
	if not _active or _ships.is_empty():
		return
	_index = wrapi(_index + dir, 0, _ships.size())
	_attach(_ships[_index])

func _to_player() -> void:
	if _player_ship:
		_attach(_player_ship)
		_active = false
		_layer.visible = false

## Reassigning the camera's ship is all that is needed -- AGCamera2097 reads
## everything else off it. reset_to_ship() re-snaps so we do not sweep across
## the level, and it deliberately skips the cinematic intro.
func _attach(ship: ShipController) -> void:
	if camera == null or ship == null:
		return
	camera.ship = ship
	if camera.has_method("reset_to_ship"):
		camera.reset_to_ship()
	# Point the cinematic cameras at the new ship too, and snap them, so a rig
	# camera on screen changes subject without sweeping across the level.
	if _rig:
		_rig.follow(ship)
		_apply_camera()

# ============================================================================
# OVERLAY
# ============================================================================

func _build_overlay() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 100
	_layer.visible = false
	add_child(_layer)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	panel.position = Vector2(16, 16)
	panel.modulate = Color(1, 1, 1, 0.9)
	_layer.add_child(panel)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 10)
	panel.add_child(margin)

	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 13)
	margin.add_child(_label)

func _process(delta: float) -> void:
	if not _active or _detail == 0 or _frozen:
		return
	_refresh -= delta
	if _refresh > 0.0:
		return
	if _clean:
		return
	_refresh = REFRESH_INTERVAL
	_label.text = _build_text()

# ============================================================================
# PROVENANCE -- "which AI am I actually looking at?"
# ============================================================================

## Everything that makes an in-race AI differ from what the training tools
## measured. The trained lap times are for skill 1.0, avoidance off, alone on
## track, on a flying lap -- anything shown here that differs from that is a
## reason the watched ship will not match them.
func _provenance_lines(ship: ShipController, ai: AIShipController) -> Array[String]:
	var out: Array[String] = []
	if not ship.ai_controlled or ai == null or not ai.is_initialized:
		return out
	
	var line: BakedRacingLine = ai.baked_line
	var source: String = ai.line_source if not ai.line_source.is_empty() else "unknown"
	var ship_id: String = ship.profile.ship_id if ship.profile else "?"
	
	if source.begins_with("TRAINED") and line != null:
		var style := "speeds only"
		if line.style_log.size() > 0:
			style = str(line.style_log.size()) + " segs" if line.style_log.size() > 1 \
					else line.style_log[0]
		# Lines assembled before v16 never recorded their lap time; re-running
		# tools/style_search.tscn stamps it.
		var measured := "%.3fs" % line.trained_lap_time if line.trained_lap_time > 0.0 \
				else "time not recorded"
		out.append("LINE  %s for %s  %s  [%s]" % [source, ship_id, measured, style])
	else:
		out.append("LINE  %s  -- NOT the trained AI (%s)" % [source, ship_id])
	
	var notes: Array[String] = []
	notes.append("skill %.2f%s" % [ai.skill_level,
			"" if ai.skill_level >= 0.999 else " HANDICAPPED"])
	notes.append("avoid " + ("ON" if ai.avoidance_enabled else "off"))
	out.append("AI    " + "   ".join(notes))
	return out

# ============================================================================
# LAP TIMES
# ============================================================================

func _physics_process(delta: float) -> void:
	if not enabled:
		return
	_clock += delta
	# Only needed for ships RaceManager is not tracking.
	if _helper == null:
		if Engine.get_physics_frames() % 30 == 0:
			_rescan()
		return
	for ship in _ships:
		if is_instance_valid(ship) and not _race_tracks(ship):
			_tick_timer(ship)

func _race_manager() -> Node:
	return get_node_or_null("/root/RaceManager")

func _race_tracks(ship: ShipController) -> bool:
	var rm := _race_manager()
	return rm != null and "ship_all_lap_times" in rm and rm.ship_all_lap_times.has(ship)

func _tick_timer(ship: ShipController) -> void:
	var t: Dictionary = _timers.get(ship, {})
	if t.is_empty():
		t = {"prev": -1.0, "start": -1.0, "laps": PackedFloat32Array()}
		_timers[ship] = t
	var offset: float = _helper.world_to_spline_offset(ship.global_position)
	var prev: float = t.prev
	if prev >= 0.0:
		if offset < prev - 0.5:
			if t.start >= 0.0:
				var laps: PackedFloat32Array = t.laps
				laps.append(_clock - t.start)
				t.laps = laps
			t.start = _clock
		elif offset > prev + 0.5:
			t.start = -1.0   # crossed the line backwards; lap is void
	t.prev = offset

## Lap 1 is flagged "s" (standing start from the grid); "best flying" excludes
## it, because only flying laps are comparable to the trained lap times.
func _lap_lines(ship: ShipController) -> Array[String]:
	var out: Array[String] = []
	var laps: Array[float] = []
	var current := -1.0
	var source := ""
	
	if _race_tracks(ship):
		var rm := _race_manager()
		for v in rm.ship_all_lap_times[ship]:
			laps.append(float(v))
		var start: float = rm.ship_lap_start_times.get(ship, 0.0)
		if start > 0.0 and not rm.has_ship_finished(ship):
			current = Time.get_ticks_msec() / 1000.0 - start
		source = "race"
	elif _timers.has(ship):
		var t: Dictionary = _timers[ship]
		for v in t.laps:
			laps.append(v)
		if t.start >= 0.0:
			current = _clock - t.start
		source = "spline"
	else:
		out.append("LAPS  waiting for the line")
		return out
	
	var best_flying := INF
	var best_i := -1
	for i in range(1, laps.size()):
		if laps[i] < best_flying:
			best_flying = laps[i]
			best_i = i
	
	out.append("LAPS  now %s   best flying %s   (%s timing)" % [
		"%.2f" % current if current >= 0.0 else "--",
		"%.3f L%d" % [best_flying, best_i + 1] if best_i >= 0 else "--",
		source])
	
	if laps.size() > 0:
		var parts: Array[String] = []
		for i in range(maxi(0, laps.size() - MAX_LAPS_SHOWN), laps.size()):
			parts.append("L%d%s %.2f%s" % [i + 1, "s" if i == 0 else "",
					laps[i], "*" if i == best_i else ""])
		out.append("      " + "  ".join(parts))
	return out

func _build_text() -> String:
	if _index >= _ships.size():
		return "no ship"
	var ship: ShipController = _ships[_index]
	var name := "ship %d/%d" % [_index + 1, _ships.size()]
	if ship.profile:
		name += "  %s" % ship.profile.display_name
	name += "  [AI]" if ship.ai_controlled else "  [PLAYER]"

	var lines: Array[String] = [name]
	lines.append("CAM   %s   (Y cycles)" % camera_label())
	lines.append("speed %6.1f  (%.0f%%)" % [
		ship.velocity.length(), ship.get_speed_ratio() * 100.0])
	lines.append_array(_provenance_lines(ship, _ais.get(ship)))
	lines.append_array(_lap_lines(ship))

	if _detail < 2:
		lines.append("[ ] cycle   \\ player   F10 detail")
		return "\n".join(lines)

	lines.append("slip %5.1f deg   yaw %5.1f deg/s   roll %5.1f deg" % [
		rad_to_deg(ship.slip_angle), rad_to_deg(ship.measured_yaw_rate),
		rad_to_deg(ship.visual_roll)])
	lines.append("thr %.2f  steer %+.2f  AB %.2f/%.2f  grounded %s" % [
		ship.throttle_input, ship.steer_input,
		ship.airbrake_left, ship.airbrake_right, ship.is_grounded])

	var ai: AIShipController = _ais.get(ship)
	if ai and ai.is_initialized:
		if ai.control_decider:
			lines.append(ai.control_decider.get_debug_info())
		if ai.line_follower and ai.baked_line:
			var offset: float = ai.line_follower.current_spline_offset
			var target: float = ai.baked_line.get_speed_at(offset)
			var desired: float = ai.baked_line.get_lateral_at(offset)
			lines.append("target %6.1f  (%+.1f)   line lateral %+.1f" % [
				target, ship.velocity.length() - target, desired])
			if ai.baked_line.has_style_gains():
				lines.append("style: AB %.2f  reserve %.2f  look %.0fm" % [
					ai.baked_line.get_style_airbrake_at(offset),
					ai.baked_line.get_style_reserve_at(offset),
					ai.baked_line.get_style_lookahead_at(offset)])
	lines.append("[ ] cycle   \\ player   F10 detail   F11 freeze")
	return "\n".join(lines)
