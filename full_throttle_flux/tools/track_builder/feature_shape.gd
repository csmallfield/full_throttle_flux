extends RefCounted
class_name FeatureShape
## A feature's shape in its canonical frame (v34): the road as it would be on
## a straight, level base heading forward. Samples are in order of travel.
##
##   x       metres forward along the base (may go backwards: a loop)
##   y       metres to the right of the base centre line
##   h       metres above it
##   up      road up in the canonical frame: (right, up, forward)
##   bank_w  how much of the keyed bank applies here (0..1)
##   road    1 = road, 0 = gap (a jump's flight)
##   marks   name -> sample index (zone and jump extents)
##
## First sample: x = y = h = 0, up = (0, 1, 0). Last sample: x = footprint,
## y = h = 0, up = (0, 1, 0) (a full roll's up comes back to the same vector).

var x := PackedFloat32Array()
var y := PackedFloat32Array()
var h := PackedFloat32Array()
var up := PackedVector3Array()
var bank_w := PackedFloat32Array()
var road := PackedByteArray()
var marks := {}
## Magnetic zone over [marks[zone_from], marks[zone_to]], or empty.
var zone := {}


func add(px: float, py: float, ph: float, u: Vector3, w: float, is_road: bool = true) -> void:
	x.append(px)
	y.append(py)
	h.append(ph)
	up.append(u.normalized())
	bank_w.append(w)
	road.append(1 if is_road else 0)


func mark(n: String) -> void:
	marks[n] = x.size()


func size() -> int:
	return x.size()


func end_x() -> float:
	return x[x.size() - 1] if x.size() > 0 else 0.0
