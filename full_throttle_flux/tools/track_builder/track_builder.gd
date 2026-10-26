@tool
extends Node3D
class_name TrackBuilder
## Track Builder (v34): authoring node for new tracks.
##
## Draw the base curve by hand (the BaseSpline child, a closed Path3D), then
## drop BankKey, WidthKey and StartKey nodes anywhere near it, features
## (RollFeature, LoopFeature, JumpFeature, BranchFeature) where you want them,
## BoostPadKeys where you want boost pads, and (after a Build) GreebleZoneKeys
## where the track dressing should change style (v36). The preview
## ribbon follows every edit within a fraction of a second, coloured by the
## overlay you pick. Build writes the track the game runs on (TrackBuild);
## Validate checks it (TrackValidator) and marks problems where they are.
##
## Rules (see docs/TRACK_AUTHORING.md):
##   * identity transforms on the track root, this node and BaseSpline;
##   * bank comes from BankKeys only, never typed tilts;
##   * width comes from WidthKeys; the walls follow the road edge;
##   * never edit the generated nodes: change the inputs and Build again.
##
## At runtime this node removes itself (it's authoring data).

enum Overlay {
	BANK,       ## Bank angle: blue = leaning left, red = leaning right.
	ROLL_RATE,  ## How fast the bank changes, °/m. Red above 0.7 (the roll limit).
	LATERAL_G,  ## Cornering load at ref_speed, in game g (25 u/s²).
	GRADE,      ## Slope: blue = descending, red = climbing.
	WIDTH,      ## Half width: blue = narrower than standard, orange = wider. Red = taper too fast.
	FAIRING,    ## How far fairing moved the curve from what you drew.
}

const PREVIEW_NAME := "_Preview"
const ISSUES_NAME := "_Issues"
const GREEBLE_PREVIEW_NAME := "_GreebleMarkers"
const GREEBLES_NODE := "TrackGreebles"
const GREEBLES_SCRIPT := "res://scripts/tracks/track_greebles.gd"
const DEBOUNCE_S := 0.2
const ROLL_LIMIT := 0.7          # °/m, design limit outside roll features
const TAPER_LIMIT := 0.1         # m of half width per m of track
const KEY_FAR := 30.0            # m from the track: validator error

@export var base_spline: NodePath = NodePath("BaseSpline")

@export_group("Curve")
## Spreads curvature changes over about this many metres, so hand-set handles
## don't jolt the ship at every control point. 0 = keep the drawn curve
## exactly (deliberate kinks).
@export_range(0.0, 200.0, 1.0, "suffix:m") var fairing_m: float = 40.0:
	set(v):
		fairing_m = v
		mark_dirty()
## The generated MainSpline starts this far before the start line.
@export_range(0.0, 200.0, 1.0, "suffix:m") var start_lead: float = 30.0:
	set(v):
		start_lead = v
		mark_dirty()

@export_group("Build")
@export_tool_button("Build", "Play") var _btn_build := build
@export_tool_button("Validate", "StatusSuccess") var _btn_validate := validate
## Removes everything Build made (MainSpline, road, walls, start, zones,
## jumps), leaving your inputs and anything hand-made.
@export_tool_button("Clear build", "Clear") var _btn_clear_build := clear_build

@export_group("Preview")
@export var auto_preview: bool = true:
	set(v):
		auto_preview = v
		if v:
			mark_dirty()
## The coloured road-width ribbon. Build turns it off so you see the real
## road; the centre line, edges, ticks and keys stay.
@export var ribbon: bool = true:
	set(v):
		ribbon = v
		mark_dirty()
@export var overlay: Overlay = Overlay.BANK:
	set(v):
		overlay = v
		mark_dirty()
## Ribbon spacing. Smaller = smoother preview, slower to update.
@export_range(1.0, 10.0, 0.5, "suffix:m") var preview_step: float = 3.0:
	set(v):
		preview_step = v
		mark_dirty()
## Speed used for the lateral-g overlay (default_racer tops out at 120).
@export_range(20.0, 200.0, 1.0, "suffix:u/s") var ref_speed: float = 110.0:
	set(v):
		ref_speed = v
		mark_dirty()
## Game gravity (ShipProfile.gravity); lateral g is measured against it.
@export var game_gravity: float = 25.0:
	set(v):
		game_gravity = v
		mark_dirty()
@export_range(0.0, 1000.0, 10.0, "suffix:m") var label_every: float = 100.0:
	set(v):
		label_every = v
		mark_dirty()

@export_tool_button("Preview now", "Reload") var _btn_preview := preview
@export_tool_button("Clear preview", "Remove") var _btn_clear := clear_preview

@export_group("Greebles")
## Re-dress the built track as you move or change GreebleZoneKeys (styles
## and rules you edit are picked up by the TrackGreebles node itself).
@export var greebles_live: bool = true:
	set(v):
		greebles_live = v
		if v:
			mark_greebles_dirty()
## Zone markers (a gate and a label at each GreebleZoneKey's start).
@export var greeble_markers: bool = true:
	set(v):
		greeble_markers = v
		mark_greebles_dirty()
@export_tool_button("Refresh greebles", "Reload") var _btn_greebles := refresh_greebles
## Removes the TrackGreebles node (the keys stay; Build or Refresh makes it again).
@export_tool_button("Remove greebles", "Remove") var _btn_greebles_clear := remove_greebles

@export_group("Report (read only)")
@export_multiline var report: String = ""

## Headless tools (validator, checks) set this so the builder survives
## outside the editor.
static var keep_at_runtime := false

