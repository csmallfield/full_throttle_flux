extends SceneTree
## Builds the Swoopy track dressing with the Utopia zone system:
##   scenes/tracks/swoopy/swoopy_track_dressing.tscn
##   scenes/tracks/swoopy/greebles/style_sky_deck.tres  (new style)
## Reuses the Utopia greeble meshes and the hairpin + service styles.
## Zones are derived from the layout: every corner -> "hairpin" (mirrored for
## right-handers so the chevrons sit on the outside wall), the overhead
## scaffold clusters and the high section -> "skyway", everything else ->
## "sky_deck" (new: light dashes, railings, lamp poles, stabiliser fins).
## Run WITH a renderer (not --headless; MultiMesh buffers need it):
##   godot --path . -s res://tools/swoopy/build_swoopy_dressing.gd
## Then re-run build_swoopy.gd (or just its city step) so swoopy_city.tscn
## picks the dressing up. After this first setup, edit in the editor and press
## Rebuild on TrackDresser instead (re-running overwrites the zone list).

const OUT := "res://scenes/tracks/swoopy/swoopy_track_dressing.tscn"
const RAILS := "res://scenes/tracks/swoopy/swoopy_road_rails.tscn"
const GB := "res://scenes/tracks/utopia/greebles/gb_%s.tres"
const STYLES := "res://scenes/tracks/utopia/greebles/styles/style_%s.tres"
const OWN_STYLE := "res://scenes/tracks/swoopy/greebles/style_sky_deck.tres"

var kit: UtopiaKit
var rails: Node3D

func _initialize() -> void:
	var track: Node3D = load("res://scenes/tracks/test_circuit_5_live.tscn").instantiate()
	for n in ["SwoopyCity", "SwoopyLighting"]:
		if track.has_node(n):
			track.get_node(n).free()
	root.add_child(track)
	await process_frame
	kit = UtopiaKit.new(track)
	var lay := SwoopyLayout.new(kit)
	DirAccess.make_dir_recursive_absolute(OWN_STYLE.get_base_dir())
	var dress := Node3D.new()
	dress.name = "SwoopyTrackDressing"
	root.add_child(dress)
	rails = load(RAILS).instantiate()
	rails.name = "Rails"
	dress.add_child(rails)
	rails.owner = dress

	var styles := {
		"sky_deck": _sky_deck(),
		"hairpin": load(STYLES % "hairpin"),
		"skyway": load(STYLES % "skyway"),
	}
	lay._plan_clusters()
	# special intervals in TRACK distance: [from, to, style, mirror, label]
	var special := []
	for c in lay.clusters:
		special.append([c[0] - 30.0, c[0] + (c[2] - 1) * c[3] + 30.0, "skyway", false, "%s%04d" % [c[1].capitalize(), int(c[0])]])
	var ci := 0
	for c in lay.corners:
		special.append([c[0] - 40.0, c[1] + 20.0, "hairpin", c[2] > 0.0, "Corner%02d" % ci])
		ci += 1
	special.sort_custom(func(a, b): return a[0] < b[0])
	# resolve overlaps: later interval starts where the previous ends
	for i in range(1, special.size()):
		if special[i][0] < special[i - 1][1]:
			special[i][0] = special[i - 1][1]
	special = special.filter(func(x): return x[1] - x[0] > 20.0)
	var zones: Array[UtopiaGreebleZone] = []
	var cursor := 0.0
	var n := 0
	for sp in special:
		if sp[0] > cursor + 10.0:
			var mid: float = (cursor + sp[0]) * 0.5
			zones.append(_zone("deck%02d" % n, cursor, sp[0], styles["skyway" if lay.in_high(mid) else "sky_deck"], false, n))
			n += 1
		zones.append(_zone(sp[4], maxf(sp[0], cursor), sp[1], styles[sp[2]], sp[3], n))
		cursor = sp[1]
		n += 1
	if cursor < kit.length - 10.0:
		zones.append(_zone("deck%02d" % n, cursor, kit.length, styles["sky_deck"], false, n))

	var dz := UtopiaZoneDresser.new()
	dz.name = "TrackDresser"
	dress.add_child(dz)
	dz.owner = dress
	dz.rails_root = dz.get_path_to(rails)
	dz.zones = zones
	dz.rebuild()
	print("zones: %d" % zones.size())
	for c in dress.get_children():
		c.owner = dress
		if c == rails:
			continue
		for zn in c.get_children():
			zn.owner = dress
			for mm in zn.get_children():
				mm.owner = dress
	var ps := PackedScene.new()
	ps.pack(dress)
	ResourceSaver.save(ps, OUT)
	print("DRESSING OK: %d instances" % dz.instance_count())
	quit()

func _zone(label: String, a: float, b: float, style: UtopiaGreebleStyle, mirror: bool, seed: int) -> UtopiaGreebleZone:
	var z := UtopiaGreebleZone.new()
	z.label = label
	z.from_d = _rd(a)
	z.to_d = _rd(b)
	z.style = style
	z.mirror = mirror
	z.seed = 500 + seed
	return z

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

func _r(layer: String, mesh: String, p := {}) -> UtopiaGreebleRule:
	var r := UtopiaGreebleRule.new()
	r.layer = layer
	r.mesh = load(GB % mesh)
	for k in p:
		r.set(k, p[k])
	return r

## Sky deck: 24 m bays, light dashes on both walls for speed, railings and
## lamp poles on the wall tops, stabiliser fins on the outer wall faces.
func _sky_deck() -> UtopiaGreebleStyle:
	var s := UtopiaGreebleStyle.new()
	s.style_name = "sky_deck"
	s.bay_length = 24.0
	var rules: Array[UtopiaGreebleRule] = [
		_r("ground", "seam", {"side": "center"}),
		_r("ground", "stud", {"lateral": 8.5, "slots_per_bay": 3, "slot_phase": 0.5, "cast_shadows": false}),
		_r("ground", "deck_vent", {"lateral": 12.0, "slots_per_bay": 2, "probability": 0.4, "jitter": Vector3(2, 0, 2)}),
		_r("wall_face", "rib", {}),
		_r("wall_face", "wall_dash", {"slots_per_bay": 3, "slot_phase": 0.5, "offset": Vector3(0, 1.1, 0), "cast_shadows": false}),
		_r("wall_face", "wall_panel", {"pattern": "-x--", "slot_phase": 0.5}),
		_r("wall_top", "railing", {"slots_per_bay": 4, "slot_phase": 0.5, "mesh_length": 6.0}),
		_r("wall_top", "lamp_pole", {"side": "left", "pattern": "x-"}),
		_r("wall_top", "lamp_pole", {"side": "right", "pattern": "-x"}),
		_r("wall_top", "sensor_pod", {"pattern": "x---", "slot_phase": 0.5}),
		_r("outside", "fin", {"pattern": "x---"}),
	]
	s.rules = rules
	s.threshold_mesh = load(GB % "portal")
	ResourceSaver.save(s, OWN_STYLE)
	return load(OWN_STYLE)
