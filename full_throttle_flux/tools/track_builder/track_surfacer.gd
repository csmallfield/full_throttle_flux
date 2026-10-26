extends RefCounted
class_name TrackSurfacer
## Track Builder: turns the SurfaceZoneKeys into the TrackSurface node's zone
## list (v38 phase 3), against the BUILT splines, like TrackGreebler does for
## greebles (and with its projection, so both kinds of key land the same way):
##
##   main track   keys under the TrackBuilder (not under a BranchFeature),
##                sorted along MainSpline; each zone runs to the next key,
##                the last one wraps past the start line to the first
##   branch       keys under its BranchFeature, along its BranchSpline; before
##                the first key (or the whole branch if it has none) the
##                branch carries on with the main zone in force at the fork
##
## v38 phase 5: SurfaceDecalKeys too, projected onto their path the same way
## (main track or their branch) into TrackSurface.decals.
##
## Used by Build (TrackBuild), by the builder's live refresh as keys move, and
## by the validator (resolve() and signature(), to see whether the node is up
## to date).

var zones: Array[Dictionary] = []      # {path, from, to, key, inherited}
var paths: Array[NodePath] = []
var keys: Array[SurfaceZoneKey] = []
var decal_keys: Array[SurfaceDecalKey] = []
var decals: Array[Dictionary] = []     # {path, distance, key}
var notes: PackedStringArray = []
var _lines: Array = []
var _branch_feats: Array[BranchFeature] = []


static func resolve(b: TrackBuilder, root: Node) -> TrackSurfacer:
	var s := TrackSurfacer.new()
	s._resolve(b, root)
	return s


func ok() -> bool:
	return not _lines.is_empty()


## Every SurfaceZoneKey of the builder: main track and branches.
static func all_decal_keys(b: TrackBuilder) -> Array[SurfaceDecalKey]:
	var out: Array[SurfaceDecalKey] = []
	for k in b.keys_of("SurfaceDecalKey"):
		out.append(k as SurfaceDecalKey)
	for bf in b.branch_nodes():
		for k in TrackBranchEval.new(bf).keys_of("SurfaceDecalKey"):
			out.append(k as SurfaceDecalKey)
	return out


## True if the builder has any surface key at all (zones or decals).
static func has_keys(b: TrackBuilder) -> bool:
	return not all_keys(b).is_empty() or not all_decal_keys(b).is_empty()


static func all_keys(b: TrackBuilder) -> Array[SurfaceZoneKey]:
	var out: Array[SurfaceZoneKey] = []
	for k in b.keys_of("SurfaceZoneKey"):
		out.append(k as SurfaceZoneKey)
	for bf in b.branch_nodes():
		for k in TrackBranchEval.new(bf).keys_of("SurfaceZoneKey"):
			out.append(k as SurfaceZoneKey)
	return out


## Writes the zones and the variation into `node`, reusing its zone
## resources (a rebuild with nothing changed leaves the scene as it was).
## Returns true if the node's data changed.
func write(node: TrackSurface, b: TrackBuilder) -> bool:
	var before := node.signature()
	node.paths = paths
	var old := node.zones
	var list: Array[TrackSurfaceZone] = []
	for i in zones.size():
		var zd: Dictionary = zones[i]
		var z: TrackSurfaceZone = old[i] if i < old.size() and old[i] != null else TrackSurfaceZone.new()
		var k: SurfaceZoneKey = zd.key
		z.key_name = String(k.name) if not zd.inherited else "%s@fork" % k.name
		z.path_index = zd.path
		z.from_d = zd.from
		z.to_d = zd.to
		z.profile = k.profile
		# An inherited zone starts the branch: nothing to blend from.
		z.blend_in = 0.0 if zd.inherited else k.blend_in
		z.seed = hash([k.seed, String(k.name)]) & 1023
		z.wear = k.wear
		list.append(z)
	node.zones = list
	var old_d := node.decals
	var dl: Array[TrackSurfaceDecal] = []
	for i in decals.size():
		var dd: Dictionary = decals[i]
		var d: TrackSurfaceDecal = old_d[i] if i < old_d.size() and old_d[i] != null else TrackSurfaceDecal.new()
		_fill_decal(d, dd)
		dl.append(d)
	node.decals = dl
	node.variation = b.surface_variation
	return node.signature() != before


static func _fill_decal(d: TrackSurfaceDecal, dd: Dictionary) -> void:
	var k: SurfaceDecalKey = dd.key
	d.key_name = String(k.name)
	d.path_index = dd.path
	d.distance = dd.distance
	d.anchor = k.anchor
	d.offset = k.offset
	d.shape = k.shape
	d.role = k.role
	d.text = k.text
	d.size = k.size
	d.width = k.width
	d.paint = k.paint
	d.glow = k.glow
	d.opacity = k.opacity
	d.count = k.count
	d.spacing = k.spacing
	d.flipped = k.flipped


## What this resolve would write, for comparing with a node (validator).
func signature(b: TrackBuilder) -> int:
	var parts := [paths, b.surface_variation.get_instance_id() if b.surface_variation else 0]
	for zd in zones:
		var k: SurfaceZoneKey = zd.key
		parts.append([zd.path, snappedf(zd.from, 0.01), snappedf(zd.to, 0.01),
				k.profile.get_instance_id() if k.profile else 0,
				snappedf(0.0 if zd.inherited else k.blend_in, 0.01), hash([k.seed, String(k.name)]) & 1023,
				snappedf(k.wear, 0.01)])
	for dd in decals:
		var d := TrackSurfaceDecal.new()
		_fill_decal(d, dd)
		parts.append(TrackSurface.decal_signature(d))
	return hash(var_to_bytes(parts))


