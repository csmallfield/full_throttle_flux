extends RefCounted
class_name TrackValidator
## Track Builder: the validator (v34). Runs in the editor (Validate button) and
## headless (validate_boot.gd). Each issue has a severity, a place on the
## track and a message; the editor draws them where they are.
##
## Step 2 checks (the core):
##   offset rule      identity transforms from the root down to the road
##   built            a MainSpline exists and matches the current inputs
##   surface          ray-cast the built road every 5 m (centre and 60% out):
##                    height within 0.05 m of the spline frame, normal within
##                    0.5° (+ 4.5 m x roll rate, the strips' facets) of the
##                    ideal extruded surface there
##   bank delivered   the spline's up vs the bank you keyed, within 0.5°
##   roll rate        over 0.7°/m warns, over 0.75°/m is an error
##   width            taper over 0.1 m/m warns; half width under 10 m warns
##   keys             more than 30 m from the track is an error
##
## Step 3 adds the features:
##   placement        overlaps / across the lap origin (errors); right after
##                    the start line or over the grid (warnings)
##   footprint bend   how far the base turns or climbs under a feature
##   keys in features bank keys inside a loop's or jump's footprint
##   roll rate        roll features may use up to 0.75°/m (no 0.7 warning)
##   jumps            clean_speed measured for the current shape
##   surface          no rays over jump gaps
##
## Step 4, the race checks, from an estimated racing speed along the lap
## (TrackSpeedProfile: the AI's own ShipPerformanceModel) and limits measured
## on the four gameworthy circuits (tools/track_builder/measure_circuits.gd):
##   cornering        over 15 g at 110 u/s warns (tighter than 99% of the
##                    circuits' corners)
##   kinks            curvature stepping more than 1.0 g per metre (circuits:
##                    p99 0.75; a faired builder track: ~0.1)
##   grade            over 50% warns (The Drop reaches 110%, others 16-48%)
##   crests           the road curving away under a ship at its estimated
##                    speed: over 110 u/s² warns (more than any circuit asks;
##                    Swoopy's worst is 101), over 200 is an error (close to
##                    gravity + the hover spring's pull, ~225: a launch)
##   jumps            racing speed at the lip vs clean_speed (main route: an
##                    error; a branch: a warning, it's a choice), and the speed
##                    a ship reaches from a respawn before the jump
##   clearance        nothing of this track within 10 m above its road
##   start and grid   straight (under 1 g at 110 u/s, radius ~480 m) and level
##                    (under 3%); every grid slot over the road
##   junctions        standard width; no feature inside one
##   branch ends      on the main spline within 0.05 m and 0.5°
##   respawns         (headless) every point over road; the largest gap
##
## Greebles (GreebleZoneKey, v36):
##   keys             more than 30 m from the built spline is an error; two
##                    keys on the same road within 2 m of each other warn
##   styles           a zone whose style has no usable rule warns
##   built            the TrackGreebles node exists and matches the keys
##                    (else: press Build or Refresh greebles)
##   corridor         pieces reaching into the flat road below 10 m (the
##                    track clearance), ground pieces over 0.3 m tall
##
## Surface zones (SurfaceZoneKey, v38):
##   keys             more than 30 m from the built spline is an error; two
##                    keys on the same road within 2 m of each other warn
##   profiles         a key without one warns; a profile's own problems
##                    (TrackSurfaceProfile.problems()) warn; more than 4
##                    profiles on one path is an error (the shader's limit)
##   built            the TrackSurface node exists and matches the keys
##                    (else: press Build or Refresh surface)
##
## Boost pads (BoostPadKey):
##   placement        on the flat road (errors), no overlaps (errors), not over
##                    a jump's gap (error) or on its kicker, not on the grid
##   built            ray-cast each pad's corners: road under every one, the
##                    pad within 0.2 m of it (a tight crest or dip buries an end)
##   boost            the speed a ship carries away from the pad (measured on
##                    default_racer: TrackSpeedProfile.boosted) into the next
##                    corner (over the AI's limit warns), crest (the crest
##                    thresholds above) and jump lip (faster than the jumps
##                    are measured warns)

enum Sev { INFO, WARNING, ERROR }

const SURFACE_EVERY := 5.0
const SURFACE_HEIGHT_TOL := 0.05
const SURFACE_NORMAL_TOL := 0.5
## Where the road twists (banks changing, rolls) its 3 m strips and 1 m rings
## triangulate a curved surface into flat facets: a slight washboard. Measured
## on Builder Lab: about 0.5° on the centre line and isolated spikes to ~4.5 m
## x the roll rate at the strip edges (~2-2.6° in an 800 m roll; Loop Lab's
## roll measured ~2° and drives fine). Finer strips everywhere would double the
## road's triangles for this.
const SURFACE_FACET_M := 4.5
const BANK_TOL := 0.5
const ROLL_WARN := 0.7
const ROLL_ERROR := 0.75
const TAPER_WARN := 0.1
const MIN_HALF_WIDTH := 10.0
const KEY_FAR := 30.0
const GROUND_MASK := 1

## {sev, pos (Vector3), d (metres, -1 = none), msg}
var issues: Array[Dictionary] = []
var stats := {}


static func run(b: TrackBuilder, space: PhysicsDirectSpaceState3D) -> TrackValidator:
	var v := TrackValidator.new()
	v._run(b, space)
	return v


func errors() -> int:
	return issues.filter(func(i: Dictionary) -> bool: return i.sev == Sev.ERROR).size()


func warnings() -> int:
	return issues.filter(func(i: Dictionary) -> bool: return i.sev == Sev.WARNING).size()


func summary() -> String:
	var lines: PackedStringArray = []
	lines.append("Validate: %d errors, %d warnings" % [errors(), warnings()])
	for k in stats:
		lines.append("  %s: %s" % [k, stats[k]])
	var shown := 0
	for i in issues:
		if shown >= 40:
			lines.append("  … %d more" % (issues.size() - shown))
			break
		var tag: String = ["ℹ", "⚠", "✗"][i.sev]
		var at := " @ %.0f m" % i.d if i.d >= 0.0 else ""
		lines.append("%s %s%s" % [tag, i.msg, at])
		shown += 1
	return "\n".join(lines)


func _add(sev: Sev, pos: Vector3, d: float, msg: String) -> void:
	issues.append({sev = sev, pos = pos, d = d, msg = msg})


func _run(b: TrackBuilder, space: PhysicsDirectSpaceState3D) -> void:
	var root: Node = b.owner if b.owner else b.get_parent()
	if not b.evaluate():
		_add(Sev.ERROR, b.global_position, -1.0, "No BaseSpline curve")
		return
	for e in b.errors():
		_add(Sev.ERROR, b.global_position, -1.0, e)
	_check_profiles(b)
	_check_keys(b)
	_check_features(b)
	_check_pads(b)
	var main := root.get_node_or_null("MainSpline") as Path3D if root else null
	if main == null or main.curve == null:
		_add(Sev.WARNING, b.global_position, -1.0, "Not built yet (press Build)")
		_check_offset_rule(root, [b.base_path()])
		return
	if not main.is_in_group(TrackBuild.GROUP):
		_add(Sev.WARNING, main.global_position, -1.0, "MainSpline is hand-made, not generated by this builder")
	elif main.get_meta(TrackBuild.META_HASH, -1) != b.input_hash():
		_add(Sev.WARNING, main.global_position, -1.0, "Build is out of date: the inputs changed since the last Build")
	var segs: Array[Node] = [b.base_path(), main]
	for c in main.get_children():
		if c is TrackRoadSegment:
			segs.append(c)
	_check_offset_rule(root, segs)
	_check_bank_delivered(b, main.curve)
	if space:
		_check_surface(b, main.curve, space)
	else:
		_add(Sev.WARNING, main.global_position, -1.0, "No physics space: surface not checked")
	_check_branches(b, root, space)
	_check_pads_built(b, root, space)
	_check_race(b, root, space)
	_check_greebles(b, root)
	_check_surface_zones(b, root)


