// v35 Phase 4: the far precipitation layer. A cylinder around the camera
// (drawn from inside) with procedural streaks (rain), flecks (snow) or wind
// sheets (dust storm) scrolling over it: depth for heavy weather at almost
// no cost. Soft against the depth buffer so buildings in front cut it.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_front, shadows_disabled, fog_disabled;

uniform vec4 tint : source_color = vec4(0.75, 0.78, 0.82, 1.0);
uniform float opacity = 0.15;
uniform vec2 cells = vec2(1.4, 0.06);  // pattern cells per metre (around, up)
uniform vec2 scroll = vec2(0.0, 11.0); // m/s (around, down)
uniform float threshold = 0.62;        // higher = sparser
uniform float sharpness = 0.08;
uniform float soft_depth = 6.0;
uniform sampler2D depth_tex : hint_depth_texture, filter_linear;

varying vec3 v_local;

float h21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

// Value noise that tiles every `period` cells along x, so the pattern wraps
// around the cylinder without a seam.
float vnoise(vec2 p, float period) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float x0 = mod(i.x, period);
	float x1 = mod(i.x + 1.0, period);
	return mix(mix(h21(vec2(x0, i.y)), h21(vec2(x1, i.y)), u.x),
		mix(h21(vec2(x0, i.y + 1.0)), h21(vec2(x1, i.y + 1.0)), u.x), u.y);
}

void vertex() {
	v_local = VERTEX;
}

void fragment() {
	float radius = length(v_local.xz);
	float circ = 6.2831853 * radius;
	float period = max(1.0, round(cells.x * circ));       // whole cells around
	float around = (atan(v_local.z, v_local.x) / 6.2831853 + 0.5) * period;
	vec2 p = vec2(around + scroll.x * TIME * period / circ, (v_local.y + scroll.y * TIME) * cells.y);
	float n = vnoise(p, period) * 0.65 + vnoise(p * 3.0 + vec2(0.0, 13.1), period * 3.0) * 0.35;
	float a = smoothstep(threshold, threshold + sharpness, n);
	// Fade toward the cylinder's top and bottom.
	float hy = abs(v_local.y) / 25.0;
	a *= 1.0 - smoothstep(0.25, 0.9, hy);
	float scene = texture(depth_tex, SCREEN_UV).r;
	vec4 vpos = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, scene, 1.0);
	float scene_z = -vpos.z / vpos.w;
	a *= clamp((scene_z - (-VERTEX.z)) / soft_depth, 0.0, 1.0);
	ALBEDO = tint.rgb;
	ALPHA = clamp(a * opacity, 0.0, 1.0);
}
