extends Node
## Headless Track Builder runner (v34), started by build_boot.gd or
## validate_boot.gd:
##
##   godot --headless --path . -s res://tools/track_builder/build_boot.gd -- --scene=res://scenes/tracks/builder_lab.tscn
##   godot --headless --path . -s res://tools/track_builder/validate_boot.gd -- --scene=res://scenes/tracks/builder_lab.tscn
##
## build: runs Build, saves the scene, then validates. validate: loads the
## scene as the game would (road built at load time) and validates it.
## Exit code 1 if Build fails or the validator reports errors.

var mode := "validate"


func _ready() -> void:
	TrackBuilder.keep_at_runtime = true
	var path := _arg("scene", OS.get_environment("TB_SCENE"))
	if path.is_empty():
		path = "res://scenes/tracks/builder_lab.tscn"
	var ps := load(path) as PackedScene
	if ps == null:
		push_error("can't load %s" % path)
		get_tree().quit(1)
		return
	var scene := ps.instantiate()
	add_child(scene)
	var tb := scene.find_child("TrackBuilder", true, false) as TrackBuilder
	if tb == null:
		push_error("no TrackBuilder in %s" % path)
		get_tree().quit(1)
		return
	await get_tree().process_frame
	var code := 0
	if mode == "build":
		var r := TrackBuild.run(tb)
		print("\n".join(r.log))
		if not r.ok:
			get_tree().quit(1)
			return
		var out := PackedScene.new()
		var err := out.pack(scene)
		if err == OK:
			err = ResourceSaver.save(out, path)
		print("BUILD saved %s (%s)" % [path, error_string(err)])
		if err != OK:
			code = 1
	# Let the physics space pick up the road.
	for i in 3:
		await get_tree().physics_frame
	var v := TrackValidator.run(tb, scene.get_viewport().world_3d.direct_space_state)
	print(v.summary())
	print("VALIDATE %s errors=%d warnings=%d" % [path, v.errors(), v.warnings()])
	if v.errors() > 0:
		code = 1
	get_tree().quit(code)


func _arg(key: String, fallback: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % key):
			return a.substr(key.length() + 3)
	return fallback
