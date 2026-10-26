extends Node
## v38: checks the track-space data TrackRoadSegment writes for the track
## surface shader, on a real builder track:
##   UV2.x  = the ring's distance along the path
##   UV2.y  = the vertex's actual offset across the frame (after widening)
##   CUSTOM0 edge class: the surface verts are at y = 0, lips above
##   CUSTOM0 half widths = the outermost surface verts at that ring
##
##   godot --headless --path . -s res://tools/dev/track_uv2_check_boot.gd
##
## Env: UC_TRACK (default builder_lab). Prints UV2CHECK lines, exits 1 on a
## failure.

var _fails := 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var track_id := OS.get_environment("UC_TRACK")
	if track_id == "":
		track_id = "builder_lab"
	var ps := load("res://scenes/tracks/%s.tscn" % track_id) as PackedScene
	var track := ps.instantiate()
	add_child(track)
	await get_tree().process_frame
	var segs := 0
	for n in track.find_children("*", "TrackRoadSegment", true, false):
		var seg := n as TrackRoadSegment
		if seg.collision_layer & 4:
			continue   # walls
		_check_segment(seg)
		segs += 1
	print("UV2CHECK %s: %d road segments, %s" % [track_id, segs,
			"ok" if _fails == 0 else "%d FAILED" % _fails])
	get_tree().quit(1 if _fails > 0 or segs == 0 else 0)


func _check_segment(seg: TrackRoadSegment) -> void:
	var mi := seg.get_child(0, true) as MeshInstance3D
	var path := seg.get_node(seg.path_node) as Path3D
	var arr := mi.mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var uv2s: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV2]
	var cust: PackedFloat32Array = arr[Mesh.ARRAY_CUSTOM0]
	var to_path := path.global_transform.affine_inverse() * seg.global_transform
	var length := path.curve.get_baked_length()
	var worst_t := 0.0
	var worst_y := 0.0
	var worst_w := 0.0
	var counts := [0, 0, 0]
	var step := maxi(1, verts.size() / 4000)
	for i in range(0, verts.size(), step):
		var s := uv2s[i].x
		var fr := TrackRoadSegment.frame_at(path.curve, s)
		if seg.weld_lap_seam and s >= length - 0.001:
			fr = TrackRoadSegment.frame_at(path.curve, 0.0)
		var p := to_path * verts[i]
		var rel := p - fr.origin
		worst_t = maxf(worst_t, absf(rel.dot(fr.basis.x) - uv2s[i].y))
		var cls := int(cust[i * 4])
		counts[cls] += 1
		var h := rel.dot(fr.basis.y)
		if cls == TrackRoadSegment.EDGE_SURFACE:
			worst_y = maxf(worst_y, absf(h))
			var w := seg.width_at(s)
			var lim := seg.width_stretch_limit
			var want := Vector2(lim + w.x - seg.width_reference, lim + w.y - seg.width_reference) \
					if not seg.width_profile.is_empty() else Vector2(lim, lim)
			worst_w = maxf(worst_w, (Vector2(cust[i * 4 + 1], cust[i * 4 + 2]) - want).abs().length())
	print("UV2CHECK  %-28s %6d verts  t err %.4f m  surface y err %.4f m  half width err %.4f m  classes %s" % [
			seg.get_path(), verts.size(), worst_t, worst_y, worst_w, counts])
	if worst_t > 0.01 or worst_y > 0.01 or worst_w > 0.01 or counts[0] == 0 or counts[1] == 0:
		_fails += 1