## Frame of the track point a key sits on, in root space (markers), or null.
func key_frame(k: SurfaceZoneKey) -> Variant:
	var pi := _path_of_key(k)
	if pi < 0 or pi >= _lines.size() or _lines[pi].is_empty():
		return null
	var p: Path3D = _lines[pi].path
	return p.global_transform * TrackRoadSegment.frame_at(p.curve, maxf(k.distance, 0.0))


func zone_length(k: SurfaceZoneKey) -> float:
	for zd in zones:
		if zd.key == k and not zd.inherited:
			return zd.to - zd.from
	return 0.0


## Distinct profiles per path (index -> count), for the 4-profile limit.
func profiles_per_path() -> Dictionary:
	var per := {}
	for zd in zones:
		var k: SurfaceZoneKey = zd.key
		if not per.has(zd.path):
			per[zd.path] = []
		if k.profile and not (per[zd.path] as Array).has(k.profile):
			(per[zd.path] as Array).append(k.profile)
	var out := {}
	for pi in per:
		out[pi] = (per[pi] as Array).size()
	return out


func _resolve(b: TrackBuilder, root: Node) -> void:
	keys = all_keys(b)
	var main := root.get_node_or_null("MainSpline") as Path3D
	if main == null or main.curve == null or not main.is_in_group(TrackBuild.GROUP):
		notes.append("The track surface needs a built track: press Build")
		return
	paths.append(NodePath("../MainSpline"))
	_lines.append(TrackGreebler._sample(main, true))
	for bf in b.branch_nodes():
		if not bf.enabled:
			continue
		_branch_feats.append(bf)
		var nm := "BranchSpline" if _branch_feats.size() == 1 else "BranchSpline_%d" % _branch_feats.size()
		paths.append(NodePath("../" + nm))
		var bp := root.get_node_or_null(nm) as Path3D
		_lines.append(TrackGreebler._sample(bp, false) if bp and bp.curve else {})
	var per_path := {}
	for k in keys:
		if k.profile == null:
			notes.append("%s has no profile: left out" % k.name)
			continue
		var pi := _path_of_key(k)
		if pi < 0 or _lines[pi].is_empty():
			continue
		var r := TrackGreebler._project(_lines[pi], k.global_position, k.distance)
		k.distance = r[0]
		k.distance_to_track = r[1]
		if not per_path.has(pi):
			per_path[pi] = []
		(per_path[pi] as Array).append(k)
	for pi in per_path:
		(per_path[pi] as Array).sort_custom(func(a: SurfaceZoneKey, c: SurfaceZoneKey) -> bool:
				return a.distance < c.distance)
	# Decals: onto their path, sorted along it.
	decal_keys = all_decal_keys(b)
	for k in decal_keys:
		var pi := _path_of_key(k)
		if pi < 0 or _lines[pi].is_empty():
			continue
		var r := TrackGreebler._project(_lines[pi], k.global_position, k.distance)
		k.distance = r[0]
		k.distance_to_track = r[1]
		decals.append({path = pi, distance = r[0], key = k})
	decals.sort_custom(func(a: Dictionary, c: Dictionary) -> bool:
			return a.path < c.path or (a.path == c.path and a.distance < c.distance))
	var main_len := main.curve.get_baked_length()
	var mk: Array = per_path.get(0, [])
	for i in mk.size():
		var k: SurfaceZoneKey = mk[i]
		var to: float = (mk[i + 1] as SurfaceZoneKey).distance if i + 1 < mk.size() \
				else (mk[0] as SurfaceZoneKey).distance + main_len
		zones.append({path = 0, from = k.distance, to = to, key = k, inherited = false})
	var graph := root.get_node_or_null("TrackGraph") as TrackGraph
	for bi in _branch_feats.size():
		var pi := bi + 1
		if _lines[pi].is_empty():
			continue
		var blen: float = (_lines[pi].path as Path3D).curve.get_baked_length()
		var bk: Array = per_path.get(pi, [])
		var first: float = (bk[0] as SurfaceZoneKey).distance if not bk.is_empty() else blen
		if first > 1.0 and graph and bi < graph.branches.size() and graph.branches[bi]:
			var mz := _main_zone_at(graph.branches[bi].fork_distance, main_len)
			if not mz.is_empty():
				zones.append({path = pi, from = 0.0, to = first, key = mz.key, inherited = true})
		for i in bk.size():
			var k: SurfaceZoneKey = bk[i]
			var to: float = (bk[i + 1] as SurfaceZoneKey).distance if i + 1 < bk.size() else blen
			zones.append({path = pi, from = k.distance, to = to, key = k, inherited = false})


func _main_zone_at(d: float, main_len: float) -> Dictionary:
	for zd in zones:
		if zd.path != 0:
			continue
		var rel := fposmod(d - float(zd.from), main_len)
		if rel <= float(zd.to) - float(zd.from):
			return zd
	return {}


func _path_of_key(k: ProfileKey) -> int:
	var n := k.get_parent()
	while n:
		if n is BranchFeature:
			var i := _branch_feats.find(n)
			return i + 1 if i >= 0 else -1
		if n is TrackBuilder:
			return 0
		n = n.get_parent()
	return 0
