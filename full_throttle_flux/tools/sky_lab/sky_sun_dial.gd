extends Control
## Sky Lab: the sun on a compass, seen from above. The centre is straight up,
## the rim is the horizon (the dashed ring just outside it is 5 degrees below).
## North (-Z) is at the top, east (+X) to the right, as sun_azimuth counts.
## Drag the sun to move it. The wedge is where the camera is looking.

signal sun_dragged(azimuth: float, elevation: float)

const BELOW := 5.0     # degrees below the horizon the dial reaches

var azimuth := 215.0
var elevation := 23.0
var sun_color := Color(1.0, 0.85, 0.6)
## Compass heading the camera faces, in degrees, or NAN to hide it.
var heading := NAN
var _dragging := false


func _init() -> void:
	custom_minimum_size = Vector2(200, 180)
	mouse_filter = Control.MOUSE_FILTER_STOP
	tooltip_text = "Drag the sun. Centre = straight up, rim = horizon."


func show_sun(az: float, el: float, col: Color, cam_heading: float) -> void:
	if is_equal_approx(az, azimuth) and is_equal_approx(el, elevation) and col == sun_color \
			and (is_nan(cam_heading) == is_nan(heading)) and (is_nan(heading) or absf(cam_heading - heading) < 0.5):
		return
	azimuth = az
	elevation = el
	sun_color = col
	heading = cam_heading
	queue_redraw()


func _radius() -> float:
	return minf(size.x, size.y - 20.0) * 0.5 - 12.0


func _centre() -> Vector2:
	return Vector2(size.x * 0.5, 10.0 + (size.y - 20.0) * 0.5)


func _to_point(az: float, el: float) -> Vector2:
	var r := _radius() * (90.0 - el) / 90.0
	var a := deg_to_rad(az)
	return _centre() + Vector2(sin(a), -cos(a)) * r


func _from_point(p: Vector2) -> Vector2:
	var v := p - _centre()
	var az := fposmod(rad_to_deg(atan2(v.x, -v.y)), 360.0)
	var el := 90.0 - v.length() / _radius() * 90.0
	return Vector2(az, clampf(el, -BELOW, 89.0))


func _draw() -> void:
	var c := _centre()
	var r := _radius()
	var font := get_theme_default_font()
	draw_circle(c, r, Color(0.16, 0.2, 0.28))
	for el: float in [30.0, 60.0]:
		draw_arc(c, r * (90.0 - el) / 90.0, 0.0, TAU, 64, Color(1, 1, 1, 0.12), 1.0)
	draw_arc(c, r, 0.0, TAU, 96, Color(1, 1, 1, 0.45), 1.5)
	var below := r * (90.0 + BELOW) / 90.0
	draw_arc(c, below, 0.0, TAU, 48, Color(1, 1, 1, 0.15), 1.0)
	for i in 4:
		var a := deg_to_rad(i * 90.0)
		var d := Vector2(sin(a), -cos(a))
		draw_line(c + d * r * 0.92, c + d * r, Color(1, 1, 1, 0.5), 1.0)
		draw_string(font, c + d * (below + 8.0) + Vector2(-4, 5), ["N", "E", "S", "W"][i],
				HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.7))
	if not is_nan(heading):
		var h := deg_to_rad(heading)
		var pts := PackedVector2Array([c])
		for k in 9:
			var a := h + deg_to_rad(-35.0 + k * 70.0 / 8.0)
			pts.append(c + Vector2(sin(a), -cos(a)) * r)
		draw_colored_polygon(pts, Color(0.55, 0.85, 1.0, 0.16))
	var sp := _to_point(azimuth, elevation)
	draw_line(c, sp, Color(sun_color, 0.4), 1.0)
	draw_circle(sp, 8.0, sun_color)
	draw_arc(sp, 10.0, 0.0, TAU, 24, Color(0, 0, 0, 0.6), 1.5)
	draw_string(font, Vector2(4, size.y - 4), "az %.0f°  el %.1f°" % [azimuth, elevation],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.85))


func _gui_input(event: InputEvent) -> void:
	var b := event as InputEventMouseButton
	if b and b.button_index == MOUSE_BUTTON_LEFT:
		_dragging = b.pressed and b.position.distance_to(_to_point(azimuth, elevation)) < 24.0 \
				or (b.pressed and b.position.distance_to(_centre()) <= _radius() * (90.0 + BELOW) / 90.0)
		if _dragging:
			_drag_to(b.position)
		accept_event()
	var m := event as InputEventMouseMotion
	if m and _dragging:
		_drag_to(m.position)
		accept_event()


func _drag_to(p: Vector2) -> void:
	var v := _from_point(p)
	azimuth = snappedf(v.x, 0.5)
	elevation = snappedf(v.y, 0.5)
	queue_redraw()
	sun_dragged.emit(azimuth, elevation)
