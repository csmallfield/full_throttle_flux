extends Node
## v35 Phase 1: chase-camera stills of the trails on Utopia for judging the
## look without playing: three ships weaving at full throttle.
## Shots: straight, weave, boost, rain (humid air streams), side (trackside).
## See render_trails_boot.gd for the command line.

const TRACK := "res://scenes/tracks/test_circuit_3_live.tscn"
const SHIP_SCENE := "res://scenes/ships/default_racer.tscn"
const SHIP_PROFILE := "res://resources/ships/default_racer.tres"
const VARIANT := "res://scenes/ships/variants/variant_red_yellow.tscn"
const START_D := 1950.0

var outdir := "user://render_trails"
var kit: UtopiaKit
var ships: Array[ShipController] = []
var probes: Array[ShipEnvProbe] = []
var cam: Camera3D
var t := 0.0
var weave := 0.0
var side_cam := false


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		outdir = args[0]
	DirAccess.make_dir_recursive_absolute(outdir)
	get_viewport().msaa_3d = Viewport.MSAA_DISABLED   # lavapipe can't resolve MSAA depth
	var track: Node3D = (load(TRACK) as PackedScene).instantiate()
	add_child(track)
	kit = UtopiaKit.new(track)
	var profile := TrackProfile.new()
	var env := EnvironmentState.install(self, track, profile)
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
		var d := START_D - 18.0 * i
		var b := kit.frame(d)
		s.global_transform = Transform3D(b, kit.center(d) + kit.right_flat(d) * [0.0, -6.0, 6.0][i] + b.y * 4.0)
		ships.append(s)
	await get_tree().physics_frame
	for s in ships:
		s.settle_on_surface()
		probes.append(ShipEnvProbe.of(s))
	await _run(3.0, 0.0)
	await _shot("straight")
	await _run(2.0, 9.0)
	await _shot("weave")
	for s in ships:
		s.apply_boost(30.0)
	await _run(0.6, 9.0)
	await _shot("boost")
	env.apply_weather(load("res://resources/weather/rain_medium.tres"), true)
	await _run(2.0, 9.0)
	await _shot("rain")
	side_cam = true
	await _run(0.5, 9.0)
	await _shot("side")
	print("render_trails: done -> %s" % ProjectSettings.globalize_path(outdir))
	get_tree().quit()


func _run(seconds: float, p_weave: float) -> void:
	weave = p_weave
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
		var lat: float = [0.0, -6.0, 6.0][i] + weave * sin(t * 1.6 + i * 0.9)
		var aim := kit.center(d + 30.0) + kit.right_flat(d + 30.0) * lat
		var local := s.global_transform.basis.inverse() * (aim - s.global_position)
		s.steer_input = clampf(atan2(-local.x, -local.z) * 2.4 - s.measured_yaw_rate * 0.25, -1.0, 1.0)
		s.throttle_input = 1.0


func _process(_delta: float) -> void:
	if ships.is_empty() or cam == null:
		return
	var lead := ships[0]
	var b := lead.global_transform.basis
	if side_cam:
		var d := probes[0].spline_distance
		var p := kit.center(d + 25.0) + kit.right_flat(d + 25.0) * 14.0 + Vector3.UP * 5.0
		cam.look_at_from_position(p, lead.global_position - b.z * 6.0, Vector3.UP)
	else:
		var back := b.z.normalized()
		var up := b.y.normalized()
		cam.look_at_from_position(lead.global_position + back * 11.0 + up * 3.2,
			lead.global_position - back * 25.0, up)


func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := outdir.path_join(shot_name + ".png")
	img.save_png(path)
	print("render_trails: %s" % path)
