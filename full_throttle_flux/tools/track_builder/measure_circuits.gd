extends Node
## Measures the four gameworthy circuits (v34) for the validator's limits:
## cornering load, radius, grade, and the crest metric (how hard the road
## curves away under a ship at its estimated racing speed, against gravity),
## with Swoopy's two known organic exits (FTF_v33_RESPAWN.md: ~6,350 m at
## 90-110 u/s, ~7,645 m at 33-65 u/s climbing) called out.
##
##   godot --headless --path . -s res://tools/track_builder/measure_circuits_boot.gd
##
## The circuits' road is their MainSpline rotated ~1° about the scene origin
## (the offset), which changes no curvature, so the spline is measured as is.
## Env MC_TRACKS = comma list of scene names (default the four circuits plus
## builder_lab).

const G := 25.0

func _ready() -> void:
	var names := OS.get_environment("MC_TRACKS")
	var tracks := (names if not names.is_empty() else
			"test_circuit_3_live,test_circuit_5_live,test_circuit_6_live,test_circuit_7_live,builder_lab").split(",")
	var model := TrackSpeedProfile.default_model()
	for t in tracks:
		var scene := (load("res://scenes/tracks/%s.tscn" % t) as PackedScene).instantiate()
		var main := scene.find_child("MainSpline", true, false) as Path3D
		var mt := scene.find_child("MagneticTrack", true, false) as MagneticTrack
		var s := TrackSampler.new()
		s.from_curve(main.curve, true)
		var skip := PackedByteArray()
		skip.resize(s.size())
		var jumps: Array = []
		var g := scene.find_child("TrackGraph", true, false) as TrackGraph
		if g:
			for j in g.jumps:
				if j and j.branch < 0:
					jumps.append(Vector2(j.kicker_start - 20.0, j.landing_end + 20.0))
		for i in s.size():
			var z := false
			if mt:
				for zone in mt.zones:
					if zone and s.S[i] > zone.start_distance - zone.ramp_in and s.S[i] < zone.end_distance + zone.ramp_out:
						z = true
			for j: Vector2 in jumps:
				if s.S[i] > j.x and s.S[i] < j.y:
					z = true
			skip[i] = 1 if z else 0
		var sp := TrackSpeedProfile.new()
		sp.compute(s, model, skip)
		var max_g110 := 0.0
		var max_g_at := 0.0
		var max_gv := 0.0
		var max_grade := 0.0
		var min_r := INF
		var crests: Array = []   # [metric, d, v, kn]
		var vsum := 0.0
		for i in s.size():
			vsum += sp.v[i]
			if skip[i] == 1:
				continue
			var gl := 110.0 * 110.0 * absf(sp.kg[i]) / G
			if gl > max_g110:
				max_g110 = gl
				max_g_at = s.S[i]
			max_gv = maxf(max_gv, sp.v[i] * sp.v[i] * absf(sp.kg[i]) / G)
			if absf(sp.kg[i]) > 1e-6:
				min_r = minf(min_r, 1.0 / absf(sp.kg[i]))
			max_grade = maxf(max_grade, absf(s.grade(i)))
			var need := sp.v[i] * sp.v[i] * maxf(-sp.kn[i], 0.0)
			var hold := G * s.U[i].dot(Vector3.UP)
			crests.append([need - hold, s.S[i], sp.v[i], sp.kn[i], need / hold if hold > 0.1 else 99.0])
		crests.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
		# Percentiles: lateral load at 110, its step per metre (kinks), grade,
		# crest demand at estimated speed.
		var lat := PackedFloat32Array()
		var jolt := PackedFloat32Array()
		var grd := PackedFloat32Array()
		var dem := PackedFloat32Array()
		for i in s.size():
			if skip[i] == 1:
				continue
			lat.append(110.0 * 110.0 * absf(sp.kg[i]) / G)
			var j := (i + 1) % s.size()
			jolt.append(110.0 * 110.0 * absf(sp.kg[j] - sp.kg[i]) / G / s.step())
			grd.append(absf(s.grade(i)))
			dem.append(sp.v[i] * sp.v[i] * maxf(-sp.kn[i], 0.0))
		for arr_name: String in ["lateral_g_110", "jolt_g_per_m", "grade_pct", "crest_demand"]:
			var arr: PackedFloat32Array = {"lateral_g_110": lat, "jolt_g_per_m": jolt, "grade_pct": grd, "crest_demand": dem}[arr_name]
			arr.sort()
			var q := func(f: float) -> float: return arr[clampi(int(f * (arr.size() - 1)), 0, arr.size() - 1)]
			print("MC   %-14s p50 %7.2f  p90 %7.2f  p99 %7.2f  p99.9 %7.2f  max %7.2f" % [arr_name,
					q.call(0.5), q.call(0.9), q.call(0.99), q.call(0.999), arr[arr.size() - 1]])
		print("MC %s: %.0f m, mean est. speed %.0f u/s, lap ~%.1f s" % [t, s.length, vsum / s.size(),
				s.length / (vsum / s.size())])
		print("MC   lateral load at 110 u/s: max %.2f g at %.0f m; at estimated speed max %.2f g; min radius %.0f m; max grade %.1f%%"
				% [max_g110, max_g_at, max_gv, min_r, max_grade])
		var shown := []
		for c in crests:
			var dup := false
			for d in shown:
				if absf(c[1] - d) < 150.0:
					dup = true
			if dup:
				continue
			shown.append(c[1])
			print("MC   crest %.0f m: v %.0f u/s, curvature %.5f /m (radius %.0f m), needs %.1f u/s² vs gravity hold -> ratio %.2f, margin %+.1f"
					% [c[1], c[2], c[3], 1.0 / maxf(absf(c[3]), 1e-6), c[0] + 0.0, c[4], c[0]])
			if shown.size() >= 6:
				break
		if t == "test_circuit_5_live":
			for at: float in [6350.0, 7645.0]:
				var worst: Array = [-INF]
				for c in crests:
					if absf(c[1] - at) < 120.0 and c[0] > worst[0]:
						worst = c
				if worst.size() > 1:
					print("MC   SWOOPY EXIT ~%.0f: worst crest at %.0f m, v %.0f, ratio %.2f, margin %+.1f" % [at, worst[1], worst[2], worst[4], worst[0]])
		scene.free()
	get_tree().quit()
