@tool
extends Node
class_name TrackGraph

## Forks and jumps for a track (v31).
##
## The MainSpline stays the canonical lap. Branches are extra Path3Ds that
## leave and rejoin it (TrackBranch); jumps are gaps in the road on any path
## (TrackJump). Everything that measures lap progress keeps working in MAIN
## distance: `locate()` finds which path a position is on and maps branch
## distance onto main distance.
##
## Found through the "track_graph" group (ships) or by searching the track
## (TrackSplineHelper, TrackRespawnManager). Tracks without one behave exactly
## as before.

const GROUP := "track_graph"

@export var main_path: NodePath = NodePath("../MainSpline")
@export var branches: Array[TrackBranch] = []
@export var jumps: Array[TrackJump] = []

var _main: Path3D
var _main_len := 0.0
var _branch_paths: Array[Path3D] = []
var _branch_lens: PackedFloat64Array = PackedFloat64Array()


func _enter_tree() -> void:
	add_to_group(GROUP)


func _ready() -> void:
	_resolve()


func _resolve() -> bool:
	if _main and is_instance_valid(_main) and _branch_paths.size() == branches.size():
		return true
	_main = get_node_or_null(main_path) as Path3D
	if _main == null or _main.curve == null:
		return false
	_main_len = _main.curve.get_baked_length()
	_branch_paths.clear()
	_branch_lens.clear()
	for b in branches:
		var p := get_node_or_null(b.path) as Path3D if b else null
		_branch_paths.append(p)
		_branch_lens.append(p.curve.get_baked_length() if p and p.curve else 0.0)
	return _main_len > 0.0


func is_valid() -> bool:
	return _resolve()


func has_branches() -> bool:
	return not branches.is_empty() and _resolve()


func main_length() -> float:
	_resolve()
	return _main_len


## -1 = MainSpline.
func path_of(index: int) -> Path3D:
	_resolve()
	return _main if index < 0 else _branch_paths[index]


func path_length(index: int) -> float:
	_resolve()
	return _main_len if index < 0 else _branch_lens[index]


## Global-space road frame on path `index` at `d`: basis.x = right, basis.y =
## tilted up, -basis.z = direction of travel.
func frame_at(index: int, d: float) -> Transform3D:
	var p := path_of(index)
	return p.global_transform * TrackRoadSegment.frame_at(p.curve, d)


## Main-lap distance for `b` metres along branch `index` (see TrackBranch).
func branch_to_main(index: int, b: float) -> float:
	_resolve()
	var br := branches[index]
	var lb := _branch_lens[index]
	var tabs: Array = _tables(index)
	var fork_tab: PackedFloat64Array = tabs[0]
	var rej_tab: PackedFloat64Array = tabs[1]
	var j0 := float(fork_tab.size() - 1)
	var j1 := float(rej_tab.size() - 1)
	var rejoin := _unwrapped_rejoin(br)
	var m: float
	if b <= j0:
		m = br.fork_distance + _lerp_tab(fork_tab, b)
	elif b >= lb - j1:
		m = rejoin - _lerp_tab(rej_tab, lb - b)
	else:
		var m0 := br.fork_distance + fork_tab[fork_tab.size() - 1]
		var m1 := rejoin - rej_tab[rej_tab.size() - 1]
		m = lerpf(m0, m1, (b - j0) / maxf(lb - j0 - j1, 0.001))
	return fposmod(m, _main_len)


func _unwrapped_rejoin(br: TrackBranch) -> float:
	return br.rejoin_distance if br.rejoin_distance >= br.fork_distance \
			else br.rejoin_distance + _main_len


static func _lerp_tab(tab: PackedFloat64Array, x: float) -> float:
	var i := clampi(int(floor(x)), 0, tab.size() - 2)
	return lerpf(tab[i], tab[i + 1], clampf(x - i, 0.0, 1.0))


## Junction correspondence tables for a branch, cached. In a junction the
## two roads overlap and a ship can be nearer either centre line, so branch
## metre b is mapped to the main distance that a position EQUIDISTANT from
## both centre lines (on the branch's normal through b) gets from the main
## line. On that medial line both answers agree exactly, so the nearest-path
## choice can flip there without moving the progress; elsewhere in the
## junction the nearer line is unambiguous. Fork table: index = branch metres
## from the fork, value = main metres from the fork. Rejoin table: index =
## branch metres before the rejoin, value = main metres before it.
var _tab_cache := {}

