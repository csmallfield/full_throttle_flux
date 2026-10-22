@tool
extends TrackFeature
class_name RollFeature
## A full barrel roll (v34): the road turns once (or more) about the direction
## of travel, smoothstep in and out. The centre line is the base curve's own;
## only the road's up changes, so a roll is pose-neutral and can sit on a
## gentle curve. Comes with its own magnetic zone.
##
## Length sets the peak roll rate: 1.5 x 360 / length degrees per metre.
## 800 m gives 0.68°/m, tested on Loop Lab. 460 m (1.2°/m) was tested and
## rejected: the road 15 m off centre pitched about 24° and threw ships into
## the wall. Under 772 m the validator warns (over 0.7°/m).

enum RollDirection { RIGHT, LEFT }

@export_range(300.0, 2000.0, 10.0, "suffix:m") var length: float = 800.0:
	set(v):
		length = v
		_changed()
@export var direction: RollDirection = RollDirection.RIGHT:
	set(v):
		direction = v
		_changed()
@export_range(1, 3) var turns: int = 1:
	set(v):
		turns = v
		_changed()

@export_group("Magnetic zone")
## 1 = forgiving (the ship can crawl round upside down), 0 = carry speed.
@export_range(0.0, 1.0) var magnet_strength: float = 1.0:
	set(v):
		magnet_strength = v
		_changed()
@export var ramp: float = 50.0:
	set(v):
		ramp = v
		_changed()


func kind() -> String:
	return "Roll"


func footprint() -> float:
	return length


func shape() -> FeatureShape:
	var s := FeatureShape.new()
	var sign := 1.0 if direction == RollDirection.RIGHT else -1.0
	var n := int(ceil(length))
	s.mark("zone_from")
	for i in n + 1:
		var t := float(i) / n
		var a := TAU * turns * sign * smoothstep01(t)
		if i == n:
			s.mark("zone_to")
		s.add(t * length, 0.0, 0.0, Vector3(sin(a), cos(a), 0.0), 1.0)
	s.up[s.size() - 1] = Vector3.UP   # exactly level at the end
	s.zone = {name = "Roll", from = "zone_from", to = "zone_to", ramp_in = ramp, ramp_out = ramp,
			magnet = magnet_strength}
	return s
