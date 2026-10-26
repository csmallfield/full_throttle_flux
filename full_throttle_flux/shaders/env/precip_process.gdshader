// v35 Phase 4: rain / snow / grit around the camera (process shader).
//
// No emission at all: every particle has a fixed seed position in a box and
// falls with the weather's velocity forever; its world position is that,
// wrapped into a box centred on the camera. So the box is always full, at
// any camera speed, and drops keep their true world motion: at 150 u/s the
// camera tears through them and the streaks lean and lengthen (the draw
// shader stretches each one along its velocity RELATIVE to the camera).
//
// The basis carries that relative motion to the draw pass: Y = relative
// velocity per second (direction and speed), X/Z unused.
shader_type particles;
render_mode disable_velocity, disable_force;

uniform vec3 cam_pos;
uniform vec3 cam_vel;
uniform vec3 box_size = vec3(44.0, 26.0, 44.0);
uniform vec3 fall = vec3(0.0, -10.0, 0.0);      // world m/s (wind included)
uniform float fall_spread = 0.15;               // +- fraction of fall per particle
uniform float sway = 0.0;                       // m of side-to-side drift (snow)
uniform float sway_rate = 0.6;
uniform float ratio = 1.0;                      // share of particles shown (0..1)
uniform float time_offset = 0.0;

float h11(float n) { return fract(sin(n * 12.9898) * 43758.5453); }

void start() {
	// Nothing to emit: process() places every particle from its INDEX.
}

void process() {
	float fi = float(INDEX);
	vec3 seed = vec3(h11(fi + 0.13), h11(fi * 1.7 + 3.1), h11(fi * 2.3 + 7.7));
	float r = h11(fi * 3.1 + 11.3);
	float t = TIME + time_offset;
	vec3 v = fall * (1.0 + (r - 0.5) * 2.0 * fall_spread);
	vec3 p = seed * box_size + v * t;
	if (sway > 0.0) {
		float ph = r * 6.2831 + t * sway_rate * (0.7 + r * 0.6);
		p.x += sin(ph) * sway;
		p.z += cos(ph * 0.83 + 1.3) * sway;
		v.x += cos(ph) * sway * sway_rate;
		v.z -= sin(ph * 0.83 + 1.3) * sway * sway_rate * 0.83;
	}
	vec3 corner = cam_pos - box_size * 0.5;
	vec3 rel = mod(p - corner, box_size);
	vec3 rv = v - cam_vel;
	// Shown share: the first `ratio` of the particles (by a per-particle
	// random, so thinning is even).
	float shown = step(h11(fi * 5.7 + 1.9), ratio);
	// Fade at the box faces so wrapping never pops.
	vec3 e = min(rel, box_size - rel) / max(box_size * 0.12, vec3(0.01));
	float face = clamp(min(min(e.x, e.y), e.z), 0.0, 1.0);
	TRANSFORM = mat4(vec4(1.0, 0.0, 0.0, 0.0), vec4(rv, 0.0), vec4(0.0, 0.0, 1.0, 0.0),
		vec4(corner + rel, 1.0));
	COLOR = vec4(1.0, 1.0, 1.0, shown * face);
	CUSTOM = vec4(r, seed.x, 0.0, 0.0);
}