func _tables(index: int) -> Array:
	if _tab_cache.has(index):
		return _tab_cache[index]
	var br := branches[index]
	var lb := _branch_lens[index]
	var rejoin := _unwrapped_rejoin(br)
	var fork_tab := PackedFloat64Array()
	var rej_tab := PackedFloat64Array()
	var nf := maxi(1, int(round(minf(br.fork_blend, lb * 0.5))))
	var nr := maxi(1, int(round(minf(br.rejoin_blend, lb * 0.5))))
	var guess := br.fork_distance
	for k in nf + 1:
		guess = _medial_main(index, float(k), guess)
		fork_tab.append(maxf(_unwrap_from(guess, br.fork_distance) - br.fork_distance, 0.0))
	guess = br.rejoin_distance
	for k in nr + 1:
		guess = _medial_main(index, lb - float(k), guess)
		rej_tab.append(maxf(rejoin - _unwrap_from(guess, br.fork_distance), 0.0))
	# Keep both monotonic (they are, for any sane junction; this just guards
	# against float noise at the coincident end).
	for k in range(1, fork_tab.size()):
		fork_tab[k] = maxf(fork_tab[k], fork_tab[k - 1])
	for k in range(1, rej_tab.size()):
		rej_tab[k] = maxf(rej_tab[k], rej_tab[k - 1])
	_tab_cache[index] = [fork_tab, rej_tab]
	return _tab_cache[index]


## Main distance of the point on the branch's normal at `b` that is equally
## far from both centre lines (searching the main line near `guess`).
func _medial_main(index: int, b: float, guess: float) -> float:
	var f := frame_at(index, b)
	var a0 := _closest_main_near(f.origin, guess, 40.0)
	var to_main := (_main_point(a0) - f.origin).dot(f.basis.x)
	var n: Vector3 = f.basis.x.normalized() * (1.0 if to_main >= 0.0 else -1.0)
	var lo := 0.0
	var hi := (_main_point(a0) - f.origin).length()
	if hi < 0.01:
		return a0
	var a := a0
	for i in 22:
		var t := (lo + hi) * 0.5
		var q := f.origin + n * t
		a = _closest_main_near(q, a, 8.0)
		if (_main_point(a) - q).length() > t:
			lo = t
		else:
			hi = t
	return _closest_main_near(f.origin + n * ((lo + hi) * 0.5), a, 8.0)


func _main_point(d: float) -> Vector3:
	return _main.global_transform * _main.curve.sample_baked(fposmod(d, _main_len), true)


## Closest main distance to `world_pos` within +-window of `guess`.
func _closest_main_near(world_pos: Vector3, guess: float, window: float) -> float:
	var best := guess
	var best_sq := INF
	var step := maxf(0.5, window / 16.0)
	var k := -window
	while k <= window:
		var sq := _main_point(guess + k).distance_squared_to(world_pos)
		if sq < best_sq:
			best_sq = sq
			best = guess + k
		k += step
	for i in 3:
		var p := _main_point(best)
		var t := _main_point(best + 0.25) - _main_point(best - 0.25)
		if t.length_squared() < 1e-8:
			break
		best += clampf((world_pos - p).dot(t.normalized()), -0.5, 0.5)
	return fposmod(best, _main_len)


func _unwrap_from(d: float, from: float) -> float:
	return d if d >= from - 1.0 else d + _main_len


## Which path `world_pos` is on, by the nearest centre line.
## Returns {path: int (-1 main), distance: path metres, main_distance, dist_sq}.
## `main_hint` (optional, >= 0): an already-computed main distance for this
## position (TrackSplineHelper passes its own search so the main-path answer is
## exactly what it was before branches existed).
func locate(world_pos: Vector3, main_hint: float = -1.0) -> Dictionary:
	_resolve()
	var md: float = main_hint
	if md < 0.0:
		md = _closest(_main, world_pos)
	else:
		md = refine_main(world_pos, md)
	var mp := _main.global_transform * _main.curve.sample_baked(md)
	var best := {"path": -1, "distance": md, "main_distance": md,
			"dist_sq": world_pos.distance_squared_to(mp)}
	for i in _branch_paths.size():
		var p := _branch_paths[i]
		if p == null:
			continue
		var bd := _closest(p, world_pos)
		var bp := p.global_transform * p.curve.sample_baked(bd)
		var sq := world_pos.distance_squared_to(bp)
		if sq < best.dist_sq:
			best = {"path": i, "distance": bd, "main_distance": branch_to_main(i, bd), "dist_sq": sq}
	return best


## Refines an approximate main distance (e.g. TrackSplineHelper's coarse
## cached search, which steps ~0.2% of the lap) to the true closest point
## nearby: a 1 m scan +-10 m, then two projections onto the tangent.
func refine_main(world_pos: Vector3, d: float) -> float:
	var c := _main.curve
	var local := _main.global_transform.affine_inverse() * world_pos
	var best := d
	var best_sq := INF
	var k := -10.0
	while k <= 10.0:
		var s := fposmod(d + k, _main_len)
		var sq := c.sample_baked(s).distance_squared_to(local)
		if sq < best_sq:
			best_sq = sq
			best = s
		k += 1.0
	for i in 2:
		var p := c.sample_baked(best)
		var t := c.sample_baked(fposmod(best + 0.5, _main_len)) - c.sample_baked(fposmod(best - 0.5, _main_len))
		if t.length_squared() < 1e-6:
			break
		best = fposmod(best + clampf((local - p).dot(t.normalized()), -1.0, 1.0), _main_len)
	return best


