extends Node
## Cinematic camera rig probe (v30). Runs a seeded RaceMode race, attaches a
## CinematicCameraRig to one AI ship exactly as AISpectator does, and measures
## every rig camera every physics tick, split by track section (open track /
## each magnetic zone):
##
##   occl    % of ticks the ship is hidden from the camera (ray camera->ship
##           hits track or wall geometry)
##   jump    ticks where the camera moved more than 25 m or turned more than
##           35 degrees in one tick beyond what the ship itself did (a glitch;
##           planted cameras' deliberate replants are reported as `cuts`)
##   cuts    replants (camera relocated > 25 m in one tick)
##   d       camera-to-ship distance range
##   flipup  ticks where the camera's up vector points below the horizon
##           (camera rolled upside down relative to the world)
##
## Also prints a checksum of every camera's transform over the whole run, so
## two versions of the rig can be compared for bit-identical behaviour.
##
##   godot --headless --fixed-fps 60 --path . -s res://tools/dev/cine_rig_probe_boot.gd
##
## Env: CR_TRACK (default loop_lab), CR_SECONDS (default 90), CR_SEED (1234),
##      CR_SHIP (index into the AI field, default 0),
##      CR_SHOTS "cam@distance,..." + CR_SHOT_DIR: save that camera's view
##      when the followed ship first passes each spline distance (needs a
##      renderer: run under xvfb-run without --headless)

var rig  # untyped: the probe also runs against older rig versions (A/B)
var ship: ShipController
var helper: TrackSplineHelper
var mt: MagneticTrack
var stats := {}
var prev := {}
var checksum := 0
var shots: Array = []
var shot_dir := "user://cine_shots"
var _dbg_cam := OS.get_environment("CR_DEBUG_CAM")
var _path := {}   # zone index -> PackedVector3Array of the followed ship (CR_ANALYZE)

func _ready() -> void:
	await get_tree().process_frame
	var root := get_tree().root
	var gm = root.get_node("GameManager")
	var track_id := OS.get_environment("CR_TRACK")
	if track_id == "":
		track_id = "loop_lab"
	gm.select_track_by_id(track_id)
	gm.selected_mode = "race"
	var seconds := OS.get_environment("CR_SECONDS").to_float()
	if seconds <= 0.0:
		seconds = 90.0
	seed(int(OS.get_environment("CR_SEED")) if OS.get_environment("CR_SEED") != "" else 1234)
	for item in OS.get_environment("CR_SHOTS").split(",", false):
		var kv := item.split("@")
		shots.append([kv[0], kv[1].to_float(), false])
	if OS.get_environment("CR_SHOT_DIR") != "":
		shot_dir = OS.get_environment("CR_SHOT_DIR")
	if not shots.is_empty():
		DirAccess.make_dir_recursive_absolute(shot_dir)
	
	var launcher: Node = load("res://scenes/race_launcher.tscn").instantiate()
	root.add_child(launcher)
	
	var rm = root.get_node("RaceManager")
	var go := [false]
	rm.race_started.connect(func(): go[0] = true)
	for i in 1800:
		await get_tree().physics_frame
		if go[0]:
			break
	
	var ais: Array = []
	_find_ais(root, ais)
	if ais.is_empty():
		print("CRP no AI"); get_tree().quit(1); return
	var idx := clampi(int(OS.get_environment("CR_SHIP")) if OS.get_environment("CR_SHIP") != "" else 0, 0, ais.size() - 1)
	var ai: AIShipController = ais[idx]
	ship = ai.ship
	helper = ai.line_follower.spline_helper if ai.line_follower else null
	mt = get_tree().get_first_node_in_group(MagneticTrack.GROUP) as MagneticTrack
	
	rig = CinematicCameraRig.new()
	rig.name = "CinematicCameraRig"
	root.add_child(rig)
	rig.spline = helper
	rig.follow(ship)
	
	var frames := int(seconds * 60.0)
	for f in frames:
		await get_tree().physics_frame
		_measure()
		if OS.get_environment("CR_ANALYZE") == "1" and f % 3 == 0:
			_record_path()
		if not shots.is_empty():
			await _maybe_shoot()
	_report(track_id, seconds)
	if OS.get_environment("CR_ANALYZE") == "1":
		_analyze()
	get_tree().quit(0)