# =============================================================================
# CHECKS
# =============================================================================

## Every node from `n` up to the root, and the root itself, at identity.
func _check_offset_rule(root: Node, nodes: Array) -> void:
	var seen := {}
	for start: Node in nodes:
		var n := start
		while n:
			if not seen.has(n):
				seen[n] = true
				if n is Node3D and not (n as Node3D).transform.is_equal_approx(Transform3D.IDENTITY):
					_add(Sev.ERROR, (n as Node3D).global_position, -1.0,
							"%s has a non-identity transform (the offset rule: edit the curve, never move the node)" % n.name)
			if n == root:
				break
			n = n.get_parent()


func _check_profiles(b: TrackBuilder) -> void:
	var s := b.sampler
	var n := s.size()
	var roll := PackedFloat32Array()
	var taper := PackedFloat32Array()
	var width := PackedFloat32Array()
	roll.resize(n)
	taper.resize(n)
	width.resize(n)
	for i in n:
		roll[i] = s.roll_rate(i)
		taper[i] = s.taper_rate(i)
		width[i] = minf(s.width_l[i], s.width_r[i])
	for j in _worst_of_runs(roll, ROLL_WARN, true):
		var in_roll := s.feat[j] >= 0 and b.composer.placed[s.feat[j]].node is RollFeature
		if in_roll and roll[j] <= ROLL_ERROR:
			continue
		_add(Sev.ERROR if roll[j] > ROLL_ERROR else Sev.WARNING, s.P[j], _main_d(b, j),
				"Roll rate %.2f °/m (limit %s): spread the change over more track"
				% [roll[j], "0.75 in a roll" if in_roll else "0.7"])
	for j in _worst_of_runs(taper, TAPER_WARN, true):
		_add(Sev.WARNING, s.P[j], _main_d(b, j),
				"Width changes %.2f m per m (limit 0.1): the wall cuts across the racing line" % taper[j])
	for j in _worst_of_runs(width, MIN_HALF_WIDTH, false):
		_add(Sev.WARNING, s.P[j], _main_d(b, j),
				"Half width %.1f m (under 10): tight for an 8-ship pack and respawn side-steps" % width[j])
	stats["max roll rate"] = "%.2f °/m" % _max(roll)
	stats["max taper"] = "%.3f m/m" % _max(taper)
	stats["min half width"] = "%.1f m" % -_max(_neg(width))


## Index of the worst sample in each contiguous stretch past `limit` (above it
## when `high`, below it otherwise), so a long bad stretch reports once.
static func _worst_of_runs(v: PackedFloat32Array, limit: float, high: bool) -> PackedInt32Array:
	var out := PackedInt32Array()
	var best := -1
	for i in v.size():
		var bad := v[i] > limit if high else v[i] < limit
		if bad:
			if best < 0 or (v[i] > v[best] if high else v[i] < v[best]):
				best = i
		elif best >= 0:
			out.append(best)
			best = -1
	if best >= 0:
		out.append(best)
	return out


static func _argmax(v: PackedFloat32Array) -> int:
	var b := 0
	for i in v.size():
		if v[i] > v[b]:
			b = i
	return b


static func _max(v: PackedFloat32Array) -> float:
	var m := -INF
	for x in v:
		m = maxf(m, x)
	return m


static func _neg(v: PackedFloat32Array) -> PackedFloat32Array:
	var o := PackedFloat32Array()
	for x in v:
		o.append(-x)
	return o


const BEND_LIMIT := {"Loop": 15.0, "Jump": 10.0, "Roll": 60.0}
const GRADE_LIMIT := {"Loop": 3.0, "Jump": 3.0, "Roll": 8.0}
const GRID_REACH := 200.0

func _check_features(b: TrackBuilder) -> void:
	var s := b.sampler
	var base := b.base
	for p in b.composer.placed:
		var f: TrackFeature = p.node
		var at := s.frame_at(p.s0).origin
		# How much the base turns and climbs under the footprint.
		var i0 := base.index_at(p.d0)
		var i1 := base.index_at(p.d1)
		var h0 := Vector2(base.T[i0].x, base.T[i0].z).normalized()
		var h1 := Vector2(base.T[i1].x, base.T[i1].z).normalized()
		var bend := rad_to_deg(absf(h0.angle_to(h1)))
		var grade := 0.0
		var u: float = p.d0
		while u <= p.d1:
			grade = maxf(grade, absf(base.grade(base.index_at(u))))
			u += 5.0
		var kind := f.kind()
		if bend > BEND_LIMIT.get(kind, 30.0):
			_add(Sev.WARNING, at, p.s0, "%s: the base turns %.0f° under it (limit %.0f): it will be bent with the curve"
					% [f.name, bend, BEND_LIMIT[kind]])
		if grade > GRADE_LIMIT.get(kind, 5.0):
			_add(Sev.WARNING, at, p.s0, "%s: the base climbs %.1f%% under it (limit %.0f%%)" % [f.name, grade, GRADE_LIMIT[kind]])
		# Next to the start.
		if p.s0 < b.start_lead + 50.0:
			_add(Sev.WARNING, at, p.s0, "%s starts right after the start line" % f.name)
		if p.s1 > s.length - GRID_REACH:
			_add(Sev.WARNING, at, p.s0, "%s runs into the starting grid" % f.name)
		# Bank keys inside a loop or jump do nothing there (the feature owns
		# the frame); inside a roll they add to it.
		if not f is RollFeature:
			for k in b.keys_of("BankKey"):
				var rel := fposmod(k.distance - p.d0, base.length)
				if rel < p.d1 - p.d0:
					_add(Sev.WARNING, k.global_position, -1.0,
							"%s is inside %s: the feature fades the keyed bank out there" % [k.name, f.name])
		if f is JumpFeature and not (f as JumpFeature).clean_speed_valid():
			_add(Sev.WARNING, at, p.s0, "%s: clean_speed not measured for this shape (run measure_jumps_boot.gd)" % f.name)


func _check_keys(b: TrackBuilder) -> void:
	for k in b.keys_of("BankKey") + b.keys_of("WidthKey") + b.keys_of("StartKey") + b.all_keys_of("BoostPadKey"):
		if k.distance_to_track > KEY_FAR:
			_add(Sev.ERROR, k.global_position, -1.0,
					"%s is %.0f m from the track (limit 30): move it closer or it may attach to the wrong stretch"
					% [k.name, k.distance_to_track])
	var starts := b.keys_of("StartKey")
	if starts.size() > 1:
		_add(Sev.ERROR, starts[1].global_position, -1.0, "%d StartKeys: keep one" % starts.size())


## The bank the game will use (the spline's tilted up) against the bank keyed.
func _check_bank_delivered(b: TrackBuilder, c: Curve3D) -> void:
	_check_bank_delivered_on(b.sampler, c, "")


