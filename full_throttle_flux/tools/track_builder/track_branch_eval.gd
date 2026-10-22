extends RefCounted
class_name TrackBranchEval
## Evaluates one BranchFeature against the main track (v34): the branch's own
## base (with its keys and features), snapped onto the main composite at both
## ends, plus the junction extents and the route lap through it.
##
## Order of work (TrackBuilder.evaluate):
##   1. place_on_base(): branch ends projected onto the MAIN BASE -> the main
##      composer's level spans (keyed bank faded out across both junctions);
##   2. the main composite is built;
##   3. evaluate(): the branch composite, snapped onto the main composite, and
##      the junction extents.

const KEY_FAR := 30.0
## Junction ends where the centre lines are this far apart (inner walls clear
## of each other; as on Fork Lab).
const JUNCTION_SEPARATION := 62.0
## The walks out of the junctions project each branch point onto the main
## track near the last answer (it moves about a metre per step).
const WALK_WINDOW := 60.0

var node: BranchFeature
var base := TrackSampler.new()
var track := TrackSampler.new()
var composer := TrackComposer.new()
var errors: PackedStringArray = []
## Main BASE distances of the drawn start and end (for the level spans).
var fork_u := 0.0
var rejoin_u := 0.0
## Main COMPOSITE distances where the branch leaves and rejoins.
var s_fork := 0.0
var s_rejoin := 0.0
## Junction extents: branch distance / main distance where the separation
## reaches JUNCTION_SEPARATION, at the fork (jf_*) and the rejoin (jr_*).
var jf_b := 0.0
var jf_m := 0.0
var jr_b := 0.0
var jr_m := 0.0
## +1 = the branch is on the right of the main track at the fork, -1 = left.
var side := 1.0
var ok := false
## Estimates from the bases (for levelling): main base distances where the
## junctions end, branch base distances where they end, and the target heights.
var est_jf_u := 0.0
var est_jr_u := 0.0
var est_jf_bu := 0.0
var est_jr_bu := 0.0
var y_fork := 0.0
var y_rejoin := 0.0
var ramp_fork := 80.0
var ramp_rejoin := 80.0
## Largest height change levelling made on the branch (m).
var levelled_max := 0.0
## Margin past the estimated junction end that's held level.
const LEVEL_MARGIN := 40.0


func _init(n: BranchFeature) -> void:
	node = n


## Keys and features that belong to this branch (anything under the node).
func keys_of(type: String) -> Array[ProfileKey]:
	var out: Array[ProfileKey] = []
	_collect(node, type, out)
	return out


func features() -> Array[TrackFeature]:
	var out: Array[TrackFeature] = []
	for k in keys_of(""):
		if k is TrackFeature:
			out.append(k)
	return out


