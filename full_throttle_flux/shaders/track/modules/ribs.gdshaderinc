// v38 phase 2: ribbed plate (refs 2, 6). Longitudinal grooves: a filtered
// trapezoid wave across t, so the pattern runs along the track and stays
// stable from the chase camera (detail that varies in t is where density
// belongs).
//
// The normal comes from the box-filtered height: slope = (h(u + fw/2) -
// h(u - fw/2)) / fw, exact up close and flattening by itself once the
// footprint spans grooves. It also fades out explicitly (at twice the
// albedo's pixel threshold), and the slope variance lost goes to roughness.

group_uniforms ribs;
// Groove spacing and the groove's share of it.
uniform float rib_pitch : hint_range(0.02, 1.0) = 0.16;
uniform float rib_groove : hint_range(0.05, 0.95) = 0.4;
uniform float rib_depth : hint_range(0.0, 0.05) = 0.006;
// Width of each groove wall (the slope).
uniform float rib_bevel : hint_range(0.001, 0.05) = 0.012;
// Albedo multiplier in the groove.
uniform float rib_dark : hint_range(0.0, 1.0) = 0.55;
group_uniforms;

// Height at `u` metres across: 0 on the ribs, -rib_depth in the grooves
// (groove centres on multiples of the pitch).
float rib_height(float u) {
	float d = abs(u - rib_pitch * round(u / rib_pitch));
	float hw = rib_groove * rib_pitch * 0.5;
	return -rib_depth * clamp((hw + rib_bevel * 0.5 - d) / rib_bevel, 0.0, 1.0);
}

void ribs(inout TSurf o, float u, float fw_t, bool normals) {
	float f;
	float groove = aa_lines(u, rib_pitch, rib_groove * rib_pitch, fw_t, f);
	ts_filt(o, f);
	o.albedo *= mix(1.0, rib_dark, groove);
	o.recess = max(o.recess, groove * 0.6);
	o.rough = mix(o.rough, min(o.rough + 0.15, 1.0), groove);
	// Unfiltered slope variance: the walls' share of the pitch times slope^2.
	float wall_slope = rib_depth / rib_bevel;
	float var = min(2.0 * rib_bevel / rib_pitch, 1.0) * wall_slope * wall_slope;
	float nfade = normals ? aa_fade(rib_pitch, fw_t * 2.0) : 1.0;
	if (nfade < 1.0) {
		float fw = max(fw_t, 1e-5);
		float slope = (rib_height(u + fw * 0.5) - rib_height(u - fw * 0.5)) / fw;
		o.slope.x += slope * (1.0 - nfade);
	}
	o.normal_var += var * nfade;
	if (normals) {
		ts_filt(o, nfade);
	}
}
