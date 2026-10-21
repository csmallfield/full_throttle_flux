@tool
extends Node3D
class_name ProfileKey
## Base for the Track Builder's distance-keyed profile keys (v34): BankKey and
## WidthKey.
##
## A key is placed in the world, not at a fixed distance. Its distance along
## the track is DERIVED by projecting it onto the (faired) base curve, so
## editing the curve upstream leaves the key where it is instead of sliding
## every key downstream. Drop it anywhere near the track: the node stays where
## you put it, and the builder draws its marker on the nearest track point,
## with a thin leader line back to the node.
##
## Where the track passes near itself, the key keeps to the stretch nearest
## the distance it had last time, so it can't jump onto a crossing section.

enum Ease {
	SMOOTH,    ## Smoothstep from this key to the next (default).
	LINEAR,    ## Straight-line change to the next key.
	HOLD,      ## Keep this value until the next key, then step.
	SMOOTHER,  ## Smootherstep: the gentlest roll-in and roll-out.
}

## How the value changes from this key to the next one along the track.
@export var ease: Ease = Ease.SMOOTH:
	set(v):
		ease = v
		_changed()

@export_group("Derived (read only)")
## Metres along the track, written by the builder. Also the hint that keeps
## the key on the right stretch where the track crosses itself.
@export var distance: float = -1.0
## How far the node sits from the track centre line (validator: over 30 m is
## an error).
@export var distance_to_track: float = 0.0


func _ready() -> void:
	set_notify_transform(true)


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED:
		_changed()


func _validate_property(property: Dictionary) -> void:
	if property.name == "distance":
		property.usage |= PROPERTY_USAGE_READ_ONLY
	elif property.name == "distance_to_track":
		property.usage = PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_READ_ONLY


## The builder this key belongs to (nearest TrackBuilder ancestor), or null.
func builder() -> Node:
	var n := get_parent()
	while n:
		if n is TrackBuilder:
			return n
		n = n.get_parent()
	return null


## Short text for the marker label in the preview.
func label_text() -> String:
	return ""


func _changed() -> void:
	if not Engine.is_editor_hint() or not is_inside_tree():
		return
	var b := builder()
	if b:
		b.mark_dirty()
