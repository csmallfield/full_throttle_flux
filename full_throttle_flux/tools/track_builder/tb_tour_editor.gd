extends Node
## Track Builder tutorial: takes the screenshots for docs/track-builder inside a
## running editor, so they show what you'll actually see and can be retaken
## when the builder changes. Started by the TrackBuilder when TB_TOUR is set:
##
##   TB_TOUR=<absolute folder> godot -e --path full_throttle_flux res://scenes/tracks/builder_lab.tscn
##
## TB_TOUR_ONLY=<prefix> retakes only the shots whose names start with it.
## Every change is put back and the scene is never saved; the editor will show
## it as modified, because live preview rewrites the generated nodes. Quit
## without saving if you run this by hand. The validator's report is written
## next to the pictures (report_*.txt) for the page to quote.

var tb: TrackBuilder
var out := ""
var only := ""
var ei: Object
var cam: Camera3D


func _ready() -> void:
	out = OS.get_environment("TB_TOUR")
	only = OS.get_environment("TB_TOUR_ONLY")
	DirAccess.make_dir_recursive_absolute(out)
	ei = Engine.get_singleton("EditorInterface")
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


## Waits out the builder's debounced live refreshes (preview, greebles, surface).
func _settle(seconds := 1.2) -> void:
	await get_tree().create_timer(seconds).timeout
	await _frames(6)


## TB_TOUR_ONLY takes one prefix, or several separated by commas.
func _wants(name: String) -> bool:
	if only == "":
		return true
	for p in only.split(","):
		if name.begins_with(p):
			return true
	return false


## Saves the editor window, or `area` of it.
func _shot(name: String, area := Rect2()) -> void:
	if not _wants(name):
		return
	await _frames(6)
	await RenderingServer.frame_post_draw
	var img := get_tree().root.get_texture().get_image()
	if area.size != Vector2.ZERO:
		img = img.get_region(Rect2i(area))
	img.convert(Image.FORMAT_RGB8)
	var err := img.save_jpg("%s/%s.jpg" % [out, name], 0.88)
	print("TBTOUR %s %s %s" % [name, img.get_size(), error_string(err)])


func _view_rect() -> Rect2:
	var vp: SubViewport = ei.get_editor_viewport_3d(0)
	return (vp.get_parent() as Control).get_global_rect()


func _inspector_rect() -> Rect2:
	var insp: Control = ei.get_inspector()
	var r := insp.get_global_rect()
	# Include the node picker above the properties.
	return Rect2(r.position - Vector2(0, 46), r.size + Vector2(0, 46))


func _dock_rect(cls: String) -> Rect2:
	var found: Array = ei.get_base_control().find_children("*", cls, true, false)
	return (found[0] as Control).get_global_rect() if not found.is_empty() else Rect2()


func _select(n: Node) -> void:
	var sel: Object = ei.get_selection()
	sel.clear()
	sel.add_node(n)
	ei.edit_node(n)
	await _frames(4)


func _node(path: String) -> Node:
	var n := tb.get_node_or_null(path)
	if n == null:
		push_warning("TBTOUR no node %s" % path)
	return n


func _look(from: Vector3, to: Vector3) -> void:
	var up := Vector3.UP if absf((to - from).normalized().y) < 0.98 else Vector3.FORWARD
	cam.global_transform = Transform3D(Basis.looking_at(to - from, up), from)


## The whole main track from above.
func _top() -> void:
	var s := tb.sampler
	var b := AABB(s.P[0], Vector3.ZERO)
	for p in s.P:
		b = b.expand(p)
	for be in tb.branches:
		for p in be.track.P:
			b = b.expand(p)
	var r := _view_rect()
	var aspect := r.size.x / maxf(r.size.y, 1.0)
	var half_v := tan(deg_to_rad(cam.fov * 0.5))
	var need := maxf(b.size.z * 0.5, b.size.x * 0.5 / aspect) * 1.08
	var c := b.get_center()
	_look(c + Vector3(0, need / half_v, 0.001), c)


