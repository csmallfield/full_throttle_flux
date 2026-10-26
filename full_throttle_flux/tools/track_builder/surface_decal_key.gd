@tool
extends ProfileKey
class_name SurfaceDecalKey
## A road decal (v38 phase 5): a word, stencil, label or barcode serial in
## one of the four decal fonts, or a chevron / arrow, painted flat on the road
## at the nearest track point. Drop it anywhere near the BUILT road; under a
## BranchFeature it goes on that branch. `count` copies sit `spacing` metres
## apart along the track (chevron rows, serials).
##
## Text reads for a ship coming along the track: letters left to right
## across the road, their tops pointing the way it's going. `flipped` turns
## it round for ships coming the other way.
##
## Fonts have jobs (docs/TRACK_AUTHORING.md §3.7, Typography): WORD (BBH
## Bartle, caps) for big road words, STENCIL (Alien Block) for short hazard
## stencils, LABEL (Audiowide) for numbers, SERIAL (Libre Barcode) for panel
## serials. A "#" in the text counts up with each copy (LANE #: LANE 1, 2...).
##
## Like the other surface keys, decals never change the drivable track.

const Role := TrackSurfaceDecal.Role
const Shape := TrackSurfaceDecal.Shape
const Anchor := TrackSurfaceDecal.Anchor
const Paint := TrackSurfaceDecal.Paint

@export var shape: TrackSurfaceDecal.Shape = TrackSurfaceDecal.Shape.TEXT:
	set(v):
		shape = v
		notify_property_list_changed()
		_changed()
@export var role: TrackSurfaceDecal.Role = TrackSurfaceDecal.Role.WORD:
	set(v):
		role = v
		_changed()
@export var text: String = "":
	set(v):
		text = v
		_changed()
## Text: letter height in metres. Shapes: length along the track.
@export_range(0.2, 30.0, 0.1, "suffix:m") var size: float = 4.0:
	set(v):
		size = v
		_changed()
## Shapes: width across the road.
@export_range(0.2, 30.0, 0.1, "suffix:m") var width: float = 4.0:
	set(v):
		width = v
		_changed()
## What `offset` is measured from: the centre line, or in from the left /
## right edge of the driving surface (so it stays put where WidthKeys change
## the width).
@export var anchor: TrackSurfaceDecal.Anchor = TrackSurfaceDecal.Anchor.CENTRE:
	set(v):
		anchor = v
		_changed()
## Metres sideways, + = right. Centre: of the decal's centre; Left / Right:
## of its near edge, in from that road edge.
@export_range(-30.0, 30.0, 0.1, "suffix:m") var offset: float = 0.0:
	set(v):
		offset = v
		_changed()
## Paint (no orange: that's the boost pads' colour).
@export var paint: TrackSurfaceDecal.Paint = TrackSurfaceDecal.Paint.WHITE:
	set(v):
		paint = v
		_changed()
## 0 = plain paint, 1 = lit (glows like the guide lights).
@export_range(0.0, 1.0, 0.05) var glow: float = 0.0:
	set(v):
		glow = v
		_changed()
@export_range(0.05, 1.0, 0.05) var opacity: float = 0.9:
	set(v):
		opacity = v
		_changed()
@export_range(1, 200) var count: int = 1:
	set(v):
		count = v
		_changed()
@export_range(0.5, 500.0, 0.5, "suffix:m") var spacing: float = 10.0:
	set(v):
		spacing = v
		_changed()
@export var flipped: bool = false:
	set(v):
		flipped = v
		_changed()


func _validate_property(property: Dictionary) -> void:
	super(property)
	if property.name == "ease":
		property.usage = PROPERTY_USAGE_NO_EDITOR
	elif property.name in ["role", "text", "flipped"] and shape != TrackSurfaceDecal.Shape.TEXT:
		property.usage = PROPERTY_USAGE_NO_EDITOR
	elif property.name == "width" and shape == TrackSurfaceDecal.Shape.TEXT:
		property.usage = PROPERTY_USAGE_NO_EDITOR


func label_text() -> String:
	var what: String = ('"%s"' % text) if shape == TrackSurfaceDecal.Shape.TEXT \
			else TrackSurfaceDecal.Shape.keys()[shape].to_lower()
	return "DECAL %s%s" % [what, " ×%d" % count if count > 1 else ""]


func _changed() -> void:
	if not Engine.is_editor_hint() or not is_inside_tree():
		return
	var b := builder()
	if b and b.has_method("mark_surface_dirty"):
		b.mark_surface_dirty()
