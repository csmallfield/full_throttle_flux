@tool
extends Resource
class_name TrackSurfaceGlyphs
## The track surface's decal glyphs (v38 phase 5): one MSDF atlas of the four
## decal fonts and each glyph's metrics, made by
## tools/track_surface/make_decal_atlas.gd (rerun it after changing CHARSETS
## there). TrackSurface lays decal text out from these, and the shader decodes
## the atlas (median of RGB, px_range pixels of distance at em_px).
##
## Keys are "role:codepoint" (role = TrackSurfaceDecal.Role). Pixel values are
## at em_px: rect in the atlas (x, y, w, h), offset of the rect's top left
## from the pen on the baseline (y down), advance, and ink (the share of the
## rect that's inside the glyph: what a glyph fades to far away).

## The atlas image (by path: the tool writes it and these metrics in one go).
@export var atlas_path := ""
@export var atlas_size := Vector2i.ZERO
@export var em_px := 64
@export var px_range := 8.0
@export var rects := {}
@export var offsets := {}
@export var advances := {}
@export var inks := {}
## Per role: the font's ascent at em_px (cap tops sit about here).
@export var ascents := PackedFloat32Array()


static func key(role: int, ch: int) -> String:
	return "%d:%d" % [role, ch]


func has_glyph(role: int, ch: int) -> bool:
	return rects.has(key(role, ch))


func atlas() -> Texture2D:
	return load(atlas_path) as Texture2D if ResourceLoader.exists(atlas_path) else null
