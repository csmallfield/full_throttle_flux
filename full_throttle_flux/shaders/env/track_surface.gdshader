// v35 Phase 4: the track grid shader (shaders/grid_shader.gdshader, same
// look, same parameters) plus env_surface. EnvSurfaces swaps it in at race
// start on every material that uses the grid shader, road and walls, so no
// track scene needs editing. With the env globals at 0 it renders exactly
// like the original.
shader_type spatial;

#include "res://shaders/env/env_surface.gdshaderinc"

uniform vec4 grid_color : source_color = vec4(0.0, 0.8, 1.0, 1.0);
uniform vec4 background_color : source_color = vec4(0.05, 0.05, 0.1, 1.0);
uniform float grid_size : hint_range(0.1, 10.0) = 1.0;
uniform float line_width : hint_range(0.01, 0.5) = 0.05;
uniform float major_grid_every : hint_range(0.0, 20.0) = 5.0;
uniform float major_line_width : hint_range(0.01, 1.0) = 0.1;

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
	// --- the original grid ------------------------------------------------
	vec2 pos = UV * 100.0;
	vec2 grid = abs(fract(pos / grid_size - 0.5) - 0.5) / fwidth(pos / grid_size);
	float line = min(grid.x, grid.y);
	vec2 major_grid = abs(fract(pos / (grid_size * major_grid_every) - 0.5) - 0.5) / fwidth(pos / (grid_size * major_grid_every));
	float major_line = min(major_grid.x, major_grid.y);
	float grid_mask = 1.0 - min(line / line_width, 1.0);
	float major_mask = 1.0 - min(major_line / major_line_width, 1.0);
	vec3 color = background_color.rgb;
	color = mix(color, grid_color.rgb, grid_mask * 0.3);
	color = mix(color, grid_color.rgb, major_mask * 0.6);

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
	s.keep = max(grid_mask * 0.3, major_mask * 0.6) * 1.4;
	env_surface_apply(s, TIME);

	ALBEDO = s.albedo;
	ROUGHNESS = s.roughness;
	METALLIC = s.metallic;
	SPECULAR = s.specular;
	EMISSION = s.emission + grid_color.rgb * (major_mask * 1.6 + grid_mask * 0.5) * env_line_glow;
	if (dot(s.normal_offset, s.normal_offset) > 1e-8) {
		vec3 nw = normalize(s.world_normal + s.normal_offset);
		NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);
	}
}
