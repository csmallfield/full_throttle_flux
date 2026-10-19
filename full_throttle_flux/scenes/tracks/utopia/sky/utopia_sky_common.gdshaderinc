// Utopia sky -- shared code. Do not assign this file directly: use one of
//   utopia_sky_full.gdshader     clouds at full resolution    (high / ultra)
//   utopia_sky_half.gdshader     clouds at half resolution    (medium)
//   utopia_sky_quarter.gdshader  clouds at quarter resolution (low)
// UtopiaSkyController.cloud_quality picks the variant + step counts.
//
// * Atmosphere: art-directed gradient + sun glow/halo/disk, follows LIGHT0.
// * Cumulus: raymarched on a curved shell (sinks to the horizon) through a
//   128^3 Perlin-Worley shape volume eroded by a 64^3 Worley detail volume
//   (tools/utopia/gen_cloud_noise.py), Beer + powder lighting with a jittered
//   sun march, dithered start to hide step banding.
// * Cirrus: 2D layer at 7 km. Wind drifts everything with TIME; `parallax`
//   slides the deck past as the camera travels.
// * Cubemap pass (ambient + reflections) skips the raymarch.

group_uniforms atmosphere;
uniform vec3 zenith_color : source_color = vec3(0.16, 0.30, 0.54);
uniform vec3 horizon_color : source_color = vec3(0.93, 0.76, 0.60);
uniform vec3 ground_color : source_color = vec3(0.30, 0.28, 0.30);
uniform float gradient_curve : hint_range(0.1, 4.0) = 0.55;
uniform float horizon_height : hint_range(0.0, 0.4) = 0.08;
uniform float sky_energy : hint_range(0.0, 4.0) = 1.0;
uniform float mie_strength : hint_range(0.0, 4.0) = 0.9;
uniform float mie_eccentricity : hint_range(0.0, 0.99) = 0.82;
uniform float halo_strength : hint_range(0.0, 2.0) = 0.35;
uniform float sun_disk_size : hint_range(0.0, 5.0) = 0.9;     // degrees
uniform float sun_disk_energy : hint_range(0.0, 50.0) = 16.0;
// night: stars and the glow of a lit city on the horizon + cloud undersides
uniform float star_intensity : hint_range(0.0, 4.0) = 0.0;
uniform vec3 city_glow_color : source_color = vec3(1.0, 0.45, 0.25);
uniform float city_glow : hint_range(0.0, 4.0) = 0.0;

group_uniforms clouds;
uniform sampler3D shape_noise : repeat_enable, filter_linear;   // 128^3 Perlin-Worley
uniform sampler3D detail_noise : repeat_enable, filter_linear;  // 64^3 Worley FBM
uniform sampler2D weather_map : repeat_enable, filter_linear;
uniform float coverage : hint_range(0.0, 1.0) = 0.45;
uniform float density : hint_range(0.0, 4.0) = 1.0;
uniform float cloud_bottom = 1400.0;        // m
uniform float cloud_thickness = 900.0;      // m
uniform float weather_scale = 0.00012;      // 1/m: size of cloud fields
uniform float shape_scale = 0.00045;        // 1/m: size of billows
uniform float detail_scale = 0.0021;        // 1/m: erosion detail
uniform float detail_strength : hint_range(0.0, 1.0) = 0.45;
// 0 = hard, crisp cloud edges, 1 = soft and wispy
uniform float edge_softness : hint_range(0.05, 1.0) = 0.4;
// erosion detail fades out past this distance (it would only alias)
uniform float detail_fade_distance = 14000.0;
uniform vec2 wind_direction = vec2(0.8, 0.6);
uniform float wind_speed = 18.0;            // m/s
uniform float evolution_speed = 0.004;      // billow churn
uniform float parallax : hint_range(0.0, 1.0) = 1.0;
uniform vec3 cloud_light_color : source_color = vec3(1.0, 0.92, 0.82);
uniform vec3 cloud_shadow_color : source_color = vec3(0.36, 0.40, 0.52);
uniform float cloud_absorption : hint_range(0.1, 8.0) = 1.6;
uniform float silver_lining : hint_range(0.0, 2.0) = 0.8;
uniform float horizon_fade : hint_range(0.0, 1.0) = 0.55;
uniform int march_steps : hint_range(8, 96) = 40;
uniform int light_steps : hint_range(1, 8) = 4;
// per-pixel jitter of the march start: trades step banding ("slices") for fine grain
uniform float jitter : hint_range(0.0, 1.0) = 0.4;
uniform float planet_radius = 60000.0;

