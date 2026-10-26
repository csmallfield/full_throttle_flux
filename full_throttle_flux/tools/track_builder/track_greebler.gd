extends RefCounted
class_name TrackGreebler
## Track Builder: the greebler (v36). Turns the GreebleZoneKeys into the
## TrackGreebles node's zone list, against the BUILT splines (so it needs a
## Build first, and it never touches the drivable track).
##
##   main track   keys under the TrackBuilder (not under a BranchFeature),
##                sorted along the MainSpline; each zone runs to the next key,
##                the last one wraps past the start line to the first
##   branch       keys under its BranchFeature, along its BranchSpline; before
##                the first key (or the whole branch if it has none) the
##                branch carries on with the main zone in force at the fork
##   no overhead  magnetic zones (loops, rolls), jumps (kicker to landing end)
##                and the start line, 10 m margins
##   ground off   boost pads and the start line
##
## Used by Build (TrackBuild), by the builder's live refresh as keys move, and
## by the validator (resolve() only, to see whether the node is up to date).

const PATH_STEP := 2.0
## A key further than this from its spline (validator: error, as the others).
const KEY_FAR := 30.0
const MARGIN := 10.0
const START_HALF := 15.0
const PAD_MARGIN := 0.5

var zones: Array[Dictionary] = []      # {path, from, to, key, inherited}
var paths: Array[NodePath] = []
var no_overhead := PackedVector3Array()
var ground_exclusions := PackedFloat32Array()
var keys: Array[GreebleZoneKey] = []
var notes: PackedStringArray = []
## One per path: {name, path (Path3D), pts (root space every PATH_STEP), closed}.
var _lines: Array = []


## Resolves every key against the built splines (writes the keys' derived
## distance and distance_to_track). ok = false when there's no build.
static func resolve(b: TrackBuilder, root: Node) -> TrackGreebler:
	var g := TrackGreebler.new()
	g._resolve(b, root)
	return g


func ok() -> bool:
	return not _lines.is_empty()


## Writes the zones into `node`, reusing its zone resources (so a rebuild
## with nothing changed leaves the scene file as it was). Returns true if the
## node's data changed.
func write(node: TrackGreebles, b: TrackBuilder) -> bool:
	var before := signature_of(node)
	node.paths = paths
	var old := node.zones
	var list: Array[TrackGreebleZone] = []
	for i in zones.size():
		var zd: Dictionary = zones[i]
		var z: TrackGreebleZone = old[i] if i < old.size() and old[i] != null else TrackGreebleZone.new()
		var k: GreebleZoneKey = zd.key
		z.label = String(k.name) if not zd.inherited else "%s@fork" % k.name
		z.key_name = String(k.name)
		z.path_index = zd.path
		z.from_d = zd.from
		z.to_d = zd.to
		z.style = k.style
		z.mirror = k.mirror
		z.density = k.density
		z.skip_layers = k.skip_layers
		# Seeded by the key, not the zone's index: adding a key doesn't
		# reshuffle every zone after it.
		z.seed = hash([k.seed, String(k.name), zd.path]) & 0x7fffffff
		list.append(z)
	node.zones = list
	node.no_overhead = no_overhead
	node.ground_exclusions = ground_exclusions
	node.rail_face = Vector2(TrackBuild.WALL_RIGHT_POLY[2].x, 3.0)
	node.rail_top = _wall_top()
	node.rail_outer = Vector2((TrackBuild.WALL_RIGHT_POLY[0].x + TrackBuild.WALL_RIGHT_POLY[4].x) * 0.5, 3.0)
	return signature_of(node) != before


## What this resolve would write, for comparing with a node (validator).
func signature() -> int:
	var parts := [paths, no_overhead, ground_exclusions]
	for zd in zones:
		var k: GreebleZoneKey = zd.key
		parts.append([zd.path, snappedf(zd.from, 0.01), snappedf(zd.to, 0.01),
				k.style.get_instance_id() if k.style else 0, k.mirror, k.density, k.skip_layers,
				hash([k.seed, String(k.name), zd.path]) & 0x7fffffff])
	return hash(var_to_bytes(parts))


static func signature_of(node: TrackGreebles) -> int:
	if node == null:
		return 0
	var parts := [node.paths, node.no_overhead, node.ground_exclusions]
	for z in node.zones:
		if z == null:
			continue
		parts.append([z.path_index, snappedf(z.from_d, 0.01), snappedf(z.to_d, 0.01),
				z.style.get_instance_id() if z.style else 0, z.mirror, z.density, z.skip_layers, z.seed])
	return hash(var_to_bytes(parts))


