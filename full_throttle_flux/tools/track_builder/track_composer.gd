extends RefCounted
class_name TrackComposer
## Splices features into the base curve (v34): the step between the base
## sampler (what Chris drew, with bank and width profiles) and the track the
## build emits.
##
## Walks the lap once from the lap origin (start line minus start_lead). Base
## samples pass through; each feature's footprint is replaced by its shape,
## mapped onto the base like a path deformer:
##
##   position = base(u) + right(u) * y + level_up(u) * h,   u = d0 + x
##   up       = right(u) * up.x + level_up(u) * up.y + tangent(u) * up.z
##
## then the whole lap is resampled every metre, and the keyed bank (times the
## feature's bank weight) is applied about the final tangent. The result is a
## TrackSampler whose distance 0 is the lap origin, so its distances are
## (within a metre or two) the generated MainSpline's.

const STEP := 1.0
## Keyed bank fades to zero over this many metres into a level span.
const LEVEL_RAMP := 40.0

## Errors that stop a build (features that overlap, or cross the lap origin).
var errors: PackedStringArray = []
## Per enabled feature: {node, d0, d1 (base), s0, s1 (composite), marks: name -> composite S}
var placed: Array[Dictionary] = []
## Junctions (TrackJunction needs them flat and level): {a, b (base
## distances), y (target height), ramp (metres)}. Inside a span the keyed bank
## is faded out (over LEVEL_RAMP) and the road is brought to height y; outside
## it eases back to the drawn height over `ramp` metres (smootherstep, so the
## grade has no kinks).
var level_spans: Array[Dictionary] = []
## Largest height change the levelling made (m), for the report.
var levelled_max := 0.0
var _open := false


## An OPEN base (a branch): the walk runs from 0 to the end, and the result
## keeps both ends (no wrap, no closing span).
func compose_open(base: TrackSampler, feats: Array[TrackFeature], out: TrackSampler) -> bool:
	_open = true
	return compose(base, feats, 0.0, out)


func compose(base: TrackSampler, feats: Array[TrackFeature], origin_d: float, out: TrackSampler) -> bool:
	var L := base.length
	# --- place the footprints, relative to the lap origin --------------------
	var items: Array[Dictionary] = []
	for f in feats:
		if not f.enabled:
			continue
		var sp := f.span()
		var rel0 := fposmod(sp.x - origin_d, L)
		var fl := sp.y - sp.x
		if fl >= L * 0.9:
			errors.append("%s is longer than the lap" % f.name)
			continue
		if _open:
			rel0 = sp.x
			if rel0 < 0.0 or rel0 + fl > L:
				errors.append("%s runs off the end of the branch" % f.name)
				continue
		elif rel0 + fl > L:
			errors.append("%s crosses the start line area: move it or the StartKey" % f.name)
			continue
		items.append({node = f, rel0 = rel0, rel1 = rel0 + fl, shape = f.shape()})
	items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.rel0 < b.rel0)
	for i in range(1, items.size()):
		if items[i].rel0 < items[i - 1].rel1:
			errors.append("%s overlaps %s" % [items[i].node.name, items[i - 1].node.name])
	if not errors.is_empty():
		items.clear()

	# --- walk the lap: raw samples ---------------------------------------------
	var raw := _Raw.new()
	var cursor := 0.0
	var fi := 0
	for it in items:
		_emit_base(raw, base, origin_d, cursor, it.rel0)
		_emit_feature(raw, base, origin_d, it, fi)
		cursor = it.rel1
		fi += 1
	_emit_base(raw, base, origin_d, cursor, L)

	# --- resample every metre --------------------------------------------------
	_resample(raw, out, base)
	for it in items:
		var m := {}
		for k in it.marks_raw:
			m[k] = raw.arc[it.marks_raw[k]]
		placed.append({node = it.node, d0 = origin_d + it.rel0, d1 = origin_d + it.rel1,
				s0 = raw.arc[it.raw0], s1 = raw.arc[it.raw1], marks = m, zone = it.shape.zone})
	return errors.is_empty()