group_uniforms cirrus;
uniform float cirrus_amount : hint_range(0.0, 1.0) = 0.25;
uniform float cirrus_height = 7000.0;
uniform float cirrus_scale = 0.00005;
uniform vec2 cirrus_stretch = vec2(1.0, 2.5);

float hg(float mu, float g) {
	float g2 = g * g;
	return (1.0 - g2) / (12.566 * pow(max(1.0 + g2 - 2.0 * g * mu, 1e-4), 1.5));
}

float remap01(float v, float lo, float hi) {
	return clamp((v - lo) / max(hi - lo, 1e-4), 0.0, 1.0);
}

// distance along unit ray d from point o (inside the sphere) to the shell
float shell(vec3 o, vec3 d, float r) {
	vec3 c = vec3(0.0, -planet_radius, 0.0);
	vec3 oc = o - c;
	float b = dot(oc, d);
	float cc = dot(oc, oc) - r * r;
	float h = b * b - cc;
	if (h < 0.0) return -1.0;
	return -b + sqrt(h);
}

vec3 atmosphere(vec3 dir, vec3 sun_dir, vec3 sun_col, float glow) {
	float y = dir.y;
	float above = clamp((y + horizon_height) / (1.0 + horizon_height), 0.0, 1.0);
	vec3 sky = mix(horizon_color, zenith_color, pow(above, gradient_curve));
	// sun-side warmth along the horizon
	float mu = dot(dir, sun_dir);
	float horizon_band = exp(-max(y, 0.0) * 6.0);
	sky += sun_col * horizon_band * max(mu, 0.0) * 0.25;
	// below the horizon
	sky = mix(sky, mix(horizon_color, ground_color, clamp(-y * 3.0, 0.0, 1.0)), smoothstep(0.0, -0.04, y));
	// city light pollution: warm band hugging the horizon
	sky += city_glow_color * city_glow * exp(-max(y, 0.0) * 9.0) * 0.35;
	// forward scattering glow + broad halo
	sky += glow * sun_col * (hg(mu, mie_eccentricity) * mie_strength * 0.08 + hg(mu, 0.35) * halo_strength * 0.25);
	return sky * sky_energy;
}

vec2 wind_offset() {
	return normalize(wind_direction + vec2(1e-5)) * wind_speed * TIME;
}

float cloud_density(vec3 p, float hfrac, vec2 wind, float lod) {
	vec2 wp = p.xz + wind;
	float w = texture(weather_map, wp * weather_scale).r;
	float cov = remap01(w, 1.0 - coverage, 1.0 - coverage + 0.35);
	cov *= smoothstep(0.0, 0.15, coverage);
	// cumulus profile: flat base, rounded top that grows with local coverage
	float profile = smoothstep(0.0, 0.08, hfrac) * smoothstep(1.0, 0.25 + 0.4 * (1.0 - cov), hfrac);
	vec3 sp = vec3(wp.x, p.y, wp.y) * shape_scale + vec3(0.0, TIME * evolution_speed, 0.0);
	float n = texture(shape_noise, sp).r;
	float base = remap01(n * profile * cov, 0.12, 0.12 + edge_softness);
	if (base <= 0.0) return 0.0;
	if (lod > 0.0) {
		// erosion: wispy at the base, billowy (inverted) toward the top
		float det = texture(detail_noise, vec3(wp.x, p.y, wp.y) * detail_scale + vec3(TIME * evolution_speed * 2.0)).r;
		det = mix(det, 1.0 - det, clamp(hfrac * 3.0, 0.0, 1.0));
		base = remap01(base, det * detail_strength * lod, 1.0);
	}
	return base * density;
}

