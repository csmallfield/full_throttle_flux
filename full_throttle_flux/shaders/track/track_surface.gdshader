// v38 track surface: the industrial road surface for builder tracks
// (TrackRoadSegment road segments; walls keep the grid).
//
// Coordinates (TrackRoadSegment writes them, see its header):
//   s = UV2.x    metres along the path
//   t = UV2.y    metres across from the centre line, +x = right, measured on
//                the actual (widened) vertex
//   CUSTOM0      (edge class, left half width, right half width): 0 driving
//                surface, 1 lip, 2 underside / sides / caps
//   TANGENT      the direction of travel: with NORMAL, the frame for normal
//                detail and parallax
// The cross-section is a band table across t (a TrackSurfaceProfile, phase
// 3): fixed bands stack inward from each real edge, flex bands share what's
// left, so a width key only changes the flex lanes. Up to MAX_PROFILES band
// tables sit in uniform arrays; a per-metre zone strip says which one is in
// force (TrackSurface builds both per path from the SurfaceZoneKeys), with
// blends and hard seams between them. Plate-like bands are split into panels by transverse seams every
// panel_len metres (snapped per path so the lap is a whole number of
// panels), each band's seams offset by a hash, with a per-panel tint and
// roughness variation.
//
// Phase 2 modules (shaders/track/modules/), switched per band type:
//   ribbed plate, hex grate, vents (in the flex plate), guide lights in the
//   channels, LED rows and painted lines on the edge bands, hazard
//   diagonals on the lips. Thin features along s (channels, light strips,
//   LED rows) are evaluated for every band the pixel's footprint touches,
//   inside the band lookup; wide ones for the band under the pixel.
//
// Every pattern goes through surface_aa.gdshaderinc: box-filtered coverage,
// the average once a feature drops below ~2 px, detail along s filtered
// hardest; normal detail fades first and its lost variance goes to
// roughness. Weather comes from env_surface.gdshaderinc; EnvSurfaces
// recognises this shader and fills along_main.
//
// Debug views (key 9, global track_surface_debug): 1 s/t, 2 band ids,
// 3 panel ids, 4 filter level (green = full detail, red = faded to average),
// 5 zones (a hue per profile slot, blends between, hard seams white).
// Quality tier (Shift+9, global track_surface_tier): 0 low = no normal
// detail, no grate parallax; 1 high = everything.
shader_type spatial;

#include "res://shaders/env/env_surface.gdshaderinc"
#include "res://shaders/track/surface_aa.gdshaderinc"
#include "res://shaders/track/modules/surface_common.gdshaderinc"
#include "res://shaders/track/modules/ribs.gdshaderinc"
#include "res://shaders/track/modules/grate.gdshaderinc"
#include "res://shaders/track/modules/vents.gdshaderinc"
#include "res://shaders/track/modules/lights.gdshaderinc"
#include "res://shaders/track/modules/edges.gdshaderinc"

global uniform int track_surface_debug;
global uniform int track_surface_tier;

// Set per mesh: the path's length (TrackRoadSegment) and whether s is
// distance along MainSpline, so the weather zone mask applies (EnvSurfaces).
instance uniform float path_length = 0.0;
instance uniform float along_main = 0.0;

group_uniforms materials;
// Industrial style (phase 2): grey metal plates, painted edge bands, black
// recesses.
uniform vec3 plate_color : source_color = vec3(0.21, 0.22, 0.24);
uniform float plate_roughness : hint_range(0.0, 1.0) = 0.42;
uniform float plate_metallic : hint_range(0.0, 1.0) = 0.6;
uniform vec3 edge_color : source_color = vec3(0.3, 0.3, 0.31);
uniform float edge_roughness : hint_range(0.0, 1.0) = 0.6;
uniform vec3 channel_color : source_color = vec3(0.03, 0.032, 0.036);
uniform float channel_roughness : hint_range(0.0, 1.0) = 0.8;
uniform vec3 underside_color : source_color = vec3(0.08, 0.08, 0.09);
// Roughness gained per unit of slope variance filtered away (Toksvig-style).
uniform float toksvig : hint_range(0.0, 50.0) = 8.0;
group_uniforms;