## Step 1: sample the branch base, apply its profiles, find where it meets the
## main base.
func place_on_base(main_base: TrackSampler, fairing_m: float) -> bool:
	var p := node.base_path()
	if p == null or p.curve == null or p.curve.point_count < 2:
		errors.append("%s needs a BranchBase child (an open Path3D) to draw the route" % node.name)
		return false
	if p.curve.closed:
		errors.append("%s: its BranchBase must be open (untick Closed)" % node.name)
		return false
	if not base.sample(p.curve, fairing_m):
		errors.append("%s: BranchBase is too short" % node.name)
		return false
	var bk: Array = []
	for k in _project(keys_of("BankKey")):
		bk.append({d = k.distance, bank = (k as BankKey).bank_deg, ease = k.ease})
	var wk: Array = []
	for k in _project(keys_of("WidthKey")):
		var w := k as WidthKey
		wk.append({d = k.distance, left = w.half_width_left, right = w.half_width_right, ease = k.ease})
	var feats: Array[ProfileKey] = []
	for f in features():
		feats.append(f)
	_project(feats)
	base.apply_bank_profile(bk)
	base.apply_width_profile(wk)
	var a := main_base.project(base.P[0], -1.0)
	var b := main_base.project(base.P[base.size() - 1], -1.0)
	fork_u = a[0]
	rejoin_u = b[0]
	# Where the junctions will end, on the bases (the composites come later).
	est_jf_bu = -1.0
	var hint := fork_u
	for i in base.size():
		var pr := main_base.project_near(base.P[i], hint, WALK_WINDOW)
		hint = pr[0]
		if pr[1] >= JUNCTION_SEPARATION:
			est_jf_bu = base.S[i]
			est_jf_u = pr[0]
			break
	est_jr_bu = -1.0
	hint = rejoin_u
	for i in range(base.size() - 1, -1, -1):
		var pr := main_base.project_near(base.P[i], hint, WALK_WINDOW)
		hint = pr[0]
		if pr[1] >= JUNCTION_SEPARATION:
			est_jr_bu = base.S[i]
			est_jr_u = pr[0]
			break
	if est_jf_bu < 0.0 or est_jr_bu < 0.0 or est_jr_bu <= est_jf_bu:
		errors.append("%s never gets %.0f m clear of the main track: draw it further away" % [node.name, JUNCTION_SEPARATION])
		return false
	y_fork = main_base.P[main_base.index_at(fork_u)].y
	y_rejoin = main_base.P[main_base.index_at(rejoin_u)].y
	# Ramps: about 3% peak grade back to the drawn heights (smootherstep peaks
	# at 1.875 x the mean grade), never shorter than 80 m.
	ramp_fork = clampf(60.0 * _max_dev(main_base, fork_u, est_jf_u + LEVEL_MARGIN, y_fork, 0.0, est_jf_bu + LEVEL_MARGIN), 80.0, 500.0)
	ramp_rejoin = clampf(60.0 * _max_dev(main_base, est_jr_u - LEVEL_MARGIN, rejoin_u, y_rejoin, est_jr_bu - LEVEL_MARGIN, base.length), 80.0, 500.0)
	if a[1] > KEY_FAR:
		errors.append("%s starts %.0f m from the main track (limit 30): start it on the main road" % [node.name, a[1]])
	if b[1] > KEY_FAR:
		errors.append("%s ends %.0f m from the main track (limit 30): end it on the main road" % [node.name, b[1]])
	return errors.is_empty()


## The level spans this branch needs on the main base.
func level_spans(main_base: TrackSampler) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	out.append({a = fork_u - 10.0, b = est_jf_u + LEVEL_MARGIN, y = y_fork, ramp = ramp_fork})
	out.append({a = est_jr_u - LEVEL_MARGIN, b = rejoin_u + 10.0, y = y_rejoin, ramp = ramp_rejoin})
	return out


## Largest height difference from y0 over a main base range and a branch
## base range.
func _max_dev(main_base: TrackSampler, u0: float, u1: float, y0: float, b0: float, b1: float) -> float:
	var m := 0.0
	var u := u0
	while u <= u1:
		m = maxf(m, absf(main_base.P[main_base.index_at(u)].y - y0))
		u += 5.0
	u = maxf(b0, 0.0)
	while u <= minf(b1, base.length):
		m = maxf(m, absf(base.P[base.index_at(u)].y - y0))
		u += 5.0
	return m


## Step 3: the branch composite, snapped onto the main composite.
func evaluate(main: TrackSampler) -> bool:
	if not errors.is_empty():
		return false
	composer = TrackComposer.new()
	composer.compose_open(base, features(), track)
	for e in composer.errors:
		errors.append("%s: %s" % [node.name, e])
	var pa := main.project(track.P[0], -1.0)
	var pb := main.project(track.P[track.size() - 1], -1.0)
	s_fork = pa[0]
	s_rejoin = pb[0]
	if s_rejoin <= s_fork + 2.0 * node.junction_blend:
		errors.append("%s must rejoin later in the lap than it forks (and not across the start line)" % node.name)
		return false
	_snap(main)
	_junctions(main)
	ok = errors.is_empty()
	return ok


