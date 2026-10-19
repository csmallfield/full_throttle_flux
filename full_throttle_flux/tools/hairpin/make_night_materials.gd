extends SceneTree
## Writes the Hairpin Alley night materials (run once; safe to re-run).
##   godot --headless --path . -s res://tools/hairpin/make_night_materials.gd
const M := "res://scenes/tracks/hairpin_alley/materials/"

func _std(name: String, albedo: Color, rough: float, emis := Color.BLACK, energy := 0.0, metal := 0.0) -> void:
	var m := StandardMaterial3D.new()
	m.albedo_color = albedo
	m.roughness = rough
	m.metallic = metal
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if energy > 0.0:
		m.emission_enabled = true
		m.emission = emis
		m.emission_energy_multiplier = energy
	ResourceSaver.save(m, M + name + ".tres")

func _initialize() -> void:
	var w := ShaderMaterial.new()
	w.shader = load(M + "night_windows.gdshader")
	ResourceSaver.save(w, M + "night_windows.tres")
	var w2 := ShaderMaterial.new()   # denser, brighter tower variant
	w2.shader = w.shader
	w2.set_shader_parameter("lit_ratio", 0.6)
	w2.set_shader_parameter("floor_height", 3.8)
	w2.set_shader_parameter("bay_width", 2.6)
	w2.set_shader_parameter("energy", 3.2)
	ResourceSaver.save(w2, M + "night_windows_tower.tres")
	var sc := ShaderMaterial.new()
	sc.shader = load(M + "night_screen.gdshader")
	ResourceSaver.save(sc, M + "night_screen.tres")
	_std("night_concrete", Color(0.13, 0.13, 0.15), 0.9)
	_std("night_dark", Color(0.05, 0.05, 0.06), 0.4, Color.BLACK, 0.0, 0.3)
	_std("night_street", Color(0.04, 0.04, 0.05), 0.95)
	_std("neon_cyan", Color(0.2, 0.9, 1.0), 0.5, Color(0.2, 0.9, 1.0), 6.0)
	_std("neon_magenta", Color(1.0, 0.2, 0.7), 0.5, Color(1.0, 0.2, 0.7), 6.0)
	_std("neon_amber", Color(1.0, 0.6, 0.15), 0.5, Color(1.0, 0.55, 0.12), 6.0)
	_std("neon_white", Color(1.0, 1.0, 1.0), 0.5, Color(0.9, 0.95, 1.0), 5.0)
	_std("beacon_red", Color(1.0, 0.1, 0.05), 0.5, Color(1.0, 0.08, 0.04), 8.0)
	print("NIGHT MATERIALS OK")
	quit()