## The base curve as drawn (faired), with the bank and width profiles, in
## base distances. Keys and features are placed on this.
var base := TrackSampler.new()
## The whole track the build emits: base plus spliced features, resampled
## every metre, distance 0 at the lap origin (start line - start_lead).
var sampler := TrackSampler.new()
var composer := TrackComposer.new()
## One per enabled BranchFeature (split tracks), evaluated against `sampler`.
var branches: Array[TrackBranchEval] = []
## Base distance of the lap origin.
var origin_d := 0.0
var _dirty := false
var _dirty_at := 0.0
var _watched: Curve3D = null
var _last_ms := 0.0
var _greebles_dirty := false
var _greebles_dirty_at := 0.0
var _last_greebles := ""


func _ready() -> void:
	if not Engine.is_editor_hint():
		if not keep_at_runtime:
			# Authoring data only: the generated nodes are what the game uses.
			queue_free()
		return
	set_process(true)
	mark_dirty()
	mark_greebles_dirty()
	if OS.get_environment("TB_EDITOR_SELFTEST") == "1":
		_editor_selftest.call_deferred()


func _process(_delta: float) -> void:
	if not Engine.is_editor_hint():
		return
	_watch_curve()
	if _dirty and auto_preview and _now() - _dirty_at >= DEBOUNCE_S:
		preview()
	if _greebles_dirty and greebles_live and _now() - _greebles_dirty_at >= DEBOUNCE_S:
		refresh_greebles()


func _validate_property(property: Dictionary) -> void:
	if property.name == "report":
		# Shown, never saved (it changes on every preview).
		property.usage = PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_READ_ONLY


func mark_dirty() -> void:
	_dirty = true
	_dirty_at = _now()


## A GreebleZoneKey moved or changed (the drivable track didn't).
func mark_greebles_dirty() -> void:
	_greebles_dirty = true
	_greebles_dirty_at = _now()


func base_path() -> Path3D:
	var n := get_node_or_null(base_spline)
	return n as Path3D


## Every BankKey / WidthKey under this builder, at any depth.
func keys_of(type: String) -> Array[ProfileKey]:
	var out: Array[ProfileKey] = []
	_collect(self, type, out)
	return out


## Every BranchFeature under this builder.
func branch_nodes() -> Array[BranchFeature]:
	var out: Array[BranchFeature] = []
	_collect_branches(self, out)
	return out


func _collect_branches(n: Node, out: Array[BranchFeature]) -> void:
	for c in n.get_children():
		if c is BranchFeature:
			out.append(c)
		elif not c.name in [PREVIEW_NAME, ISSUES_NAME]:
			_collect_branches(c, out)


## Every feature on the main track (enabled or not; not those under a
## BranchFeature, which belong to that branch).
func features() -> Array[TrackFeature]:
	var out: Array[TrackFeature] = []
	for k in keys_of(""):
		if k is TrackFeature:
			out.append(k)
	return out


# =============================================================================
# EVALUATION (shared by preview, build and validate)
# =============================================================================

## Samples the base curve, places the keys and applies both profiles.
## Returns false if there's nothing to sample.
func evaluate() -> bool:
	var path := base_path()
	if path == null or path.curve == null:
		return false
	if not base.sample(path.curve, fairing_m):
		return false
	var bank_keys := _project(keys_of("BankKey"))
	var width_keys := _project(keys_of("WidthKey"))
	var starts := _project(keys_of("StartKey"))
	var feats: Array[ProfileKey] = []
	for f in features():
		feats.append(f)
	_project(feats)
	var bk: Array = []
	for k in bank_keys:
		bk.append({d = k.distance, bank = (k as BankKey).bank_deg, ease = k.ease})
	var wk: Array = []
	for k in width_keys:
		var w := k as WidthKey
		wk.append({d = k.distance, left = w.half_width_left, right = w.half_width_right, ease = k.ease})
	base.apply_bank_profile(bk)
	base.apply_width_profile(wk)
	# Lap origin: start_lead before the start line (StartKey, or the base's
	# first point).
	var line_d := starts[0].distance if starts.size() > 0 else 0.0
	origin_d = fposmod(line_d - start_lead, base.length)
	composer = TrackComposer.new()
	if not base.closed:
		composer.errors.append("BaseSpline must be a closed loop (tick Closed on its Curve3D)")
	# Branches first find their ends on the base: the main track is levelled
	# across their junctions.
	branches.clear()
	for bf in branch_nodes():
		if not bf.enabled:
			continue
		var be := TrackBranchEval.new(bf)
		if be.place_on_base(base, fairing_m):
			composer.level_spans.append_array(be.level_spans(base))
		branches.append(be)
	composer.compose(base, features(), origin_d, sampler)
	for be in branches:
		if be.errors.is_empty():
			be.evaluate(sampler)
	# Boost pads sit on the finished track (features included), so they're
	# projected onto it rather than onto the base.
	_project_on(keys_of("BoostPadKey"), sampler)
	for be in branches:
		if be.ok:
			_project_on(be.keys_of("BoostPadKey"), be.track)
	return true


## Every boost pad: {key, branch (-1 = main, else index into `branches`),
## track (its TrackSampler), s (distance along it), x (+ = right), i (index in
## the key's row)}. Pads under a branch that didn't evaluate are left out.
func pad_placements() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var sets: Array = [[-1, sampler, keys_of("BoostPadKey")]]
	for bi in branches.size():
		if branches[bi].ok:
			sets.append([bi, branches[bi].track, branches[bi].keys_of("BoostPadKey")])
	for st: Array in sets:
		var ts: TrackSampler = st[1]
		for k: ProfileKey in st[2]:
			var pk := k as BoostPadKey
			var j := ts.index_at(pk.distance)
			var xs := pk.pad_offsets(ts.width_l[j], ts.width_r[j])
			for i in xs.size():
				out.append({key = pk, branch = st[0], track = ts, s = pk.distance, x = xs[i], i = i})
	return out