## Ease the first and last junction_blend metres from the main centre line
## (same progress along the main) into the drawn curve, positions and ups,
## with the bank faded out (the junctions are level).
func _snap(main: TrackSampler) -> void:
	var L := track.length
	var bl := minf(node.junction_blend, L * 0.4)
	for i in track.size():
		var s := track.S[i]
		var w := 1.0
		var target := Transform3D()
		if s < bl:
			w = TrackFeature.smootherstep01(s / bl)
			target = main.frame_at(s_fork + s)
		elif s > L - bl:
			w = TrackFeature.smootherstep01((L - s) / bl)
			target = main.frame_at(s_rejoin - (L - s))
		else:
			continue
		track.P[i] = target.origin.lerp(track.P[i], w)
		var lvl := TrackSampler.level_up(-target.basis.z)
		track.U[i] = lvl.lerp(track.U[i], w).normalized()
		track.bank[i] *= w
		track.width_l[i] = lerpf(TrackSampler.DEFAULT_HALF_WIDTH, track.width_l[i], w)
		track.width_r[i] = lerpf(TrackSampler.DEFAULT_HALF_WIDTH, track.width_r[i], w)
	# Hold the branch level through each junction (as the main track is),
	# easing back to the drawn heights.
	var yf := main.frame_at(s_fork).origin.y
	var yr := main.frame_at(s_rejoin).origin.y
	for i in track.size():
		var bu := track.base_u[i]
		var df := maxf(bu - (est_jf_bu + LEVEL_MARGIN), 0.0)
		var dr := maxf((est_jr_bu - LEVEL_MARGIN) - bu, 0.0)
		var hf := 1.0 - TrackFeature.smootherstep01(df / ramp_fork)
		var hr := 1.0 - TrackFeature.smootherstep01(dr / ramp_rejoin)
		var p := track.P[i]
		var y := p.y
		if hf > 0.0:
			y = lerpf(y, yf, hf)
		if hr > 0.0:
			y = lerpf(y, yr, hr)
		levelled_max = maxf(levelled_max, absf(y - p.y))
		p.y = y
		track.P[i] = p
	track._tangents()
	for i in track.size():
		var up := track.U[i].slide(track.T[i])
		track.U[i] = up.normalized() if up.length() > 1e-4 else TrackSampler.level_up(track.T[i])


## Walk out from each end until the centre lines are JUNCTION_SEPARATION apart.
func _junctions(main: TrackSampler) -> void:
	var L := track.length
	var hint := s_fork
	jf_b = -1.0
	for i in track.size():
		var pr := main.project_near(track.P[i], hint, WALK_WINDOW)
		hint = pr[0]
		if pr[1] >= JUNCTION_SEPARATION:
			jf_b = track.S[i]
			jf_m = pr[0]
			var f := main.frame_at(pr[0])
			side = signf((track.P[i] - f.origin).dot(f.basis.x))
			break
	hint = s_rejoin
	jr_b = -1.0
	for i in range(track.size() - 1, -1, -1):
		var pr := main.project_near(track.P[i], hint, WALK_WINDOW)
		hint = pr[0]
		if pr[1] >= JUNCTION_SEPARATION:
			jr_b = track.S[i]
			jr_m = pr[0]
			break
	if jf_b < 0.0 or jr_b < 0.0 or jr_b <= jf_b:
		errors.append("%s never gets %.0f m clear of the main track: draw it further away" % [node.name, JUNCTION_SEPARATION])
		return
	if side == 0.0:
		side = 1.0
	# Both junctions must sit on one side: the inner walls depend on it.
	var fr := main.frame_at(jr_m)
	var side_r := signf((track.P[track.index_at(jr_b)] - fr.origin).dot(fr.basis.x))
	if side_r != side:
		errors.append("%s leaves on one side of the main track and rejoins on the other" % node.name)


func _project(keys: Array[ProfileKey]) -> Array[ProfileKey]:
	for k in keys:
		var r := base.project(k.global_position, k.distance)
		k.distance = r[0]
		k.distance_to_track = r[1]
	keys.sort_custom(func(a: ProfileKey, b: ProfileKey) -> bool: return a.distance < b.distance)
	return keys


func _collect(n: Node, type: String, out: Array[ProfileKey]) -> void:
	for c in n.get_children():
		if c is ProfileKey and (type.is_empty() or (c as Object).get_script().get_global_name() == type):
			out.append(c)
		_collect(c, type, out)
