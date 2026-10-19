// Swoopy cloud sea: a patchy cloud deck far below the raceway, between the
// track and the city. A flat plane, so it is cheap: two scrolling noise
// layers -> coverage mask, a fake "thickness" shade, and soft fades where
// piers punch through it (scene depth) and at the edge of the plane.
// Unshaded but still fogged, so it recedes into the haze with the city.
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded;

uniform sampler2D noise_large : repeat_enable, filter_linear_mipmap;
uniform sampler2D noise_small : repeat_enable, filter_linear_mipmap;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;

group_uniforms Shape;
uniform float coverage : hint_range(0.0, 1.0) = 0.45;
uniform float softness : hint_range(0.01, 0.5) = 0.16;
uniform float opacity : hint_range(0.0, 1.0) = 0.92;
uniform float large_tile = 3200.0;   // metres per repeat
uniform float small_tile = 900.0;
uniform vec2 wind = vec2(4.0, 1.5); // m/s
uniform float seed_offset = 0.0;
group_uniforms Look;
uniform vec3 lit_color : source_color = vec3(1.0, 0.98, 0.95);
uniform vec3 shade_color : source_color = vec3(0.58, 0.65, 0.78);
uniform float brightness : hint_range(0.0, 4.0) = 1.25;
group_uniforms Fades;
uniform float proximity_fade = 45.0; // soft contact with piers/towers
uniform vec2 plane_center = vec2(-240.0, 0.0);
uniform float fade_radius = 6200.0;
uniform float camera_fade_start = 2300.0;  // dissolve before the 4 km far plane
uniform float camera_fade_end = 3700.0;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = wpos.xz + vec2(seed_offset * 731.0, seed_offset * 397.0);
	float n1 = texture(noise_large, (p + wind * TIME) / large_tile).r;
	float n2 = texture(noise_small, (p - wind * TIME * 0.6) / small_tile).r;
	float n = n1 * 0.68 + n2 * 0.32;
	float edge = 1.0 - coverage;
	float a = smoothstep(edge - softness, edge + softness, n);
	float thick = clamp((n - edge) * 3.5, 0.0, 1.0);
	vec3 col = mix(shade_color, lit_color, 0.3 + 0.7 * thick) * brightness;

	float depth = texture(depth_tex, SCREEN_UV).r;
	vec4 v = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	v.xyz /= v.w;
	a *= clamp((VERTEX.z - v.z) / proximity_fade, 0.0, 1.0);
	a *= 1.0 - smoothstep(fade_radius * 0.7, fade_radius, length(wpos.xz - plane_center));

	a *= 1.0 - smoothstep(camera_fade_start, camera_fade_end, length(VERTEX));
	ALBEDO = col;
	ALPHA = a * opacity;
}
