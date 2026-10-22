extends RefCounted
class_name TrackSampler
## Dense, evenly spaced samples of a hand-drawn base curve (v34, Track Builder).
##
## The base Path3D is what Chris draws: few control points, 150-300 m apart.
## Everything the builder makes comes from these samples instead of the base
## curve itself, because:
##   - the bank is solved at every sample (Godot's own frame twists between
##     sparse control points, so tilts there would drift);
##   - curvature can be faired here (hand-set handles leave a curvature step,
##     felt as a lateral-g jolt, at every control point).
##
## Positions, tangents and arc lengths only. Banks are applied on top by
## apply_bank_profile(); metrics are derived from both.

const STEP := 1.0                 # metres between samples
const MIN_HORIZONTAL := 0.05      # |T.xz| below this = near-vertical tangent
## Half width to the outer edge of the lip on the circuits' cross-section
## (road 19.5, lips out to 21.5). Width keys set this edge; the walls follow it.
const DEFAULT_HALF_WIDTH := 21.5

var closed := false
var length := 0.0
var P: PackedVector3Array = PackedVector3Array()     # position
var T: PackedVector3Array = PackedVector3Array()     # unit tangent (travel direction)
var U: PackedVector3Array = PackedVector3Array()     # desired road up
var S: PackedFloat32Array = PackedFloat32Array()     # arc length
var bank: PackedFloat32Array = PackedFloat32Array()  # degrees, + = leans right (right edge low)
var width_l: PackedFloat32Array = PackedFloat32Array()  # road half width, left of travel (m)
var width_r: PackedFloat32Array = PackedFloat32Array()  # road half width, right of travel (m)
## Composite tracks only (TrackComposer): base distance behind each sample,
## the feature it belongs to (-1 = none), and 1 = road / 0 = a jump's gap.
var base_u: PackedFloat32Array = PackedFloat32Array()
var feat: PackedInt32Array = PackedInt32Array()
var road: PackedByteArray = PackedByteArray()
## Largest distance (m) any sample moved because of fairing, and per sample.
var fair_deviation := 0.0
var fair_dev: PackedFloat32Array = PackedFloat32Array()


## Samples `curve` (in the space of its Path3D; the builder requires identity
## transforms, so this is world space too). `fairing_m` = 0 keeps the drawn
## curve exactly; otherwise curvature changes are spread over about that many
## metres.
func sample(curve: Curve3D, fairing_m: float) -> bool:
	P.clear()
	T.clear()
	U.clear()
	S.clear()
	bank.clear()
	fair_deviation = 0.0
	if curve == null or curve.point_count < 2:
		return false
	closed = curve.closed
	var c := curve.duplicate() as Curve3D
	c.bake_interval = 0.25
	var baked := c.get_baked_length()
	if baked < STEP * 4.0:
		return false
	# Closed: n samples, the last segment wraps to sample 0. Open: n + 1 samples
	# including both ends.
	var n := int(round(baked / STEP))
	var step := baked / n
	var count := n if closed else n + 1
	P.resize(count)
	S.resize(count)
	for i in count:
		S[i] = i * step
		P[i] = c.sample_baked(minf(S[i], baked), true)
	length = baked
	fair_dev.resize(count)
	fair_dev.fill(0.0)
	if fairing_m > 0.0:
		_fair(fairing_m, _control_distances(c))
	_tangents()
	U.resize(P.size())
	bank.resize(P.size())
	width_l.resize(P.size())
	width_r.resize(P.size())
	for i in P.size():
		U[i] = level_up(T[i])
		bank[i] = 0.0
		width_l[i] = DEFAULT_HALF_WIDTH
		width_r[i] = DEFAULT_HALF_WIDTH
	return true


## Arc length of each control point on the (baked) curve.
func _control_distances(c: Curve3D) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for i in c.point_count:
		out.append(c.get_closest_offset(c.get_point_position(i)))
	if not closed:
		out[0] = 0.0
		out[out.size() - 1] = length
	return out


## Samples an existing (built or hand-made) curve every metre: positions, and
## the curve's own TILTED up vectors (what the game uses). `closed`: treat as
## a lap (an open curve with coincident ends drops its duplicate end).
func from_curve(c: Curve3D, as_lap: bool) -> void:
	var L := c.get_baked_length()
	closed = as_lap
	var n := int(round(L / STEP))
	var count := n if as_lap else n + 1
	var step_m := L / n
	P.resize(count)
	U.resize(count)
	S.resize(count)
	bank.resize(count)
	width_l.resize(count)
	width_r.resize(count)
	for i in count:
		S[i] = i * step_m
		P[i] = c.sample_baked(S[i], true)
		U[i] = c.sample_baked_up_vector(S[i], true)
		bank[i] = 0.0
		width_l[i] = DEFAULT_HALF_WIDTH
		width_r[i] = DEFAULT_HALF_WIDTH
	length = L
	_tangents()
	for i in count:
		U[i] = U[i].slide(T[i]).normalized()


