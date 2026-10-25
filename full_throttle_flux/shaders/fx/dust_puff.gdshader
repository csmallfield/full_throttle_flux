// v35 dust / spray / snow-powder puffs for FxPools (GPUParticles3D draw pass).
//
// Billboard quad, sun-lit (it is dust, not light), soft where it meets
// geometry, eroded by noise as it ages, and faded out close to the camera so a
// ship's own plume (or the pack ahead's) never paints over the racing line.
//
// Per particle (ParticleProcessMaterial): COLOR.a = opacity over life,
// INSTANCE_CUSTOM.x = rotation, INSTANCE_CUSTOM.y = life fraction 0..1.
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, shadows_disabled, diffuse_lambert_wrap,
	specular_disabled;

uniform vec4 tint : source_color = vec4(0.62, 0.52, 0.38, 1.0);
uniform float opacity : hint_range(0.0, 1.0) = 0.6;
uniform float softness : hint_range(0.05, 1.0) = 0.55;       // radial falloff
uniform float noise_scale = 3.0;
uniform float erosion : hint_range(0.0, 1.0) = 0.6;           // how much noise eats the puff as it ages
uniform float soft_depth = 1.5;                               // metres of blend into geometry
uniform float near_fade_start = 2.0;                          // metres from the camera: fully gone...
uniform float near_fade_end = 9.0;                            // ...to fully visible
uniform float emission_boost = 0.0;                           // >0 lets spray catch a little light
uniform sampler2D depth_tex : hint_depth_texture, filter_linear;

varying float v_life;
varying float v_seed;

void vertex() {
	// Particle billboard (same idea as StandardMaterial3D BILLBOARD_PARTICLES),
	// keeping the particle's scale and spinning by its rotation.
	float sx = length(MODEL_MATRIX[0].xyz);
	float sy = length(MODEL_MATRIX[1].xyz);
	float a = INSTANCE_CUSTOM.x;
	mat2 rot = mat2(vec2(cos(a), -sin(a)), vec2(sin(a), cos(a)));
	vec2 corner = rot * VERTEX.xy;
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * sx, INV_VIEW_MATRIX[1] * sy,
			INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	VERTEX = vec3(corner, 0.0);
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
	v_life = INSTANCE_CUSTOM.y;
	v_seed = fract(MODEL_MATRIX[3].x * 0.137 + MODEL_MATRIX[3].z * 0.311);
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
			mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

void fragment() {
	vec2 c = UV * 2.0 - 1.0;
	float r = length(c);
	float radial = 1.0 - smoothstep(1.0 - softness, 1.0, r);
	vec2 np = UV * noise_scale + vec2(v_seed * 17.0, v_seed * 31.0);
	float n = vnoise(np) * 0.65 + vnoise(np * 2.3) * 0.35;
	float eaten = smoothstep(erosion * v_life, erosion * v_life + 0.35, n);
	float a = radial * mix(1.0, eaten, erosion);

	// Soft particles: fade where the puff meets geometry behind it.
	float depth = texture(depth_tex, SCREEN_UV).r;
	vec4 world = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	float scene_z = -world.z / world.w;
	float soft = clamp((scene_z - (-VERTEX.z)) / max(soft_depth, 0.01), 0.0, 1.0);

	float cam = smoothstep(near_fade_start, near_fade_end, -VERTEX.z);

	// A rounded view-space normal so the sun shades the puff like a volume.
	NORMAL = normalize(mix(vec3(0.0, 0.0, 1.0), vec3(c * 0.8, 1.0), 0.6));
	ALBEDO = tint.rgb;
	EMISSION = tint.rgb * emission_boost;
	ALPHA = clamp(COLOR.a * opacity * a * soft * cam, 0.0, 1.0);
}
