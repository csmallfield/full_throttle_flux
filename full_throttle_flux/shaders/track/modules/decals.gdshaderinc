// v38 phase 5: road decals. Text in the four decal fonts from one MSDF atlas
// (TrackSurfaceGlyphs), and analytic chevrons and arrows, painted flat on
// the road before wear, so grime and scuffs go over the paint.
//
// TrackSurface lays each SurfaceDecalKey out into records (one per glyph or
// shape, sorted along s): DECAL_TEXELS RGBAF texels each, in surf_decals:
//   0  s0, t0, height along s, width across t (the record's rect)
//   1  atlas uv rect (u0, v0, u1, v1), glyphs only
//   2  kind (0 glyph, 1 chevron, 2 arrow), paint, glow, opacity
//   3  ink (the glyph's average coverage), stroke width (m), flipped
// and a per-metre strip, surf_decal_strip: (first record, count) reaching
// that metre. Paths without decals have surf_decal_info.x = 0 and skip it
// all (a uniform branch).
//
// Anti-aliasing as every module: glyph edges from the MSDF distance in
// screen pixels (explicit gradients, so zone branching can't upset the mips),
// fading to the record's ink average once its strokes are under ~2 pixels
// (later than other patterns: the distance field keeps an edge exact down
// to about there); barcode serials have the thinnest strokes and go first. Shapes are
// box-filtered distances, fading the same way.

group_uniforms decals;
uniform sampler2D surf_decal_atlas : hint_default_black, filter_linear_mipmap, repeat_disable;
uniform sampler2D surf_decals : filter_nearest, repeat_disable;
uniform sampler2D surf_decal_strip : filter_nearest, repeat_disable;
// (strip texels, strip width, records per row, MSDF pixel range)
uniform vec4 surf_decal_info = vec4(0.0);
uniform vec3 decal_white : source_color = vec3(0.82, 0.82, 0.8);
uniform vec3 decal_yellow : source_color = vec3(0.92, 0.74, 0.06);
uniform vec3 decal_red : source_color = vec3(0.8, 0.07, 0.05);
uniform vec3 decal_blue : source_color = vec3(0.12, 0.42, 0.95);
uniform float decal_roughness : hint_range(0.0, 1.0) = 0.6;
uniform float decal_glow_energy : hint_range(0.0, 8.0) = 2.0;
group_uniforms;

const int DECAL_TEXELS = 4;
const int DECAL_MAX = 24;

vec3 decal_paint(float p) {
	int i = int(p + 0.5);
	return i == 1 ? decal_yellow : (i == 2 ? decal_red : (i == 3 ? decal_blue : decal_white));
}

float decal_seg(vec2 p, vec2 a, vec2 b) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
	return length(pa - ba * h);
}

// Signed distance to a triangle (inside < 0). After Inigo Quilez.
float decal_tri(vec2 p, vec2 a, vec2 b, vec2 c) {
	vec2 e0 = b - a, e1 = c - b, e2 = a - c;
	vec2 v0 = p - a, v1 = p - b, v2 = p - c;
	vec2 pq0 = v0 - e0 * clamp(dot(v0, e0) / dot(e0, e0), 0.0, 1.0);
	vec2 pq1 = v1 - e1 * clamp(dot(v1, e1) / dot(e1, e1), 0.0, 1.0);
	vec2 pq2 = v2 - e2 * clamp(dot(v2, e2) / dot(e2, e2), 0.0, 1.0);
	float sg = sign(e0.x * e2.y - e0.y * e2.x);
	vec2 d = min(min(vec2(dot(pq0, pq0), sg * (v0.x * e0.y - v0.y * e0.x)),
			vec2(dot(pq1, pq1), sg * (v1.x * e1.y - v1.y * e1.x))),
			vec2(dot(pq2, pq2), sg * (v2.x * e2.y - v2.y * e2.x)));
	return -sqrt(d.x) * sign(d.y);
}

