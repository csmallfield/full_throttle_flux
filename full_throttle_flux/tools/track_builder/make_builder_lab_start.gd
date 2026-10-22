extends SceneTree
## One-off (v34 step 1): writes the starting Builder Lab scene, a plain
## hand-drawn-style base with a few bank and width keys, for trying the
## preview. From here on the scene is edited by hand in the editor, the way a
## real track is; this script is kept only as a record of the starting point.
##
##   godot --headless --path . -s res://tools/track_builder/make_builder_lab_start.gd

const OUT := "res://scenes/tracks/builder_lab.tscn"

# Control points (x, y, z) as you'd click them in: about 5.5 km, a long back
# straight (room for a loop later), a fast sweeper, a hairpin, a hill, and a
# chicane. Handles are set from the neighbours with uneven lengths, like
# hand-dragged ones, so fairing has something to do.
const PTS := [
	Vector3(0, 0, 0),
	Vector3(0, 0, -420),
	Vector3(40, 4, -780),
	Vector3(260, 14, -1010),
	Vector3(600, 22, -1060),
	Vector3(900, 18, -930),
	Vector3(1010, 10, -700),
	Vector3(1180, 6, -560),
	Vector3(1380, 6, -640),
	Vector3(1460, 10, -420),
	Vector3(1300, 28, -180),
	Vector3(1240, 40, 160),
	Vector3(1320, 30, 520),
	Vector3(1180, 14, 820),
	Vector3(820, 4, 900),
	Vector3(420, 0, 860),
	Vector3(140, 0, 700),
	Vector3(10, 0, 380),
]
const HANDLE_SCALE := [0.30, 0.36, 0.28, 0.34, 0.31, 0.38, 0.27, 0.33, 0.36, 0.30,
		0.29, 0.35, 0.32, 0.28, 0.37, 0.31, 0.34, 0.30]

# Bank key positions (metres along). Each key's bank leans into the local
# corner: 6° per g of cornering load at 110 u/s, capped at 22°, so the start
# is plausible rather than tuned. (Width keys: metres along, half width L, R.)
const BANK_AT := [350.0, 700.0, 1150.0, 1500.0, 1900.0, 2350.0, 2700.0, 3100.0,
		3900.0, 4400.0, 4900.0, 5300.0]
const START_AT := 120.0
const MB_SCRIPT := "res://scripts/rendering/motion_blur_effect.gd"
const WIDTHS := [[1500.0, 21.5, 21.5], [1800.0, 26.0, 21.5], [2300.0, 21.5, 21.5],
		[3300.0, 21.5, 21.5], [3550.0, 15.0, 15.0], [3800.0, 21.5, 21.5]]


func _init() -> void:
	var root := Node3D.new()
	root.name = "BuilderLab"

	var tb := TrackBuilder.new()
	tb.name = "TrackBuilder"
	root.add_child(tb)
	tb.owner = root

	var path := Path3D.new()
	path.name = "BaseSpline"
	var c := Curve3D.new()
	c.closed = true
	c.bake_interval = 0.5
	var n := PTS.size()
	for i in n:
		var p: Vector3 = PTS[i]
		var prev: Vector3 = PTS[(i - 1 + n) % n]
		var next: Vector3 = PTS[(i + 1) % n]
		var dir := (next - prev).normalized()
		var k: float = HANDLE_SCALE[i]
		c.add_point(p, -dir * p.distance_to(prev) * k, dir * p.distance_to(next) * (0.62 - k))
	path.curve = c
	tb.add_child(path)
	path.owner = root

	var s := TrackSampler.new()
	s.sample(c, 0.0)

	var banks := Node3D.new()
	banks.name = "BankKeys"
	tb.add_child(banks)
	banks.owner = root
	var bi := 0
	for d: float in BANK_AT:
		var k := BankKey.new()
		bi += 1
		k.name = "Bank%02d" % bi
		k.bank_deg = _lean(s, d)
		banks.add_child(k)
		k.owner = root
		# Hovering 6 m above the centre line, like a dropped node.
		k.position = s.frame_at(d).origin + Vector3.UP * 6.0
		k.distance = d

	var widths := Node3D.new()
	widths.name = "WidthKeys"
	tb.add_child(widths)
	widths.owner = root
	var wi := 0
	for w: Array in WIDTHS:
		var k := WidthKey.new()
		wi += 1
		k.name = "Width%02d" % wi
		k.linked = is_equal_approx(w[1], w[2])
		k.half_width_left = w[1]
		k.half_width_right = w[2]
		widths.add_child(k)
		k.owner = root
		k.position = s.frame_at(w[0]).origin + Vector3.UP * 6.0
		k.distance = w[0]

	var sk := StartKey.new()
	sk.name = "StartKey"
	tb.add_child(sk)
	sk.owner = root
	sk.position = s.frame_at(START_AT).origin + Vector3.UP * 6.0
	sk.distance = START_AT

	_add_environment(root)

	var ps := PackedScene.new()
	var err := ps.pack(root)
	if err == OK:
		err = ResourceSaver.save(ps, OUT)
	print("builder_lab start scene: length %.0f m, save %s" % [s.length, error_string(err)])
	root.free()
	quit()


## Lean into the corner at `d`: mean curvature over ±60 m, 6° per g at
## 110 u/s (game gravity 25), capped at 22°, rounded to 0.5°.
func _lean(s: TrackSampler, d: float) -> float:
	var k := 0.0
	var count := 0
	var x := d - 60.0
	while x <= d + 60.0:
		k += s.curvature_h(s.index_at(x))
		count += 1
		x += 5.0
	var g := 110.0 * 110.0 * (k / count) / 25.0
	return clampf(snappedf(g * 6.0, 0.5), -22.0, 22.0)


## Same look as Fork Lab: sky, sun, the shadowless upward fill, and a visual
## floor well below the track (no collision: falls go to the respawn rules).
func _add_environment(root: Node3D) -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.10, 0.14, 0.30)
	sky_mat.sky_horizon_color = Color(0.45, 0.50, 0.62)
	sky_mat.ground_bottom_color = Color(0.20, 0.22, 0.28)
	sky_mat.ground_horizon_color = Color(0.36, 0.39, 0.48)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.6
	env.glow_bloom = 0.2
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = env
	if ResourceLoader.exists(MB_SCRIPT):
		var mb: CompositorEffect = load(MB_SCRIPT).new()
		var comp := Compositor.new()
		comp.compositor_effects = [mb] as Array[CompositorEffect]
		we.compositor = comp
	root.add_child(we)
	we.owner = root
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.transform = Transform3D(Basis.from_euler(Vector3(deg_to_rad(-50), deg_to_rad(210), 0)), Vector3(0, 80, 0))
	sun.light_color = Color(1.0, 0.95, 0.9)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 600.0
	root.add_child(sun)
	sun.owner = root
	var fill := DirectionalLight3D.new()
	fill.name = "GroundFill"
	fill.rotation_degrees = Vector3(90, 0, 0)
	fill.light_color = Color(0.75, 0.82, 1.0)
	fill.light_energy = 0.35
	fill.shadow_enabled = false
	root.add_child(fill)
	fill.owner = root
	var mi := MeshInstance3D.new()
	mi.name = "FloorVisual"
	var pm := PlaneMesh.new()
	pm.size = Vector2(6000, 6000)
	mi.mesh = pm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.07, 0.08, 0.11)
	mat.roughness = 1.0
	mi.material_override = mat
	mi.position = Vector3(700, -40, -100)
	root.add_child(mi)
	mi.owner = root
