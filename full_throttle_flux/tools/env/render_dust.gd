extends Node
## v35 Phase 2: stills of ship-kicked particles on Utopia, made dusty for the
## occasion (TrackEnvironment.dust 0.7, test only).
## Shots: dust (chase), airbrake (both brakes), wall (hugging the right wall),
## side (trackside), spray (rain), powder (snow).

const TRACK := "res://scenes/tracks/test_circuit_3_live.tscn"
const SHIP_SCENE := "res://scenes/ships/default_racer.tscn"
const SHIP_PROFILE := "res://resources/ships/default_racer.tres"
const VARIANT := "res://scenes/ships/variants/variant_red_yellow.tscn"
const START_D := 1950.0

var outdir := "user://render_dust"
var kit: UtopiaKit
var env: EnvironmentState
var ships: Array[ShipController] = []
var probes: Array[ShipEnvProbe] = []
var cam: Camera3D
var t := 0.0
var lat_lead := 0.0
var brakes := 0.0
var side_cam := false


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
	tenv.dust = 0.7
	var profile := TrackProfile.new()
	profile.environment = tenv
	env = EnvironmentState.install(self, track, profile)
	cam = Camera3D.new()
	cam.far = 4000.0
	cam.fov = 74.0
	add_child(cam)
	cam.make_current()
	for i in 3:
		var s: ShipController = (load(SHIP_SCENE) as PackedScene).instantiate()
		s.profile = load(SHIP_PROFILE)
		s.ai_controlled = true
		ShipVisuals.swap_mesh(s, load(VARIANT))
		add_child(s)
		var d := START_D - 16.0 * (i + 1) if i > 0 else START_D
		var b := kit.frame(d)
		s.global_transform = Transform3D(b, kit.center(d) + kit.right_flat(d) * [0.0, -6.0, 6.0][i] + b.y * 4.0)
		ships.append(s)
	await get_tree().physics_frame
	for s in ships:
		s.settle_on_surface()
		probes.append(ShipEnvProbe.of(s))
	await _run(3.0)
	await _shot("dust")
	brakes = 1.0
	await _run(0.6)
	await _shot("airbrake")
	brakes = 0.0
	lat_lead = 30.0   # past the wall: ride along it
	await _run(2.0)
	await _shot("wall")
	lat_lead = 0.0
	side_cam = true
	await _run(1.0)
	await _shot("side")
	side_cam = false
	env.apply_weather(load("res://resources/weather/rain_medium.tres"), true)
	await _run(1.5)
	await _shot("spray")
	env.apply_weather(load("res://resources/weather/snow_medium.tres"), true)
	await _run(1.5)
	await _shot("powder")
	print("render_dust: done -> %s" % ProjectSettings.globalize_path(outdir))
	get_tree().quit()


func _run(seconds: float) -> void:
	var end := t + seconds
	while t < end:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()


func _physics_process(_delta: float) -> void:
	if ships.size() < 3 or probes.size() < 3:
		return
	for i in ships.size():
		var s := ships[i]
		var d := probes[i].spline_distance
		var lat: float = lat_lead if i == 0 else [0.0, -6.0, 6.0][i]
		var aim := kit.center(d + 30.0) + kit.right_flat(d + 30.0) * lat
		var local := s.global_transform.basis.inverse() * (aim - s.global_position)
		s.steer_input = clampf(atan2(-local.x, -local.z) * 2.4 - s.measured_yaw_rate * 0.25, -1.0, 1.0)
		s.throttle_input = 1.0
		s.airbrake_left = brakes if i == 0 else 0.0
		s.airbrake_right = brakes if i == 0 else 0.0


func _process(_delta: float) -> void:
	if ships.is_empty() or cam == null:
		return
	var lead := ships[0]
	var b := lead.global_transform.basis
	if side_cam:
		var d := probes[0].spline_distance
		var p := kit.center(d + 18.0) + kit.right_flat(d + 18.0) * 15.0 + Vector3.UP * 4.0
		cam.look_at_from_position(p, lead.global_position - b.z * 2.0, Vector3.UP)
	else:
		var back := b.z.normalized()
		var up := b.y.normalized()
		cam.look_at_from_position(lead.global_position + back * 13.0 + up * 3.5,
			lead.global_position - back * 25.0, up)


func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := outdir.path_join(shot_name + ".png")
	img.save_png(path)
	var pools := FxPools.for_env(env)
	print("render_dust: %s  emitted dust %d spray %d powder %d" % [path,
		pools.emitted_total[0], pools.emitted_total[1], pools.emitted_total[2]])
