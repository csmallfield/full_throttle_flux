extends Control
## Surface Lab: the road's cross-section at the camera, with both layers drawn
## to one scale: the zone's bands across the bottom, the greeble rules of the
## zone's style pinned where they actually sit at this road width.
##
## Click a band or a pin to select it. Drag a boundary between bands to resize
## the fixed band (fixed bands stack in from the edge, as in the shader). Drag a
## ground pin to change its lateral.

signal band_selected(index: int)
signal rule_selected(index: int)
signal band_width_dragged(index: int, width: float)
signal pin_dragged(rule: int, lateral: float)

const BAND_COLORS := {
	TrackSurfaceBand.Type.PLATE: Color(0.34, 0.36, 0.40),
	TrackSurfaceBand.Type.CHANNEL: Color(0.06, 0.06, 0.07),
	TrackSurfaceBand.Type.EDGE: Color(0.56, 0.56, 0.54),
	TrackSurfaceBand.Type.RIBBED: Color(0.28, 0.40, 0.48),
	TrackSurfaceBand.Type.GRATE: Color(0.14, 0.42, 0.40),
}
const PIN := Color(1.0, 0.45, 0.2)
const PIN_SEL := Color(1.0, 0.9, 0.3)
const WALL_LINE := Color(0.65, 0.68, 0.72)
const STRIP_H := 26.0
const MARGIN := 16.0

var profile: TrackSurfaceProfile
var style: UtopiaGreebleStyle
## Surface half widths (left, right) and wall-edge half widths at the camera.
var half := Vector2(19.5, 19.5)
var edge := Vector2(21.5, 21.5)
var greebles: TrackGreebles
var mirror_zone := false
var selected_band := -1    # index into profile.bands
var selected_rule := -1

var _bands: Array[Dictionary] = []    # {x0, x1, src, type}
var _pins: Array[Dictionary] = []     # {x, y, rule, ground, label}
var _drag_band := -1
var _drag_edge := 0.0
var _drag_sign := 1.0
var _drag_w0 := 0.0
var _drag_pin := -1


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	custom_minimum_size = Vector2(0, 150)


## Bands left to right, laid out as the shader's band_lookup does.
func _layout_bands() -> void:
	_bands.clear()
	if profile == null:
		return
	var all := profile.resolved()
	var src := []
	for i in profile.bands.size():
		if profile.bands[i]:
			src.append(i)
	if profile.mirror:
		for i in range(src.size() - 2, -1, -1):
			src.append(src[i])
	var fixed := 0.0
	var flex := 0.0
	for b in all:
		fixed += 0.0 if b.flex > 0.0 else b.width
		flex += b.flex
	var width := half.x + half.y
	var squeeze := width / fixed if width < fixed and fixed > 0.0 else 1.0
	var space := maxf(width - fixed, 0.0)
	var x := -half.x
	for i in all.size():
		var b := all[i]
		var w := (0.0 if b.flex > 0.0 else b.width) * squeeze + (b.flex / flex * space if flex > 0.0 else 0.0)
		_bands.append({x0 = x, x1 = x + w, src = src[i], type = b.type, flex = b.flex > 0.0, width = b.width})
		x += w


## Each enabled rule where TrackGreebles._rail() puts it at this width.
func _layout_pins() -> void:
	_pins.clear()
	if style == null or greebles == null:
		return
	var dl := edge.x - TrackGreebles.ROAD_EDGE
	var dr := edge.y - TrackGreebles.ROAD_EDGE
	for ri in style.rules.size():
		var rule := style.rules[ri]
		if rule == null or not rule.enabled or rule.mesh == null:
			continue
		var name := rule.mesh.resource_path.get_file().get_basename().trim_prefix("gb_")
		var off := rule.offset.y + rule.surface_offset
		for side in _sides(rule):
			var sgn := -1.0 if side == "L" else 1.0
			var grow := dl if side == "L" else dr
			var p := Vector2.ZERO
			match rule.layer:
				"ground":
					if side == "C":
						p.x = (edge.y - edge.x) * 0.5
					else:
						var flat := (edge.x if side == "L" else edge.y) - TrackGreebles.LIP
						p.x = sgn * rule.lateral * flat / (TrackGreebles.ROAD_EDGE - TrackGreebles.LIP)
				"wall_face":
					p = Vector2(sgn * (greebles.rail_face.x + grow), greebles.rail_face.y)
				"wall_top":
					p = Vector2(sgn * (greebles.rail_top.x + grow), greebles.rail_top.y)
				"outside":
					p = Vector2(sgn * (greebles.rail_outer.x + grow), greebles.rail_outer.y)
				"overhead":
					p = Vector2((dr - dl) * 0.5, greebles.rail_top.y + 3.0)
			_pins.append({x = p.x, y = p.y + off, rule = ri, ground = rule.layer == "ground" and side != "C",
					sgn = sgn, flat = (edge.x if side == "L" else edge.y) - TrackGreebles.LIP, label = name,
					layer = rule.layer})


