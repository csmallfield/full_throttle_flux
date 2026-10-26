// v38 phase 4: wear. Layered last, so it modulates every module above.
// Wear follows use (refs 2, 5, 6, 9):
//   polish   a clean, smoother strip where ships run: along the racing line,
//            as wide as a share of its corridor (both from the trained AI
//            line, baked into the strip when the track loads)
//   grime    in recesses (channels, holes, grooves, seams, slots: TSurf
//            recess) and toward the edges; swept off the polished line
//   panels   per-panel age: some panels more stained, a few replaced (clean)
//   scuffs   longitudinal scratches, brightest on the line (high tier)
//   scorch   a heat tint in braking zones, on the line (blue / violet
//            temper colours: nothing in the boost pads' orange)
// The track's age (wear_age) times the zone's wear multiplier scales it all.
//
// The detail comes from one small tiling texture (wear_detail: R grime
// noise, G scratch streaks along +V, B stains, A speckle), mipmapped and
// anisotropic, so the hardware filters it: no ringing at any distance. It
// is sampled with explicit gradients (taken at the top of fragment()), so
// branching on the zone can't upset its mip selection. The low tier skips
// the texture and the scuffs: polish, grime, panel age and scorch only.

group_uniforms wear;
// How used the track looks: 0 = factory new, 1 = old.
uniform float wear_age : hint_range(0.0, 1.0) = 0.5;
uniform sampler2D wear_detail : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
// Metres per tile of the grime / stain layers, and of the scratches (across,
// along: long streaks run along s).
uniform float wear_grime_scale : hint_range(0.5, 20.0) = 3.0;
uniform vec2 wear_scuff_scale = vec2(1.6, 28.0);
// Polish: the strip is this share of the corridor's half width (at least
// polish_min_width metres), roughness times polish_rough on it.
uniform float polish_width : hint_range(0.05, 1.0) = 0.4;
uniform float polish_min_width : hint_range(0.5, 10.0) = 3.0;
uniform float polish_rough : hint_range(0.1, 1.0) = 0.6;
uniform float polish_bright : hint_range(0.0, 0.5) = 0.08;
uniform vec3 grime_color : source_color = vec3(0.045, 0.042, 0.04);
uniform float grime_amount : hint_range(0.0, 1.0) = 0.65;
// Extra grime toward the road edges.
uniform float grime_edge : hint_range(0.0, 1.0) = 0.35;
uniform float panel_age_var : hint_range(0.0, 1.0) = 0.6;
// Share of panels that are newer replacements.
uniform float panel_replaced : hint_range(0.0, 0.5) = 0.05;
uniform float scuff_amount : hint_range(0.0, 1.0) = 0.45;
uniform vec3 scorch_color : source_color = vec3(0.16, 0.15, 0.3);
uniform float scorch_amount : hint_range(0.0, 1.0) = 0.6;
group_uniforms;

// The wear inputs at a pixel, unpacked from the strip.
struct WearIn {
	float zone;    // zone wear multiplier (0..2)
	float brake;   // 0..1
	bool line;     // a racing line is known here
	float line_t;  // its lateral position, m
	float half;    // corridor half width, m
};

struct WearOut {
	float polish;
	float grime;
	float scorch;
};

// `lat01`: 0 at the centre line .. 1 at the surface edge; `panel`, `pbf`,
// `var_fade` from the panel lookup; `dx`, `dy` the screen gradients of (t, s).
WearOut wear(inout TSurf o, WearIn wi, float s, float t, int cls, float lat01, float panel,
		float pbf, float var_fade, vec2 dx, vec2 dy, bool high) {
	WearOut w;
	w.polish = 0.0;
	w.grime = 0.0;
	w.scorch = 0.0;
	float age = wear_age * wi.zone;
	if (age <= 0.001 || cls > 1) {
		return w;
	}
	vec4 tex = vec4(0.5);
	if (high) {
		vec2 uv = vec2(t, s) / wear_grime_scale;
		tex = textureGrad(wear_detail, uv, dx / wear_grime_scale, dy / wear_grime_scale);
	}
	// Polish along the racing line (none on the lips).
	if (wi.line && cls == 0) {
		float pw = max(wi.half * polish_width, polish_min_width);
		w.polish = (1.0 - smoothstep(pw * 0.45, pw, abs(t - wi.line_t))) * clamp(age * 1.6, 0.0, 1.0);
	}
	// Per-panel age; a few panels are replacements. Faded with the panel
	// variation, so tiny panels average out.
	float ph = mix(env_hash(vec2(panel * 3.17, pbf * 7.7 + 3.1)), 0.5, var_fade);
	float replaced = step(1.0 - panel_replaced, ph) * (1.0 - var_fade);
	float page = clamp(age * (1.0 + (ph - 0.5) * 2.0 * panel_age_var), 0.0, 1.0) * (1.0 - replaced * 0.85);
	// Grime: recesses and edges, swept off the line.
	float edge = smoothstep(0.55, 1.0, lat01);
	w.grime = clamp(page * grime_amount * (o.recess * 0.9 + edge * grime_edge + 0.08)
			* (0.45 + tex.r * 1.1) * (1.0 - w.polish * 0.8), 0.0, 0.9);
	float stain = high ? tex.b * page * 0.35 : page * 0.12;
	o.albedo = mix(o.albedo, grime_color, clamp(w.grime + stain * (1.0 - w.polish), 0.0, 0.9));
	o.rough = clamp(o.rough + w.grime * 0.3 + stain * 0.1, 0.0, 1.0);
	// A replaced panel: a touch cleaner and smoother.
	o.albedo *= 1.0 + replaced * 0.06;
	o.rough = max(o.rough - replaced * 0.05, 0.0);
	// The polished line.
	o.rough *= mix(1.0, polish_rough, w.polish);
	o.albedo *= 1.0 + w.polish * polish_bright;
	// Scuffs: long scratches along s, brightest on the line (high tier).
	if (high) {
		vec2 suv = vec2(t / wear_scuff_scale.x, s / wear_scuff_scale.y);
		vec2 sdx = vec2(dx.x / wear_scuff_scale.x, dx.y / wear_scuff_scale.y);
		vec2 sdy = vec2(dy.x / wear_scuff_scale.x, dy.y / wear_scuff_scale.y);
		float sc = textureGrad(wear_detail, suv, sdx, sdy).g;
		float scuff = sc * scuff_amount * age * (0.35 + 0.65 * w.polish);
		o.albedo = mix(o.albedo, o.albedo * 1.6 + 0.02, scuff * 0.5);
		o.rough = mix(o.rough, 0.3, scuff * 0.5);
	}
	// Brake scorch: a temper tint where ships brake, on the line.
	w.scorch = wi.brake * clamp(age * 1.4, 0.0, 1.0) * scorch_amount * (0.1 + 0.9 * w.polish)
			* (0.75 + 0.5 * tex.r);
	o.albedo = mix(o.albedo, scorch_color, clamp(w.scorch, 0.0, 0.8) * 0.6);
	o.rough = clamp(o.rough + w.scorch * 0.1, 0.0, 1.0);
	return w;
}
