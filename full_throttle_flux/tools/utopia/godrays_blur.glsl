#[compute]
#version 450
// Utopia god rays, pass 2: radial blur of the mask toward the sun, added to
// the HDR colour buffer (before tonemapping).
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;
layout(rgba16f, set = 0, binding = 0) uniform restrict image2D color_image;
layout(set = 0, binding = 1) uniform sampler2D mask_tex;
layout(push_constant, std430) uniform Params {
	vec2 sun_uv;
	vec2 full_size;
	vec4 tint;        // rgb tint, a = intensity
	float decay;
	float length_frac;
	float samples;
	float weight;
} p;

void main() {
	ivec2 px = ivec2(gl_GlobalInvocationID.xy);
	if (px.x >= int(p.full_size.x) || px.y >= int(p.full_size.y)) {
		return;
	}
	vec2 uv = (vec2(px) + 0.5) / p.full_size;
	if (p.weight < 0.0) {   // debug: show the emission mask
		imageStore(color_image, px, vec4(vec3(texture(mask_tex, uv).r), 1.0));
		return;
	}
	int n = int(p.samples);
	vec2 delta = (uv - p.sun_uv) * p.length_frac / float(n);
	// per-pixel jitter hides banding
	float j = fract(sin(dot(vec2(px), vec2(12.9898, 78.233))) * 43758.5453);
	vec2 suv = uv - delta * j * 0.5;
	float illum = 1.0;
	float acc = 0.0;
	for (int i = 0; i < 128; i++) {
		if (i >= n) {
			break;
		}
		acc += texture(mask_tex, suv).r * illum;
		illum *= p.decay;
		suv -= delta;
	}
	acc *= p.weight / float(n);
	vec4 c = imageLoad(color_image, px);
	c.rgb += acc * p.tint.rgb * p.tint.a;
	imageStore(color_image, px, c);
}
