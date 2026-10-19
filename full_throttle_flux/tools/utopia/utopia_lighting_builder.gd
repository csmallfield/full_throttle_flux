extends RefCounted
## Builds scenes/tracks/utopia/utopia_lighting.tscn
## Late-afternoon key from the WSW, cool sky fill, height haze that sinks
## the lower city levels into atmosphere so the layers read in depth.

static func build(path: String, params := {}) -> void:
	var root := Node3D.new()
	root.name = params.get("root_name", "UtopiaLighting")

	# procedural cloud sky (see sky/utopia_sky_common.gdshaderinc + UtopiaSkyController)
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = load("res://scenes/tracks/utopia/sky/utopia_sky_full.gdshader")
	# noise volumes: python3 tools/utopia/gen_cloud_noise.py + bake_cloud_noise.gd
	sky_mat.set_shader_parameter("shape_noise", load("res://scenes/tracks/utopia/sky/cloud_shape_128.res"))
	sky_mat.set_shader_parameter("detail_noise", load("res://scenes/tracks/utopia/sky/cloud_detail_64.res"))
	sky_mat.set_shader_parameter("weather_map", _weather())
	ResourceSaver.save(sky_mat, "res://scenes/tracks/utopia/sky/utopia_sky_material.tres")
	sky_mat = load("res://scenes/tracks/utopia/sky/utopia_sky_material.tres")
	var sky := Sky.new()
	sky.sky_material = sky_mat
	# the ambient/reflection cubemap uses the cheap pass; incremental keeps the
	# cost of drifting clouds spread over frames
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	sky.radiance_size = Sky.RADIANCE_SIZE_128

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = params.get("ambient", 0.55)
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = params.get("exposure", 1.0)
	env.tonemap_white = 6.0
	# contact shadows -- essential on greybox
	env.ssao_enabled = true
	env.ssao_radius = 3.0
	env.ssao_intensity = 2.5
	env.ssao_power = 1.6
	env.ssao_detail = 0.5
	env.ssil_enabled = params.get("ssil", true)
	env.ssil_radius = 8.0
	env.ssil_intensity = 0.8
	# aerial perspective + low-level haze
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_light_color = params.get("fog_color", Color(0.72, 0.70, 0.72))
	env.fog_light_energy = 1.0
	env.fog_sun_scatter = params.get("sun_scatter", 0.35)
	env.fog_density = params.get("fog_density", 0.00055)
	env.fog_aerial_perspective = params.get("aerial", 0.35)
	env.fog_sky_affect = 0.12
	env.fog_height = params.get("fog_height", -25.0)
	env.fog_height_density = params.get("fog_height_density", 0.018)
	# glow keeps the neon track and light strips alive
	env.glow_enabled = true
	env.glow_intensity = params.get("glow_intensity", 0.5)
	env.glow_bloom = params.get("glow_bloom", 0.04)
	env.glow_hdr_threshold = params.get("glow_threshold", 1.2)
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.06
	env.adjustment_saturation = 1.0

	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = env
	var comp := Compositor.new()
	var rays := UtopiaGodRays.new()
	var effects: Array[CompositorEffect] = [rays]
	comp.compositor_effects = effects
	we.compositor = comp
	root.add_child(we)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	var elev: float = params.get("sun_elev", 19.0)
	var azim: float = params.get("sun_azim", 250.0)  # compass deg the light comes FROM (0=N/-Z, 90=E/+X)
	# direction the light travels:
	var from_dir := Vector3(sin(deg_to_rad(azim)), 0.0, -cos(deg_to_rad(azim))) * cos(deg_to_rad(elev)) + Vector3.UP * sin(deg_to_rad(elev))
	sun.transform = Transform3D(Basis.looking_at(-from_dir, Vector3.UP), Vector3(0, 300, 0))
	sun.light_color = params.get("sun_color", Color(1.0, 0.80, 0.60))
	sun.light_energy = params.get("sun_energy", 2.4)
	sun.light_angular_distance = 0.6
	sun.shadow_enabled = true
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.2
	sun.shadow_blur = 1.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = params.get("shadow_dist", 1400.0)
	sun.directional_shadow_split_1 = 0.03
	sun.directional_shadow_split_2 = 0.10
	sun.directional_shadow_split_3 = 0.32
	sun.directional_shadow_blend_splits = true
	sun.directional_shadow_fade_start = 0.85
	sun.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_AND_SKY
	root.add_child(sun)

	# soft cool counter-light (no shadows) so shadow sides keep their shape
	var fill := DirectionalLight3D.new()
	fill.name = "SkyFill"
	var fill_from := Vector3(-from_dir.x, 0.6, -from_dir.z).normalized()
	fill.transform = Transform3D(Basis.looking_at(-fill_from, Vector3.UP), Vector3(0, 300, 0))
	fill.light_color = Color(0.55, 0.68, 0.95)
	fill.light_energy = params.get("fill_energy", 0.22)
	fill.shadow_enabled = false
	fill.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	root.add_child(fill)

	we.owner = root
	sun.owner = root
	fill.owner = root
	var ctl := UtopiaSkyController.new()
	ctl.name = "SkyController"
	root.add_child(ctl)
	ctl.owner = root
	ctl.world_environment = ctl.get_path_to(we)
	ctl.sun = ctl.get_path_to(sun)
	ctl.sky_fill = ctl.get_path_to(fill)
	# apply the preset once so the saved scene matches it (the node is not in
	# the tree here, so drive it by hand)
	var tmp := Node.new()
	Engine.get_main_loop().root.add_child(tmp)
	tmp.add_child(root)
	ctl.apply_preset(params.get("sky_preset", "golden_afternoon"))
	ctl.set("preset", params.get("sky_preset", "golden_afternoon"))   # so the inspector shows it
	tmp.remove_child(root)
	tmp.queue_free()
	var ps := PackedScene.new()
	ps.pack(root)
	ResourceSaver.save(ps, path)
	root.free()


static func _weather() -> NoiseTexture2D:
	var path := "res://scenes/tracks/utopia/sky/cloud_weather.tres"
	var fn := FastNoiseLite.new()
	fn.noise_type = FastNoiseLite.TYPE_PERLIN
	fn.frequency = 0.012
	fn.fractal_type = FastNoiseLite.FRACTAL_FBM
	fn.fractal_octaves = 5
	var t := NoiseTexture2D.new()
	t.width = 512
	t.height = 512
	t.seamless = true
	t.normalize = true
	t.noise = fn
	ResourceSaver.save(t, path)
	return load(path)