## All errors that stop a build: the main composer's and every branch's.
func errors() -> PackedStringArray:
	var out := composer.errors.duplicate()
	for be in branches:
		out.append_array(be.errors)
	return out


## Composite distance of base distance `u` (for drawing keys on the track):
## the nearest sample outside features if there is one within 2 m, else the
## nearest sample at all.
func track_s_for_base(u: float) -> float:
	return s_for_base(sampler, base.length, u)


## Same, on any composite `s` built from a base of length `base_len`.
static func s_for_base(s: TrackSampler, base_len: float, u: float) -> float:
	var best := -1
	var best_d := INF
	var best_free := -1
	var best_free_d := INF
	for i in s.size():
		var d := absf(wrapf(s.base_u[i] - u, -base_len * 0.5, base_len * 0.5)) if s.closed \
				else absf(s.base_u[i] - u)
		if d < best_d:
			best_d = d
			best = i
		if s.feat[i] < 0 and d < best_free_d:
			best_free_d = d
			best_free = i
	if best_free >= 0 and best_free_d <= 2.0:
		return s.S[best_free]
	return s.S[maxi(best, 0)]


func _key_frame(k: ProfileKey) -> Transform3D:
	if k is BoostPadKey:
		var kt := _key_track(k)
		if kt.size() < 2:
			return Transform3D(Basis(), k.global_position)   # its branch didn't evaluate
		return kt.frame_at(k.distance)
	for be in branches:
		if be.node.is_ancestor_of(k):
			return be.track.frame_at(s_for_base(be.track, be.base.length, k.distance))
	return sampler.frame_at(track_s_for_base(k.distance))


func _key_track(k: ProfileKey) -> TrackSampler:
	for be in branches:
		if be.node.is_ancestor_of(k):
			return be.track
	return sampler


## Every key of a type, on the main track and on every branch (for drawing).
func all_keys_of(type: String) -> Array[ProfileKey]:
	var out := keys_of(type)
	for be in branches:
		out.append_array(be.keys_of(type))
	return out


## Projects keys straight onto a finished track `ts` (boost pads).
static func _project_on(keys: Array[ProfileKey], ts: TrackSampler) -> void:
	for k in keys:
		var r := ts.project(k.global_position, k.distance)
		k.distance = r[0]
		k.distance_to_track = r[1]


## Projects keys onto the track (writing their derived distances) and returns
## them sorted by distance.
func _project(keys: Array[ProfileKey]) -> Array[ProfileKey]:
	for k in keys:
		var r := base.project(k.global_position, k.distance)
		k.distance = r[0]
		k.distance_to_track = r[1]
	keys.sort_custom(func(a: ProfileKey, b: ProfileKey) -> bool: return a.distance < b.distance)
	return keys


# =============================================================================
# PREVIEW
# =============================================================================

func preview() -> void:
	_dirty = false
	var t0 := Time.get_ticks_usec()
	if not evaluate():
		clear_preview()
		report = "No BaseSpline curve to preview (add a Path3D child named BaseSpline)."
		return
	var root := _preview_root()
	for c in root.get_children():
		c.free()
	if ribbon:
		_draw_ribbon(root, sampler)
		for be in branches:
			if be.track.size() > 1:
				_draw_ribbon(root, be.track)
	_draw_lines(root)
	_draw_labels(root)
	_last_ms = (Time.get_ticks_usec() - t0) / 1000.0
	report = _make_report()


func clear_preview() -> void:
	var p := get_node_or_null(PREVIEW_NAME)
	if p:
		p.free()


func _preview_root() -> Node3D:
	var p := get_node_or_null(PREVIEW_NAME) as Node3D
	if p == null:
		p = Node3D.new()
		p.name = PREVIEW_NAME
		p.top_level = true    # world space, whatever this node's transform
		add_child(p)          # owner left unset: never saved into the scene
	p.global_transform = Transform3D.IDENTITY
	return p


func _preview_indices(sm: TrackSampler = null) -> PackedInt32Array:
	if sm == null:
		sm = sampler
	var out := PackedInt32Array()
	var n := sm.size()
	var every := maxi(1, int(round(preview_step / sm.step())))
	var i := 0
	while i < n:
		out.append(i)
		i += every
	if sm.closed:
		out.append(0)            # close the ribbon
	elif out[out.size() - 1] != n - 1:
		out.append(n - 1)
	return out


func _draw_ribbon(root: Node3D, s: TrackSampler) -> void:
	var idx := _preview_indices(s)
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	var norms := PackedVector3Array()
	for i in idx:
		var r := TrackSampler.right_of(s.T[i], s.U[i])
		var c := _overlay_color(i, s) if s.road[i] == 1 else Color(0.9, 0.1, 0.1, 0.25)
		var lift := s.U[i] * 0.05
		verts.append(s.P[i] - r * s.width_l[i] + lift)
		verts.append(s.P[i] + lift)
		verts.append(s.P[i] + r * s.width_r[i] + lift)
		for _k in 3:
			cols.append(c)
			norms.append(s.U[i])
	var tris := PackedInt32Array()
	for row in idx.size() - 1:
		var a := row * 3
		var b := a + 3
		for col in 2:
			tris.append_array([a + col, b + col, a + col + 1, a + col + 1, b + col, b + col + 1])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = tris
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mi := MeshInstance3D.new()
	mi.name = "Ribbon"
	mi.mesh = mesh
	mi.material_override = _vertex_material(false, 0.85)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)


