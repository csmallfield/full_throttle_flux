// v38 phase 5b: CSG mode (the circuits). A CSGPolygon3D extrusion has only
// UVs: UV.x * csg_u_scale = metres along, UV.y = position round the outline.
// TrackSurface.csg_edge_table() gives every outline edge's UV.y range, ends
// (x in the CSG's frame; t = x * csg_x_sign) and heights, and its class;
// csg_lookup() finds the pixel's edge and interpolates along it.

group_uniforms csg;
uniform bool csg_mode = false;
uniform float csg_u_scale = 100.0;
// Per edge: (v0, v1, x0, x1) and (y0, y1, class, 0).
uniform vec4 csg_edges[16];
uniform vec4 csg_edges_y[16];
uniform int csg_edge_count = 0;
// Surface half widths (left, right) and the surface's height in the section.
uniform vec2 csg_half = vec2(19.5);
uniform float csg_surface_y = 0.0;
// The CSG's +x against the road's t (TrackSurface.CSG_X_SIGN).
uniform float csg_x_sign = 1.0;
group_uniforms;

// (t, height above the surface, class) at outline position `v`.
vec3 csg_lookup(float v) {
	int k = 0;
	for (int i = 0; i < 16; i++) {
		if (i >= csg_edge_count) {
			break;
		}
		if (v >= csg_edges[i].x && v <= csg_edges[i].y) {
			k = i;
			break;
		}
	}
	vec4 e = csg_edges[k];
	vec4 ey = csg_edges_y[k];
	float f = clamp((v - e.x) / max(e.y - e.x, 1e-6), 0.0, 1.0);
	return vec3(csg_x_sign * mix(e.z, e.w, f), mix(ey.x, ey.y, f) - csg_surface_y, ey.z);
}
