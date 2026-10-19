#[compute]
#version 450
// Motion blur, pass 3: largest tile radius in the 3x3 tile neighbourhood.
// A pixel can be reached by blur from at most one tile away (radius <= tile).
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(rg16f, set = 0, binding = 0) uniform restrict readonly image2D tile_max;
layout(rg16f, set = 0, binding = 1) uniform restrict writeonly image2D neighbor_max;

layout(push_constant, std430) uniform Params {
	vec2 tiles;
	vec2 pad;
} p;

void main() {
	ivec2 t = ivec2(gl_GlobalInvocationID.xy);
	ivec2 n = ivec2(p.tiles);
	if (t.x >= n.x || t.y >= n.y) {
		return;
	}
	vec2 best = vec2(0.0);
	float best_l = -1.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			ivec2 q = t + ivec2(x, y);
			if (q.x < 0 || q.y < 0 || q.x >= n.x || q.y >= n.y) {
				continue;
			}
			vec2 v = imageLoad(tile_max, q).xy;
			float l = dot(v, v);
			if (l > best_l) {
				best_l = l;
				best = v;
			}
		}
	}
	imageStore(neighbor_max, t, vec4(best, 0.0, 0.0));
}
