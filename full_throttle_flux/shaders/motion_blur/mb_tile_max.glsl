#[compute]
#version 450
// Motion blur, pass 2: per-tile dominant (largest) blur radius.
// One 8x8 workgroup per tile; threads stride over the tile, then reduce.
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 0, binding = 0) uniform sampler2D vel_tex;
layout(rg16f, set = 0, binding = 1) uniform restrict writeonly image2D tile_max;
layout(set = 0, binding = 2, std430) restrict buffer Stats {
	uint data[];
} stats;

layout(push_constant, std430) uniform Params {
	vec2 size;
	float tile;
	float flags;   // 8 = write stats
} p;

shared vec2 s_v[64];
shared float s_l[64];

void main() {
	ivec2 tile = ivec2(gl_WorkGroupID.xy);
	int k = int(p.tile);
	ivec2 origin = tile * k;
	ivec2 isize = ivec2(p.size);
	uint li = gl_LocalInvocationIndex;
	vec2 best = vec2(0.0);
	float best_l = 0.0;
	for (int y = int(gl_LocalInvocationID.y); y < k; y += 8) {
		for (int x = int(gl_LocalInvocationID.x); x < k; x += 8) {
			ivec2 q = origin + ivec2(x, y);
			if (q.x < isize.x && q.y < isize.y) {
				vec2 v = texelFetch(vel_tex, q, 0).xy;
				float l = dot(v, v);
				if (l > best_l) {
					best_l = l;
					best = v;
				}
			}
		}
	}
	s_v[li] = best;
	s_l[li] = best_l;
	memoryBarrierShared();
	barrier();
	for (uint s = 32u; s > 0u; s >>= 1u) {
		if (li < s && s_l[li + s] > s_l[li]) {
			s_l[li] = s_l[li + s];
			s_v[li] = s_v[li + s];
		}
		memoryBarrierShared();
		barrier();
	}
	if (li == 0u) {
		imageStore(tile_max, tile, vec4(s_v[0], 0.0, 0.0));
		if ((uint(p.flags) & 8u) != 0u) {
			float l = sqrt(s_l[0]);
			atomicMax(stats.data[0], floatBitsToUint(l));   // positive floats order like uints
			if (l >= 0.5) {
				atomicAdd(stats.data[1], 1u);
			}
		}
	}
}