## Every GreebleZoneKey of the builder: main track and branches.
static func all_keys(b: TrackBuilder) -> Array[GreebleZoneKey]:
	var out: Array[GreebleZoneKey] = []
	for k in b.keys_of("GreebleZoneKey"):
		out.append(k as GreebleZoneKey)
	for bf in b.branch_nodes():
		for k in TrackBranchEval.new(bf).keys_of("GreebleZoneKey"):
			out.append(k as GreebleZoneKey)
	return out


## Frame of the track point a key sits on, in root space (for markers), or
## null if the key's spline isn't built.
func key_frame(k: GreebleZoneKey) -> Variant:
	var pi := _path_of_key(k)
	if pi < 0 or pi >= _lines.size() or _lines[pi].is_empty():
		return null
	var p: Path3D = _lines[pi].path
	return p.global_transform * TrackRoadSegment.frame_at(p.curve, maxf(k.distance, 0.0))


## Zone length along its spline (for the marker label).
func zone_length(k: GreebleZoneKey) -> float:
	for zd in zones:
		if zd.key == k and not zd.inherited:
			return zd.to - zd.from
	return 0.0


# =============================================================================
# INTERNALS
# =============================================================================

var _branch_feats: Array[BranchFeature] = []


func _resolve(b: TrackBuilder, root: Node) -> void:
	keys = all_keys(b)
	var main := root.get_node_or_null("MainSpline") as Path3D
	if main == null or main.curve == null or not main.is_in_group(TrackBuild.GROUP):
		notes.append("Greebles need a built track: press Build")
		return
	paths.append(NodePath("../MainSpline"))
	_lines.append(_sample(main, true))
	for bf in b.branch_nodes():
		if not bf.enabled:
			continue
		_branch_feats.append(bf)
		var nm := "BranchSpline" if _branch_feats.size() == 1 else "BranchSpline_%d" % _branch_feats.size()
		paths.append(NodePath("../" + nm))
		var bp := root.get_node_or_null(nm) as Path3D
		_lines.append(_sample(bp, false) if bp and bp.curve else {})
		if bp == null:
			notes.append("%s isn't built (press Build): its greebles are left out" % bf.name)
	# Keys onto their splines.
	var per_path := {}
	for k in keys:
		var pi := _path_of_key(k)
		if pi < 0 or _lines[pi].is_empty():
			continue
		var r := _project(_lines[pi], k.global_position, k.distance)
		k.distance = r[0]
		k.distance_to_track = r[1]
		if not per_path.has(pi):
			per_path[pi] = []
		(per_path[pi] as Array).append(k)
	for pi in per_path:
		(per_path[pi] as Array).sort_custom(func(a: GreebleZoneKey, c: GreebleZoneKey) -> bool:
				return a.distance < c.distance)
	# Main zones.
	var main_len := main.curve.get_baked_length()
	var mk: Array = per_path.get(0, [])
	for i in mk.size():
		var k: GreebleZoneKey = mk[i]
		var to: float = (mk[i + 1] as GreebleZoneKey).distance if i + 1 < mk.size() \
				else (mk[0] as GreebleZoneKey).distance + main_len
		zones.append({path = 0, from = k.distance, to = to, key = k, inherited = false})
	# Branch zones.
	var graph := root.get_node_or_null("TrackGraph") as TrackGraph
	for bi in _branch_feats.size():
		var pi := bi + 1
		if _lines[pi].is_empty():
			continue
		var blen: float = (_lines[pi].path as Path3D).curve.get_baked_length()
		var bk: Array = per_path.get(pi, [])
		var first: float = (bk[0] as GreebleZoneKey).distance if not bk.is_empty() else blen
		if first > 1.0 and graph and bi < graph.branches.size() and graph.branches[bi]:
			var mz := _main_zone_at(graph.branches[bi].fork_distance, main_len)
			if not mz.is_empty():
				zones.append({path = pi, from = 0.0, to = first, key = mz.key, inherited = true})
		for i in bk.size():
			var k: GreebleZoneKey = bk[i]
			var to: float = (bk[i + 1] as GreebleZoneKey).distance if i + 1 < bk.size() else blen
			zones.append({path = pi, from = k.distance, to = to, key = k, inherited = false})
	# Bare stretches ("None") end the zone before them but make nothing.
	zones = zones.filter(func(zd: Dictionary) -> bool: return (zd.key as GreebleZoneKey).style != null)
	_spans(b, root, graph)


func _main_zone_at(d: float, main_len: float) -> Dictionary:
	for zd in zones:
		if zd.path != 0:
			continue
		var rel := fposmod(d - float(zd.from), main_len)
		if rel <= float(zd.to) - float(zd.from):
			return zd
	return {}


