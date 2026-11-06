extends Control
## Sky Lab: how the frame's brightness is spread, after tonemapping, as the
## player sees it. Bars are a histogram of luma; the marks underneath give the
## average, and how much of the frame is crushed to black or clipped to white.
##
## Reading the frame back from the GPU stalls it for a moment, so this samples
## at most twice a second, and only the 3D area the panels don't cover.

const BINS := 48
const SAMPLE := Vector2i(192, 108)

var hist := PackedFloat32Array()
var mean := 0.0
var crushed := 0.0
var clipped := 0.0
var sky_mean := 0.0
var enabled := true


func _init() -> void:
	custom_minimum_size = Vector2(260, 150)
	hist.resize(BINS)
	tooltip_text = "Brightness of the 3D view after tonemapping.\nCrushed: under 2%. Clipped: over 98%."


## Measures `img` (the part of the frame to judge). `sky_rows` = how many rows
## at the top to report separately as the sky's average.
func measure(img: Image, sky_rows := 0.25) -> void:
	if img == null or img.is_empty():
		return
	img.resize(SAMPLE.x, SAMPLE.y, Image.INTERPOLATE_BILINEAR)
	hist.fill(0.0)
	var n := 0
	var sum := 0.0
	var low := 0
	var high := 0
	var sky_sum := 0.0
	var sky_n := 0
	var sky_y := int(SAMPLE.y * sky_rows)
	for y in SAMPLE.y:
		for x in SAMPLE.x:
			var c := img.get_pixel(x, y)
			var l := clampf(c.r * 0.2126 + c.g * 0.7152 + c.b * 0.0722, 0.0, 1.0)
			hist[mini(int(l * BINS), BINS - 1)] += 1.0
			sum += l
			n += 1
			low += int(l < 0.02)
			high += int(l > 0.98)
			if y < sky_y:
				sky_sum += l
				sky_n += 1
	mean = sum / maxf(n, 1)
	crushed = float(low) / maxf(n, 1)
	clipped = float(high) / maxf(n, 1)
	sky_mean = sky_sum / maxf(sky_n, 1)
	var top := 0.0
	for v in hist:
		top = maxf(top, v)
	for i in BINS:
		hist[i] = hist[i] / maxf(top, 1.0)
	queue_redraw()


func _draw() -> void:
	var font := get_theme_default_font()
	var area := Rect2(4, 18, size.x - 8, size.y - 44)
	draw_rect(area, Color(0, 0, 0, 0.35))
	draw_string(font, Vector2(4, 13), "Exposure" if enabled else "Exposure (off)",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.8))
	if not enabled:
		return
	var w := area.size.x / BINS
	for i in BINS:
		var h := hist[i] * area.size.y
		var g := (i + 0.5) / BINS
		draw_rect(Rect2(area.position.x + i * w, area.end.y - h, maxf(w - 1.0, 1.0), h), Color(g, g, g).lerp(Color(0.5, 0.75, 1.0), 0.25))
	var mx := area.position.x + mean * area.size.x
	draw_line(Vector2(mx, area.position.y), Vector2(mx, area.end.y), Color(1.0, 0.75, 0.3), 2.0)
	var warn := Color(1.0, 0.55, 0.4)
	var ok := Color(0.75, 0.85, 0.9)
	draw_string(font, Vector2(4, size.y - 17), "average %.0f%%   sky %.0f%%" % [mean * 100.0, sky_mean * 100.0],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, ok)
	draw_string(font, Vector2(4, size.y - 3), "crushed %.1f%%   clipped %.1f%%" % [crushed * 100.0, clipped * 100.0],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, warn if crushed > 0.05 or clipped > 0.05 else ok)
