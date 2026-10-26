extends Node
## v38: what EnvSurfaces.adopt() does to a track's surfaces: which materials
## it adopted (and with which shader) and the per-mesh instance values it set.
##
##   godot --headless --path . -s res://tools/dev/env_adopt_check_boot.gd
##
## Env: EA_TRACK (default builder_lab). Prints ENVADOPT lines.


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var track_id := OS.get_environment("EA_TRACK")
	if track_id == "":
		track_id = "builder_lab"
	var track := (load("res://scenes/tracks/%s.tscn" % track_id) as PackedScene).instantiate()
	add_child(track)
	await get_tree().process_frame
	var main := track.find_child("MainSpline", true, false) as Path3D
	var rep := EnvSurfaces.adopt(track, main)
	print("ENVADOPT %s: %d materials, %d nodes, %d conflicts, road_u_scale %.1f" % [
			track_id, rep.materials, rep.nodes, rep.conflicts, rep.road_u_scale])
	for n in track.find_children("*", "TrackRoadSegment", true, false):
		var seg := n as TrackRoadSegment
		var mi := seg.get_child(0, true) as MeshInstance3D
		var sm := mi.mesh.surface_get_material(0) as ShaderMaterial
		print("ENVADOPT  %-24s %-44s along_main %s  path_length %s  u_scale %s  kind %s" % [
				"%s/%s" % [seg.get_parent().name, seg.name], sm.shader.resource_path,
				mi.get_instance_shader_parameter("along_main"),
				mi.get_instance_shader_parameter("path_length"),
				sm.get_shader_parameter("u_scale"), sm.get_shader_parameter("surface_kind")])
	get_tree().quit(0)