func size() -> int:
	return P.size()


func step() -> float:
	return length / (P.size() if closed else P.size() - 1)


## Index of the sample at or before arc length `d` (wrapped on closed curves).
func index_at(d: float) -> int:
	if closed:
		d = fposmod(d, length)
	return clampi(int(floor(d / step())), 0, P.size() - 1)


## Signed difference b - a along the track, shortest way round on closed ones.
func delta(a: float, b: float) -> float:
	var x := b - a
	if closed:
		x = wrapf(x, -length * 0.5, length * 0.5)
	return x


# =============================================================================
# BANK
# =============================================================================

## Reference up with no bank: world up made perpendicular to the tangent.
static func level_up(t: Vector3) -> Vector3:
	var u := Vector3.UP.slide(t)
	if u.length() < MIN_HORIZONTAL:
		return Vector3.BACK.slide(t).normalized()
	return u.normalized()


## Right of travel for tangent `t` and up `u`.
static func right_of(t: Vector3, u: Vector3) -> Vector3:
	return t.cross(u).normalized()


## `keys` = [{d, bank, ease}] sorted by d. `ease` shapes the change from that
## key to the next one (ProfileKey.Ease). No keys = level road.
func apply_bank_profile(keys: Array) -> void:
	for i in P.size():
		var b := profile_at(S[i], keys, "bank", 0.0)
		bank[i] = b
		var up0 := level_up(T[i])
		var r := right_of(T[i], up0)
		var a := deg_to_rad(b)
		U[i] = (up0 * cos(a) + r * sin(a)).normalized()


## `keys` = [{d, left, right, ease}] sorted by d. No keys = the default width.
func apply_width_profile(keys: Array) -> void:
	for i in P.size():
		width_l[i] = profile_at(S[i], keys, "left", DEFAULT_HALF_WIDTH)
		width_r[i] = profile_at(S[i], keys, "right", DEFAULT_HALF_WIDTH)


## Value of `field` at arc length `d`, interpolated between keys (sorted by d,
## each with an `ease` for the change to the next key). Closed curves wrap
## from the last key to the first; open ones hold the end values.
func profile_at(d: float, keys: Array, field: String, fallback: float) -> float:
	var k := keys.size()
	if k == 0:
		return fallback
	if k == 1:
		return keys[0][field]
	# Key before d (or the last one, wrapping, on a closed curve).
	var j := -1
	for i in k:
		if keys[i].d <= d:
			j = i
	if not closed:
		if j < 0:
			return keys[0][field]
		if j == k - 1:
			return keys[k - 1][field]
	if j < 0:
		j = k - 1
	var a: Dictionary = keys[j]
	var b: Dictionary = keys[(j + 1) % k]
	var span: float = fposmod(b.d - a.d, length) if closed else b.d - a.d
	if span <= 0.001:
		return b[field]
	var t := clampf(fposmod(d - a.d, length) / span if closed else (d - a.d) / span, 0.0, 1.0)
	return lerpf(a[field], b[field], ease_weight(t, a.ease))


## Half-width change per metre on the faster-changing side (taper rate).
func taper_rate(i: int) -> float:
	var a := _wrap_index(i - 1)
	var b := _wrap_index(i + 1)
	var ds := absf(delta(S[a], S[b]))
	if ds <= 0.0:
		return 0.0
	return maxf(absf(width_l[b] - width_l[a]), absf(width_r[b] - width_r[a])) / ds


static func ease_weight(t: float, mode: int) -> float:
	match mode:
		1:  # linear
			return t
		2:  # hold, then step at the next key
			return 0.0
		3:  # smoother (zero 2nd derivative at the ends: gentlest roll-in)
			return t * t * t * (t * (t * 6.0 - 15.0) + 10.0)
		_:  # smooth
			return t * t * (3.0 - 2.0 * t)


# =============================================================================
# METRICS (per sample)
# =============================================================================

