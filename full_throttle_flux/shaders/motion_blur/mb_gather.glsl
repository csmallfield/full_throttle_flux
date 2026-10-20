#[compute]
#version 450
// Motion blur, pass 4: depth-aware reconstruction gather, written back into
// the HDR colour buffer.
// McGuire, Hennessy, Bukowski, Osman, "A Reconstruction Filter for Plausible
// Motion Blur" (I3D 2012) with the tile-jitter and centre-velocity sampling
// from Guertin, McGuire, Nowrouzezahrai, "A Fast and Stable Feature-Aware
// Motion Blur Filter" (HPG 2014).
// Each tap Y along the dominant direction contributes if
//   - Y is in front of X and Y's own blur reaches X        (Y smears over X)
//   - Y is behind X and X's blur reaches Y                 (X smears over Y)
//   - both are blurry and overlap                          (same surface)
// so a sharp foreground (the ship, |v| ~ 0) neither smears nor is smeared.
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(rgba16f, set = 0, binding = 0) uniform restrict image2D color_image;
layout(set = 0, binding = 1) uniform sampler2D scratch_color;   // rgb, a = linear distance
layout(set = 0, binding = 2) uniform sampler2D scratch_vel;     // blur radius px
layout(rg16f, set = 0, binding = 3) uniform restrict readonly image2D neighbor_max;

layout(push_constant, std430) uniform Params {
	vec2 size;
	vec2 tiles;
	float tile;
	float samples;
	float soft_rel;      // depth softness relative to distance
	float debug;         // 0 off, 1 velocity, 2 neighbour max, 3 distance
	float max_radius;
	float noise_offset;  // animates the jitter when non-zero
	vec2 pad;
} p;

float ign(vec2 q) {
	// interleaved gradient noise (Jimenez 2014)
	return fract(52.9829189 * fract(dot(q, vec2(0.06711056, 0.00583715))));
}

float cone(float dist, float r) {
	return clamp(1.0 - dist / r, 0.0, 1.0);
}

float cylinder(float dist, float r) {
	return 1.0 - smoothstep(0.95 * r, 1.05 * r, dist);
}

vec3 debug_color(vec2 r) {
	float l = length(r);
	vec2 w = l > 1e-4 ? r / l : vec2(0.0);
	return vec3(0.5 + 0.5 * w.x, 0.5 + 0.5 * w.y, 0.5 - 0.5 * w.x) * clamp(l / p.max_radius, 0.0, 1.0) * 4.0;
}

void main() {
	ivec2 px = ivec2(gl_GlobalInvocationID.xy);
	ivec2 isize = ivec2(p.size);
	if (px.x >= isize.x || px.y >= isize.y) {
		return;
	}
	float noise = ign(vec2(px) + p.noise_offset);
	// jitter the tile lookup a little so tile borders turn into noise
	vec2 tj = vec2(noise, ign(vec2(px.yx) + 17.0 + p.noise_offset)) - 0.5;
	ivec2 tile = clamp(ivec2((vec2(px) + 0.5 + tj * p.tile * 0.5) / p.tile), ivec2(0), ivec2(p.tiles) - 1);
	vec2 vn = imageLoad(neighbor_max, tile).xy;
	float ln = length(vn);

	int dbg = int(p.debug + 0.5);
	if (dbg > 0) {
		vec4 c0 = imageLoad(color_image, px);
		vec3 o;
		if (dbg == 1) {
			o = debug_color(texelFetch(scratch_vel, px, 0).xy);
		} else if (dbg == 2) {
			o = debug_color(vn);
		} else {
			o = vec3(fract(texelFetch(scratch_color, px, 0).a / 50.0));
		}
		imageStore(color_image, px, vec4(o, c0.a));
		return;
	}
	if (ln < 0.5) {
		return;   // nothing in reach moves by half a pixel: leave colour untouched
	}

	vec4 cx = texelFetch(scratch_color, px, 0);
	float zx = cx.a;
	vec2 vx = texelFetch(scratch_vel, px, 0).xy;
	float lx_raw = length(vx);
	float lx = max(lx_raw, 0.5);

	vec2 wn = vn / ln;
	// second sampling direction: the centre's own motion, or perpendicular to
	// the dominant one when the centre barely moves (2014 paper)
	vec2 wp = vec2(-wn.y, wn.x);
	if (dot(wp, vx) < 0.0) {
		wp = -wp;
	}
	vec2 wx = lx_raw > 1e-3 ? vx / lx_raw : wp;
	wx = normalize(mix(wp, wx, clamp((lx_raw - 0.5) / 1.5, 0.0, 1.0)) + 1e-6);

	float ext_x = max(0.1, p.soft_rel * zx);
	float weight = 1.0 / lx;
	vec3 sum = cx.rgb * weight;

	int n = int(p.samples);
	vec2 xf = vec2(px) + 0.5;
	for (int i = 0; i < 32; i++) {
		if (i >= n) {
			break;
		}
		// taps spread over [-1, 1], jittered as a group
		float t = mix(-1.0, 1.0, (float(i) + noise) / float(n));
		vec2 w = ((i & 1) == 0) ? wn : wx;
		float dist = abs(t) * ln;
		ivec2 y = clamp(ivec2(floor(xf + t * ln * w)), ivec2(0), isize - 1);
		vec4 cy = texelFetch(scratch_color, y, 0);
		vec2 vy = texelFetch(scratch_vel, y, 0).xy;
		float ly_raw = length(vy);
		float ly = max(ly_raw, 0.5);
		float zy = cy.a;
		float front = clamp(1.0 - (zy - zx) / ext_x, 0.0, 1.0);   // Y at or in front of X
		float back = clamp(1.0 - (zx - zy) / ext_x, 0.0, 1.0);    // Y at or behind X
		float wa = abs(dot(wx, w));
		float wb = ly_raw > 1e-3 ? abs(dot(vy / ly_raw, w)) : wa;
		float a = front * cone(dist, ly) * wb
				+ back * cone(dist, lx) * wa
				+ cylinder(dist, ly) * cylinder(dist, lx) * max(wa, wb) * 2.0;
		weight += a;
		sum += cy.rgb * a;
	}
	vec4 c = imageLoad(color_image, px);
	imageStore(color_image, px, vec4(sum / weight, c.a));
}
