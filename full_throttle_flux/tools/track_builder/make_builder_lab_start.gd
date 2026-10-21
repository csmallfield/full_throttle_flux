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

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-50, 30, 0)
	root.add_child(sun)
	sun.owner = root

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