## Roll rate in degrees per metre: how fast the road twists about the
## direction of travel (the up vector's turn after the tangent's own turn is
## taken out). Works for banks, rolls and loops alike.
func roll_rate(i: int) -> float:
	var a := _wrap_index(i - 1)
	var b := _wrap_index(i + 1)
	var ds := absf(delta(S[a], S[b]))
	if ds <= 0.0:
		return 0.0
	var ua := U[a]
	var ta := T[a]
	var tb := T[b]
	var axis := ta.cross(tb)
	if axis.length() > 1e-9:
		ua = ua.rotated(axis.normalized(), ta.angle_to(tb))
	return rad_to_deg(ua.angle_to(U[b])) / ds


## Signed horizontal curvature (1/m), + = turning right.
func curvature_h(i: int) -> float:
	var a := _wrap_index(i - 2)
	var b := _wrap_index(i + 2)
	var ta := Vector2(T[a].x, T[a].z)
	var tb := Vector2(T[b].x, T[b].z)
	if ta.length() < MIN_HORIZONTAL or tb.length() < MIN_HORIZONTAL:
		return 0.0
	var ds := absf(delta(S[a], S[b]))
	if ds <= 0.0:
		return 0.0
	# Angle from ta to tb in the xz plane. Godot: -Z forward, +X right, so a
	# positive (counter-clockwise in x,z) angle is a right turn.
	return ta.angle_to(tb) / ds


## Grade in percent (+ = climbing).
func grade(i: int) -> float:
	var h := Vector2(T[i].x, T[i].z).length()
	if h < MIN_HORIZONTAL:
		return 999.0 * signf(T[i].y)
	return T[i].y / h * 100.0


## Vertical curvature (1/m): + = sag (compression), - = crest.
func curvature_v(i: int) -> float:
	var a := _wrap_index(i - 2)
	var b := _wrap_index(i + 2)
	var ds := absf(delta(S[a], S[b]))
	if ds <= 0.0:
		return 0.0
	return (asin(clampf(T[b].y, -1.0, 1.0)) - asin(clampf(T[a].y, -1.0, 1.0))) / ds


# =============================================================================
# PROJECTION
# =============================================================================

## Distance along the track of the point nearest `p`. Where the track passes
## near itself (crossings, over/unders), several stretches are about as close;
## then the one nearest `hint` (a previous answer, or < 0 for none) wins, so a
## key can't jump to another section of track. Returns [d, distance_to_track].
func project(p: Vector3, hint: float) -> Array:
	var n := P.size()
	var best := 0
	var best_d2 := INF
	var d2s := PackedFloat32Array()
	d2s.resize(n)
	for i in n:
		var d2 := P[i].distance_squared_to(p)
		d2s[i] = d2
		if d2 < best_d2:
			best_d2 = d2
			best = i
	if hint >= 0.0:
		# Local minima almost as close as the best one.
		var lim := sqrt(best_d2) * 1.5 + 10.0
		lim *= lim
		var chosen := best
		var chosen_gap := absf(delta(hint, S[best]))
		for i in n:
			if d2s[i] > lim:
				continue
			if d2s[i] > d2s[_wrap_index(i - 1)] or d2s[i] > d2s[_wrap_index(i + 1)]:
				continue
			var gap := absf(delta(hint, S[i]))
			if gap < chosen_gap:
				chosen = i
				chosen_gap = gap
		best = chosen
	return _refine(p, best)


## project() for walks that move a little each step: only the samples within
## `window` metres of `hint` (along the track) are searched. Much cheaper on a
## long lap, and it can't jump to another stretch of track.
func project_near(p: Vector3, hint: float, window: float) -> Array:
	var n := P.size()
	var c := index_at(hint)
	var k := int(ceil(window / step()))
	var best := c
	var best_d2 := INF
	for o in range(-k, k + 1):
		var i := c + o
		if closed:
			i = posmod(i, n)
		elif i < 0 or i >= n:
			continue
		var d2 := P[i].distance_squared_to(p)
		if d2 < best_d2:
			best_d2 = d2
			best = i
	return _refine(p, best)


## [d, distance] of the nearest point to `p` on the segments either side of
## sample `best`.
func _refine(p: Vector3, best: int) -> Array:
	var n := P.size()
	var d := S[best]
	var bestp := P[best]
	for j: int in [best - 1, best]:
		if not closed and (j < 0 or j >= n - 1):
			continue
		var a := _wrap_index(j)
		var b := _wrap_index(j + 1)
		var q := Geometry3D.get_closest_point_to_segment(p, P[a], P[b])
		if q.distance_squared_to(p) <= bestp.distance_squared_to(p):
			bestp = q
			var seg := P[a].distance_to(P[b])
			d = S[a] + (P[a].distance_to(q) if seg > 0.0 else 0.0)
	if closed:
		d = fposmod(d, length)
	return [d, bestp.distance_to(p)]