func _check_bank_delivered_on(s: TrackSampler, c: Curve3D, label: String) -> void:
	var length := c.get_baked_length()
	var worst := 0.0
	var worst_d := 0.0
	var hint := -1.0
	var d := 0.0
	while d < length:
		var f := TrackRoadSegment.frame_at(c, d)
		var pr := s.project(f.origin, hint)
		hint = pr[0]
		var want := s.frame_at(pr[0])
		var err := rad_to_deg(f.basis.y.angle_to(want.basis.y))
		if err > worst:
			worst = err
			worst_d = d
		d += SURFACE_EVERY
	var pre := label + ": " if not label.is_empty() else ""
	stats[pre + "bank delivered"] = "max error %.3f° (limit %.1f)" % [worst, BANK_TOL]
	if worst > BANK_TOL:
		_add(Sev.ERROR, c.sample_baked(worst_d, true), worst_d,
				pre + "Built bank is %.2f° off the keyed bank (tilt solve problem)" % worst)


const JUNCTION_HEIGHT_TOL := 0.15
const JUNCTION_LEVEL_TOL := 1.0

## Split tracks: the junctions flat and level on both paths, and the branch's
## own road checked like the main one.
func _check_branches(b: TrackBuilder, root: Node, space: PhysicsDirectSpaceState3D) -> void:
	var graph := root.get_node_or_null("TrackGraph") as TrackGraph
	var main := root.get_node_or_null("MainSpline") as Path3D
	for bi in b.branches.size():
		var be: TrackBranchEval = b.branches[bi]
		if not be.ok:
			continue
		var sfx := "" if bi == 0 else "_%d" % (bi + 1)
		var bp := root.get_node_or_null("BranchSpline" + sfx) as Path3D
		if bp == null or bp.curve == null:
			_add(Sev.WARNING, be.node.global_position, -1.0, "%s: not built yet (press Build)" % be.node.name)
			continue
		var segs: Array[Node] = [bp]
		for c in bp.get_children():
			segs.append(c)
		for jn: String in ["ForkJunction" + sfx, "RejoinJunction" + sfx]:
			var j := root.get_node_or_null(jn)
			if j:
				segs.append(j)
		_check_offset_rule(root, segs)
		# Junctions flat and level, on both paths.
		for jn: String in ["ForkJunction" + sfx, "RejoinJunction" + sfx]:
			var j := root.get_node_or_null(jn) as TrackJunction
			if j == null or main == null:
				continue
			var y0 := main.curve.sample_baked(j.a_start if j.point_at_start else j.a_end, true).y
			var worst_h := 0.0
			var worst_a := 0.0
			var at := Vector3.ZERO
			for pair: Array in [[main.curve, j.a_start, j.a_end], [bp.curve, j.b_start, j.b_end]]:
				var c: Curve3D = pair[0]
				var d: float = pair[1]
				while d <= pair[2]:
					var f := TrackRoadSegment.frame_at(c, d)
					var h := absf(f.origin.y - y0)
					var a := rad_to_deg(f.basis.y.angle_to(Vector3.UP))
					if h > worst_h:
						worst_h = h
						at = f.origin
					worst_a = maxf(worst_a, a)
					d += 5.0
			stats["%s" % jn] = "height within %.2f m, tilt within %.2f°" % [worst_h, worst_a]
			if worst_h > JUNCTION_HEIGHT_TOL:
				_add(Sev.ERROR, at, -1.0, "%s isn't flat: the roads are %.2f m off its level (limit 0.15): make the curves level there"
						% [jn, worst_h])
			if worst_a > JUNCTION_LEVEL_TOL:
				_add(Sev.ERROR, at, -1.0, "%s isn't level: %.1f° of bank or grade (limit 1)" % [jn, worst_a])
		for p in be.composer.placed:
			if p.node is JumpFeature and not (p.node as JumpFeature).clean_speed_valid():
				_add(Sev.WARNING, be.track.frame_at(p.s0).origin, -1.0,
						"%s: clean_speed not measured for this shape (run measure_jumps_boot.gd)" % p.node.name)
		# The branch's own road.
		_check_bank_delivered_on(be.track, bp.curve, be.node.name)
		if space:
			var skip: Array[Vector2] = []
			var j1 := root.get_node_or_null("ForkJunction" + sfx) as TrackJunction
			var j2 := root.get_node_or_null("RejoinJunction" + sfx) as TrackJunction
			if j1:
				skip.append(Vector2(-1.0, j1.b_end + 1.0))
			if j2:
				skip.append(Vector2(j2.b_start - 1.0, INF))
			if graph:
				for jp in graph.jumps:
					if jp and jp.branch == bi:
						skip.append(Vector2(jp.lip - 0.5, jp.landing + 0.5))
			_surface_rays(bp.curve, bp.get_node_or_null("Road") as TrackRoadSegment, space, skip,
					be.track, be.node.name)


## Ray-casts the road under the spline: centre and 60% out to each side.
func _check_surface(b: TrackBuilder, c: Curve3D, space: PhysicsDirectSpaceState3D) -> void:
	var main := b.owner.get_node("MainSpline") as Path3D if b.owner else null
	var road := main.get_node_or_null("Road") as TrackRoadSegment if main else null
	var skip: Array[Vector2] = []
	var graph := main.get_parent().get_node_or_null("TrackGraph") as TrackGraph if main else null
	if graph:
		for j in graph.jumps:
			if j and j.branch < 0:
				skip.append(Vector2(j.lip - 0.5, j.landing + 0.5))
	var root := main.get_parent() if main else null
	if root:
		for jn in root.get_children():
			if jn is TrackJunction:
				var tj := jn as TrackJunction
				skip.append(Vector2(tj.a_start - 0.5, tj.a_end + 0.5))
	_surface_rays(c, road, space, skip, b.sampler, "")


func _surface_rays(c: Curve3D, road: TrackRoadSegment, space: PhysicsDirectSpaceState3D,
		skip: Array[Vector2], track: TrackSampler, label: String) -> void:
	var length := c.get_baked_length()
	var worst_h := 0.0
	var worst_n := 0.0
	var misses := 0
	var rays := 0
	var bad_h := -1.0
	var bad_n := -1.0
	var bad_n_ratio := 0.0
	var bad_n_val := 0.0
	var worst_n_ratio := 0.0
	var d := 0.0
	while d < length:
		var in_gap := false
		for g in skip:
			if d > g.x and d < g.y:
				in_gap = true
		if in_gap:
			d += SURFACE_EVERY
			continue
		var f := TrackRoadSegment.frame_at(c, d)
		var w := road.width_at(d) if road else Vector2(21.5, 21.5)
		for lat: float in [0.0, -0.6 * (w.x - 2.0), 0.6 * (w.y - 2.0)]:
			var o := f.origin + f.basis.x * lat
			var q := PhysicsRayQueryParameters3D.create(o + f.basis.y * 5.0, o - f.basis.y * 5.0, GROUND_MASK)
			q.hit_back_faces = false
			var hit := space.intersect_ray(q)
			rays += 1
			if hit.is_empty():
				misses += 1
				if misses <= 5:
					_add(Sev.ERROR, o, d, "%sNo road under the spline (%.0f m across)" % [label + ": " if not label.is_empty() else "", lat])
				continue
			var h := absf((hit.position - o).dot(f.basis.y))
			var nerr := rad_to_deg((hit.normal as Vector3).angle_to(_surface_normal(c, d, lat, f)))
			if h > worst_h:
				worst_h = h
				if h > SURFACE_HEIGHT_TOL:
					bad_h = d
			var tol := SURFACE_NORMAL_TOL + SURFACE_FACET_M * track.roll_rate(track.index_at(d))
			if nerr / tol > worst_n_ratio:
				worst_n_ratio = nerr / tol
			if nerr > worst_n:
				worst_n = nerr
			if nerr > tol and (bad_n < 0.0 or nerr / tol >= bad_n_ratio):
				bad_n = d
				bad_n_ratio = nerr / tol
				bad_n_val = nerr
		d += SURFACE_EVERY
	var pre := label + ": " if not label.is_empty() else ""
	if rays > 0 and misses == rays:
		issues = issues.filter(func(i: Dictionary) -> bool: return not (i.msg as String).contains("No road under"))
		_add(Sev.WARNING, c.sample_baked(0.0, true), -1.0,
				"No road found at all: the physics space isn't ready yet (press Validate again)")
		return
	stats[pre + "surface"] = "%d rays, max height error %.3f m, max normal error %.2f° (%.0f%% of its limit), %d misses" % [rays, worst_h, worst_n, worst_n_ratio * 100.0, misses]
	if bad_h >= 0.0:
		_add(Sev.ERROR, c.sample_baked(bad_h, true), bad_h,
				pre + "Road surface %.3f m off the spline (limit 0.05): something moved the geometry" % worst_h)
	if bad_n >= 0.0:
		_add(Sev.ERROR, c.sample_baked(bad_n, true), bad_n,
				pre + "Road normal %.2f° off the ideal surface (limit 0.5° + 4.5 m x roll rate)" % bad_n_val)


