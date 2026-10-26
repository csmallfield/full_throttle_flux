// v35 Phase 4: wet / frozen / dusty surfaces.
//
// Any spatial shader includes this and, at the end of fragment(), fills an
// EnvSurface and calls env_surface_apply(). Everything reads the global
// uniforms EnvironmentState publishes, so no per-material plumbing: with all
// globals at 0 (menus, clear weather) the surface is returned untouched.
//
//   wet     darker (porosity), smoother; puddles on flat ground where world
//           noise meets wetness (more in standing-water zones); rain rings in
//           puddles while it rains; run-off streaks down vertical faces
//   frozen  frost tint and sparkle; snow on up-facing ground, thinned on the
//           racing groove so the line stays dark and the edges go white; ice
//           (smooth, bluish) in the groove
//   dusty   albedo toward env_dust_color, rougher, heavier at the edges
//
// The per-distance track mask (EnvironmentState builds it from TrackFxZones)
// makes covered spans dry and unfrozen and adds standing water / drifts /
// local dust, with the SAME formulas the ship probe uses, so a ship's spray
// stops exactly where the puddles stop.

global uniform float env_wetness;
global uniform float env_frost;
global uniform float env_dust;
global uniform float env_precip;
global uniform vec4 env_wind;          // xy = direction (world X, Z), z = m/s
global uniform vec4 env_dust_color;
// R covered, G standing water, B snow drift, A dust scale / 4. x = d / length.
global uniform sampler2D env_track_mask : filter_linear, repeat_enable;
global uniform float env_track_length; // 0 = no mask on this track
// Track lines glow this much in poor visibility (fog, storms, heavy rain).
global uniform float env_line_glow;

struct EnvSurface {
	vec3 albedo;
	float roughness;
	float metallic;
	float specular;
	vec3 emission;
	vec3 world_pos;
	vec3 world_normal;    // geometric, normalized
	float along;          // metres along the track spline, < 0 = unknown
	float edge;           // 0 = on the racing groove ... 1 = at / past the road edge
	float is_wall;        // 0 road, 1 wall
	float keep;           // 0..1: how much of the base look survives cover (grid lines)
	vec3 normal_offset;   // OUT: world-space normal perturbation to add
};

float env_hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float env_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(env_hash(i), env_hash(i + vec2(1.0, 0.0)), u.x),
		mix(env_hash(i + vec2(0.0, 1.0)), env_hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float env_fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * env_noise(p);
		p = p * 2.03 + vec2(17.1, 9.2);
		a *= 0.5;
	}
	return v;
}

// Expanding rain rings, two layers of cells. Returns a world XZ slope.
vec2 env_ripples(vec2 p, float t) {
	vec2 slope = vec2(0.0);
	for (int layer = 0; layer < 2; layer++) {
		float fl = float(layer);
		vec2 q = p * (1.7 + fl * 0.9) + fl * 7.31;
		vec2 cell = floor(q);
		vec2 f = fract(q) - 0.5;
		float h = env_hash(cell + fl * 13.0);
		vec2 ofs = (vec2(env_hash(cell + 1.7), env_hash(cell + 3.1)) - 0.5) * 0.4;
		vec2 d = f - ofs;
		float r = length(d);
		float ph = fract(t * (0.9 + 0.5 * h) + h);
		float ring_r = ph * 0.42;
		float x = (r - ring_r) * 28.0;
		float a = (1.0 - ph) * (1.0 - ph) * exp(-x * x * 0.35);
		slope += (d / max(r, 1e-3)) * sin(x * 2.2) * a;
	}
	return slope;
}

