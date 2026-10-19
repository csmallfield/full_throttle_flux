extends SceneTree
## Sweeps the racing envelope along the Utopia track and reports any city
## geometry that intrudes into it.
##   godot --headless --path . -s res://tools/utopia/check_clearance.gd
## Envelope per sample (in the BANKED track frame):
##   lateral  -HALF_W .. +HALF_W     height  H_BOT .. H_TOP above the centreline

const HALF_W := 31.0     # walls' outer face is at ~28.6
const H_BOT := -2.0     # underside of the road slab
const H_TOP := 19.0
const STEP := 2.0

func _initialize() -> void:
	var track: Node3D = load("res://scenes/tracks/test_circuit_3_live.tscn").instantiate()
	root.add_child(track)
	await process_frame
	var city := track.get_node_or_null("UtopiaCity")
	if city == null:
		push_error("no UtopiaCity under the track")
		quit(1)
		return
	# build collision proxies for every visual mesh in the city
	var body_of := {}
	var n := 0
	for mi in _meshes(city):
		if mi.mesh == null:
			continue
		var sb := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		cs.shape = mi.mesh.create_trimesh_shape()
		sb.add_child(cs)
		root.add_child(sb)
		sb.global_transform = mi.global_transform
		body_of[sb.get_rid()] = mi
		n += 1
	await physics_frame
	await physics_frame
	var kit := UtopiaKit.new(track)
	var L := kit.length
	var space := root.get_world_3d().direct_space_state
	var shape := BoxShape3D.new()
	shape.size = Vector3(HALF_W * 2.0, H_TOP - H_BOT, STEP * 1.2)
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.collide_with_bodies = true
	var hits := {}
	var d := 0.0
	while d < L:
		var c := kit.center(d)
		var b := kit.frame(d)
		var u := b.y
		q.transform = Transform3D(b, c + u * ((H_TOP + H_BOT) * 0.5))
		for res in space.intersect_shape(q, 32):
			var mi: Node = body_of.get(res["rid"])
			if mi == null:
				continue
			var key := str(city.get_path_to(mi))
			if not hits.has(key):
				hits[key] = [d, d]
			hits[key][1] = d
		d += STEP
	print("CLEARANCE: %d meshes checked, %d intrusions" % [n, hits.size()])
	for key in hits:
		print("  INTRUDES d=%d..%d  %s" % [hits[key][0], hits[key][1], key])
	quit()

func _meshes(n: Node) -> Array:
	var out := []
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		out.append_array(_meshes(c))
	return out