## Normal of the ideal extruded road at `lat` metres across. Off the centre
## line it isn't the frame's up: while the bank changes the surface twists
## (a helicoid), tilting fore and aft by about lat x roll rate.
static func _surface_normal(c: Curve3D, d: float, lat: float, f: Transform3D) -> Vector3:
	var length := c.get_baked_length()
	var a := TrackRoadSegment.frame_at(c, clampf(d - 0.5, 0.0, length))
	var b := TrackRoadSegment.frame_at(c, clampf(d + 0.5, 0.0, length))
	var along := (b.origin + b.basis.x * lat) - (a.origin + a.basis.x * lat)
	var n := f.basis.x.cross(along).normalized()
	return n if n.dot(f.basis.y) > 0.0 else -n


## Sample index -> MainSpline distance (the composite's distance; within a
## metre or two of the baked one).
func _main_d(b: TrackBuilder, i: int) -> float:
	return b.sampler.S[i]


# =============================================================================
# STEP 4: RACE CHECKS
# =============================================================================

const LAT_G_WARN := 15.0
const JOLT_WARN := 1.0
const GRADE_WARN := 50.0
const CREST_WARN := 110.0
const CREST_ERROR := 200.0
const REF_SPEED := 110.0
const GAME_G := 25.0
const CLEARANCE := 10.0
const TRACK_MASK := 1 | 4
const JUMP_MARGIN := 5.0
const START_GRADE_WARN := 3.0
const START_LAT_G_WARN := 1.0
## Fork Lab measured that a respawned ship needs 150-220 m of run-up for its
## jumps (the respawn settle and throttle response aren't in the AI's
## acceleration model, which would say ~60 m); the handoff's rule is 250 m.
const RESPAWN_RUNUP_MIN := 250.0
const BRANCH_END_POS_TOL := 0.05
const BRANCH_END_ANGLE_TOL := 0.5

var profile: TrackSpeedProfile


func _check_race(b: TrackBuilder, root: Node, space: PhysicsDirectSpaceState3D) -> void:
	var s := b.sampler
	var skip := _skip_mask(b, s)
	profile = TrackSpeedProfile.new()
	profile.compute(s, TrackSpeedProfile.default_model(), skip)
	var n := s.size()
	var lat := PackedFloat32Array()
	var jolt := PackedFloat32Array()
	var grade := PackedFloat32Array()
	var crest := PackedFloat32Array()
	lat.resize(n)
	jolt.resize(n)
	grade.resize(n)
	crest.resize(n)
	var vsum := 0.0
	for i in n:
		vsum += profile.v[i]
		if skip[i] == 1:
			continue
		var j := (i + 1) % n
		lat[i] = REF_SPEED * REF_SPEED * absf(profile.kg[i]) / GAME_G
		jolt[i] = REF_SPEED * REF_SPEED * absf(profile.kg[j] - profile.kg[i]) / GAME_G / s.step()
		grade[i] = absf(s.grade(i))
		crest[i] = profile.v[i] * profile.v[i] * maxf(-profile.kn[i], 0.0)
	for j in _worst_of_runs(lat, LAT_G_WARN, true):
		_add(Sev.WARNING, s.P[j], s.S[j], "Corner of %.1f g at 110 u/s (radius %.0f m): tighter than 99%% of the circuits' corners"
				% [lat[j], 1.0 / maxf(absf(profile.kg[j]), 1e-6)])
	for j in _worst_of_runs(jolt, JOLT_WARN, true):
		_add(Sev.WARNING, s.P[j], s.S[j], "Kink: the curvature jumps %.2f g per metre (limit 1.0): smooth the handles or raise fairing_m" % jolt[j])
	for j in _worst_of_runs(grade, GRADE_WARN, true):
		_add(Sev.WARNING, s.P[j], s.S[j], "Grade %.0f%% (limit 50)" % grade[j])
	for j in _worst_of_runs(crest, CREST_WARN, true):
		var sev := Sev.ERROR if crest[j] > CREST_ERROR else Sev.WARNING
		_add(sev, s.P[j], s.S[j], "Crest: at ~%.0f u/s it needs %.0f u/s² to hold the road (%s): %s"
				% [profile.v[j], crest[j], "a launch" if sev == Sev.ERROR else "more than any circuit asks",
				"soften it or make it a jump" if sev == Sev.ERROR else "drive it"])
	stats["estimated lap"] = "%.1f s at %.0f u/s mean (default_racer, AI limits)" % [s.length / (vsum / n), vsum / n]
	stats["race limits"] = "max %.1f g at 110 (@%.0f m), kinks %.2f g/m (@%.0f m), grade %.0f%% (@%.0f m), crest %.0f u/s² (@%.0f m)" % [
			_max(lat), s.S[_argmax(lat)], _max(jolt), s.S[_argmax(jolt)], _max(grade), s.S[_argmax(grade)],
			_max(crest), s.S[_argmax(crest)]]
	_check_jumps(b, s, profile, root)
	_check_pad_boosts(b, s, profile)
	_check_start(b, root, s)
	_check_junction_widths(b)
	_check_branch_ends(b, root)
	if space:
		var skip_gaps: Array[Vector2] = []
		var graph := root.get_node_or_null("TrackGraph") as TrackGraph
		var main := root.get_node_or_null("MainSpline") as Path3D
		if graph:
			for jp in graph.jumps:
				if jp and jp.branch < 0:
					skip_gaps.append(Vector2(jp.lip - 1.0, jp.landing + 1.0))
		if main:
			_clearance(main.curve, main.get_node_or_null("Road") as TrackRoadSegment, space, skip_gaps, "")
		for bi in b.branches.size():
			var sfx := "" if bi == 0 else "_%d" % (bi + 1)
			var bp := root.get_node_or_null("BranchSpline" + sfx) as Path3D
			if bp == null:
				continue
			var gaps: Array[Vector2] = []
			if graph:
				for jp in graph.jumps:
					if jp and jp.branch == bi:
						gaps.append(Vector2(jp.lip - 1.0, jp.landing + 1.0))
			_clearance(bp.curve, bp.get_node_or_null("Road") as TrackRoadSegment, space, gaps, b.branches[bi].node.name)


## 1 where the race limits don't apply: magnetic zones (loops, rolls) and
## jumps (the kicker's and landing's bend is designed).
func _skip_mask(b: TrackBuilder, s: TrackSampler) -> PackedByteArray:
	var m := PackedByteArray()
	m.resize(s.size())
	for i in s.size():
		var f := s.feat[i]
		if f >= 0:
			m[i] = 1
	return m