static func _closest(p: Path3D, world_pos: Vector3) -> float:
	return p.curve.get_closest_offset(p.global_transform.affine_inverse() * world_pos)


## The jump a ship taking off at `world_pos` is flying from, or null. A ship is
## on a jump from its kicker until the landing ramp ends.
func jump_at(world_pos: Vector3) -> TrackJump:
	if jumps.is_empty() or not _resolve():
		return null
	var loc := locate(world_pos)
	for j in jumps:
		if j and j.branch == int(loc.path) and float(loc.distance) >= j.kicker_start - 5.0 \
				and float(loc.distance) <= j.landing_end:
			return j
	return null


## True if a respawn point at `d` on path `index` would be unsafe: inside a
## jump (kicker to landing end) or too close before one to get up to speed.
func is_respawn_excluded(index: int, d: float) -> bool:
	for j in jumps:
		if j == null or j.branch != index:
			continue
		if d >= j.kicker_start - j.respawn_runup and d <= j.landing_end:
			return true
	return false


# =============================================================================
# ROUTE LAPS (v32)
# =============================================================================
# A route is a whole lap: -1 = the MainSpline, i = through branch i (main to
# its fork, the branch, main from its rejoin), carried by the branch's
# route_path. The AI and the cinematic rig work along one lap spline at a time.

## Route-lap Path3D (-1 = MainSpline), or null if the branch has none.
func route_path(route: int) -> Path3D:
	_resolve()
	if route < 0:
		return _main
	if route >= branches.size() or branches[route] == null or branches[route].route_path.is_empty():
		return null
	return get_node_or_null(branches[route].route_path) as Path3D


func has_routes() -> bool:
	for i in branches.size():
		if route_path(i) != null:
			return true
	return false


## [path, path distance] for route-lap distance `dr`.
func route_to_path(route: int, dr: float) -> Array:
	if route < 0:
		return [-1, fposmod(dr, _main_len)]
	var br := branches[route]
	if dr < br.route_fork:
		return [-1, dr]
	if dr < br.route_rejoin:
		var s := (dr - br.route_fork) / maxf(br.route_rejoin - br.route_fork, 0.001)
		return [route, s * _branch_lens[route]]
	return [-1, fposmod(br.rejoin_distance + (dr - br.route_rejoin), _main_len)]


## Route-lap distance of `d` metres along `path` (which must lie on the route).
func path_to_route(route: int, path: int, d: float) -> float:
	if route < 0:
		return d
	var br := branches[route]
	if path == route:
		return br.route_fork + d / maxf(_branch_lens[route], 0.001) * (br.route_rejoin - br.route_fork)
	if d <= br.fork_distance:
		return d
	return br.route_rejoin + (d - br.rejoin_distance)


## The jumps a lap along `route` goes over, as route-lap distances:
## [{jump, kicker, lip, landing, end}].
func route_jumps(route: int) -> Array:
	var out: Array = []
	for j in jumps:
		if j == null:
			continue
		if j.branch >= 0 and j.branch != route:
			continue
		if j.branch < 0 and route >= 0:
			# Main jump: only if it isn't on the stretch the branch bypasses.
			var br := branches[route]
			if j.kicker_start > br.fork_distance and j.landing_end < br.rejoin_distance:
				continue
		var p := j.branch
		out.append({"jump": j, "kicker": path_to_route(route, p, j.kicker_start),
				"lip": path_to_route(route, p, j.lip), "landing": path_to_route(route, p, j.landing),
				"end": path_to_route(route, p, j.landing_end)})
	return out


## Per-ship tracker of which path the ship is on and how far along it (v32).
func make_tracker() -> Tracker:
	return Tracker.new(self)


