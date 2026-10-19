#[compute]
#version 450
// Motion blur, pass 1 (full res): prepare inputs for the reconstruction filter.
//   scratch_color.rgb = HDR colour, .a = linear view distance
//   scratch_vel.xy    = blur RADIUS in pixels (half the streak), clamped
// Velocity convention (Forward+ scene shader): v = prev_uv - cur_uv with
// uv = clip.xy * 0.5, i.e. full-screen = 1.0 per axis, texture space (y down).
// Fixes up three cases the raw buffer gets wrong for us:
//   * (-1,-1) sentinel: Forward+ with a temporal upscaler (FSR2) only draws
//     moving objects in a motion pass and clears the rest to (-1,-1). Those
//     pixels get camera-only motion reprojected from depth.
//   * sky: never written (0,0). Reprojected at the far plane, so it streaks
//     with camera rotation but not translation, like something infinitely far.
//   * MSAA: the resolved velocity and depth are AVERAGES of the samples, so a
//     silhouette pixel gets half the background's velocity at an in-between
//     depth and would smear the ship's edge colour into the streaks. Edge
//     pixels adopt the velocity/depth of their closest 3x3 neighbour instead.
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(rgba16f, set = 0, binding = 0) uniform restrict readonly image2D color_image;
layout(set = 0, binding = 1) uniform sampler2D depth_tex;
layout(set = 0, binding = 2) uniform sampler2D velocity_tex;
layout(rgba16f, set = 0, binding = 3) uniform restrict writeonly image2D scratch_color;
layout(rg16f, set = 0, binding = 4) uniform restrict writeonly image2D scratch_vel;
layout(set = 0, binding = 5, std430) restrict buffer Stats {
	uint data[];
} stats;

layout(push_constant, std430) uniform Params {
	mat4 reproj;        // prev_view_proj * inverse(cur_view_proj)
	vec2 size;
	float scale;        // uv velocity * size * scale = radius in px
	float max_radius;   // px
	float p22;          // projection[2][2]
	float p32;          // projection[3][2]
	float flags;        // bit flags, see F_*
	float soft_rel;     // depth softness relative to distance
	vec2 probe;         // pixel written to the stats buffer
	vec2 pad;
} p;

const uint F_REPROJ = 1u;    // reproj matrix is valid
const uint F_SKY = 2u;       // reproject sky pixels
const uint F_MSAA_FIX = 4u;  // closest-neighbour fix for MSAA silhouettes
const uint F_STATS = 8u;     // write debug stats
const uint F_ORTHO = 16u;

float linear_dist(float d) {
	if ((uint(p.flags) & F_ORTHO) != 0u) {
		return -(d - p.p32) / p.p22;
	}
	// reverse-Z perspective: view z = -p32 / (d + p22)
	return p.p32 / max(d + p.p22, 1e-7);
}

vec2 reproject(vec2 uv, float d) {
	vec4 ndc = vec4(uv * 2.0 - 1.0, d, 1.0);
	vec4 prev = p.reproj * ndc;
	vec2 prev_ndc = prev.xy / max(abs(prev.w), 1e-6) * sign(prev.w);
	return (prev_ndc - ndc.xy) * 0.5;
}

vec2 raw_velocity(ivec2 q, float d) {
	uint f = uint(p.flags);
	vec2 v = texelFetch(velocity_tex, q, 0).xy;
	bool sentinel = v.x <= -0.999 && v.y <= -0.999;
	bool sky = d <= 0.0;
	if ((f & F_REPROJ) != 0u && (sentinel || (sky && (f & F_SKY) != 0u))) {
		vec2 uv = (vec2(q) + 0.5) / p.size;
		return reproject(uv, max(d, 0.0));
	}
	return sentinel ? vec2(0.0) : v;
}

void main() {
	ivec2 px = ivec2(gl_GlobalInvocationID.xy);
	ivec2 isize = ivec2(p.size);
	if (px.x >= isize.x || px.y >= isize.y) {
		return;
	}
	uint f = uint(p.flags);
	float d = texelFetch(depth_tex, px, 0).r;
	float z = linear_dist(d);
	vec2 v = raw_velocity(px, d);

	if ((f & F_MSAA_FIX) != 0u) {
		// closest neighbour; adopt it only if this pixel sits on a depth edge
		float best_z = z;
		ivec2 best_q = px;
		for (int y = -1; y <= 1; y++) {
			for (int x = -1; x <= 1; x++) {
				ivec2 q = clamp(px + ivec2(x, y), ivec2(0), isize - 1);
				float zq = linear_dist(texelFetch(depth_tex, q, 0).r);
				if (zq < best_z) {
					best_z = zq;
					best_q = q;
				}
			}
		}
		if (z - best_z > max(0.05, p.soft_rel * best_z) * 2.0) {
			float dq = texelFetch(depth_tex, best_q, 0).r;
			v = raw_velocity(best_q, dq);
			z = best_z;
		}
	}

	vec2 r = v * p.size * p.scale;
	float l = length(r);
	if (l > p.max_radius) {
		r *= p.max_radius / l;
	}
	vec4 c = imageLoad(color_image, px);
	imageStore(scratch_color, px, vec4(c.rgb, z));
	imageStore(scratch_vel, px, vec4(r, 0.0, 0.0));

	if ((f & F_STATS) != 0u && px == ivec2(p.probe)) {
		stats.data[2] = floatBitsToUint(v.x);
		stats.data[3] = floatBitsToUint(v.y);
		stats.data[4] = floatBitsToUint(z);
		stats.data[5] = floatBitsToUint(l);
		stats.data[6] = floatBitsToUint(d);
	}
}
