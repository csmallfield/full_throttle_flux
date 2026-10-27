// v35 wingtip air streams: thin, pale, alpha-blended (not additive), and lit by
// fog like the rest of the scene so they sit in the air rather than glow.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled,
	world_vertex_coords;

#include "res://shaders/fx/trail_common.gdshaderinc"

uniform float edge_softness : hint_range(0.0, 1.0) = 1.0;
uniform float noise_scale = 0.12;
uniform float noise_amount : hint_range(0.0, 1.0) = 0.5;
uniform float twist_speed = 1.5;   // slow drift of the noise, reads as swirl

void vertex() {
	TRAIL_BUILD;
	trail_vertex(VERTEX, NORMAL, UV, UV2, INV_VIEW_MATRIX);
	TRAIL_VARYINGS;
}

void fragment() {
	float edge = trail_edge(edge_softness);
	float n = trail_noise(vec2(v_along * noise_scale, v_edge * 2.0 + TIME * twist_speed));
	n = mix(1.0, 0.4 + 1.2 * n, noise_amount);
	ALBEDO = COLOR.rgb;
	ALPHA = clamp(COLOR.a * edge * n, 0.0, 1.0);
}
