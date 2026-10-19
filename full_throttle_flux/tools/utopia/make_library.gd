extends SceneTree
## One-off: writes the shared greybox materials + unit meshes.
func _mat(path: String, albedo: Color, rough: float, emissive := Color.BLACK, energy := 0.0, metal := 0.0) -> void:
	var m := StandardMaterial3D.new()
	m.albedo_color = albedo
	m.roughness = rough
	m.metallic = metal
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if energy > 0.0:
		m.emission_enabled = true
		m.emission = emissive
		m.emission_energy_multiplier = energy
	ResourceSaver.save(m, path)

func _initialize() -> void:
	var M := "res://scenes/tracks/utopia/materials/"
	_mat(M + "greybox_light.tres", Color(0.80, 0.79, 0.77), 0.85)
	_mat(M + "greybox_mid.tres", Color(0.52, 0.52, 0.53), 0.9)
	_mat(M + "greybox_dark.tres", Color(0.12, 0.13, 0.15), 0.25, Color.BLACK, 0.0, 0.2)
	_mat(M + "greybox_floor.tres", Color(0.42, 0.42, 0.44), 0.95)
	_mat(M + "greybox_far.tres", Color(0.40, 0.42, 0.47), 0.9)
	_mat(M + "greybox_accent.tres", Color(0.93, 0.92, 0.90), 0.6)
	_mat(M + "greybox_water.tres", Color(0.06, 0.08, 0.10), 0.04, Color.BLACK, 0.0, 0.0)
	_mat(M + "greybox_glow.tres", Color(1, 0.9, 0.75), 0.5, Color(1.0, 0.82, 0.6), 4.0)
	_mat(M + "greybox_glow_cool.tres", Color(0.8, 0.95, 1.0), 0.5, Color(0.45, 0.85, 1.0), 5.0)
	var P := "res://scenes/tracks/utopia/meshes/"
	var b := BoxMesh.new(); b.size = Vector3.ONE
	ResourceSaver.save(b, P + "unit_box.tres")
	var c := CylinderMesh.new(); c.top_radius = 0.5; c.bottom_radius = 0.5; c.height = 1.0; c.radial_segments = 48; c.rings = 1
	ResourceSaver.save(c, P + "unit_cyl.tres")
	var c16 := CylinderMesh.new(); c16.top_radius = 0.5; c16.bottom_radius = 0.5; c16.height = 1.0; c16.radial_segments = 16; c16.rings = 1
	ResourceSaver.save(c16, P + "unit_cyl16.tres")
	var cone := CylinderMesh.new(); cone.top_radius = 0.0; cone.bottom_radius = 0.5; cone.height = 1.0; cone.radial_segments = 48; cone.rings = 1
	ResourceSaver.save(cone, P + "unit_cone.tres")
	var taper := CylinderMesh.new(); taper.top_radius = 0.3; taper.bottom_radius = 0.5; taper.height = 1.0; taper.radial_segments = 48; taper.rings = 1
	ResourceSaver.save(taper, P + "unit_taper.tres")
	var s := SphereMesh.new(); s.radius = 0.5; s.height = 1.0; s.radial_segments = 48; s.rings = 24
	ResourceSaver.save(s, P + "unit_sphere.tres")
	var dm := SphereMesh.new(); dm.radius = 0.5; dm.height = 0.5; dm.is_hemisphere = true; dm.radial_segments = 48; dm.rings = 16
	ResourceSaver.save(dm, P + "unit_dome.tres")
	print("library done")
	quit()