## Follows one ship with local searches (cheap, and never confused by another
## part of the track running nearby). In the junctions it compares the ship's
## distance to both centre lines; `ambiguous` is true while that comparison is
## too close to call (the ship is between the two roads before they split).
## `route` is the route lap the ship is committed to: the branch once it is
## unambiguously on it, the main route once it is unambiguously on the main
## road between fork and rejoin; on shared road it keeps its last value.
class Tracker extends RefCounted:
	var graph: TrackGraph
	var path: int = -1
	var distance: float = -1.0
	var route: int = -1
	var ambiguous: bool = false
	## |distance to the other centre line - distance to this one| in junctions.
	var separation: float = INF
	
	const WINDOW := 30.0
	const STEP := 2.0
	const LOST := 40.0
	const CLEAR := 12.0
	
	func _init(g: TrackGraph) -> void:
		graph = g
	
	func reset() -> void:
		distance = -1.0
	
	func main_distance() -> float:
		if path < 0:
			return distance
		return graph.branch_to_main(path, distance)
	
	func update(world_pos: Vector3) -> void:
		if not graph.is_valid():
			return
		if distance < 0.0:
			var loc := graph.locate(world_pos)
			path = loc.path
			distance = loc.distance
			_update_route(world_pos)
			return
		var sq := _local(path, world_pos)
		if sq > LOST * LOST:
			var loc2 := graph.locate(world_pos)
			path = loc2.path
			distance = loc2.distance
		_transitions(world_pos)
		_update_route(world_pos)
	
	func _local(p: int, world_pos: Vector3) -> float:
		var res := _search(p, world_pos, distance)
		distance = res[0]
		return res[1]
	
	## [best distance, squared distance] on path p near d.
	func _search(p: int, world_pos: Vector3, d0: float) -> Array:
		var path3d := graph.path_of(p)
		var length := graph.path_length(p)
		var local := path3d.global_transform.affine_inverse() * world_pos
		var c := path3d.curve
		var best := d0
		var best_sq := INF
		var k := -WINDOW
		while k <= WINDOW:
			var s := d0 + k
			s = fposmod(s, length) if p < 0 else clampf(s, 0.0, length)
			var q := c.sample_baked(s).distance_squared_to(local)
			if q < best_sq:
				best_sq = q
				best = s
			k += STEP
		for i in 2:
			var a := c.sample_baked(best)
			var t := c.sample_baked(clampf(best + 0.5, 0.0, length)) - c.sample_baked(clampf(best - 0.5, 0.0, length))
			if t.length_squared() < 1e-6:
				break
			var s2 := best + clampf((local - a).dot(t.normalized()), -STEP, STEP)
			best = fposmod(s2, length) if p < 0 else clampf(s2, 0.0, length)
		return [best, c.sample_baked(best).distance_squared_to(local)]
	
	func _transitions(world_pos: Vector3) -> void:
		ambiguous = false
		separation = INF
		var own_sq := _search(path, world_pos, distance)[1] as float
		if path < 0:
			for bi in graph.branches.size():
				var br: TrackBranch = graph.branches[bi]
				var lb := graph.path_length(bi)
				var into := _since(distance, br.fork_distance)
				var before := _since(br.rejoin_distance, distance)
				var guess := -1.0
				if into >= 0.0 and into <= br.fork_blend + 20.0:
					guess = into
				elif before >= 0.0 and before <= br.rejoin_blend + 20.0:
					guess = lb - before
				if guess < 0.0:
					continue
				var r := _search(bi, world_pos, guess)
				_compare(sqrt(own_sq), sqrt(r[1] as float))
				if (r[1] as float) + 1.0 < own_sq and not ambiguous:
					path = bi
					distance = r[0]
					return
		else:
			var br2: TrackBranch = graph.branches[path]
			var lb2 := graph.path_length(path)
			if distance >= lb2 - 0.5:
				path = -1
				distance = fposmod(br2.rejoin_distance + 0.5, graph.main_length())
				return
			var mg := -1.0
			if distance <= br2.fork_blend + 20.0:
				mg = br2.fork_distance + distance
			elif distance >= lb2 - br2.rejoin_blend - 20.0:
				mg = br2.rejoin_distance - (lb2 - distance)
			if mg < 0.0:
				return
			var r2 := _search(-1, world_pos, fposmod(mg, graph.main_length()))
			_compare(sqrt(own_sq), sqrt(r2[1] as float))
			if (r2[1] as float) + 1.0 < own_sq and not ambiguous or distance <= 0.5:
				path = -1
				distance = r2[0]
	
	func _compare(own: float, other: float) -> void:
		separation = absf(own - other)
		ambiguous = separation < CLEAR
	
	## Metres from `from` forward to `d` on the main lap (negative = behind).
	func _since(d: float, from: float) -> float:
		var L := graph.main_length()
		var x := fposmod(d - from, L)
		return x if x < L * 0.5 else x - L
	
	func _update_route(_world_pos: Vector3) -> void:
		if ambiguous:
			return
		if path >= 0:
			route = path
			return
		for bi in graph.branches.size():
			var br: TrackBranch = graph.branches[bi]
			var into := _since(distance, br.fork_distance)
			var to_rejoin := _since(br.rejoin_distance, distance)
			if into > 0.0 and to_rejoin > 0.0 and separation > CLEAR and separation < INF:
				route = -1
			elif into > br.fork_blend and to_rejoin > br.rejoin_blend:
				route = -1