func _check_jumps(b: TrackBuilder, s: TrackSampler, sp: TrackSpeedProfile, root: Node) -> void:
	var jobs: Array = []    # [JumpFeature, marks, speed at lip, on branch]
	for p in b.composer.placed:
		if p.node is JumpFeature:
			jobs.append([p.node, p.marks, sp.v[s.index_at(p.marks.lip)], false, s.frame_at(p.marks.lip).origin])
	for be in b.branches:
		if not be.ok:
			continue
		var bsp := TrackSpeedProfile.new()
		bsp.compute_open(be.track, sp.model, _skip_mask_branch(be), sp.v[s.index_at(be.s_fork)])
		for p in be.composer.placed:
			if p.node is JumpFeature:
				jobs.append([p.node, p.marks, bsp.v[be.track.index_at(p.marks.lip)], true,
						be.track.frame_at(p.marks.lip).origin])
	for jb in jobs:
		var jf: JumpFeature = jb[0]
		var marks: Dictionary = jb[1]
		var v_lip: float = jb[2]
		var branch: bool = jb[3]
		var at: Vector3 = jb[4]
		if jf.clean_speed <= 0.0:
			continue
		stats[jf.name] = "racing speed at the lip ~%.0f u/s, clean from %.0f" % [v_lip, jf.clean_speed]
		if v_lip < jf.clean_speed + JUMP_MARGIN:
			_add(Sev.WARNING if branch else Sev.ERROR, at, marks.lip,
					"%s: racing speed at the lip is only ~%.0f u/s, it needs %.0f (+%.0f margin)%s"
					% [jf.name, v_lip, jf.clean_speed, JUMP_MARGIN, ": the AI will avoid the route" if branch else ""])
		if jf.respawn_runup < RESPAWN_RUNUP_MIN:
			_add(Sev.WARNING, at, marks.lip, "%s: respawn_runup %.0f m is under %.0f m (measured on Fork Lab: a respawned ship needs 150-220 m)"
					% [jf.name, jf.respawn_runup, RESPAWN_RUNUP_MIN])
		# From a respawn: the run-up with no respawn points, plus the kicker.
		var run: float = jf.respawn_runup + (marks.lip - marks.kicker)
		var v_ss := sp.standing_start(run)
		if v_ss < jf.clean_speed:
			var need := run
			while sp.standing_start(need) < jf.clean_speed and need < 3000.0:
				need += 10.0
			_add(Sev.ERROR, at, marks.lip, "%s: after a respawn a ship only reaches %.0f u/s by the lip (needs %.0f): set respawn_runup to %.0f m or more"
					% [jf.name, v_ss, jf.clean_speed, need - (marks.lip - marks.kicker)])


func _skip_mask_branch(be: TrackBranchEval) -> PackedByteArray:
	var m := PackedByteArray()
	m.resize(be.track.size())
	for i in be.track.size():
		m[i] = 1 if be.track.feat[i] >= 0 else 0
	return m


func _check_start(b: TrackBuilder, root: Node, s: TrackSampler) -> void:
	# The grid reaches about 200 m behind the line; check to 50 m past it.
	var worst_grade := 0.0
	var worst_g := 0.0
	var d := -GRID_REACH
	while d <= 50.0:
		var i := s.index_at(fposmod(b.start_lead + d, s.length))
		worst_grade = maxf(worst_grade, absf(s.grade(i)))
		worst_g = maxf(worst_g, REF_SPEED * REF_SPEED * absf(profile.kg[i]) / GAME_G)
		if s.feat[i] >= 0:
			_add(Sev.WARNING, s.P[i], s.S[i], "The start line or grid is on a feature")
			break
		d += 5.0
	var line_at := s.frame_at(b.start_lead).origin
	stats["start"] = "grid area grade %.1f%%, %.1f g at 110" % [worst_grade, worst_g]
	if worst_grade > START_GRADE_WARN:
		_add(Sev.WARNING, line_at, b.start_lead, "The grid is on a %.1f%% slope (limit 3): ships roll on the start" % worst_grade)
	if worst_g > START_LAT_G_WARN:
		_add(Sev.WARNING, line_at, b.start_lead, "The grid is on a bend (%.1f g at 110): put the StartKey on a straight" % worst_g)
	var grid := root.find_child("StartingGrid", true, false)
	if grid == null:
		return
	var space := (root as Node3D).get_world_3d().direct_space_state if root is Node3D and root.is_inside_tree() else null
	for slot in grid.get_children():
		if not slot is Node3D:
			continue
		var p := (slot as Node3D).global_position
		var up := (slot as Node3D).global_basis.y.normalized()
		if space:
			var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(p, p - up * 8.0, GROUND_MASK))
			if hit.is_empty():
				_add(Sev.ERROR, p, -1.0, "Grid %s isn't over the road (the road is too narrow there?)" % slot.name)


func _check_junction_widths(b: TrackBuilder) -> void:
	var s := b.sampler
	for be in b.branches:
		if not be.ok:
			continue
		for span: Vector2 in [Vector2(be.s_fork, be.jf_m), Vector2(be.jr_m, be.s_rejoin)]:
			var d := span.x
			while d <= span.y:
				var i := s.index_at(d)
				if absf(s.width_l[i] - TrackSampler.DEFAULT_HALF_WIDTH) > 0.1 or absf(s.width_r[i] - TrackSampler.DEFAULT_HALF_WIDTH) > 0.1:
					_add(Sev.ERROR, s.P[i], d, "%s: the main road isn't the standard width in a junction (WidthKeys there)" % be.node.name)
					break
				d += 5.0
		for p in b.composer.placed:
			for span: Vector2 in [Vector2(be.s_fork - 60.0, be.jf_m + 60.0), Vector2(be.jr_m - 60.0, be.s_rejoin + 60.0)]:
				if p.s0 < span.y and p.s1 > span.x:
					_add(Sev.WARNING, s.frame_at(p.s0).origin, p.s0,
							"%s overlaps %s's junction: the junction levels the road under it" % [p.node.name, be.node.name])


func _check_branch_ends(b: TrackBuilder, root: Node) -> void:
	var graph := root.get_node_or_null("TrackGraph") as TrackGraph
	var main := root.get_node_or_null("MainSpline") as Path3D
	if graph == null or main == null:
		return
	for bi in graph.branches.size():
		var tb: TrackBranch = graph.branches[bi]
		var bp := graph.get_node_or_null(tb.path) as Path3D
		if bp == null:
			continue
		var bl := bp.curve.get_baked_length()
		for end: Array in [[tb.fork_distance, 0.0, "fork"], [tb.rejoin_distance, bl, "rejoin"]]:
			var fm := TrackRoadSegment.frame_at(main.curve, end[0])
			var fb := TrackRoadSegment.frame_at(bp.curve, end[1])
			var dp := fm.origin.distance_to(fb.origin)
			var da := rad_to_deg(fm.basis.z.angle_to(fb.basis.z))
			stats["%s %s" % [tb.branch_name, end[2]]] = "%.3f m, %.2f°" % [dp, da]
			if dp > BRANCH_END_POS_TOL or da > BRANCH_END_ANGLE_TOL:
				_add(Sev.ERROR, fb.origin, -1.0, "%s: the branch's %s end is %.2f m / %.1f° off the main spline (limit 0.05 m / 0.5°)"
						% [tb.branch_name, end[2], dp, da])