## Above and beside the track at `d`, looking along it.
func _oblique(track: TrackSampler, d: float, back := 160.0, side := -90.0, up := 70.0, ahead := 60.0) -> void:
	var f := track.frame_at(d)
	var fwd := -f.basis.z
	var eye := f.origin - fwd * back + f.basis.x * side + Vector3.UP * up
	_look(eye, track.frame_at(d + ahead).origin)


## Chase height at `d`, looking `ahead` metres down the road.
func _chase(track: TrackSampler, d: float, ahead := 150.0, height := 14.0) -> void:
	var f := track.frame_at(d)
	var to := track.frame_at(d + ahead)
	var eye := f.origin + f.basis.y * height
	cam.global_transform = Transform3D(Basis.looking_at(to.origin + to.basis.y * 2.0 - eye, f.basis.y), eye)


func _key_pose(k: ProfileKey, back := 70.0, side := -45.0, up := 32.0) -> void:
	var t := tb._key_track(k)
	var f := t.frame_at(k.distance)
	var fwd := -f.basis.z
	_look(f.origin - fwd * back + f.basis.x * side + Vector3.UP * up, f.origin + fwd * 25.0)


## Labels and zone markers off (true) or back to the scene's settings.
var _saved_view := {}
func _clean(on: bool) -> void:
	if on:
		_saved_view = {label_every = tb.label_every, greeble_markers = tb.greeble_markers,
				surface_markers = tb.surface_markers}
		tb.label_every = 0.0
		tb.greeble_markers = false
		tb.surface_markers = false
	else:
		for k: String in _saved_view:
			tb.set(k, _saved_view[k])
	tb.preview()


func _placed(node: Node) -> Dictionary:
	for p in tb.composer.placed:
		if p.node == node:
			return p
	return {}


func _run() -> void:
	await _settle(3.0)
	var vp: SubViewport = ei.get_editor_viewport_3d(0)
	cam = vp.get_camera_3d()
	cam.far = 20000.0
	tb.overlay = TrackBuilder.Overlay.BANK
	tb.ribbon = true
	tb.preview()
	await _select(tb)
	await _settle()

	# The editor with Builder Lab open.
	_top()
	await _shot("overview")
	await _shot("scene_tree", _dock_rect("SceneTreeDock"))
	await _shot("insp_builder", _inspector_rect())

	# Every overlay, from above, without labels or zone markers.
	_clean(true)
	for o: int in TrackBuilder.Overlay.values():
		tb.overlay = o
		tb.preview()
		await _frames(3)
		await _shot("overlay_" + String(TrackBuilder.Overlay.keys()[o]).to_lower(), _view_rect())
	tb.overlay = TrackBuilder.Overlay.BANK
	_clean(false)

	await _keys()
	await _features()
	await _examples()
	await _validator()
	await _built()
	await _dressing()

	# Leave it as found.
	tb.overlay = TrackBuilder.Overlay.BANK
	tb.ribbon = true
	tb.preview()
	print("TBTOUR done")
	get_tree().quit(0)


# =============================================================================
# KEYS AND FEATURES
# =============================================================================

func _keys() -> void:
	for spec: Array in [
			["BankKeys/Bank03", "key_bank"],
			["WidthKeys/Width02", "key_width"],
			["StartKey", "key_start"],
			["BoostPadKeys/BoostRow", "key_boost"]]:
		var k := _node(spec[0]) as ProfileKey
		if k == null:
			continue
		await _select(k)
		_key_pose(k)
		await _shot(spec[1], _view_rect())
		await _shot("insp_" + spec[1].trim_prefix("key_"), _inspector_rect())


