extends SceneTree
## Builds the zoned track dressing:
##   scenes/tracks/utopia/greebles/styles/*.tres     dressing styles (edit these)
##   scenes/tracks/utopia/utopia_track_dressing.tscn  rails + UtopiaZoneDresser
## Run WITH a renderer (not --headless): the headless dummy renderer drops
## MultiMesh buffers, so the scene would save empty.
##   godot --path . -s res://tools/utopia/build_dressing.gd
## After this first setup, edit styles/zones in the editor and press Rebuild on
## the TrackDresser node. Re-running this script OVERWRITES the style files
## and the zone list.

const OUT := "res://scenes/tracks/utopia/utopia_track_dressing.tscn"
const RAILS := "res://scenes/tracks/utopia/utopia_road_rails.tscn"
const GB := "res://scenes/tracks/utopia/greebles/gb_%s.tres"
const STYLES := "res://scenes/tracks/utopia/greebles/styles"

var kit: UtopiaKit
var rails: Node3D

func _initialize() -> void:
	var track: Node3D = load("res://scenes/tracks/test_circuit_3_live.tscn").instantiate()
	for n in ["UtopiaCity", "UtopiaLighting"]:
		if track.has_node(n):
			track.get_node(n).free()
	root.add_child(track)
	await process_frame
	kit = UtopiaKit.new(track)
	DirAccess.make_dir_recursive_absolute(STYLES)
	var dress := Node3D.new()
	dress.name = "UtopiaTrackDressing"
	root.add_child(dress)
	rails = load(RAILS).instantiate()
	rails.name = "Rails"
	dress.add_child(rails)
	rails.owner = dress

	var st := _styles()
	var dz := UtopiaZoneDresser.new()
	dz.name = "TrackDresser"
	dress.add_child(dz)
	dz.owner = dress
	dz.rails_root = dz.get_path_to(rails)
	dz.tunnels = PackedVector2Array([Vector2(_rd(1615), _rd(1800)), Vector2(_rd(4350), _rd(4450))])
	# [label, from (track d), to, style, mirror, density]
	var plan := [
		["concourse", 5650, 300, "civic", false, 1.0],
		["terraces", 300, 700, "garden", false, 1.0],
		["skyway", 700, 1300, "skyway", false, 1.0],
		["canyon", 1300, 1900, "service", false, 1.0],
		["corner", 1900, 2300, "civic", false, 0.8],
		["arcade", 2300, 2880, "civic", false, 1.0],
		["hairpin", 2880, 3160, "hairpin", false, 1.0],     # left-hander: chevrons on the right
		["northloop", 3160, 3850, "garden", false, 1.0],
		["spirerun", 3850, 4150, "civic", false, 1.0],
		["viaduct", 4150, 4680, "skyway", false, 1.0],
		["spiral", 4680, 5080, "hairpin", false, 0.8],     # left spiral
		["eastsweep", 5080, 5560, "maritime", false, 1.0],
		["uturn", 5560, 5650, "hairpin", true, 1.0],       # right-hander: mirror
	]
	var zones: Array[UtopiaGreebleZone] = []
	var i := 0
	for p in plan:
		var z := UtopiaGreebleZone.new()
		z.label = p[0]
		z.from_d = _rd(p[1])
		z.to_d = _rd(p[2])
		z.style = st[p[3]]
		z.mirror = p[4]
		z.density = p[5]
		z.seed = 100 + i
		zones.append(z)
		i += 1
	dz.zones = zones
	dz.rebuild()
	for zn in dz.get_children():
		var n := 0
		for c in zn.get_children():
			n += c.multimesh.instance_count
		print("  %-26s %5d" % [zn.name, n])
	_own(dress)
	var ps := PackedScene.new()
	ps.pack(dress)
	ResourceSaver.save(ps, OUT)
	print("DRESSING OK: %d instances" % dz.instance_count())
	quit()

## Track (MainSpline) distance -> Road rail distance.
func _rd(track_d: float) -> float:
	var cv := (rails.get_node("Road") as Path3D).curve
	var L := cv.get_baked_length()
	var target := kit.center(fposmod(track_d, kit.length))
	var est := fposmod(track_d, kit.length) * L / kit.length
	var best := est
	var bd := INF
	var o := est - 60.0
	while o <= est + 60.0:
		var dd := cv.sample_baked(fposmod(o, L)).distance_squared_to(target)
		if dd < bd:
			bd = dd
			best = o
		o += 0.5
	return fposmod(best, L)

