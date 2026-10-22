@tool
extends ProfileKey
class_name TrackFeature
## Base for the Track Builder's features (v34): RollFeature, LoopFeature,
## JumpFeature. Placed like a key: drop it where you want the feature, and its
## FOOTPRINT (a stretch of the base curve, centred on the node's projection)
## is replaced by the feature's own shape.
##
## The builder fits the ends: the shape is defined in a canonical frame (a
## straight, level road heading forward) and mapped onto the base curve along
## the footprint, like a path deformer: forward = distance along the base,
## lateral and height = offsets in the base's level frame there. The shape
## starts and ends on the centre line with zero offset, slope and curvature, so
## it joins the drawn curve exactly at both ends, whatever the base does in
## between. A gently curving or climbing footprint bends the feature with it;
## the validator warns when it bends too much.
##
## Bank keys keep applying inside a footprint, weighted by the feature (a roll
## adds its turn on top of the keyed bank; a loop or jump fades the keyed bank
## out and back in).

## Off = the base curve as drawn, as if the feature weren't there.
@export var enabled: bool = true:
	set(v):
		enabled = v
		_changed()


## Footprint length along the base, metres. Overridden.
func footprint() -> float:
	return 0.0


## The canonical shape. Overridden.
func shape() -> FeatureShape:
	return FeatureShape.new()


## Short name for labels and messages.
func kind() -> String:
	return "Feature"


func label_text() -> String:
	return kind().to_upper()


## Base distances [d0, d1] of the footprint (d1 may exceed the base length on
## a closed curve; the composer wraps).
func span() -> Vector2:
	var f := footprint()
	return Vector2(distance - f * 0.5, distance + f * 0.5)


# Shared helpers -------------------------------------------------------------

static func smoothstep01(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)


static func smootherstep01(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return x * x * x * (x * (x * 6.0 - 15.0) + 10.0)