## Position, tangent and up at arc length `d` (interpolated between samples).
func frame_at(d: float) -> Transform3D:
	var i := index_at(d)
	var j := _wrap_index(i + 1)
	if not closed and i >= P.size() - 1:
		j = i
	var t := 0.0
	if j != i:
		t = clampf((fposmod(d, length) if closed else d) - S[i], 0.0, step()) / step()
	var pos := P[i].lerp(P[j], t)
	var fwd := T[i].lerp(T[j], t).normalized()
	var up := U[i].lerp(U[j], t).normalized()
	up = up.slide(fwd).normalized()
	var x := right_of(fwd, up)
	return Transform3D(Basis(x, up, -fwd), pos)


# =============================================================================
# INTERNALS
# =============================================================================

func _wrap_index(i: int) -> int:
	var n := P.size()
	if closed:
		return posmod(i, n)
	return clampi(i, 0, n - 1)


func _tangents() -> void:
	var n := P.size()
	T.resize(n)
	for i in n:
		var a := _wrap_index(i - 1)
		var b := _wrap_index(i + 1)
		var t := P[b] - P[a]
		T[i] = t.normalized() if t.length() > 0.0 else Vector3.FORWARD


## Fairing, local: a cubic Bezier's curvature only jumps AT control points
## (inside a segment it is smooth), so only a window around each control point
## is rewritten. The window is replaced by a quintic Hermite blend that matches
## position, direction and curvature at both window ends: the curvature step
## becomes a smooth ramp, and everything outside the windows stays exactly as
## drawn. `cp_d` = arc length of each control point; `fairing_m` = window
## width (capped at 45% of the gap to each neighbouring control point).
func _fair(fairing_m: float, cp_d: PackedFloat32Array) -> void:
	var n := P.size()
	var k := cp_d.size()
	var src := P.duplicate()
	for c in k:
		if not closed and (c == 0 or c == k - 1):
			continue   # open ends: nothing on the far side to blend with
		var dc := cp_d[c]
		var gap_prev := absf(delta(cp_d[(c - 1 + k) % k], dc))
		var gap_next := absf(delta(dc, cp_d[(c + 1) % k]))
		var half := minf(fairing_m * 0.5, 0.45 * minf(gap_prev, gap_next))
		var ia := int(round((dc - half) / step()))
		var ib := int(round((dc + half) / step()))
		if ib - ia < 6:
			continue
		if not closed and (ia < 3 or ib > n - 4):
			continue
		# Arc-length derivatives at the window ends, from the drawn curve.
		var pa := src[_wrap_index(ia)]
		var pb := src[_wrap_index(ib)]
		var va := _d1(src, ia)
		var vb := _d1(src, ib)
		var aa := _d2(src, ia)
		var ab := _d2(src, ib)
		var h := (ib - ia) * step()
		for i in range(ia + 1, ib):
			var u := float(i - ia) / float(ib - ia)
			var u2 := u * u
			var u3 := u2 * u
			var u4 := u3 * u
			var u5 := u4 * u
			var h0 := 1.0 - 10.0 * u3 + 15.0 * u4 - 6.0 * u5
			var h1 := u - 6.0 * u3 + 8.0 * u4 - 3.0 * u5
			var h2 := 0.5 * u2 - 1.5 * u3 + 1.5 * u4 - 0.5 * u5
			var h3 := 0.5 * u3 - u4 + 0.5 * u5
			var h4 := -4.0 * u3 + 7.0 * u4 - 3.0 * u5
			var h5 := 10.0 * u3 - 15.0 * u4 + 6.0 * u5
			var q := pa * h0 + va * (h * h1) + aa * (h * h * h2) \
					+ ab * (h * h * h3) + vb * (h * h4) + pb * h5
			var j := _wrap_index(i)
			P[j] = q
	for i in n:
		fair_dev[i] = P[i].distance_to(src[i])
		fair_deviation = maxf(fair_deviation, fair_dev[i])


## First and second derivatives by arc length (central differences, 2 m).
func _d1(arr: PackedVector3Array, i: int) -> Vector3:
	var h := 2
	return (arr[_wrap_index(i + h)] - arr[_wrap_index(i - h)]) / (2.0 * h * step())


func _d2(arr: PackedVector3Array, i: int) -> Vector3:
	var h := 2
	var ds := h * step()
	return (arr[_wrap_index(i + h)] - arr[_wrap_index(i)] * 2.0 + arr[_wrap_index(i - h)]) / (ds * ds)
