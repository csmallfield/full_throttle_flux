@tool
extends TrackFeature
class_name JumpFeature
## A jump (v34), as on Fork Lab: a climb, a run-up, a kicker, a real GAP in
## the road (no collision under it), a landing ramp and an outrun. The climb
## first makes the whole jump height-neutral, so the road after it is where
## you drew it. The defaults are Fork Lab's shared jump (55 m gap, 6° kicker,
## 4 m drop), measured to land cleanly from 66 u/s.
##
## clean_speed is the slowest approach that lands cleanly. Measure it with
## the real ship (tools/track_builder/measure_jumps_boot.gd, which flies
## default_racer off this exact shape) and the AI uses it to judge the jump.
## The validator warns while it's unmeasured or stale.

@export_group("Shape")
@export_range(0.0, 15.0, 0.5, "suffix:°") var kicker_deg: float = 6.0:
	set(v):
		kicker_deg = v
		_changed()
@export_range(30.0, 200.0, 1.0, "suffix:m") var kicker_length: float = 70.0:
	set(v):
		kicker_length = v
		_changed()
## Horizontal distance from the lip to the landing.
@export_range(10.0, 200.0, 1.0, "suffix:m") var gap: float = 55.0:
	set(v):
		gap = v
		_changed()
## How much lower the landing is than the lip.
@export_range(0.0, 30.0, 0.5, "suffix:m") var drop: float = 4.0:
	set(v):
		drop = v
		_changed()
@export_range(0.0, 15.0, 0.5, "suffix:°") var landing_deg: float = 6.0:
	set(v):
		landing_deg = v
		_changed()
@export_range(10.0, 200.0, 1.0, "suffix:m") var landing_length: float = 40.0:
	set(v):
		landing_length = v
		_changed()
## Pitch transition from the landing slope back to level.
@export_range(30.0, 300.0, 1.0, "suffix:m") var outrun: float = 80.0:
	set(v):
		outrun = v
		_changed()
## Level road between the climb and the kicker.
@export_range(0.0, 400.0, 1.0, "suffix:m") var runup: float = 64.0:
	set(v):
		runup = v
		_changed()

@export_group("Climb (makes the jump height-neutral)")
@export_range(1.0, 8.0, 0.5, "suffix:°") var climb_deg: float = 3.0:
	set(v):
		climb_deg = v
		_changed()
@export_range(20.0, 120.0, 1.0, "suffix:m") var climb_transition: float = 40.0:
	set(v):
		climb_transition = v
		_changed()

@export_group("Game")
## Slowest approach that lands cleanly, u/s (measured). 0 = not measured yet.
@export var clean_speed: float = 0.0
## Shape hash clean_speed was measured on (stale check).
@export var clean_speed_hash: int = 0
## Metres before the kicker with no respawn points.
@export var respawn_runup: float = 250.0:
	set(v):
		respawn_runup = v
		_changed()

const DS := 0.05


func kind() -> String:
	return "Jump"


func footprint() -> float:
	return shape().end_x()


## Hash of everything that changes the flight (for the stale check).
func shape_hash() -> int:
	return hash([kicker_deg, kicker_length, gap, drop, landing_deg, landing_length, outrun])


func clean_speed_valid() -> bool:
	return clean_speed > 0.0 and clean_speed_hash == shape_hash()