func _sides(rule: UtopiaGreebleRule) -> Array:
	if rule.layer == "overhead":
		return ["C"]
	var s := rule.side
	if mirror_zone:
		s = {"left": "right", "right": "left"}.get(s, s)
	match s:
		"left":
			return ["L"]
		"right":
			return ["R"]
		"center":
			return ["C"] if rule.layer == "ground" else []
	return ["L", "R"]


func _scale() -> float:
	var outer := maxf(edge.x, edge.y)
	if greebles:
		outer += greebles.rail_outer.x - TrackGreebles.ROAD_EDGE + 1.0
	return (size.x - 2.0 * MARGIN) / (2.0 * outer)


func _x(m: float) -> float:
	return size.x * 0.5 + m * _scale()


func _road_y() -> float:
	return size.y - STRIP_H - 16.0


## Height has its own scale: the view is far wider than it is tall.
func _y(h: float) -> float:
	var top := 8.44
	if greebles:
		top = greebles.rail_top.y
	return _road_y() - h * minf(_scale(), (_road_y() - 20.0) / (top + 4.0))


func _draw() -> void:
	_layout_bands()
	_layout_pins()
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.07, 0.08, 0.09))
	var font := get_theme_default_font()
	var ry := _road_y()
	for side in [-1.0, 1.0]:
		_draw_wall(side)
	for i in _bands.size():
		var b: Dictionary = _bands[i]
		var r := Rect2(_x(b.x0), ry, _x(b.x1) - _x(b.x0), STRIP_H)
		draw_rect(r, BAND_COLORS.get(b.type, Color.GRAY))
		if b.src == selected_band:
			draw_rect(r, Color(1.0, 0.9, 0.3), false, 1.5)
		if r.size.x > 34.0:
			var name: String = TrackSurfaceBand.Type.keys()[b.type].to_lower()
			draw_string(font, Vector2(r.position.x + 3, ry + 17), name, HORIZONTAL_ALIGNMENT_LEFT,
					r.size.x - 4, 11, Color(1, 1, 1, 0.8))
	for p in _pins:
		var c := PIN_SEL if p.rule == selected_rule else PIN
		var x := _x(p.x)
		if p.layer == "ground":
			draw_line(Vector2(x, ry - 10), Vector2(x, ry + STRIP_H + 3), c, 1.5)
			draw_circle(Vector2(x, ry - 10), 3.5, c)
		else:
			draw_circle(Vector2(x, _y(p.y)), 3.5, c)
	# The selected rule's name, once, by its pin.
	for p in _pins:
		if p.rule == selected_rule:
			var at := Vector2(clampf(_x(p.x) + 6, 2.0, size.x - 110.0), (ry - 14) if p.layer == "ground" else _y(p.y) - 6)
			draw_string(font, at, str(p.label), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, PIN_SEL)
			break
	var cap := "half width %.1f / %.1f m" % [half.x, half.y]
	draw_string(font, Vector2(6, size.y - 3), cap, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1, 0.6))
	var who := "%s + %s" % [profile.profile_name if profile else "-", style.style_name if style else "bare"]
	draw_string(font, Vector2(6, 14), who, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.75))