func _features() -> void:
	var roll := _node("Features/Roll")
	var loop := _node("Features/Loop")
	var jump := _node("Features/Jump")
	var fork := _node("Features/Shortcut")
	var s := tb.sampler
	if roll:
		var p := _placed(roll)
		await _select(roll)
		_oblique(s, p.s0 + 120.0, 110.0, -55.0, 38.0, 260.0)
		await _shot("feat_roll", _view_rect())
		await _shot("insp_roll", _inspector_rect())
	if loop:
		var p := _placed(loop)
		await _select(loop)
		var mid: float = (p.marks.zone_from + p.marks.zone_to) * 0.5
		var top := s.frame_at(mid).origin
		var base := s.frame_at(p.s0).origin
		var side := TrackSampler.right_of(-s.frame_at(p.s0).basis.z, Vector3.UP)
		var eye := (top + base) * 0.5 + side * -360.0 + Vector3.UP * 30.0
		_look(eye, top + Vector3.DOWN * 65.0)
		await _shot("feat_loop", _view_rect())
		await _shot("insp_loop", _inspector_rect())
	if jump:
		var p := _placed(jump)
		await _select(jump)
		_oblique(s, p.marks.kicker, 150.0, -110.0, 45.0, 80.0)
		await _shot("feat_jump", _view_rect())
		await _shot("insp_jump", _inspector_rect())
	if fork:
		await _select(fork)
		for be in tb.branches:
			if be.ok:
				var a := s.frame_at(be.s_fork - 150.0)
				var b := s.frame_at(be.s_fork + 650.0)
				_look(a.origin + Vector3.UP * 520.0 + a.basis.x * -150.0, (a.origin + b.origin) * 0.5)
				await _shot("feat_fork", _view_rect())
				break
		await _shot("insp_fork", _inspector_rect())


# =============================================================================
# WORKED EXAMPLES: each the saved value, then an edit, then put back
# =============================================================================

func _examples() -> void:
	var s := tb.sampler
	_clean(true)
	# Bank: steeper on one key.
	var bank := _node("BankKeys/Bank03") as BankKey
	if bank and _wants("ex_bank"):
		tb.overlay = TrackBuilder.Overlay.BANK
		tb.preview()
		var was := bank.bank_deg
		_key_pose(bank, 260.0, -170.0, 140.0)
		await _settle()
		await _shot("ex_bank_before", _view_rect())
		bank.bank_deg = clampf(was + signf(was if was != 0.0 else 1.0) * 18.0, -80.0, 80.0)
		await _settle()
		await _shot("ex_bank_after", _view_rect())
		print("TBTOUR bank %s: %.1f -> %.1f" % [bank.name, was, bank.bank_deg])
		bank.bank_deg = was
		await _settle()
	# Width: one side wider.
	var width := _node("WidthKeys/Width02") as WidthKey
	if width and _wants("ex_width"):
		tb.overlay = TrackBuilder.Overlay.WIDTH
		tb.preview()
		var wl := width.half_width_left
		var wr := width.half_width_right
		var linked := width.linked
		_key_pose(width, 260.0, -170.0, 150.0)
		await _settle()
		await _shot("ex_width_before", _view_rect())
		width.linked = false
		width.half_width_left = minf(wl + 10.0, 45.0)
		await _settle()
		await _shot("ex_width_after", _view_rect())
		print("TBTOUR width %s: left %.1f -> %.1f" % [width.name, wl, width.half_width_left])
		width.half_width_left = wl
		width.half_width_right = wr
		width.linked = linked
		await _settle()
	# Roll: shorter, so it rolls faster than the limit.
	var roll := _node("Features/Roll") as RollFeature
	if roll and _wants("ex_roll"):
		tb.overlay = TrackBuilder.Overlay.ROLL_RATE
		tb.preview()
		var was := roll.length
		var p := _placed(roll)
		_oblique(s, p.s0 + 120.0, 110.0, -55.0, 38.0, 260.0)
		await _settle()
		await _shot("ex_roll_before", _view_rect())
		roll.length = 560.0
		await _settle()
		p = _placed(roll)
		_oblique(s, p.s0 + 120.0, 110.0, -55.0, 38.0, 260.0)
		await _shot("ex_roll_after", _view_rect())
		roll.length = was
		await _settle()
	tb.overlay = TrackBuilder.Overlay.BANK
	_clean(false)
	await _settle()


# =============================================================================
# THE VALIDATOR
# =============================================================================

