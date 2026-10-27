// v35 trail ribbons (TrailRibbon): shared vertex expansion and noise.
//
// v38.1: the ribbon is built HERE, on the GPU. Every ribbon draws the same
// static strip (TrailRibbon's shared mesh): each point twice, UV.x = the
// point's index along the subdivided spline, UV.y = -1 / +1 (which edge).
// Its data is one row of `trail_data` (row = instance uniform trail_row),
// written by TrailRibbon each frame and uploaded once per frame for all
// ribbons:
//   texel 0  head (live socket) xyz, w: 0 = not emitting, 1 = live head,
//            2 = live but the head sits on the newest sample (skip it)
//   texel 1  tint rgb, w = tint alpha * intensity
//   texel 2  now (s), 1 / lifetime, 1 / max length, width scale
//   texel 3  sample count, newest ring slot, subdivisions, head odometer
//   texel 4  width head, width tail, fade power, head fade (m)
//   then TRAIL_MAX samples, two texels each: (xyz, time), (odometer, -, -, -)
// The odometer is the distance travelled along the samples, so a point's
// distance from the head is head_odo - odo without walking the chain.
// trail_build() turns that into what the CPU used to send per point:
//   VERTEX  centre of the ribbon at that point (world_vertex_coords)
//   NORMAL  tangent along the ribbon
//   UV      x = metres from the head, y = -1 / +1 (which edge)
//   UV2     x = full width (m), y = 0..1 how far along its life the point is
//   COLOR   rgb tint, a = opacity
// and trail_vertex() turns the strip to face whichever camera is drawing it,
// so it works from the chase cam, the cinematic rig and the spectator alike.

uniform sampler2D trail_data : filter_nearest, repeat_disable;
instance uniform float trail_row = 0.0;

// Must match TrailRibbon.HEADER / MAX_SAMPLES.
const int TRAIL_HEADER = 5;
const int TRAIL_MAX = 48;

varying float v_edge;   // -1 .. +1 across
varying float v_along;  // metres from the head
varying float v_life;   // 0 head .. 1 tail

vec4 trail_fetch(int row, int texel) {
	return texelFetch(trail_data, ivec2(texel, row), 0);
}

// Control point k, head first: position, age (s), distance from the head (m).
void trail_ctrl(int row, int k, bool has_head, int newest, float now, float head_odo, vec3 head,
		out vec3 p, out float age, out float along) {
	if (has_head && k == 0) {
		p = head;
		age = 0.0;
		along = 0.0;
		return;
	}
	int s = k - (has_head ? 1 : 0);   // 0 = newest sample
	int slot = (newest - s + TRAIL_MAX * 4) % TRAIL_MAX;
	vec4 a = trail_fetch(row, TRAIL_HEADER + slot * 2);
	vec4 b = trail_fetch(row, TRAIL_HEADER + slot * 2 + 1);
	p = a.xyz;
	age = now - a.w;
	along = head_odo - b.x;
}

// Centripetal Catmull-Rom (alpha 0.5, Barry-Goldman): no cusps or loops at
// uneven sample spacing. Same as the CPU reference in TrailRibbon.
vec3 trail_catmull_rom(vec3 p0, vec3 p1, vec3 p2, vec3 p3, float t) {
	float t0 = 0.0;
	float t1 = t0 + max(sqrt(distance(p0, p1)), 1e-4);
	float t2 = t1 + max(sqrt(distance(p1, p2)), 1e-4);
	float t3 = t2 + max(sqrt(distance(p2, p3)), 1e-4);
	float tt = mix(t1, t2, t);
	vec3 a1 = p0 * ((t1 - tt) / (t1 - t0)) + p1 * ((tt - t0) / (t1 - t0));
	vec3 a2 = p1 * ((t2 - tt) / (t2 - t1)) + p2 * ((tt - t1) / (t2 - t1));
	vec3 a3 = p2 * ((t3 - tt) / (t3 - t2)) + p3 * ((tt - t2) / (t3 - t2));
	vec3 b1 = a1 * ((t2 - tt) / (t2 - t0)) + a2 * ((tt - t0) / (t2 - t0));
	vec3 b2 = a2 * ((t3 - tt) / (t3 - t1)) + a3 * ((tt - t1) / (t3 - t1));
	return b1 * ((t2 - tt) / (t2 - t1)) + b2 * ((tt - t1) / (t2 - t1));
}