## The wall's outline through the three rails.
func _draw_wall(side: float) -> void:
	if greebles == null:
		return
	var grow := (edge.x if side < 0.0 else edge.y) - TrackGreebles.ROAD_EDGE
	var flat := (half.x if side < 0.0 else half.y)
	var pts := PackedVector2Array([
		Vector2(_x(side * flat), _road_y()),
		Vector2(_x(side * (greebles.rail_face.x + grow)), _y(greebles.rail_face.y)),
		Vector2(_x(side * (greebles.rail_top.x + grow - 1.0)), _y(greebles.rail_top.y)),
		Vector2(_x(side * (greebles.rail_top.x + grow + 1.0)), _y(greebles.rail_top.y)),
		Vector2(_x(side * (greebles.rail_outer.x + grow)), _y(greebles.rail_outer.y)),
		Vector2(_x(side * (greebles.rail_outer.x + grow)), _road_y()),
	])
	draw_polyline(pts, WALL_LINE, 1.0, true)


func _gui_input(event: InputEvent) -> void:
	var b := event as InputEventMouseButton
	if b and b.button_index == MOUSE_BUTTON_LEFT:
		if b.pressed:
			_press(b.position)
		else:
			_drag_band = -1
			_drag_pin = -1
		accept_event()
	var m := event as InputEventMouseMotion
	if m:
		if _drag_band >= 0:
			var w := _drag_w0 + (m.position.x - _x(_drag_edge)) / _scale() * _drag_sign
			band_width_dragged.emit(_drag_band, maxf(snappedf(w, 0.05), 0.05))
		elif _drag_pin >= 0:
			var p: Dictionary = _pins[_drag_pin]
			var x := (m.position.x - size.x * 0.5) / _scale()
			var lateral: float = x * p.sgn * (TrackGreebles.ROAD_EDGE - TrackGreebles.LIP) / p.flat
			pin_dragged.emit(p.rule, snappedf(maxf(lateral, 0.0), 0.05))
		else:
			tooltip_text = _hover_text(m.position)


func _press(pos: Vector2) -> void:
	for i in _pins.size():
		var p: Dictionary = _pins[i]
		var at := Vector2(_x(p.x), (_road_y() - 10.0) if p.layer == "ground" else _y(p.y))
		if pos.distance_to(at) < 8.0:
			rule_selected.emit(p.rule)
			if p.ground:
				_drag_pin = i
			return
	if pos.y < _road_y() or pos.y > _road_y() + STRIP_H:
		return
	# A boundary between a fixed band and whatever's inside it: drag it.
	for i in _bands.size():
		var bd: Dictionary = _bands[i]
		for end in [0, 1]:
			var x: float = bd.x0 if end == 0 else bd.x1
			if absf(pos.x - _x(x)) < 4.0 and not bd.flex:
				var left_half: bool = (bd.x0 + bd.x1) * 0.5 < 0.0
				# The inner edge moves; the outer one is fixed by the bands outside.
				if (left_half and end == 1) or (not left_half and end == 0):
					_drag_band = bd.src
					_drag_edge = x
					_drag_w0 = bd.width
					_drag_sign = 1.0 if left_half else -1.0
					band_selected.emit(bd.src)
					return
	for bd: Dictionary in _bands:
		if pos.x >= _x(bd.x0) and pos.x < _x(bd.x1):
			band_selected.emit(bd.src)
			return


func _hover_text(pos: Vector2) -> String:
	for p: Dictionary in _pins:
		var at := Vector2(_x(p.x), (_road_y() - 10.0) if p.layer == "ground" else _y(p.y))
		if pos.distance_to(at) < 8.0:
			return "%s (%s), %.1f m from the centre" % [p.label, p.layer, absf(p.x)]
	for bd: Dictionary in _bands:
		if pos.x >= _x(bd.x0) and pos.x < _x(bd.x1) and pos.y >= _road_y():
			return "%s, %.2f m wide, from %.2f to %.2f m" % [TrackSurfaceBand.Type.keys()[bd.type].to_lower(),
					bd.x1 - bd.x0, bd.x0, bd.x1]
	return ""
