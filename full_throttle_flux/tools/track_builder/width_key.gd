@tool
extends ProfileKey
class_name WidthKey
## Road width at one point of the track (v34). Half widths are measured from
## the centre line to the outer edge of the lip (the circuits' standard is
## 21.5 m: 19.5 m of road plus a 2 m lip). The walls move with the edge; they
## keep their shape.
##
## Linked (default) keeps both sides equal. Unlink to widen or narrow one side
## only, e.g. the outside of a corner, without moving the centre line.

const STANDARD := 21.5

@export var linked: bool = true:
	set(v):
		linked = v
		if linked:
			half_width_right = half_width_left
		_changed()

@export_range(6.0, 45.0, 0.1, "suffix:m") var half_width_left: float = STANDARD:
	set(v):
		half_width_left = v
		if linked and not is_equal_approx(half_width_right, v):
			half_width_right = v
		_changed()

@export_range(6.0, 45.0, 0.1, "suffix:m") var half_width_right: float = STANDARD:
	set(v):
		half_width_right = v
		if linked and not is_equal_approx(half_width_left, v):
			half_width_left = v
		_changed()


func label_text() -> String:
	if linked:
		return "W %.1f" % half_width_left
	return "W %.1f | %.1f" % [half_width_left, half_width_right]
