extends SceneTree
## Writes the starting Builder Lab scene: a hand-drawn-style base with bank,
## width and start keys, and the features (v34 step 3: a jump, a loop, a
## roll, and a fork whose shortcut has a bigger jump). From here on the scene is edited by hand in the editor, the way a
## real track is; this script is kept as a record of the starting point.
##
##   godot --headless --path . -s res://tools/track_builder/make_builder_lab_start.gd

const OUT := "res://scenes/tracks/builder_lab.tscn"

# Control points (x, y, z) as you'd click them in: about 8 km, roughly a
# rectangle with a straight for each feature. North straight: the start and
# the jump. East straight: the loop. South straight (gently downhill): the
# roll. The fork leaves the south straight and cuts across the inside of the
# south-west corner, over a jump, to the bottom straight. Handles are
# set from the neighbours with uneven lengths, like hand-dragged ones, so
# fairing has something to do.
const PTS := [
	Vector3(0, 0, 0),
	Vector3(0, 0, -450),
	Vector3(0, 0, -900),
	Vector3(60, 4, -1180),
	Vector3(300, 8, -1320),
	Vector3(600, 10, -1360),
	Vector3(1300, 10, -1360),
	Vector3(2000, 10, -1360),
	Vector3(2300, 6, -1300),
	Vector3(2460, 0, -1080),
	Vector3(2480, -4, -800),
	Vector3(2480, -10, -200),
	Vector3(2470, -10, 300),
	Vector3(2380, -6, 600),
	Vector3(2150, 0, 760),
	Vector3(1600, 0, 800),
	Vector3(900, 0, 800),
	Vector3(400, 0, 780),
	Vector3(150, 0, 640),
	Vector3(20, 0, 380),
]
const HANDLE_SCALE := [0.30, 0.31, 0.30, 0.34, 0.31, 0.33, 0.31, 0.30, 0.36, 0.30,
		0.31, 0.31, 0.32, 0.28, 0.34, 0.31, 0.31, 0.30, 0.36, 0.30]

# Bank keys go on every control point where the corner asks for 2° or more
# (6° per g of cornering load at 110 u/s, capped at 22°): plausible rather
# than tuned. Width keys and features are placed at world points, the way
# you'd drop them in the viewport.
const START_AT := Vector3(0, 0, -150)
const WIDTHS := [
	[Vector3(0, 0, -900), 21.5, 21.5],      # the north-east corner's exit
	[Vector3(300, 8, -1320), 27.0, 21.5],   #   widens on the outside (left)
	[Vector3(700, 10, -1360), 21.5, 21.5],
	[Vector3(900, 0, 800), 21.5, 21.5],     # the end of the bottom straight
	[Vector3(600, 0, 790), 16.0, 16.0],     #   narrows into the last corner
	[Vector3(330, 0, 750), 16.0, 16.0],
	[Vector3(130, 0, 610), 21.5, 21.5],
]
const JUMP_AT := Vector3(0, 0, -560)
const LOOP_AT := Vector3(1300, 10, -1360)
const ROLL_AT := Vector3(2480, -8, -350)
# The shortcut, as you'd click it in: from the south straight across the
# inside of the corner to the bottom straight. Its jump is bigger than the
# main one (8° kicker, 80 m gap).
const BRANCH_PTS := [
	Vector3(2478, -10, 150),
	Vector3(2440, -9, 380),
	Vector3(2260, -6, 540),
	Vector3(2000, -3, 650),
	Vector3(1720, 0, 760),
	Vector3(1450, 0, 800),
]
const BRANCH_JUMP_AT := Vector3(2120, -4, 600)
const MB_SCRIPT := "res://scripts/rendering/motion_blur_effect.gd"


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
	for p: Vector3 in PTS:
		var d: float = s.project(p, -1.0)[0]
		var lean := _lean(s, d)
		if absf(lean) < 2.0:
			continue
		var k := BankKey.new()
		bi += 1
		k.name = "Bank%02d" % bi
		k.bank_deg = lean
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
		var d: float = s.project(w[0], -1.0)[0]
		k.position = s.frame_at(d).origin + Vector3.UP * 6.0
		k.distance = d

	var sk := StartKey.new()
	sk.name = "StartKey"
	tb.add_child(sk)
	sk.owner = root
	sk.position = START_AT + Vector3.UP * 6.0

	var feats := Node3D.new()
	feats.name = "Features"
	tb.add_child(feats)
	feats.owner = root
	for f: Array in [[JumpFeature.new(), "Jump", JUMP_AT], [LoopFeature.new(), "Loop", LOOP_AT],
			[RollFeature.new(), "Roll", ROLL_AT]]:
		var node: TrackFeature = f[0]
		node.name = f[1]
		feats.add_child(node)
		node.owner = root
		node.position = f[2] + Vector3.UP * 10.0

	var br := BranchFeature.new()
	br.name = "Shortcut"
	br.branch_name = "Corner cut"
	feats.add_child(br)
	br.owner = root
	var bpath := Path3D.new()
	bpath.name = "BranchBase"
	var bc := Curve3D.new()
	bc.bake_interval = 0.5
	var m := BRANCH_PTS.size()
	for i in m:
		var p: Vector3 = BRANCH_PTS[i]
		var prev: Vector3 = BRANCH_PTS[maxi(i - 1, 0)]
		var next: Vector3 = BRANCH_PTS[mini(i + 1, m - 1)]
		var dir := (next - prev).normalized()
		bc.add_point(p, -dir * p.distance_to(prev) * 0.32, dir * p.distance_to(next) * 0.32)
	bpath.curve = bc
	br.add_child(bpath)
	bpath.owner = root
	var bj := JumpFeature.new()
	bj.name = "BranchJump"
	bj.kicker_deg = 8.0
	bj.gap = 80.0
	bj.drop = 5.0
	br.add_child(bj)
	bj.owner = root
	bj.position = BRANCH_JUMP_AT + Vector3.UP * 10.0

	_add_environment(root)

	var ps := PackedScene.new()
	var err := ps.pack(root)
	if err == OK:
		err = ResourceSaver.save(ps, OUT)
	print("builder_lab start scene: base %.0f m, %d bank keys, save %s" % [s.length, bi, error_string(err)])
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
	pm.size = Vector2(7000, 7000)
	mi.mesh = pm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.07, 0.08, 0.11)
	mat.roughness = 1.0
	mi.material_override = mat
	mi.position = Vector3(1200, -50, -300)
	root.add_child(mi)
	mi.owner = root
