// v35 trail ribbons (TrailRibbon): shared vertex expansion and noise.
//
// TrailRibbon sends each ribbon point TWICE, as world-space centre points:
//   VERTEX  centre of the ribbon at that point (world_vertex_coords)
//   NORMAL  tangent along the ribbon
//   UV      x = metres from the head, y = -1 / +1 (which edge)
//   UV2     x = full width (m), y = 0..1 how far along its life the point is
//   COLOR   rgb tint, a = opacity
// The vertex stage turns the strip to face whichever camera is drawing it, so
// it works from the chase cam, the cinematic rig and the spectator alike.

varying float v_edge;   // -1 .. +1 across
varying float v_along;  // metres from the head
varying float v_life;   // 0 head .. 1 tail

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

// Varyings can only be written in vertex() itself, so each shader calls this
// there: trail_vertex(...); TRAIL_VARYINGS;
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
