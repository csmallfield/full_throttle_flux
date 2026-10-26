// v35 dust / spray / snow-powder puffs (FxPools puff emitters).
//
// Each particle draws one of 64 baked puffs from assets/fx/dust_puffs.png
// (tools/env/bake_dust_atlas.py): RG = normal, B = thickness, A = density.
// - Billboard, spun by the particle's own rotation; normals are spun with it
//   and lit by the scene's sun (wrap diffuse + back-light for the bright rim
//   dust gets when looking toward the sun).
// - Thin wisps dissolve first as the puff ages; thick cores read darker.
// - Soft where it meets geometry; faded right in front of the camera so a
//   plume never paints over the racing line.
//
// Per particle (ParticleProcessMaterial): COLOR = brightness variation and
// opacity over life, INSTANCE_CUSTOM.x = rotation (rad), .y = life 0..1,
// .z = a STABLE random 0..1 (anim_offset, anim_speed 0) that picks the puff.
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, shadows_disabled, diffuse_lambert_wrap,
	specular_disabled;

uniform sampler2D puffs : source_color, filter_linear_mipmap, repeat_disable;
uniform int atlas_grid = 8;
uniform vec4 tint : source_color = vec4(0.62, 0.52, 0.38, 1.0);
uniform float opacity : hint_range(0.0, 2.0) = 0.9;
uniform float erosion : hint_range(0.0, 1.0) = 0.6;     // how fast thin wisps dissolve with age
uniform float core_darken : hint_range(0.0, 1.0) = 0.3; // self-shadow in thick cores
uniform float normal_strength : hint_range(0.0, 2.0) = 1.0;
uniform float backlight : hint_range(0.0, 2.0) = 0.5;   // light through thin parts
uniform float soft_depth = 0.35;                        // metres of blend into geometry
uniform float near_fade_start = 1.5;                    // metres from the camera: gone...
uniform float near_fade_end = 6.0;                      // ...to fully visible
uniform float emission_boost = 0.0;                     // spray / powder catch a little light
uniform sampler2D depth_tex : hint_depth_texture, filter_linear;

varying float v_life;
varying vec2 v_atlas;     // top-left of this particle's tile, in UV
varying float v_angle;

void vertex() {
	float sx = length(MODEL_MATRIX[0].xyz);
	float sy = length(MODEL_MATRIX[1].xyz);
	float a = INSTANCE_CUSTOM.x;
	v_angle = a;
	mat2 rot = mat2(vec2(cos(a), sin(a)), vec2(-sin(a), cos(a)));
	vec2 corner = rot * VERTEX.xy;
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * sx, INV_VIEW_MATRIX[1] * sy,
			INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	VERTEX = vec3(corner, 0.0);
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
	v_life = INSTANCE_CUSTOM.y;
	int frames = atlas_grid * atlas_grid;
	int f = clamp(int(INSTANCE_CUSTOM.z * float(frames)), 0, frames - 1);
	v_atlas = vec2(float(f % atlas_grid), float(f / atlas_grid)) / float(atlas_grid);
}

void fragment() {
	vec4 t = texture(puffs, v_atlas + UV / float(atlas_grid));
	float dens = t.a;
	float thick = t.b;

	// Wisps (low thickness) dissolve first as the puff ages.
	float d = v_life * erosion;
	dens *= smoothstep(d - 0.05, d + 0.25, thick + 0.15);

	// Soft particles against the scene behind.
	float depth = texture(depth_tex, SCREEN_UV).r;
	vec4 world = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	float scene_z = -world.z / world.w;
	float soft = clamp((scene_z + VERTEX.z) / max(soft_depth, 0.01), 0.0, 1.0);
	float cam = smoothstep(near_fade_start, near_fade_end, -VERTEX.z);

	// Texture normal (y down in the texture) spun with the billboard.
	vec2 n2 = (t.rg * 2.0 - 1.0) * vec2(1.0, -1.0) * normal_strength;
	n2 = mat2(vec2(cos(v_angle), sin(v_angle)), vec2(-sin(v_angle), cos(v_angle))) * n2;
	NORMAL = normalize(vec3(n2, 1.0));

	vec3 col = tint.rgb * COLOR.rgb * (1.0 - core_darken * thick);
	ALBEDO = col;
	BACKLIGHT = col * backlight * (1.0 - thick);
	EMISSION = col * emission_boost;
	ALPHA = clamp(dens * COLOR.a * opacity * soft * cam, 0.0, 1.0);
}
