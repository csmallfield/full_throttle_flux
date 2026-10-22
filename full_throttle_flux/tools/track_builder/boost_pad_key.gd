@tool
extends ProfileKey
class_name BoostPadKey
## Boost pads at one point of the track (v34). Drop the node anywhere near the
## road: the pads sit on the road surface at the nearest track point, facing
## the direction of travel, banked, rolled or upside down with the road. Build
## places the game's BoostPad scene (scenes/boost_pad.tscn) there.
##
## Sideways: `anchor` picks what `offset` is measured from (the centre line,
## or the left / right edge of the flat road), so a pad anchored to an edge
## stays against that edge where WidthKeys change the width. `count` pads sit
## side by side, `spacing` apart, centre to centre.
##
## Under a BranchFeature the pads go on that branch's road.
##
## The validator checks the pads are on the road, don't overlap, aren't over
## a jump's gap or on the grid, and what the boost does to the next corner,
## crest or jump (a pad adds `strength` u/s on top of the ship's speed, and
## the extra fades in about a second).

enum Anchor {
	CENTRE,  ## `offset` from the centre line.
	LEFT,    ## The row against the left edge; + offset moves it in.
	RIGHT,   ## The row against the right edge; - offset moves it in.
}

## The pad scene's footprint (scenes/boost_pad.tscn: 8 m wide, 12 m long,
## chevrons pointing down its +Z).
const PAD_HALF_WIDTH := 4.0
const PAD_HALF_LENGTH := 6.0
## The flat road ends this far inside the edge (then the 2 m lip rises to the
## wall), and an edge-anchored row keeps this gap from where it ends.
const LIP := 2.0
const EDGE_GAP := 1.0

@export var anchor: Anchor = Anchor.CENTRE:
	set(v):
		anchor = v
		_changed()
## Metres sideways, + = right. From the centre line, or in from the anchored
## edge.
@export_range(-30.0, 30.0, 0.5, "suffix:m") var offset: float = 0.0:
	set(v):
		offset = v
		_changed()
## Pads side by side.
@export_range(1, 5) var count: int = 1:
	set(v):
		count = v
		_changed()
## Centre to centre, across the road (a pad is 8 m wide).
@export_range(8.0, 30.0, 0.5, "suffix:m") var spacing: float = 10.0:
	set(v):
		spacing = v
		_changed()
## Speed added on top of the ship's (u/s; default_racer tops out at 120).
## The extra fades back to normal in about a second.
@export_range(20.0, 300.0, 5.0, "suffix:u/s") var strength: float = 150.0:
	set(v):
		strength = v
		_changed()


func _validate_property(property: Dictionary) -> void:
	super(property)
	if property.name == "ease":
		property.usage = PROPERTY_USAGE_NO_EDITOR    # pads don't blend between keys


## Lateral offsets (+ = right) of each pad's centre, for a road with these
## half widths (centre line to the lip's outer edge) where the pads sit.
func pad_offsets(half_left: float, half_right: float) -> PackedFloat32Array:
	var half_row := (count - 1) * spacing * 0.5
	var c := offset
	match anchor:
		Anchor.LEFT:
			c = -(half_left - LIP) + EDGE_GAP + PAD_HALF_WIDTH + half_row + offset
		Anchor.RIGHT:
			c = (half_right - LIP) - EDGE_GAP - PAD_HALF_WIDTH - half_row + offset
	var out := PackedFloat32Array()
	for i in count:
		out.append(c - half_row + i * spacing)
	return out


func label_text() -> String:
	var where: String = ["centre", "left", "right"][anchor]
	if not is_zero_approx(offset):
		where += " %+.1f" % offset
	return "BOOST %s%s +%.0f" % ["%d× " % count if count > 1 else "", where, strength]