void env_surface_apply(inout EnvSurface s, float time) {
	s.normal_offset = vec3(0.0);
	// --- local condition ---------------------------------------------------
	float covered = 0.0;
	float water = 0.0;
	float drift = 0.0;
	float dust_scale = 1.0;
	if (env_track_length > 0.0 && s.along >= 0.0) {
		vec4 m = texture(env_track_mask, vec2(s.along / env_track_length, 0.5));
		covered = m.r;
		water = m.g;
		drift = m.b;
		dust_scale = m.a * 4.0;
	}
	float wet = clamp(env_wetness * (1.0 - covered) * (1.0 + water), 0.0, 1.0);
	float frost = clamp(env_frost * (1.0 - covered) * (1.0 + drift), 0.0, 1.0);
	float dust = clamp(env_dust * dust_scale, 0.0, 1.0);
	float rain = env_precip * (1.0 - covered) * step(0.3, env_wetness);
	if (wet + frost + dust < 0.001) {
		return;
	}
	vec3 wp = s.world_pos;
	float up = clamp(s.world_normal.y, 0.0, 1.0);
	float flat_ground = smoothstep(0.8, 0.97, up);
	float vertical = 1.0 - smoothstep(0.25, 0.6, abs(s.world_normal.y));
	float edge = clamp(s.edge, 0.0, 1.0);
	float base_keep = clamp(s.keep, 0.0, 1.0);

	// --- dust: settles at the edges, swept off the groove ------------------
	if (dust > 0.001) {
		float n = env_fbm(wp.xz * 0.35 + env_wind.xy * time * 0.05);
		float amount = dust * mix(0.35, 0.85, edge) * mix(0.6, 1.2, n) * mix(1.0, 0.6, s.is_wall);
		amount *= 1.0 - wet * 0.8;                // mud is another story
		amount *= 1.0 - base_keep * 0.6;
		s.albedo = mix(s.albedo, env_dust_color.rgb * 0.75, clamp(amount, 0.0, 0.9));
		s.roughness = mix(s.roughness, 0.95, clamp(amount * 1.4, 0.0, 1.0));
	}

	// --- wet ------------------------------------------------------------------
	if (wet > 0.001) {
		s.albedo *= mix(1.0, 0.6, wet);
		s.roughness = mix(s.roughness, 0.18, wet);
		s.specular = mix(s.specular, 0.6, wet);
		// Puddles on flat ground: world noise thresholded by wetness, wider
		// where the zone mask says standing water.
		float n = env_fbm(wp.xz * 0.07) * 0.75 + env_noise(wp.xz * 0.6) * 0.25;
		float thresh = mix(0.78, 0.38, clamp(wet * 0.8 + water * 0.6, 0.0, 1.0));
		float puddle = smoothstep(thresh, thresh + 0.06, n) * flat_ground * smoothstep(0.35, 0.8, wet);
		puddle *= mix(0.55, 1.0, edge);           // ships blow the groove clear; water pools at the edges
		s.albedo *= mix(1.0, 0.55, puddle);
		s.roughness = mix(s.roughness, 0.02, puddle);
		s.specular = mix(s.specular, 1.0, puddle);
		// Rain rings in the puddles, a faint drizzle texture everywhere else.
		if (rain > 0.001) {
			vec2 r = env_ripples(wp.xz, time) * rain;
			float amp = mix(0.12, 0.45, puddle) * flat_ground;
			s.normal_offset += vec3(r.x, 0.0, r.y) * amp;
		}
		// Run-off: streaks running down vertical faces while it rains.
		if (vertical > 0.01) {
			float along_h = s.along >= 0.0 ? s.along : dot(wp.xz, vec2(0.7, 0.7));
			float st = env_noise(vec2(along_h * 5.0, wp.y * 0.35 + time * (0.6 + rain * 1.2)));
			st = smoothstep(0.6, 0.85, st) * vertical * wet * (0.4 + 0.6 * rain);
			s.albedo *= 1.0 - st * 0.35;
			s.roughness = mix(s.roughness, 0.05, st);
		}
	}

	// --- frost / snow / ice --------------------------------------------------
	if (frost > 0.001) {
		vec3 frost_tint = vec3(0.70, 0.78, 0.88);
		s.albedo = mix(s.albedo, frost_tint, frost * 0.18 * (1.0 - base_keep * 0.5));
		// Snow lies on up-facing surfaces, broken up by noise; the racing
		// groove is thinned (ships blow it off) so the line reads dark.
		float n = env_fbm(wp.xz * 0.45);
		float groove = mix(0.25, 1.0, smoothstep(0.15, 0.75, edge));
		float cover = frost * groove * smoothstep(0.35, 0.85, up);
		float snow = smoothstep(0.55 - cover * 0.6, 0.75 - cover * 0.6, n + cover * 0.5) * cover;
		snow *= 1.0 - base_keep * 0.75;           // keep the grid lines readable
		vec3 snow_col = vec3(0.86, 0.89, 0.93);
		s.albedo = mix(s.albedo, snow_col, clamp(snow, 0.0, 1.0));
		s.roughness = mix(s.roughness, 0.75, snow);
		s.specular = mix(s.specular, 0.35, snow);
		s.normal_offset += vec3(env_noise(wp.xz * 9.0) - 0.5, 0.0, env_noise(wp.zx * 9.0) - 0.5) * 0.12 * snow;
		// Ice where the snow is thin: smooth and bluish, mostly in the groove.
		float ice = frost * (1.0 - snow) * flat_ground * (1.0 - smoothstep(0.2, 0.7, edge)) * (1.0 - s.is_wall);
		s.roughness = mix(s.roughness, 0.08, ice * 0.8);
		s.albedo = mix(s.albedo, s.albedo * vec3(0.8, 0.9, 1.15), ice * 0.5);
		// Sparkle: sparse, sharp flecks in the frost and snow.
		vec2 cell = floor(wp.xz * 22.0 + wp.y * 3.0);
		float fleck = step(0.985, env_hash(cell)) * frost * (0.4 + 0.6 * snow);
		s.emission += vec3(0.8, 0.9, 1.0) * fleck * 0.6;
	}
}
