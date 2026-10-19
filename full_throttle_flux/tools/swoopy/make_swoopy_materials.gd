extends SceneTree
## Writes the Swoopy greybox materials to scenes/tracks/swoopy/materials/.
##   godot --headless --path . -s res://tools/swoopy/make_swoopy_materials.gd
## Swap any of them for real materials later: the meshes reference these files.

const DIR := "res://scenes/tracks/swoopy/materials/"

func _initialize() -> void:
	_std("concrete", Color(0.70, 0.68, 0.65), 0.92)
	_std("concrete_dk", Color(0.47, 0.46, 0.45), 0.94)
	_std("steel", Color(0.27, 0.29, 0.32), 0.5, 0.35)
	_std("city_a", Color(0.50, 0.52, 0.56), 0.9)
	_std("city_b", Color(0.36, 0.38, 0.43), 0.9)
	_std("city_roof", Color(0.62, 0.62, 0.62), 0.95)
	_std("city_ground", Color(0.30, 0.31, 0.33), 0.97)
	_std("river", Color(0.10, 0.13, 0.17), 0.08)
	_std("glass", Color(0.16, 0.20, 0.27), 0.12, 0.65)
	_std("pale", Color(0.90, 0.89, 0.87), 0.55)
	var beacon := _std("beacon", Color(1.0, 0.15, 0.1), 0.5)
	beacon.emission_enabled = true
	beacon.emission = Color(1.0, 0.12, 0.08)
	beacon.emission_energy_multiplier = 6.0
	ResourceSaver.save(beacon, DIR + "beacon.tres")
	var halo := _std("halo", Color(0.85, 0.95, 1.0), 0.4)
	halo.emission_enabled = true
	halo.emission = Color(0.55, 0.85, 1.0)
	halo.emission_energy_multiplier = 1.6
	ResourceSaver.save(halo, DIR + "halo.tres")
	# cloud sea
	var sm := ShaderMaterial.new()
	sm.shader = load(DIR + "cloud_sea.gdshader")
	sm.set_shader_parameter("noise_large", _noise(11, 3.0, 6))
	sm.set_shader_parameter("noise_small", _noise(29, 4.0, 4))
	sm.render_priority = -1
	sm.set_shader_parameter("coverage", 0.32)
	sm.set_shader_parameter("opacity", 0.88)
	ResourceSaver.save(sm, DIR + "cloud_sea.tres")
	print("MATERIALS OK")
	quit()

func _std(name: String, c: Color, rough: float, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	ResourceSaver.save(m, DIR + name + ".tres")
	return m

func _noise(seed: int, freq_tiles: float, octaves: int) -> NoiseTexture2D:
	var fn := FastNoiseLite.new()
	fn.seed = seed
	fn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	fn.frequency = freq_tiles / 512.0
	fn.fractal_type = FastNoiseLite.FRACTAL_FBM
	fn.fractal_octaves = octaves
	var t := NoiseTexture2D.new()
	t.width = 512
	t.height = 512
	t.seamless = true
	t.seamless_blend_skirt = 0.15
	t.normalize = true
	t.generate_mipmaps = true
	t.noise = fn
	return t