// per-pixel dither. A plain integer hash: reads as fine film grain, whereas
// structured patterns (IGN, Bayer) showed up as hatching on flat cloud areas.
float dither_hash(vec2 px) {
	uvec2 q = uvec2(ivec2(px)) * uvec2(1597334673u, 3812015801u);
	uint n = (q.x ^ q.y) * 1597334673u;
	return float(n) * (1.0 / 4294967295.0);
}

vec4 march_clouds(vec3 ro, vec3 rd, vec3 sun_dir, vec3 sun_col, vec3 amb, float dither) {
	if (rd.y < -0.02 || coverage < 0.01) return vec4(0.0);
	float r0 = planet_radius + cloud_bottom;
	float r1 = planet_radius + cloud_bottom + cloud_thickness;
	float t0 = shell(ro, rd, r0);
	float t1 = shell(ro, rd, r1);
	if (t0 < 0.0 || t1 < 0.0) return vec4(0.0);
	float span = min(t1 - t0, cloud_thickness * 6.0);
	// grazing rays cross far more cloud: give them more steps
	int steps = min(int(float(march_steps) * mix(1.0, 1.75, smoothstep(0.35, 0.04, rd.y))), 128);
	float dt = span / float(steps);
	vec2 wind = wind_offset();
	float mu = dot(rd, sun_dir);
	float phase = mix(hg(mu, 0.6), hg(mu, -0.25), 0.3) * 12.566;
	phase = mix(1.0, phase, silver_lining);
	float lod = 1.0 - smoothstep(detail_fade_distance * 0.5, detail_fade_distance, t0);
	float ls = cloud_thickness * 0.36 / float(light_steps);
	float T = 1.0;
	vec3 col = vec3(0.0);
	float t = t0 + dt * mix(0.5, dither, jitter);
	for (int i = 0; i < 128; i++) {
		if (i >= steps || T < 0.015) break;
		vec3 p = ro + rd * t;
		float alt = length(p - vec3(0.0, -planet_radius, 0.0)) - planet_radius;
		float hfrac = clamp((alt - cloud_bottom) / cloud_thickness, 0.0, 1.0);
		float d = cloud_density(p, hfrac, wind, lod);
		if (d > 0.001) {
			// light march toward the sun, jittered, growing steps
			float dl = 0.0;
			float lt = ls * mix(0.5, dither, jitter);
			for (int j = 0; j < 8; j++) {
				if (j >= light_steps) break;
				vec3 lp = p + sun_dir * lt;
				float la = length(lp - vec3(0.0, -planet_radius, 0.0)) - planet_radius;
				dl += cloud_density(lp, clamp((la - cloud_bottom) / cloud_thickness, 0.0, 1.0), wind, lod * 0.5) * ls;
				lt += ls;
			}
			float sigma = d * cloud_absorption * 0.004;
			float light = exp(-dl * cloud_absorption * 0.004);
			float powder = 1.0 - exp(-d * 2.0);
			vec3 lit = sun_col * cloud_light_color * light * phase * mix(1.0, powder, 0.6);
			vec3 ambient = amb * mix(cloud_shadow_color, vec3(1.0), hfrac);
			// city glow lights the cloud bases from below
			ambient += city_glow_color * city_glow * 0.6 * (1.0 - hfrac) * (1.0 - hfrac);
			vec3 S = (lit + ambient) * sigma;
			float Tstep = exp(-sigma * dt);
			col += T * (S - S * Tstep) / max(sigma, 1e-6);
			T *= Tstep;
		}
		t += dt;
	}
	float a = 1.0 - T;
	// aerial perspective: distant clouds dissolve into the horizon haze
	float fade = exp(-t0 * 0.00004 * horizon_fade * 4.0);
	vec3 haze = horizon_color * sky_energy;
	col = mix(haze * a, col, fade);
	return vec4(col, a * mix(0.6, 1.0, fade));
}