// `first`, `count` from the strip; `dx`, `dy` the screen gradients of (t, s).
void decals(inout TSurf o, int first, int count, float s, float t, vec2 dx, vec2 dy,
		float fw_s, float fw_t) {
	int row = int(surf_decal_info.z);
	float fw = max(fw_s, fw_t);
	vec2 asz = vec2(textureSize(surf_decal_atlas, 0));
	for (int k = 0; k < DECAL_MAX; k++) {
		if (k >= count) {
			break;
		}
		int idx = first + k;
		ivec2 at = ivec2((idx % row) * DECAL_TEXELS, idx / row);
		vec4 r0 = texelFetch(surf_decals, at, 0);
		// Quick reject: outside the record's rect and footprint.
		if (s < r0.x - fw_s || s > r0.x + r0.z + fw_s || t < r0.y - fw_t || t > r0.y + r0.w + fw_t) {
			continue;
		}
		vec4 r1 = texelFetch(surf_decals, at + ivec2(1, 0), 0);
		vec4 r2 = texelFetch(surf_decals, at + ivec2(2, 0), 0);
		vec4 r3 = texelFetch(surf_decals, at + ivec2(3, 0), 0);
		float lx = (t - r0.y) / r0.w;
		float ly = (s - r0.x) / r0.z;
		float fl = r3.z > 0.5 ? -1.0 : 1.0;
		if (r3.z > 0.5) {
			lx = 1.0 - lx;
			ly = 1.0 - ly;
		}
		float rect = aa_pulse(r0.y, r0.y + r0.w, t, fw_t) * aa_pulse(r0.x, r0.x + r0.z, s, fw_s);
		// An MSDF edge stays exact down to strokes of 1-2 px, so decals fade
		// later than box-filtered patterns: from 3 px strokes, done at 1.5.
		float fade = aa_fade(r3.y * 2.0, fw);
		float cov;
		int kind = int(r2.x + 0.5);
		if (kind == 0) {
			vec2 uv = vec2(mix(r1.x, r1.z, lx), mix(r1.w, r1.y, ly));
			// d(uv)/d(screen): through (t, s) -> (lx, ly) -> uv.
			vec2 du = vec2((r1.z - r1.x) / r0.w, -(r1.w - r1.y) / r0.z) * fl;
			vec2 uv_dx = vec2(du.x * dx.x, du.y * dx.y);
			vec2 uv_dy = vec2(du.x * dy.x, du.y * dy.y);
			vec3 msd = textureGrad(surf_decal_atlas, uv, uv_dx, uv_dy).rgb;
			float md = max(min(msd.r, msd.g), min(max(msd.r, msd.g), msd.b));
			// Distance field pixels per screen pixel (the larger footprint).
			float tex_px = max(length(uv_dx * asz), length(uv_dy * asz));
			float spx = surf_decal_info.w / max(tex_px, 1e-5);
			cov = clamp((md - 0.5) * spx + 0.5, 0.0, 1.0) * rect;
		} else {
			vec2 p = vec2((lx - 0.5) * r0.w, ly * r0.z);
			float th = r3.y;
			float d;
			if (kind == 1) {
				// Chevron pointing along +s.
				vec2 a = vec2(-0.5 * r0.w + th, 0.1 * r0.z);
				vec2 b = vec2(0.0, 0.9 * r0.z - th * 0.5);
				vec2 c = vec2(0.5 * r0.w - th, 0.1 * r0.z);
				d = min(decal_seg(p, a, b), decal_seg(p, b, c)) - th * 0.5;
			} else {
				// Arrow: a shaft and a head.
				float shaft = decal_seg(p, vec2(0.0, 0.05 * r0.z), vec2(0.0, 0.6 * r0.z)) - th * 0.5;
				float head = decal_tri(p, vec2(-0.5 * r0.w, 0.55 * r0.z), vec2(0.0, 0.98 * r0.z),
						vec2(0.5 * r0.w, 0.55 * r0.z));
				d = min(shaft, head);
			}
			cov = aa_step(0.0, -d, fw) * rect;
		}
		cov = mix(cov, r3.x * rect, fade);
		ts_filt(o, fade * rect);
		float a = cov * r2.w;
		vec3 col = decal_paint(r2.y);
		o.albedo = mix(o.albedo, col, a);
		o.rough = mix(o.rough, decal_roughness, a);
		o.metal = mix(o.metal, 0.0, a);
		o.emission += col * r2.z * decal_glow_energy * a;
		o.keep = max(o.keep, a);
	}
}