group_uniforms panels;
// Target panel length in metres; snapped so path_length / panel_len is whole.
uniform float panel_len : hint_range(0.5, 20.0) = 6.0;
uniform float seam_width : hint_range(0.0, 0.2) = 0.03;
// Albedo multiplier and roughness inside a seam.
uniform float seam_dark : hint_range(0.0, 1.0) = 0.3;
uniform float seam_roughness : hint_range(0.0, 1.0) = 0.85;
// Per-panel variation: +- this much albedo (relative) and roughness.
uniform float panel_tint_var : hint_range(0.0, 0.5) = 0.08;
uniform float panel_rough_var : hint_range(0.0, 0.3) = 0.08;
uniform float seed = 0.0;
group_uniforms;

// --- the cross-section: band tables and zones (phase 3) ----------------------
const int BT_PLATE = 0;
const int BT_CHANNEL = 1;
const int BT_EDGE = 2;
const int BT_RIBBED = 3;
const int BT_GRATE = 4;
const int MAX_PROFILES = 4;
const int MAX_BANDS = 16;

group_uniforms zones;
// Band tables of up to MAX_PROFILES profiles (TrackSurfaceProfile.packed():
// width, flex weight, type, param), MAX_BANDS slots each. The base material
// holds the industrial preset in slot 0; TrackSurface writes each path's.
uniform vec4 surf_bands[64];
// Per profile: (band count, sum of fixed widths, sum of flex weights, 0).
uniform vec4 surf_profiles[4];
// One texel per metre of path (TrackSurface.build_strip()): R = slot A +
// 16 * slot B, G = transition start (< 0: none), B = its length (0 = hard
// seam), A = seed A + 1024 * seed B.
uniform sampler2D surf_strip : filter_nearest, repeat_disable;
// (texel count, texture width); 0 texels = no zones: profile 0 everywhere.
uniform vec2 surf_strip_info = vec2(0.0);
group_uniforms;

const int EDGE_SURFACE = 0;
const int EDGE_LIP = 1;

varying vec2 v_st;
varying vec3 v_meta;

struct Bands {
	int id;           // band under t
	float x0;         // its extent
	float x1;
	int plate;        // the band whose panels t uses (a channel's nearer neighbour)
	float px0;        // its extent
	float px1;
	float channel;    // filtered channel coverage
	float channel_fade;
	vec3 lights;      // channel lights + edge LEDs, filtered
	float edge_line;  // painted edge line coverage
};

Bands band_lookup(int p, float t, float fw_t, float fw_s, float wl, float wr, float dots, float leds) {
	vec4 info = surf_profiles[p];
	int count = int(info.x);
	float fixed_w = info.y;
	float flex_w = info.z;
	float width = wl + wr;
	// Narrower than the fixed bands: squeeze them, no flex.
	float squeeze = width < fixed_w ? width / fixed_w : 1.0;
	float flex_space = max(width - fixed_w, 0.0);
	Bands b;
	b.id = t < -wl ? 0 : count - 1;
	b.x0 = t < -wl ? -wl : wr;
	b.x1 = b.x0;
	b.plate = b.id;
	b.px0 = b.x0;
	b.px1 = b.x1;
	b.channel = 0.0;
	b.channel_fade = 0.0;
	b.lights = vec3(0.0);
	b.edge_line = 0.0;
	float x = -wl;
	float prev_x0 = x;
	for (int i = 0; i < MAX_BANDS; i++) {
		if (i >= count) {
			break;
		}
		vec4 bd = surf_bands[p * MAX_BANDS + i];
		int type = int(bd.z);
		float w = bd.x * squeeze + (flex_w > 0.0 ? bd.y / flex_w * flex_space : 0.0);
		float x1 = x + w;
		if (i == b.plate && i == b.id + 1) {
			b.px0 = x;     // the channel's right neighbour, one band on
			b.px1 = x1;
		}
		if (t >= x && t < x1) {
			b.id = i;
			b.x0 = x;
			b.x1 = x1;
			b.plate = i;
			b.px0 = x;
			b.px1 = x1;
			if (type == BT_CHANNEL) {
				bool right_side = t > (x + x1) * 0.5;
				b.plate = right_side ? i + 1 : i - 1;
				b.px0 = right_side ? x1 : prev_x0;
				b.px1 = right_side ? x1 : x;
			}
		}
		// Thin features along s: every band the footprint can reach.
		if (t > x - fw_t && t < x1 + fw_t) {
			if (type == BT_CHANNEL) {
				b.channel += aa_pulse(x, x1, t, fw_t);
				b.channel_fade = max(b.channel_fade, aa_fade(w, fw_t));
				b.lights += channel_light(int(bd.w), x, x1, t, fw_t, dots);
			} else if (type == BT_EDGE) {
				// Its outer side is the road edge it's nearer.
				bool outer_left = x + x1 < wr - wl;
				b.lights += edge_leds(x, x1, outer_left, t, fw_t, max(fw_t, fw_s), leds);
				float a = outer_left ? x : x1 - edge_line_width;
				b.edge_line += aa_pulse(a, a + edge_line_width, t, fw_t);
			}
		}
		prev_x0 = x;
		x = x1;
		// Past the footprint (and the band under t found, and a channel's
		// right neighbour recorded): no later band can matter.
		if (x > t + fw_t && i > b.id) {
			break;
		}
	}
	b.plate = clamp(b.plate, 0, max(count - 1, 0));
	b.channel = clamp(b.channel, 0.0, 1.0);
	b.edge_line = clamp(b.edge_line, 0.0, 1.0);
	return b;
}

