// Animated billboard screen for turn signs and ads (unshaded emissive).
// Per-instance parameters (GeometryInstance3D > Instance Shader Parameters):
//   screen_color  neon colour
//   arrow_dir     -1 = turn left, +1 = turn right, 0 = ad pattern
//   pattern_seed  varies the ad pattern
// The arrow mode scrolls chevrons in the turn direction so the sign reads at
// speed from far away. Mesh: QuadMesh (UV 0..1), facing the approaching cam.
shader_type spatial;
render_mode unshaded, cull_disabled;

instance uniform vec3 screen_color : source_color = vec3(1.0, 0.2, 0.7);
instance uniform float arrow_dir = 1.0;
instance uniform float pattern_seed = 0.0;
uniform float brightness = 3.0;
uniform float scroll_speed = 1.4;
uniform float chevron_count = 3.0;

float h11(float x) { return fract(sin(x * 91.7) * 43758.5); }

void fragment() {
	vec2 uv = UV;
	vec3 c;
	if (abs(arrow_dir) > 0.5) {
		// chevrons pointing in arrow_dir, scrolling that way
		float x = uv.x * chevron_count * arrow_dir - TIME * scroll_speed;
		float v = abs(uv.y - 0.5) * 1.2;
		float s = fract(x + v);
		float chev = smoothstep(0.0, 0.04, s) * (1.0 - smoothstep(0.42, 0.47, s));
		float frame = step(0.035, uv.x) * step(uv.x, 0.965) * step(0.06, uv.y) * step(uv.y, 0.94);
		float border = 1.0 - frame;
		c = screen_color * (chev * frame * 1.0 + border * 0.6 + frame * 0.06);
	} else {
		// ad: slow gradient bands + blocky "text" lines
		float band = 0.5 + 0.5 * sin(uv.y * 6.0 + TIME * 0.6 + pattern_seed * 6.0);
		float rows = step(0.55, h11(floor(uv.y * 9.0) + pattern_seed * 13.0));
		float txt = rows * step(0.3, fract(uv.x * 7.0 + h11(floor(uv.y * 9.0)))) * step(uv.y, 0.55);
		vec3 alt = vec3(screen_color.b, screen_color.r, screen_color.g);
		c = mix(screen_color, alt, band * 0.5) * (0.15 + 0.35 * txt);
	}
	// unshaded ignores EMISSION: write the (HDR) colour to ALBEDO, glow still picks it up
	ALBEDO = c * brightness;
}
