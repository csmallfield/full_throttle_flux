// v35 Phase 3 sparks (FxImpacts spark emitter).
//
// The process material aligns each particle's Y axis to its velocity
// (particle_flag_align_y); this keeps that axis and turns the quad around it
// to face the camera, so every spark is a thin streak along its flight path.
// Additive, unshaded, HDR so the scene glow blooms it. COLOR comes from the
// process material's ramp: white-hot -> orange -> dull red, fading out.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled,
	world_vertex_coords;

uniform float energy = 6.0;
uniform float streak_width = 0.045;    // metres
uniform float streak_length = 0.7;     // metres at birth
uniform float shrink = 0.6;            // the streak shortens this much over its life
uniform float fade_distance = 400.0;

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	vec3 along = normalize(MODEL_MATRIX[1].xyz);
	vec3 to_cam = normalize(INV_VIEW_MATRIX[3].xyz - origin);
	vec3 side = cross(along, to_cam);
	side = length(side) > 1e-4 ? normalize(side) : normalize(cross(along, vec3(0.0, 1.0, 0.0001)));
	float len = streak_length * (1.0 - shrink * INSTANCE_CUSTOM.y);
	// Corners from UV (QuadMesh: UV (0,0) = top-left): x across, head at UV.y = 0.
	float x = UV.x - 0.5;
	float y = 0.5 - UV.y;
	VERTEX = origin + side * x * streak_width + along * (y - 0.5) * len;
}

void fragment() {
	float across = abs(UV.x * 2.0 - 1.0);
	float core = 1.0 - smoothstep(0.2, 1.0, across);
	float dist_fade = 1.0 - smoothstep(fade_distance * 0.6, fade_distance, length(VERTEX));
	ALBEDO = COLOR.rgb * energy;
	ALPHA = clamp(COLOR.a * core * mix(1.0, 0.25, UV.y) * dist_fade, 0.0, 1.0);
}