// Everything that doesn't depend on the profile, computed once per pixel.
struct Px {
	float s;
	float t;
	int cls;
	float wl;
	float wr;
	float fw_t;
	float fw_s;
	float q;
	float fw_q;
	float pl;
	float dots;
	float dots_fade;
	float leds;
	float leds_fade;
	bool high;
	vec3 view_ts;
};

// The surface as profile `p` draws it (zone seed `zseed`), plus what the
// debug views need.
TSurf shade(int p, float zseed, Px x, out int band_id, out float panel, out float seam) {
	float sd = seed + zseed;
	Bands b = band_lookup(p, x.t, x.fw_t, x.fw_s, x.wl, x.wr, x.dots, x.leds);
	band_id = b.id;
	// Lips carry on the nearer edge band's panels.
	int count = int(surf_profiles[p].x);
	int pb = x.cls == EDGE_SURFACE ? b.plate : (x.t < 0.0 ? 0 : count - 1);
	vec4 bd = surf_bands[p * MAX_BANDS + pb];
	int bt = int(bd.z);
	float pbf = float(pb);
	float u = x.s + env_hash(vec2(pbf * 1.37 + sd, 7.31)) * x.pl;
	panel = floor(u / x.pl);
	float seam_fade;
	seam = aa_lines(u, x.pl, seam_width, x.fw_s, seam_fade);
	float var_fade = aa_fade(x.pl, x.fw_s);
	float h_tint = mix(env_hash(vec2(panel, pbf * 13.1 + 1.7 + sd)) * 2.0 - 1.0, 0.0, var_fade);
	float h_rough = mix(env_hash(vec2(panel * 1.91 + 3.3, pbf * 5.7 + sd)) * 2.0 - 1.0, 0.0, var_fade);

	TSurf o;
	o.emission = vec3(0.0);
	o.slope = vec2(0.0);
	o.normal_var = 0.0;
	o.keep = 0.0;
	o.filt = max(seam_fade, var_fade);
	if (x.cls == EDGE_SURFACE) {
		bool edge_band = bt == BT_EDGE;
		o.albedo = (edge_band ? edge_color : plate_color) * (1.0 + h_tint * panel_tint_var);
		o.rough = clamp((edge_band ? edge_roughness : plate_roughness) + h_rough * panel_rough_var, 0.0, 1.0);
		o.metal = edge_band ? 0.2 : plate_metallic;
		// The plate band's own extent (pb may be a channel's neighbour).
		float px0 = b.px0;
		float px1 = b.px1;
		if (bt == BT_RIBBED) {
			ribs(o, x.t - px0, x.fw_t, x.high);
		} else if (bt == BT_GRATE) {
			grate(o, x.t - px0, px1 - px0, x.s, x.fw_t, x.fw_s, x.view_ts, x.high);
		} else if (bt == BT_PLATE && int(bd.w) == 1) {
			vents(o, x.t - px0, px1 - px0, x.s, x.fw_t, x.fw_s, sd);
		}
		o.albedo *= mix(1.0, seam_dark, seam);
		o.rough = mix(o.rough, seam_roughness, seam);
		o.albedo = mix(o.albedo, channel_color, b.channel);
		o.rough = mix(o.rough, channel_roughness, b.channel);
		o.metal = mix(o.metal, 0.2, b.channel);
		o.slope *= 1.0 - b.channel;
		o.albedo = mix(o.albedo, edge_line_color, b.edge_line);
		o.rough = mix(o.rough, 0.6, b.edge_line);
		o.metal = mix(o.metal, 0.0, b.edge_line);
		o.emission += b.lights;
		o.keep = max(o.keep, max(b.channel, max(seam * 0.8, b.edge_line)));
		o.keep = max(o.keep, clamp(dot(b.lights, vec3(0.3)), 0.0, 1.0));
		o.filt = max(o.filt, max(b.channel_fade,
				max(x.dots_fade, x.leds_fade) * step(0.001, dot(b.lights, vec3(1.0)))));
	} else if (x.cls == EDGE_LIP) {
		hazard(o, x.q, x.fw_q);
	} else {
		o.albedo = underside_color;
		o.rough = 0.8;
		o.metal = 0.0;
		o.filt = 0.0;
		seam = 0.0;
	}
	return o;
}