func _find_ais(n: Node, out: Array) -> void:
	if n is AIShipController:
		out.append(n)
	for c in n.get_children():
		_find_ais(c, out)

func _section() -> String:
	if mt == null:
		return "open"
	var d := mt.closest_distance(ship.global_position)
	var zr := mt.zone_at(d)
	if (zr[0] as float) >= 1.0 and zr[1] != null:
		return (zr[1] as MagneticZone).zone_name
	return "open"

func _measure() -> void:
	var space := ship.get_world_3d().direct_space_state
	var sec := _section()
	var sp: Vector3 = ship.global_position
	var ship_move: float = (sp - prev.get("__ship", sp)).length()
	prev["__ship"] = sp
	for i in rig.cameras.size():
		var cam: Camera3D = rig.cameras[i]
		var cname: String = rig.CAMERA_NAMES[i]
		var t := cam.global_transform
		checksum = hash([checksum, t, cam.fov])
		var key := cname + "|" + sec
		if not stats.has(key):
			stats[key] = {"n": 0, "occl": 0, "jump": 0, "cuts": 0, "dmin": INF, "dmax": 0.0, "flipup": 0, "nan": 0}
		var s: Dictionary = stats[key]
		s.n += 1
		if not t.origin.is_finite() or not t.basis.x.is_finite():
			s.nan += 1
			continue
		var d := t.origin.distance_to(sp)
		s.dmin = minf(s.dmin, d)
		s.dmax = maxf(s.dmax, d)
		if t.basis.y.y < -0.05:
			s.flipup += 1
		var q := PhysicsRayQueryParameters3D.create(t.origin, sp, 5)
		q.exclude = [ship.get_rid()]
		var hit := space.intersect_ray(q)
		if not hit.is_empty():
			s.occl += 1
			if cname == _dbg_cam and sec != "open" and s.occl % 20 == 1:
				var hp: Vector3 = hit.position
				print("OCC %s %s cam=%s ship=%s hit=%s by=%s frac=%.2f" % [cname, sec,
						t.origin.snapped(Vector3.ONE * 0.1), sp.snapped(Vector3.ONE * 0.1),
						hp.snapped(Vector3.ONE * 0.1), (hit.collider as Node).name,
						t.origin.distance_to(hp) / maxf(t.origin.distance_to(sp), 0.01)])
		if prev.has(cname):
			var pt: Transform3D = prev[cname]
			var moved: float = t.origin.distance_to(pt.origin) - ship_move
			var turned: float = rad_to_deg(t.basis.get_rotation_quaternion().angle_to(pt.basis.get_rotation_quaternion()))
			if moved > 25.0:
				s.cuts += 1
			elif turned > 35.0:
				s.jump += 1
		prev[cname] = t

func _record_path() -> void:
	if rig._zones.is_empty() or rig._ship_d < 0.0:
		return
	for i in rig._zones.size():
		var rel: float = rig._zone_rel(rig._zones[i])
		if rel >= 0.0 and rel <= float(rig._zones[i].span):
			var arr: PackedVector3Array = _path.get(i, PackedVector3Array())
			arr.append(ship.global_position)
			_path[i] = arr   # packed arrays are values: write it back