func _own(dress: Node) -> void:
	for c in dress.get_children():
		c.owner = dress
		if c == rails:
			continue
		for zn in c.get_children():
			zn.owner = dress
			for mm in zn.get_children():
				mm.owner = dress

# =============================================================================
# STYLES -- each saved to greebles/styles/<name>.tres
# =============================================================================

func _r(layer: String, mesh: String, p := {}) -> UtopiaGreebleRule:
	var r := UtopiaGreebleRule.new()
	r.layer = layer
	r.mesh = load(GB % mesh)
	for k in p:
		r.set(k, p[k])
	return r

func _style(name: String, bay: float, rules: Array, threshold := "") -> UtopiaGreebleStyle:
	var s := UtopiaGreebleStyle.new()
	s.style_name = name
	s.bay_length = bay
	var typed: Array[UtopiaGreebleRule] = []
	typed.assign(rules)
	s.rules = typed
	if threshold != "":
		s.threshold_mesh = load(GB % threshold)
	var path := "%s/style_%s.tres" % [STYLES, name]
	ResourceSaver.save(s, path)
	var loaded: UtopiaGreebleStyle = load(path)
	return loaded

func _styles() -> Dictionary:
	var st := {}
	# CIVIC -- formal and ordered. 24 m bays: a seam, a rib and a fin on every
	# bay line; lit panels between ribs on alternate bays; lamps on alternate
	# bays, staggered left/right; a continuous railing on the wall tops.
	st["civic"] = _style("civic", 24.0, [
		_r("ground", "seam", {"side": "center"}),
		_r("ground", "stud", {"lateral": 8.5, "slots_per_bay": 3, "slot_phase": 0.5, "cast_shadows": false}),
		_r("ground", "deck_plate", {"lateral": 13.0, "slots_per_bay": 2, "pattern": "-x", "probability": 0.6}),
		_r("wall_face", "rib", {}),
		_r("wall_face", "ad_panel", {"slots_per_bay": 2, "pattern": "-x--", "slot_phase": 0.0, "offset": Vector3(0, -0.6, 0)}),
		_r("wall_face", "wall_dash", {"slots_per_bay": 4, "pattern": "x---", "slot_phase": 0.5, "offset": Vector3(0, 1.1, 0), "cast_shadows": false}),
		_r("wall_top", "railing", {"slots_per_bay": 4, "slot_phase": 0.5, "mesh_length": 6.0}),
		_r("wall_top", "lamp_pole", {"side": "left", "pattern": "x-"}),
		_r("wall_top", "lamp_pole", {"side": "right", "pattern": "-x"}),
		_r("outside", "fin", {"slot_phase": 0.0, "offset": Vector3(-1.1, -7.0, 0)}),
	], "portal")
	# GARDEN -- soft and open: planters on the wall tops, little on the walls,
	# nothing outside so the terraces and views stay clear.
	st["garden"] = _style("garden", 20.0, [
		_r("ground", "seam", {"side": "center", "pattern": "x-"}),
		_r("ground", "stud", {"lateral": 8.5, "slots_per_bay": 2, "slot_phase": 0.5, "cast_shadows": false}),
		_r("wall_face", "rib", {"pattern": "x-"}),
		_r("wall_face", "wall_dash", {"slots_per_bay": 2, "pattern": "-x", "slot_phase": 0.5, "offset": Vector3(0, 1.1, 0), "cast_shadows": false}),
		_r("wall_top", "planter", {"slots_per_bay": 2, "slot_phase": 0.5}),
		_r("wall_top", "lamp_pole", {"side": "left", "pattern": "x--"}),
		_r("wall_top", "lamp_pole", {"side": "right", "pattern": "-x-", "slot_phase": 0.5}),
	], "gantry")
	# SKYWAY -- elevated structure: a tall pylon frame on every 30 m bay line,
	# fast light dashes (every 5 m) for speed, antennas on the wall tops.
	st["skyway"] = _style("skyway", 30.0, [
		_r("ground", "seam", {"side": "center"}),
		_r("ground", "stud", {"lateral": 8.5, "slots_per_bay": 3, "slot_phase": 0.5, "cast_shadows": false}),
		_r("ground", "deck_vent", {"lateral": 10.0, "slots_per_bay": 2, "probability": 0.4, "slot_phase": 0.5, "jitter": Vector3(2, 0, 3)}),
		_r("wall_face", "rib", {}),
		_r("wall_face", "wall_dash", {"slots_per_bay": 6, "slot_phase": 0.5, "offset": Vector3(0, 1.1, 0), "cast_shadows": false}),
		_r("wall_top", "bollard", {"slots_per_bay": 2, "slot_phase": 0.5}),
		_r("wall_top", "antenna", {"side": "left", "pattern": "x--"}),
		_r("wall_top", "antenna", {"side": "right", "pattern": "--x"}),
		_r("outside", "pylon_tall", {}),
	], "gantry")
	# SERVICE -- the industrial guts: gutter grates and hazard strips on the
	# ground, continuous pipe runs and louvres on the walls, sensors on top,
	# dense fins outside and a truss overhead every 6 bays.
	st["service"] = _style("service", 16.0, [
		_r("ground", "seam", {"side": "center"}),
		_r("ground", "hazard_edge", {"lateral": 15.5, "slot_phase": 0.0}),
		_r("ground", "grate", {"lateral": 15.5, "slot_phase": 0.5}),
		_r("ground", "deck_vent", {"lateral": 8.0, "slots_per_bay": 2, "probability": 0.6, "jitter": Vector3(2, 0, 2)}),
		_r("ground", "deck_plate", {"side": "center", "pattern": "-x", "slot_phase": 0.5, "probability": 0.7}),
		_r("wall_face", "pipe_run", {"slots_per_bay": 2, "slot_phase": 0.5, "mesh_length": 1.0}),
		_r("wall_face", "wall_panel", {"slot_phase": 0.5, "offset": Vector3(0, 0.0, 0)}),
		_r("wall_face", "rib", {}),
		_r("wall_top", "sensor_pod", {"pattern": "x-", "slot_phase": 0.5}),
		_r("wall_top", "bollard", {"slot_phase": 0.0}),
		_r("outside", "fin", {"offset": Vector3(-1.1, -7.0, 0)}),
		_r("overhead", "truss", {"pattern": "x-----", "slot_phase": 0.5, "avoid_tunnels": true}),
	], "gantry")
	# MARITIME -- harbour front: masts with pennants outside, bollards on top,
	# cool light dashes, lamps every third bay.
	st["maritime"] = _style("maritime", 28.0, [
		_r("ground", "seam", {"side": "center", "pattern": "x-"}),
		_r("ground", "stud", {"lateral": 8.5, "slots_per_bay": 4, "slot_phase": 0.5, "cast_shadows": false}),
		_r("wall_face", "wall_dash", {"slots_per_bay": 4, "slot_phase": 0.5, "offset": Vector3(0, 1.1, 0), "cast_shadows": false}),
		_r("wall_face", "wall_panel", {"pattern": "x-", "slot_phase": 0.0, "offset": Vector3(0, -0.6, 0)}),
		_r("wall_top", "bollard", {"slots_per_bay": 2}),
		_r("wall_top", "lamp_pole", {"side": "left", "pattern": "x--", "slot_phase": 0.5}),
		_r("wall_top", "lamp_pole", {"side": "right", "pattern": "--x", "slot_phase": 0.5}),
		_r("outside", "mast", {"pattern": "x-"}),
	], "portal")
	# HAIRPIN -- read the corner: chevron boards every 12 m on the OUTSIDE
	# wall (right; mirror the zone for right-handers), hazard edges, sensors.
	st["hairpin"] = _style("hairpin", 12.0, [
		_r("ground", "hazard_edge", {"lateral": 15.5}),
		_r("ground", "stud", {"lateral": 8.5, "slots_per_bay": 2, "slot_phase": 0.5, "cast_shadows": false}),
		_r("wall_face", "chevron_sign", {"side": "right", "offset": Vector3(0, -0.2, 0), "mesh_right": load(GB % "chevron_sign_r")}),
		_r("wall_face", "rib", {"side": "left"}),
		_r("wall_face", "wall_dash", {"side": "left", "slot_phase": 0.5, "offset": Vector3(0, 1.1, 0), "cast_shadows": false}),
		_r("wall_top", "sensor_pod", {"pattern": "x--", "slot_phase": 0.5}),
		_r("wall_top", "bollard", {}),
		_r("outside", "fin", {"pattern": "x-", "offset": Vector3(-1.1, -7.0, 0)}),
	])
	return st
