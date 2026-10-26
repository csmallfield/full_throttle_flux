extends Node
## v35 Phase 4: stills of every weather on Utopia. For each preset: a chase
## shot behind a racing ship and a low road close-up from the side.
##   WEATHERS="rain_medium,snow_medium"  limit the presets (file names in
##   resources/weather, default all); RENDER_ONLY / START_D as usual.

const TRACK := "res://scenes/tracks/test_circuit_3_live.tscn"
const SHIP_SCENE := "res://scenes/ships/default_racer.tscn"
const SHIP_PROFILE := "res://resources/ships/default_racer.tres"
const VARIANT := "res://scenes/ships/variants/variant_red_yellow.tscn"

var outdir := "user://render_weather"
var kit: UtopiaKit
var env: EnvironmentState
var ship: ShipController
var probe: ShipEnvProbe
var cam: Camera3D
var t := 0.0
var cam_mode := "chase"
var start_d := 1950.0


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		outdir = args[0]
	if OS.get_environment("START_D") != "":
		start_d = float(OS.get_environment("START_D"))
	DirAccess.make_dir_recursive_absolute(outdir)
	get_viewport().msaa_3d = Viewport.MSAA_DISABLED
	var track: Node3D = (load(TRACK) as PackedScene).instantiate()
	add_child(track)
	kit = UtopiaKit.new(track)
	var profile := load("res://resources/tracks/test_circuit_3_live.tres") as TrackProfile
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
	var b := kit.frame(start_d)
	ship.global_transform = Transform3D(b, kit.center(start_d) + b.y * 4.0)
	await get_tree().physics_frame
	ship.settle_on_surface()
	probe = ShipEnvProbe.of(ship)
	cam.set("ship", ship)
	var names := ["clear", "rain_medium", "snow_medium", "fog_medium", "dust_storm_medium"]
	if OS.get_environment("WEATHERS") != "":
		names = Array(OS.get_environment("WEATHERS").split(","))
	await _run(2.0)
	for n in names:
		var preset := load("res://resources/weather/%s.tres" % n) as WeatherPreset
		env.apply_weather(preset, true)
		cam_mode = "chase"
		await _run(1.5)
		await _shot(n + "_chase")
		cam_mode = "road"
		await _run(0.3)
		await _shot(n + "_road")
	print("render_weather: done -> %s" % ProjectSettings.globalize_path(outdir))
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
	var aim := kit.center(d + 30.0)
	var local := ship.global_transform.basis.inverse() * (aim - ship.global_position)
	ship.steer_input = clampf(atan2(-local.x, -local.z) * 2.4 - ship.measured_yaw_rate * 0.25, -1.0, 1.0)
	ship.throttle_input = 0.8


func _process(_delta: float) -> void:
	if ship == null or cam == null:
		return
	var b := ship.global_transform.basis
	if cam_mode == "road":
		# Low, off the ship's left side and a little ahead, looking down the
		# road (ship space, so banking and slopes never put it underground).
		var up := b.y.normalized()
		var fwd := -b.z.normalized()
		var right := b.x.normalized()
		var p := ship.global_position + fwd * 6.0 - right * 7.0 + up * 2.2
		cam.look_at_from_position(p, ship.global_position + fwd * 60.0 + right * 2.0, up)
	else:
		var back := b.z.normalized()
		var up := b.y.normalized()
		cam.look_at_from_position(ship.global_position + back * 12.0 + up * 3.2,
			ship.global_position - back * 25.0, up)


func _shot(shot_name: String) -> void:
	var only := OS.get_environment("RENDER_ONLY")
	if only != "" and not (shot_name in only.split(",")):
		return
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := outdir.path_join(shot_name + ".png")
	img.save_png(path)
	print("render_weather: %s  wet %.2f frost %.2f dust %.2f precip %.2f ssr %s" % [path,
		env.wetness, env.frost, env.dust, env.precipitation,
		str(env.world_env.environment.ssr_enabled) if env.world_env else "-"])
