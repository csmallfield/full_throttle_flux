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

const REFRESH_INTERVAL := 0.1

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

func _unhandled_input(event: InputEvent) -> void:
	if not enabled or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match (event as InputEventKey).keycode:
		KEY_F9:
			_activate(not _active)
		KEY_BRACKETLEFT:
			_step(-1)
		KEY_BRACKETRIGHT:
			_step(1)
		KEY_BACKSLASH:
			_to_player()
		KEY_F10:
			_detail = (_detail + 1) % 3
			_layer.visible = _detail > 0
		KEY_F11:
			_frozen = not _frozen

func _activate(on: bool) -> void:
	if on and _ships.is_empty():
		_rescan()
		if _ships.is_empty():
			push_warning("AISpectator: no ships found")
			return
	_active = on
	_layer.visible = on and _detail > 0
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
	_refresh = REFRESH_INTERVAL
	_label.text = _build_text()

func _build_text() -> String:
	if _index >= _ships.size():
		return "no ship"
	var ship: ShipController = _ships[_index]
	var name := "ship %d/%d" % [_index + 1, _ships.size()]
	if ship.profile:
		name += "  %s" % ship.profile.display_name
	name += "  [AI]" if ship.ai_controlled else "  [PLAYER]"

	var lines: Array[String] = [name]
	lines.append("speed %6.1f  (%.0f%%)" % [
		ship.velocity.length(), ship.get_speed_ratio() * 100.0])

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
