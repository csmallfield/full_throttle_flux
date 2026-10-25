// v35 thrust trail: additive, unshaded, HDR so the scene glow blooms it.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled,
	world_vertex_coords, fog_disabled;

#include "res://shaders/fx/trail_common.gdshaderinc"

uniform float energy = 1.6;                       // above the glow threshold (1.2 on the city tracks)
uniform float core_width : hint_range(0.0, 1.0) = 0.35;
uniform float core_boost = 1.0;                   // white-hot centre line
uniform float edge_softness : hint_range(0.0, 1.0) = 0.8;
uniform float noise_scale = 0.7;                 // cells per metre along the trail
uniform float noise_amount : hint_range(0.0, 1.0) = 0.8;
uniform float scroll_speed = 6.0;                 // metres per second, head to tail
uniform float fade_distance = 900.0;              // fades out with camera distance (no fog on additive)

void vertex() {
	trail_vertex(VERTEX, NORMAL, UV, UV2, INV_VIEW_MATRIX);
	TRAIL_VARYINGS;
}

void fragment() {
	float edge = trail_edge(edge_softness);
	float n = trail_noise(vec2(v_along * noise_scale - TIME * scroll_speed * noise_scale, v_edge * 1.7 + 3.1));
	n = mix(1.0, 0.35 + 1.3 * n, noise_amount);
	float core = smoothstep(core_width, 0.0, abs(v_edge)) * (1.0 - v_life);
	float dist_fade = 1.0 - smoothstep(fade_distance * 0.6, fade_distance, length(VERTEX));
	ALBEDO = COLOR.rgb * energy * (1.0 + core * core_boost);
	ALPHA = clamp(COLOR.a * edge * n * dist_fade, 0.0, 1.0);
}