## Nothing of this track within CLEARANCE above its road (overhangs, the loop
## exit over its entry, crossings).
func _clearance(c: Curve3D, road: TrackRoadSegment, space: PhysicsDirectSpaceState3D,
		skip: Array[Vector2], label: String) -> void:
	var length := c.get_baked_length()
	var pre := label + ": " if not label.is_empty() else ""
	var worst := INF
	var worst_at := -1.0
	var d := 0.0
	while d < length:
		var in_gap := false
		for g in skip:
			if d > g.x and d < g.y:
				in_gap = true
		if not in_gap:
			var f := TrackRoadSegment.frame_at(c, d)
			var w := road.width_at(d) if road else Vector2(21.5, 21.5)
			for lat: float in [0.0, -0.6 * (w.x - 2.0), 0.6 * (w.y - 2.0)]:
				var o := f.origin + f.basis.x * lat + f.basis.y * 0.5
				var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(o, o + f.basis.y * CLEARANCE, TRACK_MASK))
				if hit.is_empty() or not _is_track_geometry(hit.collider):
					continue
				var h: float = ((hit.position as Vector3) - o).length() + 0.5
				if h < worst:
					worst = h
					worst_at = d
		d += SURFACE_EVERY
	if worst_at >= 0.0:
		_add(Sev.ERROR, c.sample_baked(worst_at, true), worst_at,
				pre + "Only %.1f m of clearance above the road (limit %.0f): another part of the track is overhead" % [worst, CLEARANCE])
	stats[pre + "clearance"] = "nothing within %.0f m overhead" % CLEARANCE if worst_at < 0.0 else "min %.1f m" % worst


static func _is_track_geometry(o: Object) -> bool:
	var n := o as Node
	while n:
		if n is TrackRoadSegment or n is TrackJunction:
			return true
		n = n.get_parent()
	return false


# =============================================================================
# RESPAWNS (headless: the respawn manager isn't a tool script)
# =============================================================================

## Builds the real TrackRespawnManager on the scene and checks its points:
## every point over road, and the largest gap between points that isn't a
## designed exclusion (magnetic zones, jump run-ups and flights).
func check_respawns(scene: Node) -> void:
	var rm := TrackRespawnManager.new()
	rm.debug_print = false
	scene.add_child(rm)
	var ok: bool = await rm.initialize(scene)
	if not ok:
		_add(Sev.WARNING, Vector3.ZERO, -1.0, "Respawn manager didn't initialise: respawns not checked")
		rm.queue_free()
		return
	var space := (scene as Node3D).get_world_3d().direct_space_state
	var by_path := {}
	var bad := 0
	for p in rm.respawn_points:
		var up := p.rotation.y.normalized()
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(p.position + up * 1.0, p.position - up * 10.0, GROUND_MASK))
		if hit.is_empty():
			bad += 1
			if bad <= 5:
				_add(Sev.ERROR, p.position, p.path_distance, "Respawn point with no road under it (path %d)" % p.path)
		var key: int = p.path
		if not by_path.has(key):
			by_path[key] = PackedFloat32Array()
		var arr: PackedFloat32Array = by_path[key]
		arr.append(p.path_distance)
		by_path[key] = arr
	var graph := scene.get_node_or_null("TrackGraph") as TrackGraph
	var mt := scene.get_node_or_null("MagneticTrack") as MagneticTrack
	var worst := 0.0
	var worst_txt := ""
	for key in by_path:
		var arr: PackedFloat32Array = by_path[key]
		arr.sort()
		for i in range(1, arr.size()):
			var a := arr[i - 1]
			var bb := arr[i]
			if bb - a <= rm.respawn_point_spacing * 2.0 + 1.0:
				continue
			if _gap_explained(key, a, bb, graph, mt):
				continue
			if bb - a > worst:
				worst = bb - a
				worst_txt = "path %d, %.0f-%.0f m" % [key, a, bb]
	stats["respawns"] = "%d points, %d over no road, largest unexplained gap %s" % [rm.respawn_points.size(), bad,
			"none" if worst == 0.0 else "%.0f m (%s)" % [worst, worst_txt]]
	if worst > 0.0:
		_add(Sev.WARNING, Vector3.ZERO, -1.0, "A %.0f m stretch with no respawn points (%s)" % [worst, worst_txt])
	rm.queue_free()


static func _gap_explained(path: int, a: float, b: float, graph: TrackGraph, mt: MagneticTrack) -> bool:
	var mid := (a + b) * 0.5
	if path < 0 and mt:
		for z in mt.zones:
			if z and mid > z.start_distance - z.ramp_in - 60.0 and mid < z.end_distance + z.ramp_out + 60.0:
				return true
	if graph:
		for j in graph.jumps:
			if j and j.branch == path and mid > j.kicker_start - j.respawn_runup - 60.0 and mid < j.landing_end + 60.0:
				return true
	return false


# =============================================================================
# BOOST PADS (v34)
# =============================================================================

## A pad's ends may sit this far off the road (a flat 12 m pad on a crest or
## in a dip): beyond it the pad is visibly buried or floating.
const PAD_SURFACE_TOL := 0.2
## measure_jumps' default sweep tops out at 120 u/s (default_racer's top
## speed): landings faster than that haven't been flown.
const JUMP_MEASURED_TO := 120.0
## How far after a pad the boost is followed (it's gone in ~300 m at +150).
const PAD_REACH := 400.0

func _check_pads(b: TrackBuilder) -> void:
	var pads := b.pad_placements()
	if pads.is_empty():
		return
	var hl := BoostPadKey.PAD_HALF_LENGTH
	var hw := BoostPadKey.PAD_HALF_WIDTH
	var strongest := 0.0
	for p in pads:
		var ts: TrackSampler = p.track
		var key: BoostPadKey = p.key
		var sd: float = p.s
		var x: float = p.x
		var at := _pad_pos(p)
		strongest = maxf(strongest, key.strength)
		# On the flat road (inside the lip), at both ends and the middle.
		var over := -INF
		for e: float in [-hl, 0.0, hl]:
			var j := ts.index_at(clampf(sd + e, 0.0, ts.length) if not ts.closed else sd + e)
			over = maxf(over, maxf((x + hw) - (ts.width_r[j] - BoostPadKey.LIP),
					-(x - hw) - (ts.width_l[j] - BoostPadKey.LIP)))
		if over > 0.01:
			_add(Sev.ERROR, at, _pad_d(b, p), "%s: %.1f m over the edge of the road: move it in, or fewer pads or less spacing"
					% [_pad_name(p), over])
		# Jumps on the same road.
		for q in _placed_of(b, p.branch):
			if not q.node is JumpFeature:
				continue
			var m: Dictionary = q.marks
			if sd + hl > m.lip and sd - hl < m.landing:
				_add(Sev.ERROR, at, _pad_d(b, p), "%s is over %s's gap" % [_pad_name(p), q.node.name])
			elif sd + hl > m.kicker and sd - hl < m.lip:
				_add(Sev.WARNING, at, _pad_d(b, p), "%s is on %s's kicker: it changes the take-off (clean_speed is measured without a pad)"
						% [_pad_name(p), q.node.name])
		# The grid: about GRID_REACH behind the line.
		if p.branch < 0:
			var rel := ts.delta(b.start_lead, sd)
			if rel > -(GRID_REACH + hl) and rel < hl:
				_add(Sev.WARNING, at, _pad_d(b, p), "%s is on the starting grid: ships start on or just behind it" % _pad_name(p))
	# Overlaps (same road).
	for i in pads.size():
		for k in range(i + 1, pads.size()):
			var a: Dictionary = pads[i]
			var c: Dictionary = pads[k]
			if a.branch != c.branch:
				continue
			if absf((a.track as TrackSampler).delta(a.s, c.s)) < 2.0 * hl and absf(float(a.x) - float(c.x)) < 2.0 * hw - 0.01:
				_add(Sev.ERROR, _pad_pos(a), _pad_d(b, a), "%s and %s overlap" % [_pad_name(a), _pad_name(c)])
	stats["boost pads"] = "%d, strongest +%.0f u/s" % [pads.size(), strongest]


