extends Control
## Surface Lab: the lap as a bar with both layers' zones on one axis, and the
## camera on it. Click anywhere to send the camera there. Read-only in phase 1.

signal jump_requested(d: float)

const LABEL_W := 70.0
const LANE_H := 20.0

var lap := 1.0
var d := 0.0
var surface_zones: Array[TrackSurfaceZone] = []
var greeble_zones: Array = []    # TrackGreebleZone on the main path


func _ready() -> void:
	custom_minimum_size = Vector2(0, 2.0 * LANE_H + 12.0)
	mouse_filter = Control.MOUSE_FILTER_STOP


func _x(m: float) -> float:
	return LABEL_W + m / lap * (size.x - LABEL_W - 4.0)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.07, 0.08, 0.09))
	var font := get_theme_default_font()
	draw_string(font, Vector2(4, 17), "road", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.7))
	draw_string(font, Vector2(4, 17 + LANE_H + 2), "greebles", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.7))
	var i := 0
	for z in surface_zones:
		var name := z.profile.profile_name if z.profile else "?"
		_span(font, 3.0, z.from_d, z.to_d, name, Color(0.25, 0.32, 0.42) if i % 2 == 0 else Color(0.31, 0.38, 0.48))
		if z.blend_in > 0.0:
			draw_rect(Rect2(_x(z.from_d), 3.0, _x(z.blend_in) - _x(0.0), LANE_H), Color(1, 1, 1, 0.12))
		i += 1
	i = 0
	for z in greeble_zones:
		var name: String = z.style.style_name if z.style else "bare"
		_span(font, 5.0 + LANE_H, z.from_d, z.to_d, name, Color(0.16, 0.36, 0.30) if i % 2 == 0 else Color(0.2, 0.43, 0.36))
		i += 1
	var x := _x(d)
	draw_line(Vector2(x, 0), Vector2(x, size.y), Color(1.0, 0.45, 0.2), 2.0)


## Draws a zone, wrapped into two rectangles if it crosses the start line.
func _span(font: Font, y: float, from: float, to: float, text: String, c: Color) -> void:
	if to <= from:
		to += lap
	var parts := [[from, minf(to, lap)]]
	if to > lap:
		parts.append([0.0, to - lap])
	for p: Array in parts:
		var x0 := _x(p[0])
		var x1 := _x(p[1])
		draw_rect(Rect2(x0, y, x1 - x0 - 1.0, LANE_H), c)
		if x1 - x0 > 30.0:
			draw_string(font, Vector2(x0 + 3, y + 14), text, HORIZONTAL_ALIGNMENT_LEFT, x1 - x0 - 5.0, 11,
					Color(1, 1, 1, 0.85))


func _gui_input(event: InputEvent) -> void:
	var b := event as InputEventMouseButton
	if b and b.pressed and b.button_index == MOUSE_BUTTON_LEFT:
		jump_requested.emit(clampf((b.position.x - LABEL_W) / (size.x - LABEL_W - 4.0), 0.0, 1.0) * lap)
		accept_event()
