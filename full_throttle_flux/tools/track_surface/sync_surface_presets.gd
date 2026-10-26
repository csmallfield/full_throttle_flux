extends SceneTree
## v38 phase 3: the track surface's preset profiles and the base material's
## fallback band table.
##
##   godot --headless --path . -s res://tools/track_surface/sync_surface_presets.gd
##
## 1. Makes the starter presets in TrackSurfaceProfile.PRESET_DIR that don't
##    exist yet (never overwrites one: edit presets in the inspector).
## 2. Writes the industrial preset into slot 0 of the base material
##    (shaders/track/track_surface_material.tres). That's what a track
##    without a TrackSurface node draws (Fork Lab, a builder track with no
##    SurfaceZoneKeys). Rerun after editing profile_industrial.tres.
## 3. Points the base material at the wear detail texture (phase 4;
##    tools/track_surface/make_wear_detail.gd makes the placeholder).

const MATERIAL := "res://shaders/track/track_surface_material.tres"
const DEFAULT_PRESET := "industrial"
const WEAR_DETAIL := "res://resources/track_surface/wear_detail.png"

const T := TrackSurfaceBand.Type
const L := TrackSurfaceBand.Light


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(TrackSurfaceProfile.PRESET_DIR)
	var made := 0
	for name in _starters():
		var path := TrackSurfaceProfile.preset_path(name)
		if ResourceLoader.exists(path):
			continue
		var p: TrackSurfaceProfile = _starters()[name]
		p.profile_name = name
		var err := ResourceSaver.save(p, path)
		print("SURFPRESET made %s (%s)" % [path, error_string(err)])
		made += 1
	var prof := load(TrackSurfaceProfile.preset_path(DEFAULT_PRESET)) as TrackSurfaceProfile
	var mat := load(MATERIAL) as ShaderMaterial
	if prof == null or mat == null:
		print("SURFPRESET missing %s or %s" % [DEFAULT_PRESET, MATERIAL])
		quit(1)
		return
	for p in prof.problems():
		print("SURFPRESET %s: %s" % [DEFAULT_PRESET, p])
	var bands := PackedVector4Array()
	bands.resize(TrackSurface.MAX_PROFILES * TrackSurface.MAX_BANDS)
	var pk := prof.packed()
	for i in pk.size():
		bands[i] = pk[i]
	var info := PackedVector4Array()
	info.resize(TrackSurface.MAX_PROFILES)
	var sums := prof.sums()
	info[0] = Vector4(pk.size(), sums.x, sums.y, 0.0)
	mat.set_shader_parameter("surf_bands", bands)
	mat.set_shader_parameter("surf_profiles", info)
	if ResourceLoader.exists(WEAR_DETAIL):
		mat.set_shader_parameter("wear_detail", load(WEAR_DETAIL))
	var err := ResourceSaver.save(mat, MATERIAL)
	if err == OK:
		_drop_null_params(MATERIAL)
	print("SURFPRESET %d presets made; %s: %d bands of %s (%s)" % [made, MATERIAL, pk.size(),
			DEFAULT_PRESET, error_string(err)])
	quit(0 if err == OK else 1)


## The saver lists every shader parameter, unset ones as "= null" (they
## mean "the shader's default"): drop those lines so the file only holds
## what's set.
static func _drop_null_params(path: String) -> void:
	var text := FileAccess.get_file_as_string(path)
	var keep := PackedStringArray()
	for line in text.split("\n"):
		if line.begins_with("shader_parameter/") and line.ends_with(" = null"):
			continue
		keep.append(line)
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("\n".join(keep))


static func _band(type: int, width: float, flex := 0.0, light := 0, vents := false) -> TrackSurfaceBand:
	var b := TrackSurfaceBand.new()
	b.type = type
	b.width = width
	b.flex = flex
	b.light = light
	b.vents = vents
	return b


static func _profile(bands: Array) -> TrackSurfaceProfile:
	var p := TrackSurfaceProfile.new()
	var list: Array[TrackSurfaceBand] = []
	for b in bands:
		list.append(b)
	p.bands = list
	p.mirror = true
	return p


## Left edge to centre; mirrored.
static func _starters() -> Dictionary:
	return {
		# Phase 2's hard-coded layout (refs 2, 9): grates by the edges,
		# ribbed lanes, a wide smooth centre with vents.
		"industrial": _profile([
			_band(T.EDGE, 1.2), _band(T.CHANNEL, 0.35, 0.0, L.RED_DOTS), _band(T.GRATE, 2.4),
			_band(T.CHANNEL, 0.3, 0.0, L.BLUE), _band(T.RIBBED, 5.0), _band(T.CHANNEL, 0.25),
			_band(T.PLATE, 0.0, 1.0, L.NONE, true)]),
		# Plainer: no grates, plate lanes, a wide ribbed centre (ref 6).
		"service": _profile([
			_band(T.EDGE, 1.5), _band(T.CHANNEL, 0.4, 0.0, L.RED_DOTS), _band(T.PLATE, 4.0),
			_band(T.CHANNEL, 0.3, 0.0, L.BLUE), _band(T.RIBBED, 0.0, 1.0)]),
		# Grate-heavy (ref 5): smooth outer lanes, wide grates, a smooth centre.
		"grate_run": _profile([
			_band(T.EDGE, 1.0), _band(T.CHANNEL, 0.3, 0.0, L.RED_DOTS), _band(T.PLATE, 3.0),
			_band(T.CHANNEL, 0.3, 0.0, L.BLUE), _band(T.GRATE, 4.0), _band(T.CHANNEL, 0.3, 0.0, L.BLUE),
			_band(T.PLATE, 0.0, 1.0)]),
	}