class _Raw:
	var p := PackedVector3Array()
	var up := PackedVector3Array()
	var bank := PackedFloat32Array()
	var bw := PackedFloat32Array()
	var wl := PackedFloat32Array()
	var wr := PackedFloat32Array()
	var fair := PackedFloat32Array()
	var bu := PackedFloat32Array()
	var feat := PackedInt32Array()
	var road := PackedByteArray()
	var arc := PackedFloat32Array()


func _push(raw: _Raw, pos: Vector3, up: Vector3, bank: float, bw: float, wl: float, wr: float,
		fair: float, bu: float, feat: int, road: int) -> int:
	var n := raw.p.size()
	if n > 0:
		var d := pos.distance_to(raw.p[n - 1])
		if d < 0.05:
			return n - 1    # duplicate of the previous point (a feature boundary)
		raw.arc.append(raw.arc[n - 1] + d)
	else:
		raw.arc.append(0.0)
	raw.p.append(pos)
	raw.up.append(up)
	raw.bank.append(bank)
	raw.bw.append(bw)
	raw.wl.append(wl)
	raw.wr.append(wr)
	raw.fair.append(fair)
	raw.bu.append(bu)
	raw.feat.append(feat)
	raw.road.append(road)
	return raw.p.size() - 1


## Base samples for lap-relative [from, to).
func _emit_base(raw: _Raw, base: TrackSampler, origin_d: float, from: float, to: float) -> void:
	var r := from
	while r < to - 0.001:
		var u := origin_d + r
		_push_base(raw, base, u)
		r += base.step()
	if _open and to >= base.length - 0.001:
		# Keep the very end of an open base.
		_push_base(raw, base, base.length)


func _push_base(raw: _Raw, base: TrackSampler, u: float) -> void:
	var b := _base_at(base, u)
	_level(b, u, base.length)
	_push(raw, b.p, b.lup, b.bank, b.level_bw, b.wl, b.wr, b.fair, u, -1, 1)


## Junction levelling, applied to a base sample (b.p's height, and the bank
## weight b.level_bw). Features use it too, so a feature inside a levelling
## ramp moves with the road under it (otherwise its ends step).
func _level(b: Dictionary, u: float, L: float) -> void:
	var bw := 1.0
	var p: Vector3 = b.p
	for sp in level_spans:
		var d := _outside(sp, u, L)
		bw = minf(bw, TrackFeature.smoothstep01(d / LEVEL_RAMP))
		var hw := 1.0 - TrackFeature.smootherstep01(d / float(sp.ramp))
		if hw > 0.0:
			var y := lerpf(p.y, sp.y, hw)
			levelled_max = maxf(levelled_max, absf(y - p.y))
			p.y = y
	b.p = p
	b.level_bw = bw


## Metres from base distance `u` to the span (0 inside it).
func _outside(sp: Dictionary, u: float, L: float) -> float:
	if _open:
		return maxf(maxf(sp.a - u, u - sp.b), 0.0)
	var into := fposmod(u - sp.a, L)
	var span := fposmod(sp.b - sp.a, L)
	return 0.0 if into <= span else minf(into - span, L - into)


func _emit_feature(raw: _Raw, base: TrackSampler, origin_d: float, it: Dictionary, fi: int) -> void:
	var sh: FeatureShape = it.shape
	var at_index := {}
	for k in sh.marks:
		at_index[sh.marks[k]] = (at_index.get(sh.marks[k], []) as Array) + [k]
	it.marks_raw = {}
	for k in sh.size():
		var u: float = origin_d + it.rel0 + sh.x[k]
		var b := _base_at(base, u)
		_level(b, u, base.length)
		var right := TrackSampler.right_of(b.t, b.lup)
		var pos: Vector3 = b.p + right * sh.y[k] + b.lup * sh.h[k]
		var c := sh.up[k]
		var up: Vector3 = right * c.x + b.lup * c.y + b.t * c.z
		var idx := _push(raw, pos, up, b.bank, sh.bank_w[k] * b.level_bw, b.wl, b.wr, 0.0, u, fi, sh.road[k])
		if k == 0:
			it.raw0 = idx
		if k == sh.size() - 1:
			it.raw1 = idx
		for name in at_index.get(k, []):
			it.marks_raw[name] = idx


