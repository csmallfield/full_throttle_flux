// v35 Phase 4: rain / snow / grit draw pass (see precip_process.gdshader).
//
// Each particle is a thin camera-facing quad stretched along its velocity
// relative to the camera (MODEL_MATRIX[1] = that velocity, m/s):
//   length = clamp(|rel v| * shutter, min_length, max_length)
// so parked rain is short streaks, at speed long raking lines. Snow and grit
// use a short shutter and a round, soft profile. Unshaded, tinted by the
// fog / sky colour so it sits in the scene's light; soft against the depth
// buffer; faded right in front of the lens so nothing smears the screen.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, world_vertex_coords;

uniform vec4 tint : source_color = vec4(0.75, 0.78, 0.82, 1.0);
uniform float opacity = 0.35;
uniform float width = 0.012;           // m
uniform float min_length = 0.1;        // m
uniform float max_length = 2.5;        // m
uniform float shutter = 0.02;          // s of motion one streak shows
uniform float roundness = 0.0;         // 0 streak (soft sides) .. 1 soft dot
uniform float near_fade = 0.6;         // m from the camera
uniform float far_fade = 30.0;         // m
uniform float soft_depth = 0.4;        // m
uniform sampler2D depth_tex : hint_depth_texture, filter_linear;

varying float v_alpha;
varying float v_len_ratio;

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	vec3 rv = MODEL_MATRIX[1].xyz;
	float speed = length(rv);
	vec3 along = speed > 1e-4 ? rv / speed : vec3(0.0, 1.0, 0.0);
	vec3 cam = INV_VIEW_MATRIX[3].xyz;
	vec3 to_cam = normalize(cam - origin);
	vec3 side = cross(along, to_cam);
	side = length(side) > 1e-4 ? normalize(side) : normalize(cross(vec3(0.0, 1.0, 0.0001), to_cam));
	float len = clamp(speed * shutter, min_length, max_length);
	float w = width * mix(1.0, 1.8, INSTANCE_CUSTOM.x);
	// The tail trails behind the particle along its relative motion.
	vec2 c = UV - 0.5;
	VERTEX = origin + side * c.x * w - along * (0.5 - UV.y) * max(len, w * roundness);
	float d = distance(origin, cam);
	v_alpha = COLOR.a * smoothstep(near_fade, near_fade * 3.0, d) * (1.0 - smoothstep(far_fade * 0.6, far_fade, d));
	v_len_ratio = len / max(w, 1e-4);
	if (v_alpha <= 0.001) {
		VERTEX = origin;   // degenerate: nothing to rasterise
	}
}

void fragment() {
	vec2 c = UV * 2.0 - 1.0;
	float across = 1.0 - smoothstep(0.0, 1.0, abs(c.x));
	float lengthwise = 1.0 - smoothstep(0.6, 1.0, abs(c.y));
	float dot_mask = 1.0 - smoothstep(0.3, 1.0, length(c));
	float a = mix(across * lengthwise * mix(0.4, 1.0, UV.y), dot_mask, roundness);
	float scene = texture(depth_tex, SCREEN_UV).r;
	vec4 ndc = vec4(SCREEN_UV * 2.0 - 1.0, scene, 1.0);
	vec4 vpos = INV_PROJECTION_MATRIX * ndc;
	float scene_z = -vpos.z / vpos.w;
	float soft = clamp((scene_z - (-VERTEX.z)) / soft_depth, 0.0, 1.0);
	ALBEDO = tint.rgb;
	ALPHA = clamp(a * opacity * v_alpha * soft, 0.0, 1.0);
}