## The built pads: road under every corner, and the pad lying on it.
func _check_pads_built(b: TrackBuilder, root: Node, space: PhysicsDirectSpaceState3D) -> void:
	var pads := b.pad_placements()
	if pads.is_empty() or space == null or root == null:
		return
	var holder := root.get_node_or_null("BoostPads")
	var built := 0
	if holder:
		for c in holder.get_children():
			if c.is_in_group(TrackBuild.GROUP):
				built += 1
	if built != pads.size():
		_add(Sev.WARNING, b.global_position, -1.0, "%d boost pads placed but %d built: press Build" % [pads.size(), built])
		return
	var hl := BoostPadKey.PAD_HALF_LENGTH
	var hw := BoostPadKey.PAD_HALF_WIDTH
	var worst := 0.0
	for c in holder.get_children():
		if not c is Node3D or not c.is_in_group(TrackBuild.GROUP):
			continue
		var t := (c as Node3D).global_transform
		var up := t.basis.y.normalized()
		var off_road := false
		var dev := 0.0
		for corner: Vector3 in [Vector3(-hw, 0, -hl), Vector3(hw, 0, -hl), Vector3(hw, 0, hl), Vector3(-hw, 0, hl), Vector3.ZERO]:
			var q := t * corner
			var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(q + up * 3.0, q - up * 3.0, GROUND_MASK))
			if hit.is_empty():
				off_road = true
				continue
			dev = maxf(dev, absf((q - (hit.position as Vector3)).dot(up)))
		worst = maxf(worst, dev)
		if off_road:
			_add(Sev.ERROR, t.origin, -1.0, "%s: no road under part of it" % c.name)
		elif dev > PAD_SURFACE_TOL:
			_add(Sev.WARNING, t.origin, -1.0, "%s: an end sits %.2f m off the road (a tight crest or dip): move it to flatter road"
					% [c.name, dev])
	stats["boost pads on the road"] = "within %.2f m" % worst


## What the boost does next: the speed a ship carries away from each pad at
## full throttle (no braking) against the corners, crests and jump lips ahead.
func _check_pad_boosts(b: TrackBuilder, s: TrackSampler, sp: TrackSpeedProfile) -> void:
	var pads := b.pad_placements()
	if pads.is_empty():
		return
	var damping := TrackSpeedProfile.default_profile().overspeed_damping
	var branch_sp := {}
	var seen := {}
	var main_skip := _skip_mask(b, s)
	for p in pads:
		var key: BoostPadKey = p.key
		# One check per key (its pads are side by side: the same speeds).
		var id := key.get_instance_id()
		if seen.has(id):
			continue
		seen[id] = true
		var ts: TrackSampler = p.track
		var prof := sp
		var skip := main_skip
		if p.branch >= 0:
			var be: TrackBranchEval = b.branches[p.branch]
			if not branch_sp.has(p.branch):
				var bsp := TrackSpeedProfile.new()
				bsp.compute_open(be.track, sp.model, _skip_mask_branch(be), sp.v[s.index_at(be.s_fork)])
				branch_sp[p.branch] = bsp
			prof = branch_sp[p.branch]
			skip = _skip_mask_branch(be)
		var sd: float = p.s
		var step := ts.step()
		var n := int(PAD_REACH / step)
		var v0 := prof.v[ts.index_at(sd)]
		var vb := prof.boosted(v0, key.strength, damping, step, n)
		var label: String = String(key.name) if key.count == 1 else "%s (%d pads)" % [key.name, key.count]
		var corner_done := false
		var crest_done := false
		for k in n:
			var d := sd + k * step
			if not ts.closed and d > ts.length:
				break
			var j := ts.index_at(d)
			if vb[k] <= prof.v[j] + 1.0:
				break      # the boost is spent
			if skip[j] == 1:
				continue   # loops, rolls, jumps: checked below / by design
			if not corner_done and absf(prof.kg[j]) > 1e-4:
				var hold := _corner_speed_uncapped(prof.model, absf(prof.kg[j]))
				if vb[k] > hold + 2.0:
					corner_done = true
					_add(Sev.WARNING, ts.P[j], _track_d(b, p.branch, d), "%s: the boost carries ~%.0f u/s into the bend %.0f m on, where default_racer can hold ~%.0f: ships brake it away or run wide"
							% [label, vb[k], k * step, hold])
			var crest := vb[k] * vb[k] * maxf(-prof.kn[j], 0.0)
			if not crest_done and crest > CREST_WARN:
				crest_done = true
				var sev := Sev.ERROR if crest > CREST_ERROR else Sev.WARNING
				_add(sev, ts.P[j], _track_d(b, p.branch, d), "%s: boosted to ~%.0f u/s, the crest %.0f m on needs %.0f u/s² to hold the road (%s)"
						% [label, vb[k], k * step, crest, "a launch" if sev == Sev.ERROR else "more than any circuit asks"])
		for q in _placed_of(b, p.branch):
			if not q.node is JumpFeature:
				continue
			var ahead := ts.delta(sd, q.marks.lip) if ts.closed else float(q.marks.lip) - sd
			if ahead <= 0.0 or ahead >= n * step:
				continue
			var v_lip := vb[int(ahead / step)]
			if v_lip > JUMP_MEASURED_TO + 1.0 and v_lip > prof.v[ts.index_at(q.marks.lip)] + 1.0:
				_add(Sev.WARNING, ts.P[ts.index_at(q.marks.lip)], _track_d(b, p.branch, q.marks.lip),
						"%s: the boost carries ~%.0f u/s to %s's lip; landings are only measured up to %.0f"
						% [label, v_lip, q.node.name, JUMP_MEASURED_TO])


## The fastest default_racer can hold a curvature `kappa`, without the cap at
## its top speed that ShipPerformanceModel.corner_speed() applies (a boosted
## ship is over it): where speed x curvature = the yaw rate it can make
## (steering + cornering airbrake), and the grip bound, as corner_speed().
static func _corner_speed_uncapped(m: ShipPerformanceModel, kappa: float) -> float:
	var lo := 5.0
	var hi := 2000.0
	for i in 40:
		var mid := (lo + hi) * 0.5
		if mid * kappa < m.max_yaw_rate(mid):
			lo = mid
		else:
			hi = mid
	var v_grip := m.grip * ShipPerformanceModel.GRIP_ROTATION_MARGIN / kappa
	return minf(lo, v_grip) * m.cornering_confidence


func _placed_of(b: TrackBuilder, branch: int) -> Array:
	return b.composer.placed if branch < 0 else b.branches[branch].composer.placed


func _pad_pos(p: Dictionary) -> Vector3:
	var f: Transform3D = (p.track as TrackSampler).frame_at(p.s)
	return f.origin + f.basis.x * float(p.x)


func _pad_name(p: Dictionary) -> String:
	var key: BoostPadKey = p.key
	return String(key.name) if key.count == 1 else "%s pad %d" % [key.name, int(p.i) + 1]


func _pad_d(b: TrackBuilder, p: Dictionary) -> float:
	return _track_d(b, p.branch, p.s)


## Distance shown in messages: main lap metres, or -1 on a branch (its own).
func _track_d(_b: TrackBuilder, branch: int, d: float) -> float:
	return d if branch < 0 else -1.0