func _validator() -> void:
	if not _wants("validate") and not _wants("report"):
		return
	await _select(tb)
	var v := tb.validate()
	_write_report("report_clean", v)
	_clean(true)
	_top()
	await _shot("validate_clean", _view_rect())
	_clean(false)
	# Break two things on purpose, then Build so the report judges the new
	# design rather than a stale build: a roll too short for its turn, and a
	# width key dragged off into the field.
	var roll := _node("Features/Roll") as RollFeature
	var width := _node("WidthKeys/Width02") as WidthKey
	var was_len := roll.length if roll else 0.0
	var was_pos := width.global_position if width else Vector3.ZERO
	if roll:
		roll.length = 560.0
	if width:
		var f := tb._key_track(width).frame_at(width.distance)
		width.global_position = f.origin + f.basis.x * -45.0
	await _settle()
	tb.build()
	await _settle(2.0)
	v = tb.validate()
	await _frames(4)
	_write_report("report_broken", v)
	if roll:
		_clean(true)
		tb.overlay = TrackBuilder.Overlay.ROLL_RATE
		tb.preview()
		var p := _placed(roll)
		_oblique(tb.sampler, p.s0 + 60.0, 130.0, -80.0, 70.0, 220.0)
		await _settle()
		await _shot("validate_broken", _view_rect())
		tb.overlay = TrackBuilder.Overlay.BANK
		_clean(false)
	if roll:
		roll.length = was_len
	if width:
		width.global_position = was_pos
	await _settle()
	tb.build()
	await _settle(2.0)
	v = tb.validate()
	_write_report("report_fixed", v)


func _write_report(name: String, v: TrackValidator) -> void:
	var f := FileAccess.open("%s/%s.txt" % [out, name], FileAccess.WRITE)
	if f:
		f.store_string(tb.report)
	print("TBTOUR %s: %d errors, %d warnings" % [name, v.errors(), v.warnings()])


# =============================================================================
# THE BUILT ROAD, GREEBLES AND SURFACE
# =============================================================================

func _built() -> void:
	tb.ribbon = false
	tb.label_every = 0.0
	tb.greeble_markers = false
	tb.surface_markers = false
	tb.preview()
	await _settle()
	var s := tb.sampler
	for p in tb.composer.placed:
		var n := String(p.node.name).to_lower()
		if not _wants("road_" + n):
			continue
		var at: float = p.s0 - 60.0
		if p.node is JumpFeature:
			at = p.marks.kicker - 140.0
		_chase(s, at)
		await _shot("road_" + n, _view_rect())
	if _wants("road_fork"):
		for be in tb.branches:
			if be.ok:
				var ff := s.frame_at(be.s_fork - 120.0)
				var fa := s.frame_at(be.s_fork + 200.0)
				_look(ff.origin + Vector3.UP * 40.0, fa.origin)
				await _shot("road_fork", _view_rect())
				break


func _dressing() -> void:
	# Greeble zone.
	var gk := _node("GreebleZoneKeys/Zone02_Service") as ProfileKey
	if gk:
		tb.greeble_markers = true
		tb.preview()
		await _select(gk)
		_key_pose(gk, 90.0, -45.0, 40.0)
		await _settle()
		await _shot("key_greeble", _view_rect())
		await _shot("insp_greeble", _inspector_rect())
		tb.greeble_markers = false
		tb.preview()
	# Surface zone.
	var sk := _node("SurfaceZoneKeys/Surface02_service") as ProfileKey
	if sk:
		tb.surface_markers = true
		tb.preview()
		await _select(sk)
		_key_pose(sk, 90.0, -45.0, 40.0)
		await _settle()
		await _shot("key_surface", _view_rect())
		await _shot("insp_surface", _inspector_rect())
		tb.surface_markers = false
		tb.preview()
	# A decal key's settings.
	var dk := _node("SurfaceDecalKeys/Decal01_FullThrottle") as ProfileKey
	if dk:
		await _select(dk)
		await _shot("insp_decal", _inspector_rect())
	_clean(false)
