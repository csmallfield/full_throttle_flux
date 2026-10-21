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
