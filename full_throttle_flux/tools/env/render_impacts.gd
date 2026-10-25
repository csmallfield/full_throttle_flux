extends Node
## v35 Phase 3: stills of wall-hit FX on Utopia (dusty, TrackEnvironment.dust
## 0.7, test only). The lead ship turns into the right wall and rides it.
## Shots: hit (chase, just after the first contact), scrape (chase, mid-
## slide), scrape_side (trackside, looking back at the slide), marks_hot (the
## line of marks just after leaving the wall), marks_cold (same, 4 s later),
## scrape_wet (rain: quenched sparks, spray).

const TRACK := "res://scenes/tracks/test_circuit_3_live.tscn"
const SHIP_SCENE := "res://scenes/ships/default_racer.tscn"
const SHIP_PROFILE := "res://resources/ships/default_racer.tres"
const VARIANT := "res://scenes/ships/variants/variant_red_yellow.tscn"
const START_D := 1950.0

var outdir := "user://render_impacts"
var kit: UtopiaKit
var env: EnvironmentState
var ship: ShipController
var probe: ShipEnvProbe
var cam: Camera3D
var t := 0.0
var lat := 0.0
## Wall-hug mode: steer for a line `hug` metres past the right wall as seen
## by the probe (the road is not centred on the spline everywhere).
var hug := false
var _hug_lat := 0.0
var throttle := 0.75
var cam_mode := "chase"
var fixed_from := Vector3.ZERO
var fixed_at := Vector3.ZERO
var hit_seen := false


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		outdir = args[0]
	DirAccess.make_dir_recursive_absolute(outdir)
	get_viewport().msaa_3d = Viewport.MSAA_DISABLED
	var track: Node3D = (load(TRACK) as PackedScene).instantiate()
	add_child(track)
	kit = UtopiaKit.new(track)
	var tenv := TrackEnvironment.new()
	tenv.dust = 0.0 if OS.get_environment("IMPACT_CLEAN") != "" else 0.7
	var profile := TrackProfile.new()
	profile.environment = tenv
	env = EnvironmentState.install(self, track, profile)
	cam = Camera3D.new()
	var cam_script := GDScript.new()
	cam_script.source_code = "extends Camera3D\nvar ship: Node3D\n"
	cam_script.reload()
	cam.set_script(cam_script)
	cam.far = 4000.0
	cam.fov = 74.0
	add_child(cam)
	cam.make_current()
	ship = (load(SHIP_SCENE) as PackedScene).instantiate()
	ship.profile = load(SHIP_PROFILE)
	ship.ai_controlled = true
	ShipVisuals.swap_mesh(ship, load(VARIANT))
	add_child(ship)
	var b := kit.frame(START_D)
	ship.global_transform = Transform3D(b, kit.center(START_D) + b.y * 4.0)
	ship.wall_hit.connect(func(_p, _n, _s, _c): hit_seen = true)
	await get_tree().physics_frame
	ship.settle_on_surface()
	probe = ShipEnvProbe.of(ship)
	cam.set("ship", ship)
	await _run(2.0)
	hug = true
	while not hit_seen and t < 10.0:
		await _run(1.0 / 60.0)
	await _run(0.05)
	await _shot("hit")
	await _run(0.9)
	await _shot("scrape")
	var d := probe.spline_distance
	fixed_from = kit.center(d + 22.0) + kit.right_flat(d + 22.0) * 4.0 + Vector3.UP * 3.0
	cam_mode = "fixed_ship"
	await _run(0.5)
	await _shot("scrape_side")
	# Leave the wall; look at the marks just laid.
	var imp := FxImpacts.for_env(env)
	var last := imp.decals[(imp._next_mark - 2 + FxImpacts.MARKS) % FxImpacts.MARKS]
	var n := last.global_transform.basis.y.normalized()
	var along := last.global_transform.basis.x.normalized()
	fixed_at = last.global_position - along * 4.0
	if OS.get_environment("IMPACT_LOG") != "":
		var space := get_viewport().world_3d.direct_space_state
		for k in range(1, 4):
			var dk := imp.decals[(imp._next_mark - k + FxImpacts.MARKS) % FxImpacts.MARKS]
			var nk := dk.global_transform.basis.y.normalized()
			var q := PhysicsRayQueryParameters3D.create(dk.global_position + nk * 1.0, dk.global_position - nk * 1.0)
			q.exclude = [ship.get_rid()]
			var hit := space.intersect_ray(q)
			print("mark %d pos %s n %s size %s -> wall at %s n %s" % [k, dk.global_position, nk, dk.size,
				str(hit.get("position", "none")), str(hit.get("normal", "-"))])
	fixed_from = last.global_position + n * 6.0 + along * 4.0 + Vector3.UP * 1.5
	cam_mode = "fixed"
	hug = false
	lat = 0.0
	await _run(0.15)
	await _shot("marks_hot")
	await _run(4.0)
	await _shot("marks_cold")
	env.apply_weather(load("res://resources/weather/rain_medium.tres"), true)
	cam_mode = "chase"
	hug = true
	await _run(2.0)
	await _shot("scrape_wet")
	print("render_impacts: done -> %s  sparks %d marks %d flashes %d" % [
		ProjectSettings.globalize_path(outdir), imp.sparks_total, imp.marks_total, imp.flashes_total])
	get_tree().quit()


func _run(seconds: float) -> void:
	var end := t + seconds
	while t < end:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()


func _physics_process(_delta: float) -> void:
	if ship == null or probe == null:
		return
	var d := probe.spline_distance
	var off := (ship.global_position - kit.center(d)).dot(kit.right_flat(d))
	var want := lat
	if hug:
		# Seek the wall; once seen, aim 2 m into it.
		want = off + probe.wall_right + 2.0 if probe.wall_right != INF else off + 6.0
		_hug_lat = lerpf(_hug_lat, want, 0.1)
		want = _hug_lat
	else:
		_hug_lat = off
	var aim := kit.center(d + 30.0) + kit.right_flat(d + 30.0) * want
	var local := ship.global_transform.basis.inverse() * (aim - ship.global_position)
	ship.steer_input = clampf(atan2(-local.x, -local.z) * 2.4 - ship.measured_yaw_rate * 0.25, -1.0, 1.0)
	ship.throttle_input = throttle
	if OS.get_environment("IMPACT_LOG") != "" and Engine.get_physics_frames() % 6 == 0:
		print("t %.2f d %.0f off %.1f v %.0f wallL %.1f wallR %.1f scrape %s" % [t, d, off,
			ship.get_speed(), probe.wall_left, probe.wall_right, str(probe.scraping)])


func _process(_delta: float) -> void:
	if ship == null or cam == null:
		return
	var b := ship.global_transform.basis
	match cam_mode:
		"fixed":
			cam.look_at_from_position(fixed_from, fixed_at, Vector3.UP)
		"fixed_ship":
			cam.look_at_from_position(fixed_from, ship.global_position, Vector3.UP)
		_:
			var back := b.z.normalized()
			var up := b.y.normalized()
			cam.look_at_from_position(ship.global_position + back * 11.0 + up * 3.0 - b.x * 2.5,
				ship.global_position - back * 25.0, up)


func _shot(shot_name: String) -> void:
	var only := OS.get_environment("RENDER_ONLY")
	if only == "none" or only != "" and not (shot_name in only.split(",")):
		return
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := outdir.path_join(shot_name + ".png")
	img.save_png(path)
	var imp := FxImpacts.for_env(env)
	print("render_impacts: %s  sparks %d marks %d flashes %d speed %.0f" % [path,
		imp.sparks_total, imp.marks_total, imp.flashes_total, ship.get_speed()])
