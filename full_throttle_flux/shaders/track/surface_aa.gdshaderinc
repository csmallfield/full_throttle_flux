// v38: anti-aliasing helpers for the track surface. EVERY pattern in the
// surface shader (and every module added later) goes through these, the v37
// discipline: analytic coverage up close, the pattern's AVERAGE once a
// feature gets smaller than a couple of pixels. Nothing is ever drawn at a
// fixed pixel width, so nothing crowds into a pixel far away, and since the
// far value is the true average the road can't brighten toward the horizon.
//
// All functions take `fw`, the pixel footprint of the coordinate they filter
// (aa_fw()). They are box filters, exact for the shapes they draw.
//
// Anisotropy: from the chase camera s (metres along) compresses hard on
// screen while t (metres across) stays wide. Detail that REPEATS along s
// (seams, dot rows, cells) aliases first: give it aa_fw_s(), which widens
// the footprint by aa_s_bias so it fades earlier than detail in t.

// Footprint widening for detail repeating along s (1 = plain box filter).
uniform float aa_s_bias : hint_range(1.0, 3.0) = 1.5;
// A pattern is fully faded to its average at this many pixels per period,
// and starts fading at twice that.
uniform float aa_fade_px : hint_range(1.0, 4.0) = 2.0;

// Pixel footprint of `x`: the length of its screen-space gradient (more
// accurate on anisotropic footprints than fwidth's |dx| + |dy|).
float aa_fw(float x) {
	return max(length(vec2(dFdx(x), dFdy(x))), 1e-6);
}

float aa_fw_s(float s) {
	return aa_fw(s) * aa_s_bias;
}

// 0 while a feature of size `period` spans more than 2 * aa_fade_px pixels,
// 1 (use the average) once it spans aa_fade_px or fewer.
float aa_fade(float period, float fw) {
	float px = period / fw;
	return 1.0 - smoothstep(aa_fade_px, aa_fade_px * 2.0, px);
}

// Box-filtered step: 0 below `edge`, 1 above.
float aa_step(float edge, float x, float fw) {
	return clamp((x - edge) / fw + 0.5, 0.0, 1.0);
}

// Box-filtered coverage of the interval [a, b] (one band, one stripe).
float aa_pulse(float a, float b, float x, float fw) {
	float lo = max(a, x - fw * 0.5);
	float hi = min(b, x + fw * 0.5);
	return clamp((hi - lo) / fw, 0.0, 1.0);
}

// Integral over [0, x] of a line `w` wide repeating every `period`, the line
// centred on multiples of the period.
float _aa_line_integral(float x, float period, float w) {
	float y = x + w * 0.5;
	float k = floor(y / period);
	return k * w + min(y - k * period, w);
}

// Box-filtered coverage of lines `w` wide every `period` (centred on
// multiples of the period), faded to the exact average w / period once the
// period drops below aa_fade_px pixels (the box filter alone still rings
// there). `fade` returns how far it has faded, for the filter-level view.
float aa_lines(float x, float period, float w, float fw, out float fade) {
	w = clamp(w, 0.0, period);
	float avg = w / period;
	float cov = (_aa_line_integral(x + fw * 0.5, period, w)
			- _aa_line_integral(x - fw * 0.5, period, w)) / fw;
	fade = aa_fade(period, fw);
	return mix(clamp(cov, 0.0, 1.0), avg, fade);
}

// A per-cell value (hash, tint) that should vanish into its mean once cells
// of size `period` get too small: lerps `v` toward `mean`.
float aa_cell_value(float v, float mean, float period, float fw) {
	return mix(v, mean, aa_fade(period, fw));
}