func _spans(b: TrackBuilder, root: Node, graph: TrackGraph) -> void:
	var mt := root.get_node_or_null("MagneticTrack") as MagneticTrack
	if mt:
		for z in mt.zones:
			if z:
				no_overhead.append(Vector3(0, z.start_distance - MARGIN, z.end_distance + MARGIN))
	if graph:
		for j in graph.jumps:
			if j:
				no_overhead.append(Vector3(j.branch + 1, j.kicker_start - MARGIN, j.landing_end + MARGIN))
	no_overhead.append(Vector3(0, b.start_lead - START_HALF, b.start_lead + START_HALF))
	ground_exclusions.append_array([0, b.start_lead, 0.0, 40.0, 3.0])
	var pads := root.get_node_or_null("BoostPads")
	if pads == null:
		return
	for pad in pads.get_children():
		if not pad is Node3D:
			continue
		var pos := (pad as Node3D).global_position
		var best := -1
		var best_r := [0.0, INF]
		for pi in _lines.size():
			if _lines[pi].is_empty():
				continue
			var r := _project(_lines[pi], pos, -1.0)
			if r[1] < best_r[1]:
				best_r = r
				best = pi
		if best < 0:
			continue
		var p: Path3D = _lines[best].path
		var f := p.global_transform * TrackRoadSegment.frame_at(p.curve, best_r[0])
		var x := (pos - f.origin).dot(f.basis.x)
		ground_exclusions.append_array([best, best_r[0], x, BoostPadKey.PAD_HALF_WIDTH + PAD_MARGIN,
				BoostPadKey.PAD_HALF_LENGTH + PAD_MARGIN])


## 0 = main track, i + 1 = the i-th enabled branch, -1 = a disabled branch.
func _path_of_key(k: GreebleZoneKey) -> int:
	var n := k.get_parent()
	while n:
		if n is BranchFeature:
			var i := _branch_feats.find(n)
			return i + 1 if i >= 0 else -1
		if n is TrackBuilder:
			return 0
		n = n.get_parent()
	return 0


static func _sample(p: Path3D, closed: bool) -> Dictionary:
	var c := p.curve
	var L := c.get_baked_length()
	var pts := PackedVector3Array()
	var n := int(ceil(L / PATH_STEP)) + 1
	for i in n:
		pts.append(p.global_transform * c.sample_baked(minf(i * PATH_STEP, L), true))
	return {path = p, pts = pts, closed = closed, length = L}


## [distance along the spline, distance from it] of `pos`. With a hint (the
## key's distance last time) it looks near there first, so a key can't jump
## to a stretch of road that passes over or under it.
static func _project(line: Dictionary, pos: Vector3, hint: float) -> Array:
	var pts: PackedVector3Array = line.pts
	var n := pts.size()
	var best := -1
	var best_sq := INF
	if hint >= 0.0:
		var hi := int(round(hint / PATH_STEP))
		var w := int(150.0 / PATH_STEP)
		for k in range(-w, w + 1):
			var i := hi + k
			i = wrapi(i, 0, n - 1) if line.closed else clampi(i, 0, n - 1)
			var sq := pos.distance_squared_to(pts[i])
			if sq < best_sq:
				best_sq = sq
				best = i
		if best_sq > KEY_FAR * KEY_FAR * 4.0:
			best = -1
			best_sq = INF
	if best < 0:
		for i in n:
			var sq := pos.distance_squared_to(pts[i])
			if sq < best_sq:
				best_sq = sq
				best = i
	# Refine on the segments either side.
	var L: float = line.length
	var d := best * PATH_STEP
	var dist := sqrt(best_sq)
	for j: int in [best - 1, best]:
		var a := j
		var b := j + 1
		if line.closed:
			a = wrapi(a, 0, n - 1)
			b = wrapi(b, 0, n - 1)
		elif a < 0 or b >= n:
			continue
		var seg := pts[b] - pts[a]
		var t := clampf((pos - pts[a]).dot(seg) / maxf(seg.length_squared(), 0.0001), 0.0, 1.0)
		var q := pts[a] + seg * t
		var dd := pos.distance_to(q)
		if dd < dist:
			dist = dd
			d = (a + t) * PATH_STEP
	return [clampf(d, 0.0, L), dist]


static func _wall_top() -> Vector2:
	# Middle of the flat top (between the bevel and the outer edge), as the
	# Utopia survey placed its WallTop rail.
	var a: Vector2 = TrackBuild.WALL_RIGHT_POLY[1]
	var c: Vector2 = TrackBuild.WALL_RIGHT_POLY[0]
	var face: float = TrackBuild.WALL_RIGHT_POLY[2].x
	var outer: float = (c.x + TrackBuild.WALL_RIGHT_POLY[4].x) * 0.5
	var x := lerpf(face, outer, 0.62)
	var y := lerpf(a.y, c.y, clampf((x - a.x) / (c.x - a.x), 0.0, 1.0))
	return Vector2(x, y)
