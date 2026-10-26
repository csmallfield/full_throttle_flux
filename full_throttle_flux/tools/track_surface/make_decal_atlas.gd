extends SceneTree
## v38 phase 5: builds the track surface's decal glyph atlas from the four
## decal fonts in res://fonts (one MSDF atlas, Godot's own MSDF renderer) and
## the glyph metrics (TrackSurfaceGlyphs).
##
##   godot --headless --path . -s res://tools/track_surface/make_decal_atlas.gd
##
## Writes ATLAS (RGB = the multichannel distance field, A = true distance)
## and GLYPHS. Only the characters in CHARSETS go in: rerun after changing
## them. The fonts are never modified (SIL OFL: see CREDITS.md).

const ATLAS := "res://resources/track_surface/decal_atlas.png"
const GLYPHS := "res://resources/track_surface/decal_glyphs.tres"
const EM := 64
const PX_RANGE := 8
const ATLAS_W := 2048
const PAD := 2

## Per TrackSurfaceDecal.Role: the font, and the characters it needs.
const FONTS := [
	"res://fonts/bbh_bartle/BBHBartle-Regular.ttf",
	"res://fonts/alien_block/AlienBlock-Regular.ttf",
	"res://fonts/audiowide/Audiowide-Regular.ttf",
	"res://fonts/libre_barcode_39_extended_text/LibreBarcode39ExtendedText-Regular.ttf",
]
const UPPER := "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
const LOWER := "abcdefghijklmnopqrstuvwxyz"
const DIGITS := "0123456789"
const CHARSETS := [
	UPPER + DIGITS + "!-.'/:",
	UPPER + LOWER + DIGITS + "!-.",
	UPPER + DIGITS + "-./:",
	UPPER + DIGITS + "-.*",
]


func _initialize() -> void:
	var g := TrackSurfaceGlyphs.new()
	g.em_px = EM
	g.px_range = PX_RANGE
	var ascents := PackedFloat32Array()
	# Render every glyph and collect its image.
	var items: Array = []    # {key, img, offset, advance}
	for role in FONTS.size():
		var f := (load(FONTS[role]) as FontFile).duplicate(true) as FontFile
		f.multichannel_signed_distance_field = true
		f.msdf_pixel_range = PX_RANGE
		f.msdf_size = EM
		var size := Vector2i(EM, 0)
		ascents.append(f.get_ascent(EM))
		var cs: String = CHARSETS[role]
		for i in cs.length():
			var c := cs.unicode_at(i)
			var gi := f.get_glyph_index(EM, c, 0)
			if gi == 0:
				print("DECALATLAS role %d: no glyph for '%s'" % [role, cs[i]])
				continue
			f.render_glyph(0, size, gi)
			var r := f.get_glyph_uv_rect(0, size, gi)
			var ti := f.get_glyph_texture_idx(0, size, gi)
			var src := f.get_texture_image(0, size, ti)
			if src.get_format() != Image.FORMAT_RGBA8:
				src.convert(Image.FORMAT_RGBA8)
			var sub := src.get_region(Rect2i(r.position, r.size))
			items.append({key = TrackSurfaceGlyphs.key(role, c), img = sub,
					offset = f.get_glyph_offset(0, size, gi), advance = f.get_glyph_advance(0, EM, gi).x})
	g.ascents = ascents
	# Shelf-pack, tallest first.
	items.sort_custom(func(a, b) -> bool: return (a.img as Image).get_height() > (b.img as Image).get_height())
	var x := PAD
	var y := PAD
	var shelf := 0
	var places: Array = []
	for it in items:
		var im: Image = it.img
		if x + im.get_width() + PAD > ATLAS_W:
			x = PAD
			y += shelf + PAD
			shelf = 0
		places.append(Vector2i(x, y))
		x += im.get_width() + PAD
		shelf = maxi(shelf, im.get_height())
	var h := nearest_po2(y + shelf + PAD)
	var atlas := Image.create(ATLAS_W, h, false, Image.FORMAT_RGBA8)
	atlas.fill(Color(0, 0, 0, 0))
	for i in items.size():
		var it: Dictionary = items[i]
		var im: Image = it.img
		var at: Vector2i = places[i]
		atlas.blit_rect(im, Rect2i(Vector2i.ZERO, im.get_size()), at)
		g.rects[it.key] = Vector4(at.x, at.y, im.get_width(), im.get_height())
		g.offsets[it.key] = it.offset
		g.advances[it.key] = it.advance
		g.inks[it.key] = _ink(im)
	DirAccess.make_dir_recursive_absolute(ATLAS.get_base_dir())
	var err := atlas.save_png(ATLAS)
	g.atlas_path = ATLAS
	g.atlas_size = Vector2i(ATLAS_W, h)
	var err2 := ResourceSaver.save(g, GLYPHS)
	print("DECALATLAS %s %dx%d, %d glyphs (%s); %s (%s)" % [ATLAS, ATLAS_W, h, items.size(),
			error_string(err), GLYPHS, error_string(err2)])
	quit(0 if err == OK and err2 == OK else 1)


## Share of the glyph's rect inside the outline (median of RGB over 0.5).
static func _ink(im: Image) -> float:
	var n := 0
	for yy in im.get_height():
		for xx in im.get_width():
			var c := im.get_pixel(xx, yy)
			var md := maxf(minf(c.r, c.g), minf(maxf(c.r, c.g), c.b))
			if md > 0.5:
				n += 1
	return float(n) / maxf(im.get_width() * im.get_height(), 1)