# =============================================================================
# GREEBLES (v36)
# =============================================================================

const GREEBLE_KEY_TWIN := 2.0

func _check_greebles(b: TrackBuilder, root: Node) -> void:
	var keys := TrackGreebler.all_keys(b)
	var node := root.get_node_or_null(TrackBuilder.GREEBLES_NODE) as TrackGreebles if root else null
	if keys.is_empty():
		if node:
			_add(Sev.WARNING, node.global_position, -1.0,
					"TrackGreebles is left from an earlier build but there are no GreebleZoneKeys: press Build")
		return
	var g := TrackGreebler.resolve(b, root)
	if not g.ok():
		_add(Sev.WARNING, keys[0].global_position, -1.0, "Greebles: " + "; ".join(g.notes))
		return
	for n in g.notes:
		_add(Sev.WARNING, b.global_position, -1.0, "Greebles: " + n)
	for i in keys.size():
		var k := keys[i]
		if k.distance_to_track > TrackGreebler.KEY_FAR:
			_add(Sev.ERROR, k.global_position, k.distance,
					"%s is %.0f m from the track (limit 30): move it closer or it may attach to the wrong stretch"
					% [k.name, k.distance_to_track])
		for j in range(i + 1, keys.size()):
			var o := keys[j]
			if _branch_of(k) == _branch_of(o) and absf(o.distance - k.distance) < GREEBLE_KEY_TWIN:
				_add(Sev.WARNING, k.global_position, k.distance,
						"%s and %s start zones within %.0f m of each other: one of them does nothing"
						% [k.name, o.name, GREEBLE_KEY_TWIN])
		if k.style and _usable_rules(k.style) == 0 and k.style.threshold_mesh == null:
			_add(Sev.WARNING, k.global_position, k.distance,
					"%s: style '%s' has no enabled rule with a mesh" % [k.name, k.style.style_name])
	if node == null:
		_add(Sev.WARNING, keys[0].global_position, -1.0, "Greebles not built yet: press Build (or Refresh greebles)")
		return
	if TrackGreebler.signature_of(node) != g.signature():
		_add(Sev.WARNING, node.global_position, -1.0,
				"Greebles are out of date: the GreebleZoneKeys changed since they were written (press Build or Refresh greebles)")
	var pl := node.placements()
	stats["greebles"] = "%d zones, %d instances, %d left out past their upright limit" % [
			node.zones.size(), pl.size(), node.skipped_upright]
	for it in node.intrusions(pl):
		var z: TrackGreebleZone = node.zones[it.zi]
		var piece := "threshold" if it.ri < 0 else _rule_label(z.style.rules[it.ri])
		_add(Sev.WARNING, it.pos, it.d, "Greebles %s (%s): %s %s%s"
				% [z.label, z.style.style_name, piece, it.what, " (×%d)" % it.count if it.count > 1 else ""])


func _check_surface_zones(b: TrackBuilder, root: Node) -> void:
	var keys := TrackSurfacer.all_keys(b)
	var node := root.get_node_or_null(TrackBuilder.SURFACE_NODE) as TrackSurface if root else null
	if not TrackSurfacer.has_keys(b):
		if node:
			_add(Sev.WARNING, b.global_position, -1.0,
					"TrackSurface is left from an earlier build but there are no SurfaceZoneKeys: press Build")
		return
	var sf := TrackSurfacer.resolve(b, root)
	if not sf.ok():
		_add(Sev.WARNING, b.global_position, -1.0, "Surface: " + "; ".join(sf.notes))
		return
	_check_decals(sf)
	for n in sf.notes:
		_add(Sev.WARNING, b.global_position, -1.0, "Surface: " + n)
	var seen := {}
	for i in keys.size():
		var k := keys[i]
		if k.distance_to_track > TrackGreebler.KEY_FAR:
			_add(Sev.ERROR, k.global_position, k.distance,
					"%s is %.0f m from the track (limit 30): move it closer or it may attach to the wrong stretch"
					% [k.name, k.distance_to_track])
		for j in range(i + 1, keys.size()):
			var o := keys[j]
			if _branch_of(k) == _branch_of(o) and absf(o.distance - k.distance) < GREEBLE_KEY_TWIN:
				_add(Sev.WARNING, k.global_position, k.distance,
						"%s and %s start zones within %.0f m of each other: one of them does nothing"
						% [k.name, o.name, GREEBLE_KEY_TWIN])
		if k.profile and not seen.has(k.profile):
			seen[k.profile] = true
			for pr in k.profile.problems():
				_add(Sev.WARNING, k.global_position, k.distance,
						"%s: profile '%s': %s" % [k.name, k.profile.profile_name, pr])
	var per := sf.profiles_per_path()
	for pi in per:
		if int(per[pi]) > TrackSurface.MAX_PROFILES:
			_add(Sev.ERROR, keys[0].global_position, -1.0,
					"Surface: %d different profiles on %s (max %d): the extra ones draw as the first"
					% [per[pi], sf.paths[pi], TrackSurface.MAX_PROFILES])
	if node == null:
		_add(Sev.WARNING, b.global_position, -1.0,
				"Surface zones not built yet: press Build (or Refresh surface)")
		return
	if node.signature() != sf.signature(b):
		_add(Sev.WARNING, b.global_position, -1.0,
				"Surface zones are out of date: the SurfaceZoneKeys changed since they were written (press Build or Refresh surface)")
	stats["surface"] = "%d zones, %s" % [node.zones.size(),
			", ".join(per.keys().map(func(pi): return "%s: %d profiles" % [sf.paths[pi], per[pi]]))]


## v38 phase 5: decal keys near the track, with text their font can draw.
func _check_decals(sf: TrackSurfacer) -> void:
	var glyphs := load(TrackSurface.GLYPHS) as TrackSurfaceGlyphs
	for dd in sf.decals:
		var k: SurfaceDecalKey = dd.key
		if k.distance_to_track > TrackGreebler.KEY_FAR:
			_add(Sev.ERROR, k.global_position, k.distance,
					"%s is %.0f m from the track (limit 30): move it closer or it may attach to the wrong stretch"
					% [k.name, k.distance_to_track])
		if k.shape != TrackSurfaceDecal.Shape.TEXT or glyphs == null:
			continue
		var missing := PackedStringArray()
		for ch in TrackSurface.decal_text(k.text, k.role, 0):
			if ch != " " and ch != "#" and not glyphs.has_glyph(k.role, ch.unicode_at(0)) and not missing.has(ch):
				missing.append(ch)
		if not missing.is_empty():
			_add(Sev.WARNING, k.global_position, k.distance, "%s: %s can't draw '%s' (left out)" % [
					k.name, TrackSurfaceDecal.Role.keys()[k.role], "".join(missing)])
		if k.text.strip_edges().is_empty():
			_add(Sev.WARNING, k.global_position, k.distance, "%s has no text" % k.name)


static func _usable_rules(st: UtopiaGreebleStyle) -> int:
	var n := 0
	for r in st.rules:
		if r and r.enabled and r.mesh:
			n += 1
	return n


static func _rule_label(r: UtopiaGreebleRule) -> String:
	var mn := r.mesh.resource_path.get_file().get_basename().trim_prefix("gb_") if r.mesh.resource_path else "mesh"
	return "%s %s" % [r.layer, mn]


## The BranchFeature a key belongs to (null = the main track).
static func _branch_of(n: Node) -> Node:
	var p := n.get_parent()
	while p:
		if p is BranchFeature:
			return p
		if p is TrackBuilder:
			return null
		p = p.get_parent()
	return null
