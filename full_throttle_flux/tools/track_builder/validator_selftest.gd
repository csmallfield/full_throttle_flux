extends Node
## Validator self-test (v34): breaks Builder Lab on purpose, one fault at a
## time, rebuilds it in memory and checks the validator reports that fault.
## Nothing is saved.
##
##   godot --headless --path . -s res://tools/track_builder/validator_selftest_boot.gd
##
## Prints PASS / FAIL per case and exits 1 if any case fails.

const SCENE := "res://scenes/tracks/builder_lab.tscn"

var cases := [
	["clean track", "", Callable(self, "_none")],
	["kink (no fairing, a sharp handle)", "Kink", Callable(self, "_kink")],
	["grid on a bend", "grid is on a bend", Callable(self, "_grid_on_bend")],
	["jump run-up too short after a respawn", "respawn_runup", Callable(self, "_short_runup")],
	["narrow road in a junction", "standard width in a junction", Callable(self, "_junction_width")],
	["track overhead", "clearance above the road", Callable(self, "_overhead")],
	["feature in a junction", "junction: the junction levels", Callable(self, "_feature_in_junction")],
	["branch drawn off the road", "from the main track", Callable(self, "_branch_off")],
	["roll too short", "Roll rate", Callable(self, "_short_roll")],
	["sharp crest", "Crest", Callable(self, "_crest")],
	["moved geometry (the offset)", "non-identity transform", Callable(self, "_moved")],
]


func _ready() -> void:
	TrackBuilder.keep_at_runtime = true
	var failed := 0
	for c in cases:
		push_warning("SELFTEST CASE %s" % c[0])    # marks stderr, to line up engine warnings
		# Uncached: the build writes into the scene's sub-resources (the curves),
		# and a cached PackedScene would carry one case's faults into the next.
		var ps := ResourceLoader.load(SCENE, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP) as PackedScene
		var scene := ps.instantiate()
		add_child(scene)
		await get_tree().process_frame
		var tb := scene.find_child("TrackBuilder", true, false) as TrackBuilder
		(c[2] as Callable).call(tb, scene)
		var r := TrackBuild.run(tb)
		for i in 3:
			await get_tree().physics_frame
		var msgs: PackedStringArray = []
		if not r.ok:
			msgs.append_array(r.log)
		_after_build(c[0], tb, scene)
		for i in 2:
			await get_tree().physics_frame
		var v := TrackValidator.run(tb, scene.get_viewport().world_3d.direct_space_state)
		for i in v.issues:
			msgs.append(("✗ " if i.sev == TrackValidator.Sev.ERROR else "⚠ ") + i.msg)
		var want: String = c[1]
		var ok := false
		if want.is_empty():
			ok = v.errors() == 0 and v.warnings() == 0 and r.ok
		else:
			for m in msgs:
				if want in m:
					ok = true
		if not ok:
			failed += 1
		print("%s  %s%s" % ["PASS" if ok else "FAIL", c[0], "" if ok else "  (wanted '%s')" % want])
		for m in msgs:
			if want.is_empty() or want in m or not ok:
				print("        " + m)
		remove_child(scene)
		scene.free()
	print("SELFTEST %d/%d passed" % [cases.size() - failed, cases.size()])
	get_tree().quit(0 if failed == 0 else 1)


## Faults that need the built nodes go here (after Build).
func _after_build(name: String, tb: TrackBuilder, scene: Node) -> void:
	if name == "track overhead":
		# A second copy of 200 m of the road, 6 m above it.
		var main := scene.get_node("MainSpline") as Path3D
		var p := Path3D.new()
		p.name = "Overhead"
		p.curve = main.curve
		p.position = Vector3.UP * 6.0
		scene.add_child(p)
		var seg := TrackRoadSegment.new()
		seg.path_node = NodePath("..")
		seg.start_distance = 1000.0
		seg.end_distance = 1200.0
		seg.polygon = PackedVector2Array([Vector2(21.5, 0.5), Vector2(-21.5, 0.5), Vector2(-21.5, -0.5), Vector2(21.5, -0.5)])
		p.add_child(seg)
	elif name == "moved geometry (the offset)":
		# What the circuits do: rotate the road geometry node.
		var road := scene.get_node("MainSpline/Road") as Node3D
		road.rotation_degrees = Vector3(1.04, 0, 0)


func _none(_tb: TrackBuilder, _scene: Node) -> void:
	pass


func _kink(tb: TrackBuilder, _scene: Node) -> void:
	tb.fairing_m = 0.0
	# A short handle on one corner point: a curvature step there.
	var c := tb.base_path().curve
	c.set_point_in(3, c.get_point_in(3) * 0.15)
	c.set_point_out(3, c.get_point_out(3) * 0.15)


func _grid_on_bend(tb: TrackBuilder, _scene: Node) -> void:
	var k := tb.keys_of("StartKey")[0]
	k.global_position = Vector3(150, 6, 640)    # the tightest corner


func _short_runup(tb: TrackBuilder, _scene: Node) -> void:
	for f in tb.features():
		if f is JumpFeature:
			(f as JumpFeature).respawn_runup = 20.0


func _junction_width(tb: TrackBuilder, _scene: Node) -> void:
	var w := WidthKey.new()
	w.name = "NarrowFork"
	tb.get_node("WidthKeys").add_child(w)
	w.half_width_left = 15.0
	w.global_position = Vector3(2478, -4, 260)


func _overhead(_tb: TrackBuilder, _scene: Node) -> void:
	pass    # added after the build (_after_build)


func _feature_in_junction(tb: TrackBuilder, _scene: Node) -> void:
	for f in tb.features():
		if f is RollFeature:
			f.global_position = Vector3(2480, -2, -100)


func _branch_off(tb: TrackBuilder, _scene: Node) -> void:
	var bf := tb.branch_nodes()[0]
	var c := bf.base_path().curve
	c.set_point_position(0, c.get_point_position(0) + Vector3(-60, 0, 0))


func _short_roll(tb: TrackBuilder, _scene: Node) -> void:
	for f in tb.features():
		if f is RollFeature:
			(f as RollFeature).length = 450.0


func _crest(tb: TrackBuilder, _scene: Node) -> void:
	# A sharp hump on the bottom straight: a point raised 70 m with short,
	# level handles (a 10% climb meeting a 10% descent over ~20 m).
	var c := tb.base_path().curve
	var i := 16
	c.set_point_position(i, c.get_point_position(i) + Vector3.UP * 70.0)
	c.set_point_in(i, Vector3(c.get_point_in(i).x, 0, c.get_point_in(i).z).normalized() * 10.0)
	c.set_point_out(i, Vector3(c.get_point_out(i).x, 0, c.get_point_out(i).z).normalized() * 10.0)


func _moved(_tb: TrackBuilder, _scene: Node) -> void:
	pass    # done after the build (_after_build)