vec4 cirrus(vec3 ro, vec3 rd, vec3 sun_dir, vec3 sun_col) {
	if (rd.y <= 0.0 || cirrus_amount <= 0.0) return vec4(0.0);
	float t = shell(ro, rd, planet_radius + cirrus_height);
	vec3 p = ro + rd * t;
	vec2 uv = (p.xz + wind_offset() * 2.0) * cirrus_scale / cirrus_stretch;
	float n = texture(weather_map, uv).r * 0.65 + texture(weather_map, uv * 3.1 + 0.37).r * 0.35;
	float a = smoothstep(1.0 - cirrus_amount * 0.7, 1.15, n) * smoothstep(0.02, 0.3, rd.y) * 0.6;
	vec3 c = mix(horizon_color, sun_col, 0.5 + 0.5 * max(dot(rd, sun_dir), 0.0)) * 1.1;
	return vec4(c * a, a);
}

vec4 clouds_all(vec3 ro, vec3 rd, vec3 sun_dir, vec3 sun_col, vec3 amb, float dither) {
	vec4 cl = march_clouds(ro, rd, sun_dir, sun_col, amb, dither);
	vec4 ci = cirrus(ro, rd, sun_dir, sun_col);
	// cumulus in front of cirrus
	return vec4(cl.rgb + ci.rgb * (1.0 - cl.a), clamp(cl.a + ci.a * (1.0 - cl.a), 0.0, 1.0));
}

void sky() {
	vec3 sun_dir = LIGHT0_ENABLED ? LIGHT0_DIRECTION : normalize(vec3(-0.5, 0.4, -0.7));
	vec3 sun_col = LIGHT0_ENABLED ? LIGHT0_COLOR * LIGHT0_ENERGY : vec3(1.0);
	vec3 amb = mix(horizon_color, zenith_color, 0.5) * sky_energy;
	vec3 ro = vec3(POSITION.x * parallax, 0.0, POSITION.z * parallax);
	float dither = dither_hash(FRAGCOORD.xy);
	if (AT_CUBEMAP_PASS) {
		// ambient/reflections: no raymarch (a soft coverage veil instead) and
		// most of the sun glow kept out, it over-warms the city
		vec3 c = atmosphere(EYEDIR, sun_dir, sun_col, 0.25);
		float veil = coverage * smoothstep(-0.05, 0.25, EYEDIR.y) * 0.7;
		c = mix(c, amb * mix(cloud_shadow_color, vec3(1.0), 0.6), veil);
		COLOR = c;
	}
#ifdef CLOUDS_LOWRES
	else if (CLOUD_PASS) {
		vec4 cl = clouds_all(ro, EYEDIR, sun_dir, sun_col, amb, dither);
		COLOR = cl.rgb;
		ALPHA = cl.a;
	}
#endif
	else {
		vec3 c = atmosphere(EYEDIR, sun_dir, sun_col, 1.0);
		float mu = dot(EYEDIR, sun_dir);
		float disk = smoothstep(cos(radians(sun_disk_size)), cos(radians(sun_disk_size * 0.7)), mu);
		c += sun_col * disk * sun_disk_energy;
		if (star_intensity > 0.0 && EYEDIR.y > 0.0) {
			// stars: hashed cells on the sphere, twinkling slightly
			vec3 sd = EYEDIR * 280.0;
			vec3 cell = floor(sd);
			float h = fract(sin(dot(cell, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
			vec3 fp = fract(sd) - 0.5;
			float star = step(0.985, h) * smoothstep(0.18, 0.0, length(fp));
			star *= 0.6 + 0.4 * sin(TIME * (2.0 + h * 5.0) + h * 40.0);
			c += vec3(star * star_intensity * smoothstep(0.0, 0.25, EYEDIR.y) * (0.5 + 2.0 * fract(h * 37.0)));
		}
#ifdef CLOUDS_LOWRES
		vec4 cl = CLOUD_TEX;
#else
		vec4 cl = clouds_all(ro, EYEDIR, sun_dir, sun_col, amb, dither);
#endif
		COLOR = c * (1.0 - cl.a) + cl.rgb;
	}
}