func _draw_lines(root: Node3D) -> void:
	var s := sampler
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	_track_lines(im, s)
	for be in branches:
		if be.track.size() > 1:
			_track_lines(im, be.track)
			# Junction ends: where the inner walls take over.
			if be.ok:
				for sd: float in [be.jf_b, be.jr_b]:
					var f := be.track.frame_at(sd)
					_line(im, f.origin, f.origin + f.basis.y * 20.0, Color(0.3, 0.9, 1.0))
				for sd: float in [be.jf_m, be.jr_m]:
					var f := s.frame_at(sd)
					_line(im, f.origin, f.origin + f.basis.y * 20.0, Color(0.3, 0.9, 1.0))
	# Distance ticks across the road.
	if label_every > 0.0:
		var d := 0.0
		while d < s.length:
			var f := s.frame_at(d)
			var i := s.index_at(d)
			var c := Color(1, 0.9, 0.2) if is_zero_approx(fmod(d, 1000.0)) else Color(1, 1, 1, 0.6)
			_line(im, f.origin - f.basis.x * s.width_l[i] + f.basis.y * 0.2,
					f.origin + f.basis.x * s.width_r[i] + f.basis.y * 0.2, c)
			d += label_every
	# Keys: leader line from the node to its track point, plus a marker.
	for k in all_keys_of("BankKey"):
		var f := _key_frame(k)
		var col := Color(1.0, 0.55, 0.1) if k.distance_to_track <= KEY_FAR else Color(1, 0, 0)
		_line(im, k.global_position, f.origin + f.basis.y * 2.0, col)
		# A tilted plank across the road, raised 2 m, showing the bank.
		var hw := 10.0
		var a := f.origin + f.basis.y * 2.0 - f.basis.x * hw
		var b := f.origin + f.basis.y * 2.0 + f.basis.x * hw
		var fw := -f.basis.z * 3.0
		_line(im, a - fw, b - fw, col)
		_line(im, b - fw, b + fw, col)
		_line(im, b + fw, a + fw, col)
		_line(im, a + fw, a - fw, col)
		_line(im, f.origin + f.basis.y * 2.0, f.origin + f.basis.y * 8.0, col)  # the up it sets
	for k in all_keys_of("WidthKey"):
		var f := _key_frame(k)
		var kt := _key_track(k)
		var i := kt.index_at(kt.project(f.origin, -1.0)[0])
		var col := Color(0.2, 0.85, 1.0) if k.distance_to_track <= KEY_FAR else Color(1, 0, 0)
		_line(im, k.global_position, f.origin + f.basis.y * 2.0, col)
		var l := f.origin - f.basis.x * kt.width_l[i]
		var r := f.origin + f.basis.x * kt.width_r[i]
		# Uprights at both edges, joined across.
		_line(im, l, l + f.basis.y * 6.0, col)
		_line(im, r, r + f.basis.y * 6.0, col)
		_line(im, l + f.basis.y * 6.0, r + f.basis.y * 6.0, col)
	for k in keys_of("StartKey"):
		var f := _key_frame(k)
		var i := s.index_at(track_s_for_base(k.distance))
		var col := Color(0.3, 1.0, 0.4) if k.distance_to_track <= KEY_FAR else Color(1, 0, 0)
		_line(im, k.global_position, f.origin + f.basis.y * 2.0, col)
		var l := f.origin - f.basis.x * s.width_l[i]
		var r := f.origin + f.basis.x * s.width_r[i]
		_line(im, l + f.basis.y * 0.3, r + f.basis.y * 0.3, col)
		_line(im, l, l + f.basis.y * 10.0, col)
		_line(im, r, r + f.basis.y * 10.0, col)
		_line(im, l + f.basis.y * 10.0, r + f.basis.y * 10.0, col)
	# Boost pads: each pad's outline on the road with a chevron, a leader to
	# the node.
	var pad_col := Color(1.0, 0.45, 0.0)
	for k in all_keys_of("BoostPadKey"):
		var f := _key_frame(k)
		_line(im, k.global_position, f.origin + f.basis.y * 2.0,
				pad_col if k.distance_to_track <= KEY_FAR else Color(1, 0, 0))
	for p in pad_placements():
		var f: Transform3D = (p.track as TrackSampler).frame_at(p.s)
		var c: Vector3 = f.origin + f.basis.x * float(p.x) + f.basis.y * 0.3
		var rx := f.basis.x * BoostPadKey.PAD_HALF_WIDTH
		var fz := -f.basis.z * BoostPadKey.PAD_HALF_LENGTH
		_line(im, c - rx - fz, c + rx - fz, pad_col)
		_line(im, c + rx - fz, c + rx + fz, pad_col)
		_line(im, c + rx + fz, c - rx + fz, pad_col)
		_line(im, c - rx + fz, c - rx - fz, pad_col)
		_line(im, c - rx * 0.6 - fz * 0.2, c + fz * 0.6, pad_col)   # a chevron pointing forward
		_line(im, c + rx * 0.6 - fz * 0.2, c + fz * 0.6, pad_col)
	# Features: footprint ends (base curve) as tall gates, a leader to the node.
	var tracks: Array = [[sampler, composer]]
	for be in branches:
		tracks.append([be.track, be.composer])
	for tc: Array in tracks:
		var ts: TrackSampler = tc[0]
		for p in (tc[1] as TrackComposer).placed:
			var col := Color(0.85, 0.4, 1.0)
			for sd: float in [p.s0, p.s1]:
				var f := ts.frame_at(sd)
				var i := ts.index_at(sd)
				var l := f.origin - f.basis.x * ts.width_l[i]
				var r := f.origin + f.basis.x * ts.width_r[i]
				_line(im, l, l + f.basis.y * 16.0, col)
				_line(im, r, r + f.basis.y * 16.0, col)
				_line(im, l + f.basis.y * 16.0, r + f.basis.y * 16.0, col)
			var mid := ts.frame_at((p.s0 + p.s1) * 0.5)
			_line(im, (p.node as Node3D).global_position, mid.origin + mid.basis.y * 2.0, col)
	im.surface_end()
	var mi := MeshInstance3D.new()
	mi.name = "Lines"
	mi.mesh = im
	mi.material_override = _vertex_material(true, 1.0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)


