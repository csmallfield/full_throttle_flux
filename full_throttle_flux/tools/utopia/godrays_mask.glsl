#[compute]
#version 450
// Utopia god rays, pass 1: half-res emission mask = bright SKY pixels near the
// sun (clouds and buildings occlude by being dark / not sky).
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;
layout(rgba16f, set = 0, binding = 0) uniform restrict readonly image2D color_image;
layout(set = 0, binding = 1) uniform sampler2D depth_tex;
layout(r16f, set = 0, binding = 2) uniform restrict writeonly image2D mask_image;
layout(push_constant, std430) uniform Params {
	vec2 sun_uv;
	vec2 full_size;
	vec2 mask_size;
	float threshold;
	float sun_radius;
	float aspect;
	float facing;
	float pad0;          // debug: 1 = show depth
	float horizon;       // min world-space elevation (sin) a pixel's ray needs
	vec4 up_view;        // world up in view space (xyz)
	vec4 proj;           // x = P[0][0], y = P[1][1]
} p;

void main() {
	ivec2 mp = ivec2(gl_GlobalInvocationID.xy);
	if (mp.x >= int(p.mask_size.x) || mp.y >= int(p.mask_size.y)) {
		return;
	}
	vec2 uv = (vec2(mp) + 0.5) / p.mask_size;
	ivec2 fp = clamp(ivec2(uv * p.full_size), ivec2(0), ivec2(p.full_size) - 1);
	// texelFetch, not texture(): with MSAA the resolved depth is R32F, and linear
	// filtering of R32F is optional in Vulkan (unsupported -> reads 0 -> every
	// bright pixel counted as sky).
	float depth = texelFetch(depth_tex, fp, 0).r;
	float sky = depth <= 1e-6 ? 1.0 : 0.0;   // reverse-Z: the far plane is 0
	// Depth-independent gate: only rays aimed above the real horizon can be sky.
	// Keeps lane lights, wall strips and panels out of the mask even if the
	// depth buffer is unavailable (e.g. MSAA without a resolve on some drivers).
	vec2 ndc = uv * 2.0 - 1.0;
	vec3 ray = normalize(vec3(ndc.x / p.proj.x, ndc.y / p.proj.y, -1.0));
	float elev = dot(ray, p.up_view.xyz);
	sky *= smoothstep(p.horizon, p.horizon + 0.03, elev);
	vec3 c = imageLoad(color_image, fp).rgb;
	float lum = dot(c, vec3(0.2126, 0.7152, 0.0722));
	vec2 d = (uv - p.sun_uv) * vec2(p.aspect, 1.0);
	float fall = 1.0 - smoothstep(0.0, p.sun_radius, length(d));
	float m = sky * max(lum - p.threshold, 0.0) * fall * p.facing;
	if (p.pad0 > 0.5) {   // debug: visualise depth
		m = depth * 200.0;
	}
	imageStore(mask_image, mp, vec4(min(m, 16.0)));
}
