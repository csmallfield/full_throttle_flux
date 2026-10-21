extends RefCounted
## Centre-line "turtle" for generated test tracks (v31, Fork Lab).
##
## Same approach as tools/loop_lab/build_loop_lab.gd: integrate curvature with
## sin^2 profiles (zero at both ends, so g builds up instead of switching on),
## emit samples (position, tangent, desired road up, arc length), then build a
## Curve3D whose tilts are SOLVED against Godot's own baked up vectors.
##
## Adds pitch (vertical curvature) for kickers and landing ramps. Yaw turns are
## made at zero pitch; pitch changes on straights.

const DS := 0.05

var P: Array[Vector3] = []
var T: Array[Vector3] = []
var U: Array[Vector3] = []
var S: Array[float] = []
var marks := {}

var pos := Vector3.ZERO
var heading := Vector3.FORWARD    # horizontal unit vector (-Z = north)
var pitch := 0.0                  # radians, + = climbing
var arc := 0.0


func tangent() -> Vector3:
	return (heading * cos(pitch) + Vector3.UP * sin(pitch)).normalized()


func right() -> Vector3:
	return heading.cross(Vector3.UP).normalized()


func mark(n: String) -> void:
	marks[n] = arc


func emit(up: Vector3 = Vector3.UP) -> void:
	var t := tangent()
	P.append(pos)
	T.append(t)
	U.append(up.slide(t).normalized())
	S.append(arc)


## Straight line along the current tangent (pitched or level).
func straight(length: float, every: float) -> void:
	if length <= 0.0:
		return
	var n := int(ceil(length / every))
	var step := length / n
	for i in n:
		emit()
		pos += tangent() * step
		arc += step


## Yaw turn with sin^2 curvature (dpsi > 0 = left), banked into the turn with a
## sin^2 bank profile. Assumes level road.
func turn(length: float, dpsi: float, bank_deg: float, every: float) -> void:
	var n := int(round(length / DS))
	var emit_every := maxi(1, int(round(every / DS)))
	var kmax := dpsi * 2.0 / length
	var bank := deg_to_rad(bank_deg) * signf(-dpsi)
	for i in n:
		var s := (i + 0.5) * DS
		var shape := pow(sin(PI * s / length), 2.0)
		if i % emit_every == 0:
			var lean := bank * pow(sin(PI * (i * DS) / length), 2.0)
			emit(Vector3.UP * cos(lean) + right() * sin(lean))
		heading = heading.rotated(Vector3.UP, kmax * shape * DS).normalized()
		pos += tangent() * DS
		arc += DS


## Pitch change with sin^2 vertical curvature: dphi > 0 pitches up (concave,
## a compression), < 0 pitches down (convex, a crest).
func pitch_change(length: float, dphi: float, every: float) -> void:
	var n := int(round(length / DS))
	var emit_every := maxi(1, int(round(every / DS)))
	var kmax := dphi * 2.0 / length
	for i in n:
		var s := (i + 0.5) * DS
		if i % emit_every == 0:
			emit()
		pitch += kmax * pow(sin(PI * s / length), 2.0) * DS
		pos += tangent() * DS
		arc += DS


## Horizontal (forward, lateral toward the turn) displacement of a sin^2 turn.
static func turn_displacement(length: float, dpsi: float) -> Vector2:
	var psi := 0.0
	var f := 0.0
	var l := 0.0
	var n := int(round(length / DS))
	var kmax := absf(dpsi) * 2.0 / length
	for i in n:
		var s := (i + 0.5) * DS
		psi += kmax * pow(sin(PI * s / length), 2.0) * DS
		f += cos(psi) * DS
		l += sin(psi) * DS
	return Vector2(f, l)


## (horizontal run, rise) of a sin^2 pitch change starting at pitch `p0`.
static func pitch_displacement(length: float, p0: float, dphi: float) -> Vector2:
	var p := p0
	var x := 0.0
	var y := 0.0
	var n := int(round(length / DS))
	var kmax := dphi * 2.0 / length
	for i in n:
		var s := (i + 0.5) * DS
		p += kmax * pow(sin(PI * s / length), 2.0) * DS
		x += cos(p) * DS
		y += sin(p) * DS
	return Vector2(x, y)