// Point q of the subdivided spline (m control points, `sub` points per
// segment): position, age and distance from the head.
void trail_point(int row, int q, int m, int sub, bool has_head, int newest, float now,
		float head_odo, vec3 head, out vec3 p, out float age, out float along) {
	int i = q / sub;
	int s = q - i * sub;
	if (i >= m - 1) {
		trail_ctrl(row, m - 1, has_head, newest, now, head_odo, head, p, age, along);
		return;
	}
	vec3 p1; float g1; float a1;
	vec3 p2; float g2; float a2;
	trail_ctrl(row, i, has_head, newest, now, head_odo, head, p1, g1, a1);
	if (s == 0) {
		p = p1;
		age = g1;
		along = a1;
		return;
	}
	trail_ctrl(row, i + 1, has_head, newest, now, head_odo, head, p2, g2, a2);
	float t = float(s) / float(sub);
	vec3 p0 = p1 * 2.0 - p2;
	vec3 p3 = p2 * 2.0 - p1;
	float dg; float da;
	if (i > 0) {
		trail_ctrl(row, i - 1, has_head, newest, now, head_odo, head, p0, dg, da);
	}
	if (i + 2 < m) {
		trail_ctrl(row, i + 2, has_head, newest, now, head_odo, head, p3, dg, da);
	}
	p = trail_catmull_rom(p0, p1, p2, p3, t);
	age = mix(g1, g2, t);
	along = mix(a1, a2, t);
}

// The ribbon point this vertex stands for, as the CPU used to send it.
void trail_build(int row, inout vec3 vertex, inout vec3 normal, inout vec2 uv, inout vec2 uv2,
		inout vec4 color) {
	vec4 h0 = trail_fetch(row, 0);
	vec4 h1 = trail_fetch(row, 1);
	vec4 h2 = trail_fetch(row, 2);
	vec4 h3 = trail_fetch(row, 3);
	vec4 h4 = trail_fetch(row, 4);
	bool live = h0.w > 0.5;
	bool has_head = live && h0.w < 1.5;
	int count = int(h3.x + 0.5);
	int newest = int(h3.y + 0.5);
	int sub = max(int(h3.z + 0.5), 1);
	float head_odo = h3.w;
	float now = h2.x;
	int m = count + (has_head ? 1 : 0);
	int last = max(m - 1, 0) * sub;
	int q = min(int(uv.x + 0.5), last);

	vec3 p; float age; float along;
	trail_point(row, q, m, sub, has_head, newest, now, head_odo, h0.xyz, p, age, along);
	vec3 prev = p;
	vec3 next = p;
	float dg; float da;
	if (q > 0) {
		trail_point(row, q - 1, m, sub, has_head, newest, now, head_odo, h0.xyz, prev, dg, da);
	}
	if (q < last) {
		trail_point(row, q + 1, m, sub, has_head, newest, now, head_odo, h0.xyz, next, dg, da);
	}
	vec3 tang = prev - next;
	if (dot(tang, tang) < 1e-10) {
		tang = vec3(0.0, 0.0, -1.0);
	}

	float life01 = clamp(max(age * h2.y, along * h2.z), 0.0, 1.0);
	float fade = pow(1.0 - life01, h4.z);
	if (live && h4.w > 0.0 && along < h4.w) {
		fade *= smoothstep(0.0, h4.w, along);
	}
	float width = (h4.x + (h4.y - h4.x) * life01) * h2.w;
	// Past the end of the trail (beyond max length, or spare points of the
	// shared strip): zero width, so the rest of the strip is degenerate.
	if (int(uv.x + 0.5) > last || along * h2.z > 1.0) {
		width = 0.0;
		fade = 0.0;
	}
	vertex = p;
	normal = tang;
	color = vec4(h1.rgb, h1.a * fade);
	uv2 = vec2(width, life01);
	uv = vec2(along, uv.y);
}

void trail_vertex(inout vec3 vertex, inout vec3 normal, vec2 uv, vec2 uv2, mat4 inv_view) {
	vec3 cam = inv_view[3].xyz;
	vec3 tangent = normalize(normal);
	vec3 to_cam = normalize(cam - vertex);
	vec3 side = cross(tangent, to_cam);
	float len = length(side);
	// Looking straight down the ribbon: any perpendicular will do.
	side = len > 1e-4 ? side / len : normalize(cross(tangent, vec3(0.0, 1.0, 0.0001)));
	vertex += side * uv.y * uv2.x * 0.5;
	normal = to_cam;
}

// Varyings can only be written in vertex() itself, so each shader calls these
// there: TRAIL_BUILD; trail_vertex(...); TRAIL_VARYINGS;
#define TRAIL_BUILD trail_build(int(trail_row + 0.5), VERTEX, NORMAL, UV, UV2, COLOR)
#define TRAIL_VARYINGS v_edge = UV.y; v_along = UV.x; v_life = UV2.y

float trail_hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float trail_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(trail_hash(i), trail_hash(i + vec2(1.0, 0.0)), u.x),
			mix(trail_hash(i + vec2(0.0, 1.0)), trail_hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

// Soft edge across the strip: 1 on the centre line, 0 at the edges.
float trail_edge(float softness) {
	return smoothstep(0.0, max(softness, 1e-3), 1.0 - abs(v_edge));
}
