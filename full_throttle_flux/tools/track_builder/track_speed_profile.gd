extends RefCounted
class_name TrackSpeedProfile
## Estimated racing speed along a track (v34), from the same performance
## limits the AI plans with (ShipPerformanceModel, default_racer):
##
##   1. each sample's limit: corner_speed(geodesic curvature), the curvature
##      the ship has to steer in the road's own plane (banked or not);
##   2. forward pass: full throttle from the previous sample, capped by the
##      limit (twice round a closed lap, so the start inherits the finish);
##   3. backward pass: brake in time for every limit ahead.
##
## Where `skip` is set (magnetic zones, jumps) the limit is left at top
## speed: the zone handles the frame, and a kicker's bend is designed.
## Used by the validator for crests that would launch a ship, jump approach
## speeds, and the speed a ship reaches from a standing start.

var v := PackedFloat32Array()        # estimated speed (u/s)
var v_lim := PackedFloat32Array()    # corner limit (u/s)
var kg := PackedFloat32Array()       # geodesic curvature (1/m, signed: + = right)
var kn := PackedFloat32Array()       # normal curvature (1/m: + = sag, - = crest)
var model: ShipPerformanceModel


static func default_model() -> ShipPerformanceModel:
	return ShipPerformanceModel.new(default_profile())


static func default_profile() -> ShipProfile:
	return load("res://resources/ships/default_racer.tres") as ShipProfile


## A closed lap (or an open path from standstill).
func compute(s: TrackSampler, m: ShipPerformanceModel, skip: PackedByteArray = PackedByteArray()) -> void:
	_limits(s, m, skip)
	_forward(s, v_lim[0] if s.closed else 0.0, 2 if s.closed else 1)
	_backward(s, 2 if s.closed else 1)


## An open path (a branch) entered at `v0`.
func compute_open(s: TrackSampler, m: ShipPerformanceModel, skip: PackedByteArray, v0: float) -> void:
	_limits(s, m, skip)
	_forward(s, v0, 1)
	_backward(s, 1)


## Speed after `distance` metres of full throttle from standstill (a respawn).
func standing_start(distance: float) -> float:
	return model.speed_after_full_throttle(0.0, distance)


## Speed every `step` metres after a boost pad (v34), `count` values: the ship
## arrives at `v0` and gains `strength`, then holds full throttle. The speed
## limit is max_speed + an extra that starts at `strength` and decays at
## `damping` per second (ShipController.apply_boost / _apply_speed_limit);
## thrust and drag as in the performance model. Checked against the real
## default_racer by measure_boost.gd.
func boosted(v0: float, strength: float, damping: float, step: float, count: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var dt := model.dt
	var lam := -log(clampf(model.drag_coefficient, 0.0001, 0.9999))
	var v := v0 + strength
	var extra := strength
	var d := 0.0
	var next := 0.0
	var guard := 0
	while out.size() < count and guard < 200000:
		while d >= next and out.size() < count:
			out.append(v)
			next += step
		v += (model.thrust_power - lam * v) * dt
		extra *= exp(-damping * dt)
		v = minf(v, model.max_speed_ref + extra)
		d += v * dt
		guard += 1
	return out


func _limits(s: TrackSampler, m: ShipPerformanceModel, skip: PackedByteArray) -> void:
	model = m
	var n := s.size()
	v.resize(n)
	v_lim.resize(n)
	kg.resize(n)
	kn.resize(n)
	var top := model.top_speed()
	for i in n:
		var a := _wrap(s, i - 2)
		var b := _wrap(s, i + 2)
		var ds := absf(s.delta(s.S[a], s.S[b]))
		var dt := (s.T[b] - s.T[a]) / maxf(ds, 1e-3)
		var r := TrackSampler.right_of(s.T[i], s.U[i])
		kg[i] = dt.dot(r)
		kn[i] = dt.dot(s.U[i])
		var lim := top
		if skip.is_empty() or skip[i] == 0:
			lim = minf(top, model.corner_speed(absf(kg[i])))
		v_lim[i] = lim


func _forward(s: TrackSampler, v0: float, passes: int) -> void:
	var n := s.size()
	var step := s.step()
	var cur := minf(v0, v_lim[0])
	for p in passes:
		for i in n:
			if i > 0 or p > 0:
				cur = model.speed_after_full_throttle(cur, step)
			cur = minf(cur, v_lim[i])
			v[i] = cur


func _backward(s: TrackSampler, passes: int) -> void:
	var n := s.size()
	var step := s.step()
	var nxt := v[0] if s.closed else v[n - 1]
	for p in passes:
		for k in n:
			var i := n - 1 - k
			if s.closed or k > 0:
				v[i] = minf(v[i], model.max_entry_speed(nxt, step))
			nxt = v[i]


static func _wrap(s: TrackSampler, i: int) -> int:
	var n := s.size()
	return posmod(i, n) if s.closed else clampi(i, 0, n - 1)