## Visibility of the recorded ship path from a grid of candidate witness
## positions around each zone (zone-local along / across / height).
func _analyze() -> void:
	var space := ship.get_world_3d().direct_space_state
	for i in _path.keys():
		var z: Dictionary = rig._zones[i]
		var pts: PackedVector3Array = _path[i]
		print("ANALYZE zone %s: %d path samples, box along[%.0f..%.0f] across[%.0f..%.0f] height[%.0f..%.0f] axis(a=%.0f,y=%.0f) loop_like=%s" % [
			z.name, pts.size(), z.a0, z.a1, z.c0, z.c1, z.y0, z.y1, z.axis_a, z.axis_y, str(z.loop_like)])
		var alongs := [z.a0 - 150.0, z.a0, z.axis_a, z.a1, z.a1 + 150.0]
		if not z.loop_like:
			alongs = [lerpf(z.a0, z.a1, 0.25), lerpf(z.a0, z.a1, 0.5), lerpf(z.a0, z.a1, 0.65),
					lerpf(z.a0, z.a1, 0.8), lerpf(z.a0, z.a1, 0.9), z.a1, z.a1 + 60.0, z.a1 + 150.0]
		var acrosses := []
		for st in [10.0, 30.0, 60.0, 100.0, 150.0]:
			acrosses.append(float(z.c0) - st)
			acrosses.append(float(z.c1) + st)
		acrosses.append((float(z.c0) + float(z.c1)) * 0.5)
		var heights := [float(z.base_y) + 10.0, float(z.base_y) + 25.0, float(z.axis_y), float(z.axis_y) + 20.0,
				float(z.y1) + 10.0, float(z.y1) + 40.0]
		if not z.loop_like:
			heights = [float(z.base_y) + 5.0, float(z.base_y) + 12.0, float(z.base_y) + 20.0,
					float(z.base_y) + 30.0, float(z.y1) + 10.0, float(z.y1) + 30.0]
		var results := []
		for a in alongs:
			for c in acrosses:
				for y in heights:
					var cam: Vector3 = rig._zone_world(z, a, c, y)
					# skip positions inside the swept envelope
					var l: Vector3 = rig._zone_local(z, cam)
					if l.x > z.a0 - 6.0 and l.x < z.a1 + 6.0 and l.y > z.c0 - 6.0 and l.y < z.c1 + 6.0 and l.z < z.y1 + 6.0:
						if not (z.loop_like and absf(l.z - float(z.axis_y)) < 1.0):
							continue
					var vis := 0
					for pt in pts:
						var q := PhysicsRayQueryParameters3D.create(cam, pt, 5)
						if space.intersect_ray(q).is_empty():
							vis += 1
					var dmean := 0.0
					for pt in pts:
						dmean += cam.distance_to(pt)
					results.append([float(vis) / pts.size(), a, c, y, dmean / pts.size()])
		results.sort_custom(func(x, y): return x[0] > y[0])
		for r in results.slice(0, 14):
			print("ANALYZE   vis=%5.1f%%  along=%7.1f across=%7.1f height=%6.1f  mean dist %.0f" % [
				100.0 * r[0], r[1], r[2], r[3], r[4]])

func _maybe_shoot() -> void:
	if helper == null:
		return
	var d := helper.world_to_spline_offset(ship.global_position) * helper.total_length
	for sh in shots:
		if sh[2]:
			continue
		var gap: float = d - (sh[1] as float)
		if gap >= 0.0 and gap < 40.0:
			sh[2] = true
			var i: int = rig.CAMERA_NAMES.find(sh[0])
			if i < 0:
				continue
			rig.select_index(i)
			await RenderingServer.frame_post_draw
			await RenderingServer.frame_post_draw
			var path: String = shot_dir.path_join("%s_%04d.png" % [sh[0], int(sh[1])])
			get_viewport().get_texture().get_image().save_png(path)
			print("SHOT %s @%.0f -> %s" % [sh[0], d, ProjectSettings.globalize_path(path)])

func _report(track_id: String, seconds: float) -> void:
	var keys := stats.keys()
	keys.sort()
	for key in keys:
		var s: Dictionary = stats[key]
		var parts: PackedStringArray = (key as String).split("|")
		print("CRP %-13s %-12s n=%5d occl=%5.1f%% jump=%3d cuts=%3d d[%6.1f..%6.1f] flipup=%4d nan=%d" % [
			parts[0], parts[1], s.n, 100.0 * s.occl / maxf(s.n, 1), s.jump, s.cuts,
			s.dmin if s.dmin < INF else -1.0, s.dmax, s.flipup, s.nan])
	print("CRP track=%s seconds=%.0f checksum=%d" % [track_id, seconds, checksum])
