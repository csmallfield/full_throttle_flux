extends RefCounted
class_name EnvSurfaces
## Makes a track's road and walls weather-aware (v35 Phase 4).
##
## The circuits and builder tracks all draw road and walls with the grid
## shader (shaders/resources/grid_material.tres, or inline copies of it in
## each circuit scene). At race start this swaps the SHADER of every such
## material for shaders/env/track_surface.gdshader (same look and
## parameters, plus env_surface) and fills in what the shader needs from the
## CSG node:
##   surface_kind  0 road, 1 wall (wall = name contains "wall" or collision
##                 layer 3, the wall layer)
##   u_scale       metres along MainSpline per UV.x unit: the CSGPolygon3D's
##                 path_u_distance when it extrudes along MainSpline with
##                 continuous U (checked on Utopia: within 0.3 m), else 0
##   road_v0/v1    UV.y range of the driving surface: CSG path UV.y runs along
##                 the polygon outline (see driving_surface_v)
##
## Only the material's shader and parameters change, never the node's
## `material`: reassigning that would rebuild the CSG mesh AND its collision
## mid-load. The swap persists on the shared resource for the session, which
## is harmless: with the env globals at 0 the new shader looks the same.

const SHADER_PATH := "res://shaders/env/track_surface.gdshader"
## A grid-shader material is recognised by its source: the v36 grid declares
## major_grid_every itself, the v37 one includes grid_filtered.gdshaderinc.
const GRID_SIGNATURES: Array[String] = ["major_grid_every", "grid_filtered.gdshaderinc"]
const WALL_LAYER := 4

## Result of adopt().
class Report extends RefCounted:
	var materials: int = 0
	var nodes: int = 0
	var conflicts: int = 0
	## u_scale of the main road (0 = no per-distance mask possible).
	var road_u_scale: float = 0.0


static func adopt(track_root: Node, main_spline: Path3D) -> Report:
	var rep := Report.new()
	if track_root == null:
		return rep
	var shader := load(SHADER_PATH) as Shader
	var seen := {}   # material -> params Dictionary it was given
	_walk(track_root, main_spline, shader, seen, rep)
	rep.materials = seen.size()
	return rep


static func _walk(n: Node, spline: Path3D, shader: Shader, seen: Dictionary, rep: Report) -> void:
	var mats: Array[Material] = []
	if n is CSGPrimitive3D:
		mats.append((n as CSGPrimitive3D).material)
	elif n is MeshInstance3D:
		var mi := n as MeshInstance3D
		mats.append(mi.material_override)
		if mi.mesh:
			for i in mi.mesh.get_surface_count():
				mats.append(mi.get_surface_override_material(i))
				mats.append(mi.mesh.surface_get_material(i))
	for m in mats:
		var sm := m as ShaderMaterial
		if sm == null or sm.shader == null:
			continue
		if sm.shader != shader and not is_grid(sm.shader):
			continue
		var params := _params_for(n, spline)
		if seen.has(sm):
			if seen[sm] != params:
				rep.conflicts += 1
			continue
		sm.shader = shader
		for k in params:
			sm.set_shader_parameter(k, params[k])
		seen[sm] = params
		rep.nodes += 1
		if params["surface_kind"] == 0.0 and params["u_scale"] > 0.0 and rep.road_u_scale == 0.0:
			rep.road_u_scale = params["u_scale"]
	for c in n.get_children():
		_walk(c, spline, shader, seen, rep)


static func is_grid(sh: Shader) -> bool:
	for sig in GRID_SIGNATURES:
		if sh.code.contains(sig):
			return true
	return false


static func _params_for(n: Node, spline: Path3D) -> Dictionary:
	var is_wall := n.name.to_lower().contains("wall")
	if n is CollisionObject3D or n is CSGShape3D:
		var layer: int = n.get("collision_layer")
		is_wall = is_wall or (layer & WALL_LAYER) != 0
	var p := {"surface_kind": 1.0 if is_wall else 0.0, "u_scale": 0.0, "road_v0": 0.0, "road_v1": 0.0}
	var poly := n as CSGPolygon3D
	if poly == null or poly.mode != CSGPolygon3D.MODE_PATH:
		return p
	if spline and poly.path_continuous_u and poly.path_u_distance > 0.0 \
			and poly.get_node_or_null(poly.path_node) == spline:
		p["u_scale"] = poly.path_u_distance
	if not is_wall:
		var v := driving_surface_v(poly.polygon)
		p["road_v0"] = v.x
		p["road_v1"] = v.y
	return p


## UV.y range of the top (driving) edge of an extrusion polygon: the widest
## edge above the polygon's centre. CSGPolygon3D reverses a counter-clockwise
## polygon before extruding, then puts outline vertex i at UV.y = i / (2 n)
## (measured on Utopia's road and walls: tools/env/probe_csg_uv.gd).
static func driving_surface_v(polygon: PackedVector2Array) -> Vector2:
	var n := polygon.size()
	if n < 3:
		return Vector2.ZERO
	var poly := polygon.duplicate()
	var area := 0.0
	for i in n:
		var a := poly[i]
		var b := poly[(i + 1) % n]
		area += a.x * b.y - b.x * a.y
	if area > 0.0:
		poly.reverse()
	var cy := 0.0
	for q in poly:
		cy += q.y
	cy /= n
	var best := -1
	var best_dx := 0.0
	for i in n:
		var a := poly[i]
		var b := poly[(i + 1) % n]
		if (a.y + b.y) * 0.5 <= cy:
			continue
		var dx := absf(b.x - a.x)
		if dx > best_dx:
			best_dx = dx
			best = i
	if best < 0:
		return Vector2.ZERO
	return Vector2(float(best) / (2.0 * n), float(best + 1) / (2.0 * n))


## Per-distance mask of the zones for the surface shader: R covered,
## G standing water, B snow drift, A dust_scale / 4. One texel per ~1 m,
## at most 8192.
static func build_mask(zones: Array[TrackFxZone], length: float) -> ImageTexture:
	var w := clampi(int(ceil(length)), 64, 8192)
	var img := Image.create(w, 1, false, Image.FORMAT_RGBA8)
	var s := TrackFxZones.Sample.new()
	for i in w:
		var d := (float(i) + 0.5) / w * length
		TrackFxZones.sample_zones(zones, d, length, s)
		img.set_pixel(i, 0, Color(clampf(s.covered, 0.0, 1.0), clampf(s.standing_water, 0.0, 1.0),
			clampf(s.snow_drift, 0.0, 1.0), clampf(s.dust_scale / 4.0, 0.0, 1.0)))
	return ImageTexture.create_from_image(img)