func shape() -> FeatureShape:
	var s := FeatureShape.new()
	var st := {x = 0.0, h = 0.0, p = 0.0, w = 1.0}
	# Climb to make the jump height-neutral (rise < 0 = a descent).
	var rise := -_jump_rise()
	_climb(s, st, rise)
	_straight(s, st, runup, 0.0)
	# Kicker.
	s.mark("kicker")
	_pitch(s, st, kicker_length, deg_to_rad(kicker_deg), 0.0)
	st.p = deg_to_rad(kicker_deg)
	# The kicker's last sample is the lip.
	s.marks["lip"] = s.size() - 1
	# Flight: a smooth (logic-only) arc from the lip to the landing, no road.
	var x0: float = st.x
	var h0: float = st.h
	var x1 := x0 + gap
	var h1 := h0 - drop
	var p1 := -deg_to_rad(landing_deg)
	var m0 := tan(st.p) * gap
	var m1 := tan(p1) * gap
	var n := int(ceil(gap))
	for i in range(1, n):
		var t := float(i) / n
		var t2 := t * t
		var t3 := t2 * t
		var hh := (2 * t3 - 3 * t2 + 1) * h0 + (t3 - 2 * t2 + t) * m0 + (-2 * t3 + 3 * t2) * h1 + (t3 - t2) * m1
		var slope := ((6 * t2 - 6 * t) * h0 + (3 * t2 - 4 * t + 1) * m0 + (-6 * t2 + 6 * t) * h1 + (3 * t2 - 2 * t) * m1) / gap
		s.add(x0 + t * gap, 0.0, hh, _up(atan(slope)), 0.0, false)
	st.x = x1
	st.h = h1
	st.p = p1
	s.mark("landing")
	s.add(st.x, 0.0, st.h, _up(st.p), 0.0)
	_straight(s, st, landing_length, 0.0)
	_pitch(s, st, outrun, -p1, 0.0)
	st.p = 0.0
	s.mark("end")
	# Bank fades back in after the outrun.
	_straight(s, st, 40.0, 1.0, true)
	s.h[s.size() - 1] = 0.0
	s.up[s.size() - 1] = Vector3.UP
	return s


# 2D turtle (forward x, height h, pitch p) -----------------------------------

func _up(p: float) -> Vector3:
	# Road normal for pitch p, canonical (right, up, forward).
	return Vector3(0.0, cos(p), -sin(p))


func _straight(s: FeatureShape, st: Dictionary, length: float, w: float, ramp_w: bool = false) -> void:
	if length <= 0.0:
		return
	var n := int(ceil(length))
	var step := length / n
	var w0: float = st.w
	for i in n:
		st.x += cos(st.p) * step
		st.h += sin(st.p) * step
		var ww := lerpf(w0, w, smoothstep01(float(i + 1) / n)) if ramp_w else w
		s.add(st.x, 0.0, st.h, _up(st.p), ww)
	st.w = w


## sin² pitch change of dp over `length`, emitting every metre; bank weight
## eases from st.w to w.
func _pitch(s: FeatureShape, st: Dictionary, length: float, dp: float, w: float) -> void:
	var n := int(round(length / DS))
	var every := int(round(1.0 / DS))
	var kmax := dp * 2.0 / length
	var w0: float = st.w
	for i in n:
		var sm := (i + 0.5) * DS
		st.p += kmax * pow(sin(PI * sm / length), 2.0) * DS
		st.x += cos(st.p) * DS
		st.h += sin(st.p) * DS
		if (i + 1) % every == 0:
			s.add(st.x, 0.0, st.h, _up(st.p), lerpf(w0, w, smoothstep01(float(i + 1) / n)))
	st.w = w


func _climb(s: FeatureShape, st: Dictionary, rise: float) -> void:
	if absf(rise) < 0.01:
		return
	var a := deg_to_rad(climb_deg) * signf(rise)
	var tr := _pitch_rise(climb_transition, 0.0, a)
	var tr2 := _pitch_rise(climb_transition, a, -a)
	var straight := maxf((rise - tr - tr2) / sin(a), 0.0)
	_pitch(s, st, climb_transition, a, 0.5)
	_straight(s, st, straight, 0.5)
	_pitch(s, st, climb_transition, -a, 0.0)
	st.p = 0.0


## Net height change from the kicker start to the end of the outrun.
func _jump_rise() -> float:
	var k := _pitch_rise(kicker_length, 0.0, deg_to_rad(kicker_deg))
	var l := -landing_length * sin(deg_to_rad(landing_deg))
	var o := _pitch_rise(outrun, -deg_to_rad(landing_deg), deg_to_rad(landing_deg))
	return k - drop + l + o


static func _pitch_rise(length: float, p0: float, dp: float) -> float:
	var p := p0
	var y := 0.0
	var n := int(round(length / DS))
	var kmax := dp * 2.0 / length
	for i in n:
		var sm := (i + 0.5) * DS
		p += kmax * pow(sin(PI * sm / length), 2.0) * DS
		y += sin(p) * DS
	return y
