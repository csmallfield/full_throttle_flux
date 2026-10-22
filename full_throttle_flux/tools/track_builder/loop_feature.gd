@tool
extends TrackFeature
class_name LoopFeature
## A vertical loop (v34), the Loop Lab teardrop: a sin² pitch-curvature profile
## over `loop_length` of arc (top radius about loop_length / 4π: 820 m gives
## 65 m), stepping `shift` metres sideways so the exit clears the entry.
##
## Fitting the ends: an S-jog before the loop moves the road shift/2 one way,
## the loop steps the full shift the other way, and an S-jog after brings it
## back to the base centre line. So the loop's exit lands exactly on the curve
## you drew, and nothing after it moves. Footprint = 2 x jog_length.
##
## The keyed bank fades out over the first jog and back in over the last.
## Inversions need light from below (Builder Lab and Loop Lab have a GroundFill
## light).

enum LoopSide { RIGHT, LEFT }

@export_range(400.0, 1600.0, 10.0, "suffix:m") var loop_length: float = 820.0:
	set(v):
		loop_length = v
		_changed()
## Sideways step through the loop, so the exit passes beside the entry.
@export_range(60.0, 200.0, 1.0, "suffix:m") var shift: float = 90.0:
	set(v):
		shift = v
		_changed()
## Which way the loop steps (the exit ends up on this side of the entry).
@export var side: LoopSide = LoopSide.RIGHT:
	set(v):
		side = v
		_changed()
## Length of each S-jog (entry and exit). Shorter = sharper jogs.
@export_range(150.0, 800.0, 10.0, "suffix:m") var jog_length: float = 300.0:
	set(v):
		jog_length = v
		_changed()

@export_group("Magnetic zone")
@export_range(0.0, 1.0) var magnet_strength: float = 1.0:
	set(v):
		magnet_strength = v
		_changed()
@export var ramp: float = 60.0:
	set(v):
		ramp = v
		_changed()

const DS := 0.05


func kind() -> String:
	return "Loop"


func footprint() -> float:
	return 2.0 * jog_length + _loop_forward()


func shape() -> FeatureShape:
	var s := FeatureShape.new()
	var sg := 1.0 if side == LoopSide.RIGHT else -1.0
	var half := shift * 0.5 * sg
	# Entry jog: 0 -> -half. Bank fades out.
	_jog(s, 0.0, 0.0, -half, true)
	# The loop, from (jog_length, -half, 0), stepping +shift.
	s.mark("zone_from")
	var x0 := jog_length
	var px := x0
	var py := -half
	var ph := 0.0
	var phi := 0.0
	var kmax := 4.0 * PI / loop_length
	var n := int(round(loop_length / DS))
	var every := int(round(0.5 / DS))
	for i in n:
		if i % every == 0 and i > 0:
			s.add(px, py, ph, Vector3(0.0, cos(phi), -sin(phi)), 0.0)
		var sm := (i + 0.5) * DS
		phi += kmax * pow(sin(PI * sm / loop_length), 2.0) * DS
		var lat := shift * sg * (1.0 - cos(TAU * sm / loop_length)) / loop_length
		px += cos(phi) * DS
		ph += sin(phi) * DS
		py += lat * DS
	# Land exactly level at the loop exit (absorbs the integration error).
	ph = 0.0
	py = half
	s.mark("zone_to")
	s.add(px, py, ph, Vector3.UP, 0.0)
	# Exit jog: +half -> 0. Bank fades back in.
	_jog(s, px, half, 0.0, false)
	s.zone = {name = "Loop", from = "zone_from", to = "zone_to", ramp_in = ramp, ramp_out = ramp,
			magnet = magnet_strength}
	return s


## S-jog over jog_length metres forward, lateral y0 -> y1 (smootherstep, so
## curvature is zero at both ends). `entry`: bank weight 1 -> 0, else 0 -> 1.
func _jog(s: FeatureShape, x0: float, y0: float, y1: float, entry: bool) -> void:
	var n := int(ceil(jog_length))
	var first := 0 if entry else 1
	for i in range(first, n + 1):
		var t := float(i) / n
		var w := 1.0 - smoothstep01(t) if entry else smoothstep01(t)
		s.add(x0 + t * jog_length, lerpf(y0, y1, smootherstep01(t)), 0.0, Vector3.UP, w)


## Forward distance from loop entry to loop exit (about 0; the loop comes back
## over itself).
func _loop_forward() -> float:
	var phi := 0.0
	var px := 0.0
	var kmax := 4.0 * PI / loop_length
	var n := int(round(loop_length / DS))
	for i in n:
		var sm := (i + 0.5) * DS
		phi += kmax * pow(sin(PI * sm / loop_length), 2.0) * DS
		px += cos(phi) * DS
	return px
