@tool
extends Node3D
class_name TrackBuilder
## Track Builder (v34): authoring node for new tracks.
##
## Draw the base curve by hand (the BaseSpline child, a Path3D), then drop
## BankKey and WidthKey nodes anywhere near it. The preview ribbon follows
## every edit within a fraction of a second, coloured by the overlay you pick.
##
## Rules (see docs/TRACK_AUTHORING.md):
##   * identity transforms on the track root, this node and BaseSpline;
##   * bank comes from BankKeys only, never typed tilts;
##   * width comes from WidthKeys; the walls follow the road edge.
##
## Step 1 of the plan: preview only. Build and Validate come next.
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

@export_group("Preview")
@export var auto_preview: bool = true:
	set(v):
		auto_preview = v
		if v:
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

@export_group("Report (read only)")
@export_multiline var report: String = ""

## Headless tools (validator, checks) set this so the builder survives
## outside the editor.
static var keep_at_runtime := false

var sampler := TrackSampler.new()
var _dirty := false
var _dirty_at := 0.0
var _watched: Curve3D = null
var _last_ms := 0.0


func _ready() -> void:
	if not Engine.is_editor_hint():
		if not keep_at_runtime:
			# Authoring data only: the generated nodes are what the game uses.
			queue_free()
		return
	set_process(true)
	mark_dirty()


func _process(_delta: float) -> void:
	if not Engine.is_editor_hint():
		return
	_watch_curve()
	if _dirty and auto_preview and _now() - _dirty_at >= DEBOUNCE_S:
		preview()


func _validate_property(property: Dictionary) -> void:
	if property.name == "report":
		# Shown, never saved (it changes on every preview).
		property.usage = PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_READ_ONLY


func mark_dirty() -> void:
	_dirty = true
	_dirty_at = _now()


func base_path() -> Path3D:
	var n := get_node_or_null(base_spline)
	return n as Path3D


## Every BankKey / WidthKey under this builder, at any depth.
func keys_of(type: String) -> Array[ProfileKey]:
	var out: Array[ProfileKey] = []
	_collect(self, type, out)
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
	if not sampler.sample(path.curve, fairing_m):
		return false
	var bank_keys := _project(keys_of("BankKey"))
	var width_keys := _project(keys_of("WidthKey"))
	var bk: Array = []
	for k in bank_keys:
		bk.append({d = k.distance, bank = (k as BankKey).bank_deg, ease = k.ease})
	var wk: Array = []
	for k in width_keys:
		var w := k as WidthKey
		wk.append({d = k.distance, left = w.half_width_left, right = w.half_width_right, ease = k.ease})
	sampler.apply_bank_profile(bk)
	sampler.apply_width_profile(wk)
	return true


## Projects keys onto the track (writing their derived distances) and returns
## them sorted by distance.
func _project(keys: Array[ProfileKey]) -> Array[ProfileKey]:
	for k in keys:
		var r := sampler.project(k.global_position, k.distance)
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
	_draw_ribbon(root)
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


func _preview_indices() -> PackedInt32Array:
	var out := PackedInt32Array()
	var n := sampler.size()
	var every := maxi(1, int(round(preview_step / sampler.step())))
	var i := 0
	while i < n:
		out.append(i)
		i += every
	if sampler.closed:
		out.append(0)            # close the ribbon
	elif out[out.size() - 1] != n - 1:
		out.append(n - 1)
	return out


func _draw_ribbon(root: Node3D) -> void:
	var s := sampler
	var idx := _preview_indices()
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	var norms := PackedVector3Array()
	for i in idx:
		var r := TrackSampler.right_of(s.T[i], s.U[i])
		var c := _overlay_color(i)
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
	var idx := _preview_indices()
	# Centre line and road edges.
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
	for k in keys_of("BankKey"):
		var f := s.frame_at(k.distance)
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
	for k in keys_of("WidthKey"):
		var f := s.frame_at(k.distance)
		var i := s.index_at(k.distance)
		var col := Color(0.2, 0.85, 1.0) if k.distance_to_track <= KEY_FAR else Color(1, 0, 0)
		_line(im, k.global_position, f.origin + f.basis.y * 2.0, col)
		var l := f.origin - f.basis.x * s.width_l[i]
		var r := f.origin + f.basis.x * s.width_r[i]
		# Uprights at both edges, joined across.
		_line(im, l, l + f.basis.y * 6.0, col)
		_line(im, r, r + f.basis.y * 6.0, col)
		_line(im, l + f.basis.y * 6.0, r + f.basis.y * 6.0, col)
	im.surface_end()
	var mi := MeshInstance3D.new()
	mi.name = "Lines"
	mi.mesh = im
	mi.material_override = _vertex_material(true, 1.0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)


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
	for k in keys_of("BankKey"):
		var f := s.frame_at(k.distance)
		_label(root, f.origin + f.basis.y * 10.0, k.label_text(), Color(1.0, 0.65, 0.2), 1500.0)
	for k in keys_of("WidthKey"):
		var f := s.frame_at(k.distance)
		_label(root, f.origin + f.basis.y * 13.0, k.label_text(), Color(0.4, 0.9, 1.0), 1500.0)


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

func lateral_g(i: int) -> float:
	return ref_speed * ref_speed * sampler.curvature_h(i) / game_gravity


func _overlay_color(i: int) -> Color:
	var s := sampler
	match overlay:
		Overlay.BANK:
			return _diverging(s.bank[i] / 30.0)
		Overlay.ROLL_RATE:
			var r := s.roll_rate(i)
			if r > ROLL_LIMIT:
				return Color(0.95, 0.1, 0.1)
			return _ramp(r / ROLL_LIMIT)
		Overlay.LATERAL_G:
			return _ramp(absf(lateral_g(i)) / 4.0)
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
		max_g = maxf(max_g, absf(lateral_g(i)))
		max_grade = maxf(max_grade, absf(s.grade(i)))
		max_taper = maxf(max_taper, s.taper_rate(i))
		min_w = minf(min_w, minf(s.width_l[i], s.width_r[i]))
		max_w = maxf(max_w, maxf(s.width_l[i], s.width_r[i]))
	var lines: PackedStringArray = []
	lines.append("Length %.0f m (%s), %d samples, preview %.0f ms"
			% [s.length, "closed" if s.closed else "open", s.size(), _last_ms])
	lines.append("Fairing moved the curve at most %.2f m" % s.fair_deviation)
	lines.append("Max roll rate %.2f °/m%s" % [max_roll, "  ← over 0.7" if max_roll > ROLL_LIMIT else ""])
	lines.append("Max lateral load %.2f g at %.0f u/s" % [max_g, ref_speed])
	lines.append("Max grade %.1f %%" % max_grade)
	lines.append("Half width %.1f – %.1f m, max taper %.3f m/m%s"
			% [min_w, max_w, max_taper, "  ← over 0.1" if max_taper > TAPER_LIMIT else ""])
	for k in keys_of("BankKey") + keys_of("WidthKey"):
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
		if c.name == PREVIEW_NAME:
			continue
		if c is ProfileKey and (c as Object).get_script().get_global_name() == type:
			out.append(c)
		_collect(c, type, out)


static func _now() -> float:
	return Time.get_ticks_msec() / 1000.0