TSurf ts_mix(TSurf a, TSurf b, float w) {
	TSurf o;
	o.albedo = mix(a.albedo, b.albedo, w);
	o.rough = mix(a.rough, b.rough, w);
	o.metal = mix(a.metal, b.metal, w);
	o.emission = mix(a.emission, b.emission, w);
	o.slope = mix(a.slope, b.slope, w);
	o.normal_var = mix(a.normal_var, b.normal_var, w);
	o.keep = max(a.keep, b.keep);
	o.filt = max(a.filt, b.filt);
	return o;
}

vec3 debug_hue(float h) {
	return clamp(abs(fract(h + vec3(0.0, 2.0, 1.0) / 3.0) * 6.0 - 3.0) - 1.0, 0.0, 1.0);
}

void vertex() {
	v_st = UV2;
	v_meta = CUSTOM0.xyz;
}

void fragment() {
	Px x;
	x.s = v_st.x;
	x.t = v_st.y;
	x.cls = int(round(v_meta.x));
	x.wl = v_meta.y;
	x.wr = v_meta.z;
	x.high = track_surface_tier > 0;
	// Derivatives first, in uniform control flow.
	x.fw_t = aa_fw(x.t);
	x.fw_s = aa_fw_s(x.s);
	x.q = (x.s + abs(x.t)) * 0.70710678;
	// The hazard diagonals: highest contrast, on thin lips: filter twice as hard.
	x.fw_q = aa_fw(x.q) * aa_s_bias * 2.0;

	// The track frame in view space (normal detail and parallax only).
	vec3 n_geo = normalize(NORMAL);
	vec3 fwd = vec3(0.0);
	vec3 right = vec3(0.0);
	x.view_ts = vec3(0.0, 0.0, 1.0);
	if (x.high) {
		fwd = normalize(TANGENT - n_geo * dot(TANGENT, n_geo));
		right = cross(fwd, n_geo);
		vec3 v = normalize(-VERTEX);
		x.view_ts = vec3(dot(v, right), dot(v, fwd), dot(v, n_geo));
	}

	// Panels: snapped per path so the lap is a whole number of panels.
	x.pl = path_length > 0.0 ? path_length / max(1.0, round(path_length / panel_len)) : panel_len;
	// Dot rows along s, shared by every channel / edge band.
	x.dots = aa_lines(x.s, light_dot_every, light_dot_len, x.fw_s, x.dots_fade);
	x.leds = aa_lines(x.s + led_every * 0.5, led_every, led_size, x.fw_s, x.leds_fade);

	// Zone: which profile(s) here, and the transition if there is one.
	int pa = 0;
	int pbz = 0;
	float seed_a = 0.0;
	float seed_b = 0.0;
	float w = 0.0;
	float hard_seam = 0.0;
	if (surf_strip_info.x > 0.0) {
		int n = int(surf_strip_info.x);
		int sw = int(surf_strip_info.y);
		int i = clamp(int(floor(x.s)), 0, n - 1);
		vec4 z = texelFetch(surf_strip, ivec2(i % sw, i / sw), 0);
		int slots = int(z.r + 0.5);
		pa = slots % 16;
		pbz = slots / 16;
		seed_a = mod(z.a, 1024.0);
		seed_b = floor(z.a / 1024.0 + 0.0005);
		if (z.g >= 0.0) {
			if (z.b > 0.0) {
				w = clamp((x.s - z.g) / z.b, 0.0, 1.0);
			} else {
				// A hard seam: switch over the footprint, and mark it.
				w = aa_step(z.g, x.s, x.fw_s);
				hard_seam = aa_pulse(z.g - seam_width, z.g + seam_width, x.s, x.fw_s);
			}
		}
	}
	int band_id;
	float panel;
	float seam;
	TSurf o;
	if (w <= 0.0) {
		o = shade(pa, seed_a, x, band_id, panel, seam);
	} else if (w >= 1.0) {
		o = shade(pbz, seed_b, x, band_id, panel, seam);
	} else {
		// Inside a transition: both profiles, cross-faded.
		int id_b;
		float panel_b;
		float seam_b;
		TSurf ob = shade(pbz, seed_b, x, id_b, panel_b, seam_b);
		o = ts_mix(shade(pa, seed_a, x, band_id, panel, seam), ob, w);
		if (w >= 0.5) {
			band_id = id_b;
			panel = panel_b;
			seam = seam_b;
		}
	}
	if (x.cls != 2) {
		o.albedo *= mix(1.0, seam_dark, hard_seam);
	}

	if (track_surface_debug > 0) {
		vec3 c;
		if (track_surface_debug == 1) {
			// s: red ramp every 10 m (white at s = 0), t: green across, class in blue.
			float ramp = fract(x.s / 10.0);
			c = vec3(ramp, clamp(0.5 + x.t / max(2.0 * max(x.wl, x.wr), 1.0), 0.0, 1.0), float(x.cls) * 0.5);
			c = mix(c, vec3(1.0), aa_pulse(-0.25, 0.25, x.s, x.fw_s));
		} else if (track_surface_debug == 2) {
			c = x.cls == EDGE_SURFACE ? debug_hue(float(band_id) / 13.0) * 0.8
					: (x.cls == EDGE_LIP ? vec3(0.9) : vec3(0.05));
		} else if (track_surface_debug == 3) {
			c = x.cls == 2 ? vec3(0.05) : debug_hue(env_hash(vec2(panel, float(band_id)))) * mix(1.0, 0.1, seam);
		} else if (track_surface_debug == 4) {
			c = mix(vec3(0.0, 0.8, 0.1), vec3(0.9, 0.05, 0.0), o.filt);
		} else {
			// Zones: one hue per profile slot, blends in between, seams white.
			c = mix(debug_hue(float(pa) * 0.27 + 0.05), debug_hue(float(pbz) * 0.27 + 0.05), w) * 0.8;
			c = mix(c, vec3(1.0), hard_seam);
		}
		ALBEDO = vec3(0.0);
		ROUGHNESS = 1.0;
		METALLIC = 0.0;
		SPECULAR = 0.0;
		EMISSION = c;
	} else {
		EnvSurface e;
		e.albedo = o.albedo;
		// Toksvig-style: the slope variance the filters removed keeps the
		// highlight's energy as roughness.
		e.roughness = clamp(sqrt(o.rough * o.rough + o.normal_var * toksvig), 0.0, 1.0);
		e.metallic = o.metal;
		e.specular = 0.5;
		e.emission = o.emission;
		e.world_pos = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
		e.world_normal = normalize((INV_VIEW_MATRIX * vec4(n_geo, 0.0)).xyz);
		e.along = along_main > 0.5 ? x.s : -1.0;
		// 0 at the centre line, 1 at the surface edges and beyond.
		float lat = x.t < 0.0 ? -x.t / max(x.wl, 0.01) : x.t / max(x.wr, 0.01);
		e.edge = x.cls == EDGE_SURFACE ? clamp(lat, 0.0, 1.0) : 1.0;
		e.is_wall = 0.0;
		e.keep = o.keep;
		env_surface_apply(e, TIME);

		ALBEDO = e.albedo;
		ROUGHNESS = e.roughness;
		METALLIC = e.metallic;
		SPECULAR = e.specular;
		EMISSION = e.emission;
		// Height gradient -> normal: tilt away from the uphill direction.
		vec3 n = n_geo;
		bool bent = x.high && dot(o.slope, o.slope) > 1e-10;
		if (bent) {
			n = normalize(n_geo - right * o.slope.x - fwd * o.slope.y);
		}
		if (dot(e.normal_offset, e.normal_offset) > 1e-8) {
			vec3 nw = normalize((INV_VIEW_MATRIX * vec4(n, 0.0)).xyz + e.normal_offset);
			n = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);
			bent = true;
		}
		if (bent) {
			NORMAL = n;
		}
	}
}