# =============================================================================
# CURVE + TILTS (from build_loop_lab.gd)
# =============================================================================

## Builds the Curve3D through the samples. Returns null if the tilt solve
## fails. Fills `offsets` with each sample's baked distance.
func build_curve(tag: String, offsets: PackedFloat32Array) -> Curve3D:
	var c := Curve3D.new()
	c.closed = false
	c.bake_interval = 0.2
	c.up_vector_enabled = true
	var n := P.size()
	for i in n:
		var prev_len := P[i].distance_to(P[i - 1]) if i > 0 else P[1].distance_to(P[0])
		var next_len := P[i].distance_to(P[i + 1]) if i < n - 1 else prev_len
		c.add_point(P[i], -T[i] * prev_len / 3.0, T[i] * next_len / 3.0)
	
	offsets.resize(n)
	offsets[0] = 0.0
	var baked_len := c.get_baked_length()
	var cursor := 0.0
	for i in range(1, n):
		# Search window covers the chord to the previous sample (a jump gap is
		# one long cubic span).
		var window := maxf(30.0, P[i].distance_to(P[i - 1]) * 1.6)
		cursor = _find_offset_after(c, P[i], cursor, baked_len, window)
		offsets[i] = cursor
	offsets[n - 1] = baked_len
	
	var raw := PackedFloat32Array()
	raw.resize(n)
	for i in n:
		var xf := c.sample_baked_with_rotation(offsets[i], true, false)
		var t: Vector3 = -xf.basis.z.normalized()
		if t.dot(T[i]) < 0.0:
			t = -t
		var up0 := c.sample_baked_up_vector(offsets[i], false).slide(t).normalized()
		var want := U[i].slide(t).normalized()
		raw[i] = atan2(up0.cross(want).dot(t), up0.dot(want))
	var acc := raw[0]
	c.set_point_tilt(0, acc)
	for i in range(1, n):
		acc += wrapf(raw[i] - raw[i - 1], -PI, PI)
		c.set_point_tilt(i, acc)
	if _tilt_error(c, offsets) > 0.2:
		for i in n:
			c.set_point_tilt(i, -c.get_point_tilt(i))
	var err := _tilt_error(c, offsets)
	print("%s tilt solve: max up error at control points %.3f deg, baked length %.1f m, %d points"
			% [tag, rad_to_deg(err), baked_len, n])
	if rad_to_deg(err) > 1.0:
		push_error("%s tilt solve failed" % tag)
		return null
	return c


## Baked distance of the sample nearest arc length `a` (needs the offsets
## build_curve() filled in).
func baked_at_arc(a: float, offsets: PackedFloat32Array) -> float:
	var best := 0
	for i in S.size():
		if absf(S[i] - a) < absf(S[best] - a):
			best = i
	# Interpolate between neighbouring samples for sub-sample accuracy.
	var j := best + 1 if S[best] < a and best + 1 < S.size() else best - 1
	if j < 0 or j >= S.size() or is_equal_approx(S[j], S[best]):
		return offsets[best]
	var t := (a - S[best]) / (S[j] - S[best])
	return lerpf(offsets[best], offsets[j], t)


func _tilt_error(c: Curve3D, offs: PackedFloat32Array) -> float:
	var e := 0.0
	for i in P.size():
		e = maxf(e, c.sample_baked_up_vector(offs[i], true).angle_to(U[i]))
	return e


func _find_offset_after(c: Curve3D, p: Vector3, from: float, length: float, window: float) -> float:
	var best := from
	var best_d := INF
	var s := from
	while s <= minf(from + window, length):
		var d := c.sample_baked(s, true).distance_squared_to(p)
		if d < best_d:
			best_d = d
			best = s
		s += 0.25
	var lo := maxf(best - 0.25, 0.0)
	var hi := minf(best + 0.25, length)
	for i in 20:
		var a := lo + (hi - lo) / 3.0
		var b := hi - (hi - lo) / 3.0
		if c.sample_baked(a, true).distance_squared_to(p) < c.sample_baked(b, true).distance_squared_to(p):
			hi = b
		else:
			lo = a
	return (lo + hi) * 0.5
