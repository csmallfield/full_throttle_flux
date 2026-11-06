extends Control
## Surface Lab: the rhythm along the track around the camera. Road panel seams
## of the selected band, wall panels, and each rule of the zone's style, on one
## metre scale, so you can see what lines up and what doesn't. Rule ticks show
## the pattern; probability thins them in the game, not here.

const WINDOW_M := 120.0
const LABEL_W := 92.0
const ROW_H := 13.0
const SEAM := Color(0.6, 0.75, 0.9)
const WALL := Color(0.75, 0.75, 0.6)
const RULE := Color(1.0, 0.5, 0.25)
const RULE_SEL := Color(1.0, 0.9, 0.3)

var d := 0.0
var lap := 1.0
var panel_len := 6.0
var wall_panel_len := 5.0
var seam_band := 0
var seed_value := 0.0
var zone: UtopiaGreebleZone
var selected_rule := -1


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	custom_minimum_size = Vector2(0, 150)


func _x(m: float) -> float:
	return LABEL_W + (m - (d - WINDOW_M * 0.5)) / WINDOW_M * (size.x - LABEL_W - 4.0)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.07, 0.08, 0.09))
	var font := get_theme_default_font()
	var y := 4.0
	var x0 := d - WINDOW_M * 0.5
	var x1 := d + WINDOW_M * 0.5
	var pl := lap / maxf(1.0, round(lap / maxf(panel_len, 0.01)))
	var phase := _env_hash(float(seam_band) * 1.37 + seed_value, 7.31) * pl
	_row_label(font, y, "road seams", SEAM)
	_ticks(y, x0, x1, pl, -phase, SEAM)
	y += ROW_H
	var wl := lap / maxf(1.0, round(lap / maxf(wall_panel_len, 0.01)))
	_row_label(font, y, "wall panels", WALL)
	_ticks(y, x0, x1, wl, 0.0, WALL)
	y += ROW_H
	if zone and zone.style:
		var st := zone.style
		var bay := maxf(st.bay_length, 1.0)
		for ri in st.rules.size():
			var r := st.rules[ri]
			if r == null or not r.enabled or r.mesh == null:
				continue
			if y + ROW_H > size.y - 12.0:
				break
			var c := RULE_SEL if ri == selected_rule else RULE
			_row_label(font, y, r.mesh.resource_path.get_file().get_basename().trim_prefix("gb_"), c)
			_rule_ticks(y, x0, x1, r, bay, c)
			y += ROW_H
	var mid := _x(d)
	draw_line(Vector2(mid, 0), Vector2(mid, size.y), Color(1, 1, 1, 0.35), 1.0)
	draw_string(font, Vector2(LABEL_W, size.y - 2), "%d m window, camera at %d m" % [WINDOW_M, d],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1, 0.6))


func _row_label(font: Font, y: float, text: String, c: Color) -> void:
	draw_string(font, Vector2(3, y + 10), text, HORIZONTAL_ALIGNMENT_LEFT, LABEL_W - 5, 11, c)


func _ticks(y: float, x0: float, x1: float, pitch: float, phase: float, c: Color) -> void:
	if pitch <= 0.0:
		return
	var k := ceilf((x0 - phase) / pitch)
	while phase + k * pitch < x1:
		var x := _x(phase + k * pitch)
		draw_line(Vector2(x, y + 1), Vector2(x, y + ROW_H - 2), c, 1.0)
		k += 1.0


## Where TrackGreebles.placements() puts this rule's slots. A zone's slots run
## on from its start; only slots near the window are drawn.
func _rule_ticks(y: float, x0: float, x1: float, r: UtopiaGreebleRule, bay: float, c: Color) -> void:
	var slots := maxi(r.slots_per_bay, 1)
	var slot_len := bay / float(slots)
	var span := zone.to_d - zone.from_d
	if span <= 0.0:
		span += lap
	var n := int(span / slot_len)
	var from := zone.from_d
	# The window may sit a lap away from the zone's numbers.
	if d < from and from + span > lap:
		from -= lap
	var s0 := maxi(int(floor((x0 - from) / slot_len)) - 1, 0)
	var s1 := mini(int(ceil((x1 - from) / slot_len)) + 1, n)
	for s in range(s0, s1):
		if r.pattern.length() > 0 and r.pattern[s % r.pattern.length()] != "x":
			continue
		var at := from + (float(s) + r.slot_phase) * slot_len
		if at >= x0 and at <= x1:
			var x := _x(at)
			draw_line(Vector2(x, y + 1), Vector2(x, y + ROW_H - 2), c, 1.5)


## The shader's env_hash in 32-bit floats, so the seams land where they draw.
static func _env_hash(a: float, b: float) -> float:
	var f := PackedFloat32Array([0.0])
	var r := func(x: float) -> float:
		f[0] = x
		return f[0]
	var px: float = r.call(_fract(r.call(a * 123.34)))
	var py: float = r.call(_fract(r.call(b * 456.21)))
	var dot: float = r.call(r.call(px * r.call(px + 45.32)) + r.call(py * r.call(py + 45.32)))
	px = r.call(px + dot)
	py = r.call(py + dot)
	return _fract(r.call(px * py))


static func _fract(x: float) -> float:
	return x - floorf(x)
