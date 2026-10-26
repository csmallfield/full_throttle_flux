// v38 phase 2: hex grates (refs 5, 9). Never transparent (decision 4): the
// holes are a dark recess faked with parallax on the high tier (the floor
// shifts with the view, and the hole's far wall shows) and a flat average
// on the low tier, with an optional faint under-glow.
//
// Cells repeat along s AND t, so the footprint is the larger of the two
// (fw_s already carries aa_s_bias); below ~2 px a cell fades to the exact
// bar / hole area mix.

group_uniforms grates;
// Distance between cell centres across the band, metres.
uniform float grate_cell : hint_range(0.05, 2.0) = 0.36;
uniform float grate_bar : hint_range(0.005, 0.3) = 0.05;
// Solid frame along both band edges.
uniform float grate_frame : hint_range(0.0, 0.5) = 0.08;
uniform float grate_depth : hint_range(0.0, 0.5) = 0.12;
uniform vec3 grate_bar_color : source_color = vec3(0.13, 0.135, 0.145);
uniform vec3 grate_floor_color : source_color = vec3(0.015, 0.017, 0.02);
uniform vec3 grate_wall_color : source_color = vec3(0.05, 0.052, 0.058);
uniform vec3 grate_glow : source_color = vec3(0.05, 0.3, 0.42);
uniform float grate_glow_energy : hint_range(0.0, 4.0) = 0.35;
group_uniforms;

// Hex tiling: cell-local position of `p` (cell units: centres 1 apart
// across) and the cell's centre in `id`.
vec2 grate_hex(vec2 p, out vec2 id) {
	vec2 r = vec2(1.0, 1.7320508);
	vec2 h = r * 0.5;
	vec2 a = mod(p, r) - h;
	vec2 b = mod(p - h, r) - h;
	vec2 g = dot(a, a) < dot(b, b) ? a : b;
	id = p - g;
	return g;
}

// Distance from cell-local `g` to the hexagon's edge (cell units, > 0 inside).
float grate_edge(vec2 g) {
	vec2 q = abs(g);
	return 0.5 - max(q.x, dot(q, vec2(0.5, 0.8660254)));
}

// `u` metres from the band's left edge, `w` the band width, `view` the view
// direction in (across, along, up).
void grate(inout TSurf o, float u, float w, float s, float fw_t, float fw_s, vec3 view,
		bool parallax) {
	float fw = max(fw_t, fw_s);
	vec2 id;
	vec2 g = grate_hex(vec2(u, s) / grate_cell, id);
	float bh = 0.5 * grate_bar / grate_cell;
	float hole = aa_step(bh * grate_cell, grate_edge(g) * grate_cell, fw);
	float avg_hole = pow(max(0.5 - bh, 0.0) / 0.5, 2.0);
	float fade = aa_fade(grate_cell, fw);
	ts_filt(o, fade);
	hole = mix(hole, avg_hole, fade);
	float frame = max(aa_pulse(-1.0, grate_frame, u, fw_t), aa_pulse(w - grate_frame, w + 1.0, u, fw_t));
	hole *= 1.0 - frame;

	// What the hole shows: the floor, or the far wall where the view ray
	// hits the wall before the floor.
	float wall = 0.4;
	if (parallax && fade < 1.0) {
		vec2 shift = -view.xy / max(view.z, 0.15) * grate_depth / grate_cell;
		float e = grate_edge(g + shift);
		float wall_px = aa_step(e, bh, fw / grate_cell);
		wall = mix(wall_px, 0.4, fade);
	}
	vec3 hole_col = mix(grate_floor_color, grate_wall_color, wall);
	o.albedo = mix(grate_bar_color, hole_col, hole);
	o.rough = mix(0.4, 0.85, hole);
	o.metal = mix(0.8, 0.2, hole);
	o.emission += grate_glow * grate_glow_energy * hole * (1.0 - wall);
	o.keep = max(o.keep, hole * 0.5);
	o.recess = max(o.recess, hole);
}