## Centre line and road edges of one track.
func _track_lines(im: ImmediateMesh, s: TrackSampler) -> void:
	var idx := _preview_indices(s)
	for e in idx.size() - 1:
		var i := idx[e]
		var j := idx[e + 1]
		var ri := TrackSampler.right_of(s.T[i], s.U[i])
		var rj := TrackSampler.right_of(s.T[j], s.U[j])
		var up_i := s.U[i] * 0.15
		var up_j := s.U[j] * 0.15
		_line(im, s.P[i] + up_i, s.P[j] + up_j, Color(1, 1, 1, 0.9))
		_line(im, s.P[i] - ri * s.width_l[i] + up_i, s.P[j] - rj * s.width_l[j] + up_j, Color(0.1, 0.1, 0.1))
		_line(im, s.P[i] + ri * s.width_r[i] + up_i, s.P[j] + rj * s.width_r[j] + up_j, Color(0.1, 0.1, 0.1))


func _draw_labels(root: Node3D) -> void:
	var s := sampler
	if label_every > 0.0:
		var d := 0.0
		while d < s.length:
			var f := s.frame_at(d)
			var km := is_zero_approx(fmod(d, 1000.0))
			var txt := "%.1f km" % (d / 1000.0) if d >= 1000.0 else "%d m" % int(d)
			# 100 m ticks only up close; whole kilometres from further out.
			_label(root, f.origin + f.basis.y * 5.0, txt,
					Color(1, 0.9, 0.3) if km else Color(1, 1, 1), 3000.0 if km else 600.0)
			d += label_every
	for k in all_keys_of("BankKey"):
		var f := _key_frame(k)
		_label(root, f.origin + f.basis.y * 10.0, k.label_text(), Color(1.0, 0.65, 0.2), 1500.0)
	for k in all_keys_of("WidthKey"):
		var f := _key_frame(k)
		_label(root, f.origin + f.basis.y * 13.0, k.label_text(), Color(0.4, 0.9, 1.0), 1500.0)
	for k in keys_of("StartKey"):
		var f := _key_frame(k)
		_label(root, f.origin + f.basis.y * 14.0, k.label_text(), Color(0.3, 1.0, 0.4), 3000.0)
	for k in all_keys_of("BoostPadKey"):
		var f := _key_frame(k)
		_label(root, f.origin + f.basis.y * 8.0, k.label_text(), Color(1.0, 0.55, 0.1), 1500.0)
	for p in composer.placed:
		var f := s.frame_at(p.s0)
		_label(root, f.origin + f.basis.y * 18.0, "%s ▸ %.0f m" % [p.node.label_text(), p.s1 - p.s0],
				Color(0.85, 0.5, 1.0), 4000.0)
	for be in branches:
		for p in be.composer.placed:
			var f := be.track.frame_at(p.s0)
			_label(root, f.origin + f.basis.y * 18.0, "%s ▸ %.0f m" % [p.node.label_text(), p.s1 - p.s0],
					Color(0.85, 0.5, 1.0), 4000.0)
		if be.track.size() > 1:
			var f := be.track.frame_at(be.track.length * 0.5)
			_label(root, f.origin + f.basis.y * 18.0, "%s (%.0f m)" % [be.node.branch_name, be.track.length],
					Color(0.3, 0.9, 1.0), 6000.0)


func _label(root: Node3D, pos: Vector3, txt: String, col: Color, visible_to: float) -> void:
	var l := Label3D.new()
	l.visibility_range_end = visible_to
	l.visibility_range_end_margin = visible_to * 0.1
	l.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	l.text = txt
	l.modulate = col
	l.outline_modulate = Color(0, 0, 0)
	l.outline_size = 12
	l.font_size = 32
	l.pixel_size = 0.0008          # with fixed_size: about 26 px tall on screen
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.fixed_size = true
	root.add_child(l)
	l.global_position = pos


func _line(im: ImmediateMesh, a: Vector3, b: Vector3, c: Color) -> void:
	im.surface_set_color(c)
	im.surface_add_vertex(a)
	im.surface_set_color(c)
	im.surface_add_vertex(b)


