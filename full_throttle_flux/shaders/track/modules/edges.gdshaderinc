// v38 phase 2: edge bands and lips. Edges are marked loudly (refs 2, 5):
// a painted line on the edge band where it meets the lip, and yellow /
// black hazard diagonals on the lips. The LED row is in lights.gdshaderinc.
//
// The diagonals run at 45 degrees in (s, t), so they repeat along both; the
// caller passes the footprint of their own coordinate (fw_q), and they fade
// to the 50/50 mix.

group_uniforms edges;
uniform vec3 edge_line_color : source_color = vec3(0.78, 0.78, 0.76);
uniform float edge_line_width : hint_range(0.0, 0.5) = 0.12;
// Yellow kept clear of the boost pads' orange.
uniform vec3 hazard_yellow : source_color = vec3(0.95, 0.76, 0.05);
uniform vec3 hazard_black : source_color = vec3(0.03, 0.03, 0.03);
uniform float hazard_period : hint_range(0.1, 5.0) = 1.1;
group_uniforms;

// The painted line at an edge band's outer edge.
void edge_line(inout TSurf o, float x0, float x1, bool outer_left, float t, float fw_t) {
	float a = outer_left ? x0 : x1 - edge_line_width;
	float line = aa_pulse(a, a + edge_line_width, t, fw_t);
	o.albedo = mix(o.albedo, edge_line_color, line);
	o.rough = mix(o.rough, 0.6, line);
	o.metal = mix(o.metal, 0.0, line);
	o.keep = max(o.keep, line);
}

// Hazard diagonals; `q` = (s + |t|) / sqrt(2), `fw_q` its footprint.
void hazard(inout TSurf o, float q, float fw_q) {
	float f;
	float black = aa_lines(q, hazard_period, hazard_period * 0.5, fw_q, f);
	ts_filt(o, f);
	o.albedo = mix(hazard_yellow, hazard_black, black);
	o.rough = 0.6;
	o.metal = 0.0;
	o.keep = 1.0;
}
