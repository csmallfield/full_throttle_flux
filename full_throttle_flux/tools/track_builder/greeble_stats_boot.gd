extends SceneTree
## Headless greeble stats (v36): placements per zone and layer, pieces left
## out past their upright limit, the intrusion check and a checksum of every
## instance transform (to compare two versions of the code bit for bit).
##
##   godot --headless --path . -s res://tools/track_builder/greeble_stats_boot.gd -- --scene=res://scenes/tracks/builder_lab.tscn
##
## GS_VERBOSE=1 prints every zone/layer count.

func _initialize() -> void:
	await process_frame
	var path := "res://scenes/tracks/builder_lab.tscn"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--scene="):
			path = a.substr(8)
	var scene: Node = (load(path) as PackedScene).instantiate()
	root.add_child(scene)
	await process_frame
	var g := scene.get_node_or_null("TrackGreebles") as TrackGreebles
	if g == null:
		print("GSTATS no TrackGreebles in %s" % path)
		quit(1)
		return
	var t0 := Time.get_ticks_usec()
	var pl := g.placements()
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	var parts := PackedFloat64Array()
	var per := {}
	for p in pl:
		var xf: Transform3D = p.xf
		for v: Vector3 in [xf.basis.x, xf.basis.y, xf.basis.z, xf.origin]:
			parts.append_array([snappedf(v.x, 0.0001), snappedf(v.y, 0.0001), snappedf(v.z, 0.0001)])
		var k := "%s/%s" % [g.zones[p.zi].label, p.layer]
		per[k] = per.get(k, 0) + 1
	if OS.get_environment("GS_VERBOSE") == "1":
		var ks := per.keys()
		ks.sort()
		for k in ks:
			print("GSTATS   %-34s %5d" % [k, per[k]])
	var bad := g.intrusions(pl)
	print("GSTATS %s: %d zones, %d instances, %d left out past upright limits, %d intrusion groups, %.0f ms, checksum %d"
			% [path.get_file(), g.zones.size(), pl.size(), g.skipped_upright, bad.size(), ms, hash(parts)])
	for b in bad:
		var z: TrackGreebleZone = g.zones[b.zi]
		print("GSTATS   %s rule %d ×%d @ %.0f m: %s" % [z.label, b.ri, b.count, b.d, b.what])
	quit(0)
