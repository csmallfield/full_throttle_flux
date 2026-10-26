// v35 Phase 4: the track grid shader (shaders/grid_shader.gdshader, same
// look, same parameters) plus env_surface. EnvSurfaces swaps it in at race
// start on every material that uses the grid shader, road and walls, so no
// track scene needs editing. With the env globals at 0 it renders exactly
// like the original.
// v38: the grid comes from grid_filtered.gdshaderinc, the same code as
// grid_shader.gdshader (this file had kept the v36 fixed-pixel grid).
shader_type spatial;

#include "res://shaders/env/env_surface.gdshaderinc"
#include "res://shaders/grid_filtered.gdshaderinc"

// Set by EnvSurfaces from the CSG node:
// 0 road, 1 wall
uniform float surface_kind = 0.0;
// metres along the spline = UV.x * u_scale (CSGPolygon3D path_u_distance with
// continuous U); 0 = unknown (no zone mask)
uniform float u_scale = 0.0;
// road: UV.y range of the driving surface (CSG path UV.y = outline position)
uniform float road_v0 = 0.0;
uniform float road_v1 = 0.0;

void fragment() {
	// --- the grid -----------------------------------------------------------
	GridLook g = grid_look(UV * 100.0);
	vec3 color = g.color;
	float grid_mask = g.minor * minor_strength;
	float major_mask = g.major * major_strength;

	// --- environment ---------------------------------------------------------
	EnvSurface s;
	s.albedo = color;
	s.roughness = 0.8;
	s.metallic = 0.0;
	s.specular = 0.5;
	s.emission = vec3(0.0);
	s.world_pos = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	s.world_normal = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	s.along = u_scale > 0.0 ? UV.x * u_scale : -1.0;
	float edge = 1.0;
	if (surface_kind < 0.5 && road_v1 > road_v0) {
		// 0 at the road centre, 1 at the edges and on the banks beyond
		float lat = (UV.y - road_v0) / (road_v1 - road_v0);
		edge = clamp(abs(lat - 0.5) * 2.0, 0.0, 1.0);
		edge = lat < 0.0 || lat > 1.0 ? 1.0 : edge;
	}
	s.edge = edge;
	s.is_wall = surface_kind;
	s.keep = max(grid_mask, major_mask) * 1.4;
	s.recess = 0.0;
	env_surface_apply(s, TIME);

	ALBEDO = s.albedo;
	ROUGHNESS = s.roughness;
	METALLIC = s.metallic;
	SPECULAR = s.specular;
	EMISSION = s.emission + grid_color.rgb * (g.major * 1.6 + g.minor * 0.5) * env_line_glow;
	if (dot(s.normal_offset, s.normal_offset) > 1e-8) {
		vec3 nw = normalize(s.world_normal + s.normal_offset);
		NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);
	}
}