## Base frame and profile values at base distance `u` (wrapped).
func _base_at(base: TrackSampler, u: float) -> Dictionary:
	var L := base.length
	var uu := clampf(u, 0.0, L) if _open else fposmod(u, L)
	var n := base.size()
	var step := base.step()
	var i := int(floor(uu / step)) % n
	var j := (i + 1) % n
	if _open:
		i = mini(int(floor(uu / step)), n - 2)
		j = i + 1
	var t := clampf((uu - i * step) / step, 0.0, 1.0)
	var tan := base.T[i].lerp(base.T[j], t).normalized()
	return {
		p = base.P[i].lerp(base.P[j], t),
		t = tan,
		lup = TrackSampler.level_up(tan),
		bank = lerpf(base.bank[i], base.bank[j], t),
		wl = lerpf(base.width_l[i], base.width_l[j], t),
		wr = lerpf(base.width_r[i], base.width_r[j], t),
		fair = lerpf(base.fair_dev[i], base.fair_dev[j], t),
	}


func _resample(raw: _Raw, out: TrackSampler, base: TrackSampler) -> void:
	# Close the loop for the arc length: the last raw point joins the first.
	var m := raw.p.size()
	var total := raw.arc[m - 1] if _open else raw.arc[m - 1] + raw.p[m - 1].distance_to(raw.p[0])
	var segs := maxi(4, int(round(total / STEP)))
	var step := total / segs
	var n := segs + 1 if _open else segs
	out.closed = not _open
	out.length = total
	out.P.resize(n)
	out.U.resize(n)
	out.S.resize(n)
	out.bank.resize(n)
	out.width_l.resize(n)
	out.width_r.resize(n)
	out.fair_dev.resize(n)
	out.base_u.resize(n)
	out.feat.resize(n)
	out.road.resize(n)
	out.fair_deviation = base.fair_deviation
	var bw := PackedFloat32Array()
	bw.resize(n)
	var seg := 0
	for i in n:
		var s := i * step
		while seg < m - 1 and raw.arc[seg + 1] <= s:
			seg += 1
		var a := seg
		var b := (seg + 1) % m
		if _open and b == 0:
			b = a
		var a_arc := raw.arc[a]
		var b_arc := raw.arc[b] if b > 0 else total
		if b == a:
			b_arc = a_arc + 1.0
		var t := clampf((s - a_arc) / maxf(b_arc - a_arc, 1e-6), 0.0, 1.0)
		out.S[i] = s
		out.P[i] = raw.p[a].lerp(raw.p[b], t)
		out.U[i] = raw.up[a].lerp(raw.up[b], t).normalized()
		out.bank[i] = lerpf(raw.bank[a], raw.bank[b], t)
		bw[i] = lerpf(raw.bw[a], raw.bw[b], t)
		out.width_l[i] = lerpf(raw.wl[a], raw.wl[b], t)
		out.width_r[i] = lerpf(raw.wr[a], raw.wr[b], t)
		out.fair_dev[i] = lerpf(raw.fair[a], raw.fair[b], t)
		# Base distance unwrapped across the seam for interpolation.
		var bub := raw.bu[b] if (b > 0 or _open) else raw.bu[0] + base.length
		var bu := lerpf(raw.bu[a], bub, t)
		out.base_u[i] = bu if _open else fposmod(bu, base.length)
		var near := a if t < 0.5 else b
		out.feat[i] = raw.feat[near]
		out.road[i] = raw.road[a] & raw.road[b] if raw.feat[a] == raw.feat[b] else raw.road[near]
	out._tangents()
	# Up perpendicular to the final tangent, then the keyed bank (weighted).
	for i in n:
		var up := out.U[i].slide(out.T[i])
		if up.length() < 1e-4:
			up = TrackSampler.level_up(out.T[i])
		up = up.normalized()
		var a := deg_to_rad(out.bank[i] * bw[i])
		var r := TrackSampler.right_of(out.T[i], up)
		out.U[i] = (up * cos(a) + r * sin(a)).normalized()
		out.bank[i] *= bw[i]
