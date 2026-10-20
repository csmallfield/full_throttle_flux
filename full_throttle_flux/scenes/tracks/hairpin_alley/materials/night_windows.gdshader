// Night facade: procedural lit windows on any box/greybox building.
// World-space, so it works on scaled unit cubes and survives rotation: every
// vertical face gets a floor/bay grid, each window randomly lit, with a few
// palettes chosen per building (hashed from the object's position).
// Roofs get no windows. Distant grids fade to their average glow (no moire).
// Swap for real facade materials later -- nothing depends on this shader.
shader_type spatial;
render_mode cull_disabled;

uniform vec3 wall_color : source_color = vec3(0.09, 0.095, 0.11);
uniform vec3 roof_color : source_color = vec3(0.06, 0.06, 0.07);
uniform float floor_height = 4.2;
uniform float bay_width = 3.4;
uniform vec2 window_fill = vec2(0.72, 0.55);    // fraction of bay / floor that is glass
uniform float lit_ratio : hint_range(0.0, 1.0) = 0.3;
uniform float energy : hint_range(0.0, 16.0) = 1.5;
uniform vec3 warm : source_color = vec3(1.0, 0.72, 0.42);
uniform vec3 cool : source_color = vec3(0.62, 0.78, 1.0);
uniform vec3 neon_a : source_color = vec3(0.2, 0.9, 1.0);
uniform vec3 neon_b : source_color = vec3(1.0, 0.25, 0.75);
uniform float ground_y = -16.0;                 // no windows below street level

varying vec3 wpos;
varying vec3 wnrm;
// flat: a per-building constant. Interpolated, it arrives with ulp-level
// per-pixel differences that h21() amplifies into per-pixel lit/unlit noise.
varying flat float bseed;

float h21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 o = MODEL_MATRIX[3].xyz;
	bseed = h21(o.xz * 0.013 + o.y * 0.07);
}

void fragment() {
	vec3 n = normalize(wnrm);
	if (abs(n.y) > 0.6) {
		ALBEDO = roof_color;
		ROUGHNESS = 0.9;
	} else {
		vec2 t = normalize(vec2(-n.z, n.x));
		float u = dot(wpos.xz, t);
		vec2 g = vec2(u / bay_width, (wpos.y - ground_y) / floor_height);
		vec2 cell = floor(g);
		vec2 f = fract(g);
		// building "type" from its seed: office (cool, dense) / residential (warm, sparse)
		float office = step(0.62, bseed);
		float ratio = lit_ratio * mix(0.8, 1.35, office);
		// per-face seed. floor(x + 0.5), not floor(x): on axis-aligned faces
		// x is exactly an integer (+-3, +-7), and the interpolated normal's
		// ~1e-7 wobble made floor() flip per pixel -> speckled windows that
		// shimmered in motion and streaked under motion blur
		float face = floor(dot(n.xz, vec2(3.0, 7.0)) + 0.5);
		float r = h21(cell + vec2(bseed * 91.0, face));
		float lit = step(1.0 - ratio, r);
		// whole lit floors in some offices, dark ground floor shop band handled below
		lit = max(lit, office * step(0.93, h21(vec2(cell.y, bseed * 17.0))));
		vec2 w = step(abs(f - 0.5) * 2.0, window_fill);
		float glass = w.x * w.y;
		float tint_pick = h21(cell * 1.7 + bseed);
		vec3 col = mix(warm, cool, office);
		col = mix(col, mix(warm, cool, 1.0 - office), step(0.8, tint_pick));
		float inten = mix(0.45, 1.0, h21(cell + 3.1));
		// street-level shop band: bright, coloured, continuous
		float shop = step(cell.y, 0.5) * step(-0.5, cell.y);
		vec3 shop_col = mix(neon_a, neon_b, step(0.5, h21(vec2(floor(u / 14.0), bseed))));
		// anti-alias: far away the grid becomes its average
		// fade by distance (not by grazing angle, which flattened close facades)
		float dist = length(wpos - CAMERA_POSITION_WORLD);
		float far = smoothstep(500.0, 1600.0, dist);
		vec3 e_near = col * lit * glass * inten;
		vec3 e_avg = col * ratio * window_fill.x * window_fill.y * 0.45;
		vec3 e = mix(e_near, e_avg, far);
		e = mix(e, shop_col * 0.8 * step(0.35, f.y), shop * (1.0 - far));
		if (wpos.y < ground_y + 0.2) e = vec3(0.0);
		ALBEDO = mix(wall_color, wall_color * 0.4, glass * (1.0 - far));
		ROUGHNESS = mix(0.85, 0.2, glass * (1.0 - far));
		METALLIC = 0.0;
		EMISSION = e * energy;
	}
}