func _vertex_material(no_depth: bool, alpha: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = no_depth
	if alpha < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color = Color(1, 1, 1, alpha)
	return m


# =============================================================================
# OVERLAYS
# =============================================================================

func lateral_g(i: int, s: TrackSampler = null) -> float:
	if s == null:
		s = sampler
	return ref_speed * ref_speed * s.curvature_h(i) / game_gravity


func _overlay_color(i: int, s: TrackSampler) -> Color:
	match overlay:
		Overlay.BANK:
			return _diverging(s.bank[i] / 30.0)
		Overlay.ROLL_RATE:
			var r := s.roll_rate(i)
			if r > ROLL_LIMIT:
				return Color(0.95, 0.1, 0.1)
			return _ramp(r / ROLL_LIMIT)
		Overlay.LATERAL_G:
			return _ramp(absf(lateral_g(i, s)) / 4.0)
		Overlay.GRADE:
			return _diverging(s.grade(i) / 15.0)
		Overlay.WIDTH:
			if s.taper_rate(i) > TAPER_LIMIT:
				return Color(0.95, 0.1, 0.1)
			var w := (s.width_l[i] + s.width_r[i]) * 0.5
			var x := (w - TrackSampler.DEFAULT_HALF_WIDTH) / 10.0
			if x < 0.0:
				return Color(0.55, 0.55, 0.58).lerp(Color(0.2, 0.45, 1.0), clampf(-x, 0.0, 1.0))
			return Color(0.55, 0.55, 0.58).lerp(Color(1.0, 0.6, 0.1), clampf(x, 0.0, 1.0))
		Overlay.FAIRING:
			return _ramp(s.fair_dev[i] / 2.0)
	return Color(0.5, 0.5, 0.5)


## -1 (blue) .. 0 (grey) .. +1 (red).
static func _diverging(x: float) -> Color:
	var grey := Color(0.55, 0.55, 0.58)
	if x < 0.0:
		return grey.lerp(Color(0.15, 0.4, 1.0), clampf(-x, 0.0, 1.0))
	return grey.lerp(Color(1.0, 0.25, 0.15), clampf(x, 0.0, 1.0))


## 0 (green) .. 0.5 (yellow) .. 1 (orange-red).
static func _ramp(x: float) -> Color:
	x = clampf(x, 0.0, 1.0)
	if x < 0.5:
		return Color(0.2, 0.75, 0.3).lerp(Color(0.95, 0.85, 0.2), x * 2.0)
	return Color(0.95, 0.85, 0.2).lerp(Color(1.0, 0.4, 0.1), (x - 0.5) * 2.0)


# =============================================================================
# GREEBLES
# =============================================================================

## Resolves the GreebleZoneKeys against the built track, writes the
## TrackGreebles node (made if missing) and re-dresses. Needs a Build.
func refresh_greebles() -> void:
	_greebles_dirty = false
	var root: Node = owner if owner else get_parent()
	if root == null:
		return
	var t0 := Time.get_ticks_usec()
	var keys := TrackGreebler.all_keys(self)
	var node := root.get_node_or_null(GREEBLES_NODE) as TrackGreebles
	if keys.is_empty() and node == null:
		_last_greebles = ""
		_clear_greeble_markers()
		report = _make_report()
		return
	var g := TrackGreebler.resolve(self, root)
	if not g.ok():
		_last_greebles = "Greebles: " + "; ".join(g.notes)
		_draw_greeble_markers(g)
		report = _make_report()
		return
	if node == null:
		node = (load(GREEBLES_SCRIPT) as GDScript).new() as TrackGreebles
		node.name = GREEBLES_NODE
		root.add_child(node)
		node.owner = root
		node.add_to_group(TrackBuild.GROUP, true)
	if g.write(node, self):
		_mark_unsaved()
		node.rebuild()
	elif node.instance_total == 0 and node.editor_preview:
		node.rebuild()
	_draw_greeble_markers(g)
	_last_greebles = "Greebles: %d zones, %d instances, %.0f ms%s" % [node.zones.size(), node.instance_total,
			(Time.get_ticks_usec() - t0) / 1000.0, "" if g.notes.is_empty() else "\n  " + "\n  ".join(g.notes)]
	report = _make_report()


func remove_greebles() -> void:
	var root: Node = owner if owner else get_parent()
	var node := root.get_node_or_null(GREEBLES_NODE) if root else null
	if node:
		node.get_parent().remove_child(node)
		node.free()
		_mark_unsaved()
	_clear_greeble_markers()
	_last_greebles = "Greebles removed (Refresh greebles or Build makes them again)"
	report = _make_report()


func _clear_greeble_markers() -> void:
	var n := get_node_or_null(GREEBLE_PREVIEW_NAME)
	if n:
		n.free()


## A gate across the road at each zone's start (posts on the wall tops) and
## a label: style, mirrored, density, length. Red leader = too far away.
func _draw_greeble_markers(g: TrackGreebler) -> void:
	_clear_greeble_markers()
	if not greeble_markers or g.keys.is_empty():
		return
	var root := Node3D.new()
	root.name = GREEBLE_PREVIEW_NAME
	root.top_level = true
	add_child(root)        # owner left unset: never saved
	root.global_transform = Transform3D.IDENTITY
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	var col := Color(0.75, 1.0, 0.25)
	for k in g.keys:
		var fv: Variant = g.key_frame(k)
		if fv == null:
			continue
		var f: Transform3D = fv
		var far := k.distance_to_track > TrackGreebler.KEY_FAR
		_line(im, k.global_position, f.origin + f.basis.y * 2.0, Color(1, 0, 0) if far else col)
		var h := 12.0
		var l := f.origin - f.basis.x * 26.0
		var r := f.origin + f.basis.x * 26.0
		_line(im, l + f.basis.y * 8.0, l + f.basis.y * h, col)
		_line(im, r + f.basis.y * 8.0, r + f.basis.y * h, col)
		_line(im, l + f.basis.y * h, r + f.basis.y * h, col)
		# An arrow along the road: the zone runs this way.
		var c := f.origin + f.basis.y * h
		_line(im, c, c - f.basis.z * 10.0, col)
		_line(im, c - f.basis.z * 10.0, c - f.basis.z * 7.0 + f.basis.x * 2.0, col)
		_line(im, c - f.basis.z * 10.0, c - f.basis.z * 7.0 - f.basis.x * 2.0, col)
		var zl := g.zone_length(k)
		_label(root, f.origin + f.basis.y * (h + 3.0),
				"%s ▸ %.0f m" % [k.label_text(), zl] if zl > 0.0 else k.label_text(), col, 2500.0)
	im.surface_end()
	var mi := MeshInstance3D.new()
	mi.name = "Lines"
	mi.mesh = im
	mi.material_override = _vertex_material(true, 1.0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)


# =============================================================================
# BUILD AND VALIDATE
# =============================================================================

var _last_build := ""
var _last_validate := ""

func clear_build() -> void:
	var n := TrackBuild.clear(self)
	_last_build = "Cleared %d generated nodes" % n
	_last_validate = ""
	_clear_issues()
	if n > 0:
		ribbon = true
		_mark_unsaved()
	preview()


func build() -> void:
	var r := TrackBuild.run(self)
	_last_build = "\n".join(r.log)
	print(_last_build)
	if r.ok:
		ribbon = false
		_mark_unsaved()
	_last_validate = ""
	_clear_issues()
	preview()
	if r.ok:
		refresh_greebles()


## Validates and marks problems in the viewport. The physics space needs a
## frame to pick up freshly built road; if it hasn't, Validate says so.
func validate() -> TrackValidator:
	var space := get_world_3d().direct_space_state if is_inside_tree() else null
	var v := TrackValidator.run(self, space)
	_last_validate = v.summary()
	print(_last_validate)
	_draw_issues(v)
	report = _make_report()
	return v


func input_hash() -> int:
	var parts := []
	var path := base_path()
	if path and path.curve:
		var c := path.curve
		parts.append(c.closed)
		for i in c.point_count:
			parts.append([c.get_point_position(i), c.get_point_in(i), c.get_point_out(i), c.get_point_tilt(i)])
	for t: String in ["BankKey", "WidthKey", "StartKey", "BoostPadKey"]:
		for k in keys_of(t):
			var vals := [t, k.global_position, k.ease]
			if k is BankKey:
				vals.append((k as BankKey).bank_deg)
			elif k is WidthKey:
				vals.append_array([(k as WidthKey).half_width_left, (k as WidthKey).half_width_right])
			elif k is BoostPadKey:
				var pk := k as BoostPadKey
				vals.append_array([pk.anchor, pk.offset, pk.count, pk.spacing, pk.strength])
			parts.append(vals)
	for f in features():
		var vals := [f.get_script().get_global_name(), f.global_position]
		for prop in f.get_property_list():
			if prop.usage & PROPERTY_USAGE_SCRIPT_VARIABLE and prop.usage & PROPERTY_USAGE_STORAGE \
					and not prop.name in ["distance", "distance_to_track"]:
				vals.append([prop.name, f.get(prop.name)])
		parts.append(vals)
	for bf in branch_nodes():
		var bp := bf.base_path()
		var vals := [bf.name, bf.branch_name, bf.junction_blend, bf.enabled]
		if bp and bp.curve:
			for i in bp.curve.point_count:
				vals.append([bp.curve.get_point_position(i), bp.curve.get_point_in(i), bp.curve.get_point_out(i)])
		var be := TrackBranchEval.new(bf)
		for k in be.keys_of(""):
			if k is GreebleZoneKey:
				continue    # dressing only: never makes the build out of date
			var kv := [k.get_script().get_global_name(), k.global_position]
			for prop in k.get_property_list():
				if prop.usage & PROPERTY_USAGE_SCRIPT_VARIABLE and prop.usage & PROPERTY_USAGE_STORAGE \
						and not prop.name in ["distance", "distance_to_track"]:
					kv.append([prop.name, k.get(prop.name)])
			vals.append(kv)
		parts.append(vals)
	parts.append([fairing_m, start_lead])
	return hash(var_to_bytes(parts))


func _clear_issues() -> void:
	var n := get_node_or_null(ISSUES_NAME)
	if n:
		n.free()


func _draw_issues(v: TrackValidator) -> void:
	_clear_issues()
	if v.issues.is_empty() or not Engine.is_editor_hint():
		return
	var root := Node3D.new()
	root.name = ISSUES_NAME
	root.top_level = true
	add_child(root)      # no owner: never saved
	root.global_transform = Transform3D.IDENTITY
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	for i in v.issues:
		var col := Color(1, 0.15, 0.1) if i.sev == TrackValidator.Sev.ERROR else Color(1, 0.75, 0.1)
		var p: Vector3 = i.pos
		_line(im, p, p + Vector3.UP * 40.0, col)
		_line(im, p + Vector3(-6, 0, 0), p + Vector3(6, 0, 0), col)
		_line(im, p + Vector3(0, 0, -6), p + Vector3(0, 0, 6), col)
		_label(root, p + Vector3.UP * 42.0, i.msg, col, 4000.0)
	im.surface_end()
	var mi := MeshInstance3D.new()
	mi.mesh = im
	mi.material_override = _vertex_material(true, 1.0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)


func _mark_unsaved() -> void:
	if not Engine.is_editor_hint():
		return
	var ei := Engine.get_singleton("EditorInterface")
	if ei:
		ei.mark_scene_as_unsaved()


## TB_EDITOR_SELFTEST=1: exercises Build and Validate inside a running editor
## (headless), then quits without saving. For checking the editor code path.
func _editor_selftest() -> void:
	await get_tree().create_timer(1.0).timeout
	print("SELFTEST build")
	build()
	for i in 3:
		await get_tree().process_frame
	print("SELFTEST validate (after 3 frames)")
	var v := validate()
	# v36: the greebler's live path (a key moved, a preset swapped, a local copy).
	var gk := TrackGreebler.all_keys(self)
	if not gk.is_empty():
		var k := gk[0]
		k.global_position += Vector3(0, 0, -40.0)
		k.preset = "maritime"
		k.make_local_copy()
		for i in 20:
			await get_tree().process_frame
		await get_tree().create_timer(DEBOUNCE_S + 0.1).timeout
		for i in 3:
			await get_tree().process_frame
		print("SELFTEST greebles: %s" % _last_greebles.replace("\n", " | "))
		var node := (owner if owner else get_parent()).get_node_or_null(GREEBLES_NODE) as TrackGreebles
		print("SELFTEST greebles node: %d zones, first style '%s' (%s), %d instances in the editor" % [
				node.zones.size() if node else -1,
				node.zones[0].style.style_name if node and node.zones.size() > 0 else "-",
				node.zones[0].style.resource_path if node and node.zones.size() > 0 else "-",
				node.instance_total if node else -1])
	print("SELFTEST done: %d errors, %d warnings" % [v.errors(), v.warnings()])
	get_tree().quit(0 if v.errors() == 0 else 1)


# =============================================================================
# REPORT
# =============================================================================

func _make_report() -> String:
	var s := sampler
	var max_roll := 0.0
	var max_g := 0.0
	var max_grade := 0.0
	var max_taper := 0.0
	var min_w := INF
	var max_w := 0.0
	for i in s.size():
		max_roll = maxf(max_roll, s.roll_rate(i))
		if s.feat.size() == s.size() and s.feat[i] >= 0:
			continue    # lateral g and grade mean nothing in a loop or on a kicker
		max_g = maxf(max_g, absf(lateral_g(i)))
		max_grade = maxf(max_grade, absf(s.grade(i)))
		max_taper = maxf(max_taper, s.taper_rate(i))
		min_w = minf(min_w, minf(s.width_l[i], s.width_r[i]))
		max_w = maxf(max_w, maxf(s.width_l[i], s.width_r[i]))
	var lines: PackedStringArray = []
	if not _last_build.is_empty():
		lines.append(_last_build)
	if not _last_validate.is_empty():
		lines.append(_last_validate)
	if not _last_greebles.is_empty():
		lines.append(_last_greebles)
	for e in errors():
		lines.append("✗ " + e)
	for be in branches:
		if be.ok:
			lines.append("%s: %.0f m, leaves at %.0f m, rejoins at %.0f m (main route %.0f m), junctions end %.0f / %.0f m along it"
					% [be.node.name, be.track.length, be.s_fork, be.s_rejoin, be.s_rejoin - be.s_fork, be.jf_b, be.jr_b])
			lines.append("  junctions levelled: main moved up to %.2f m, branch up to %.2f m"
					% [composer.levelled_max, be.levelled_max])
	for p in composer.placed:
		lines.append("%s: %.0f m of base -> %.0f m of track" % [p.node.name, p.d1 - p.d0, p.s1 - p.s0])
	lines.append("Length %.0f m (%s), %d samples, preview %.0f ms"
			% [s.length, "closed" if s.closed else "open", s.size(), _last_ms])
	lines.append("Fairing moved the curve at most %.2f m" % s.fair_deviation)
	lines.append("Max roll rate %.2f °/m%s" % [max_roll, "  ← over 0.7" if max_roll > ROLL_LIMIT else ""])
	lines.append("Max lateral load %.2f g at %.0f u/s (outside features)" % [max_g, ref_speed])
	lines.append("Max grade %.1f %% (outside features)" % max_grade)
	lines.append("Half width %.1f – %.1f m, max taper %.3f m/m%s"
			% [min_w, max_w, max_taper, "  ← over 0.1" if max_taper > TAPER_LIMIT else ""])
	for k in keys_of("BankKey") + keys_of("WidthKey") + keys_of("StartKey") + all_keys_of("BoostPadKey"):
		if k.distance_to_track > KEY_FAR:
			lines.append("⚠ %s is %.0f m from the track (limit 30)" % [k.name, k.distance_to_track])
	for w in _offset_rule_problems():
		lines.append("⚠ " + w)
	return "\n".join(lines)


## The offset rule: no transforms between the scene root and the curve.
func _offset_rule_problems() -> PackedStringArray:
	var out: PackedStringArray = []
	var root: Node = owner if owner else self
	var n: Node = base_path()
	while n:
		if n is Node3D and not (n as Node3D).transform.is_equal_approx(Transform3D.IDENTITY):
			out.append("%s has a non-identity transform (offset rule)" % n.name)
		if n == root:
			break
		n = n.get_parent()
	return out


# =============================================================================
# INTERNALS
# =============================================================================

func _watch_curve() -> void:
	var path := base_path()
	var c: Curve3D = path.curve if path else null
	if c == _watched:
		return
	if _watched and _watched.changed.is_connected(mark_dirty):
		_watched.changed.disconnect(mark_dirty)
	_watched = c
	if c:
		c.changed.connect(mark_dirty)
	mark_dirty()


func _collect(n: Node, type: String, out: Array[ProfileKey]) -> void:
	for c in n.get_children():
		if c.name in [PREVIEW_NAME, ISSUES_NAME, GREEBLE_PREVIEW_NAME] or c is BranchFeature:
			continue
		if c is ProfileKey and (type.is_empty() or (c as Object).get_script().get_global_name() == type):
			out.append(c)
		_collect(c, type, out)


static func _now() -> float:
	return Time.get_ticks_msec() / 1000.0
