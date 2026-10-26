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
// The cross-section is a band table across t (hard-coded below until the
// profile resources of phase 3): fixed bands stack inward from each real
// edge, flex bands share what's left, so a width key only changes the flex
// lane. Plate-like bands are split into panels by transverse seams every
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
// 3 panel ids, 4 filter level (green = full detail, red = faded to average).
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

// --- the cross-section (hard-coded until phase 3) ---------------------------
const int BT_PLATE = 0;
const int BT_CHANNEL = 1;
const int BT_EDGE = 2;
const int BT_RIBBED = 3;
const int BT_GRATE = 4;
const int BAND_COUNT = 13;
// Left to right. Width in metres; flex bands (weight > 0) share the space the
// fixed bands leave. BAND_PARAM: channels = light kind (LIGHT_*), plates =
// 1 for vents.
const int BAND_TYPE[13] = { BT_EDGE, BT_CHANNEL, BT_GRATE, BT_CHANNEL, BT_RIBBED, BT_CHANNEL,
		BT_PLATE, BT_CHANNEL, BT_RIBBED, BT_CHANNEL, BT_GRATE, BT_CHANNEL, BT_EDGE };
const float BAND_W[13] = { 1.2, 0.35, 2.4, 0.3, 5.0, 0.25, 0.0, 0.25, 5.0, 0.3, 2.4, 0.35, 1.2 };
const float BAND_FLEX[13] = { 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0 };
const int BAND_PARAM[13] = { 0, LIGHT_RED_DOTS, 0, LIGHT_BLUE, 0, LIGHT_NONE, 1, LIGHT_NONE, 0,
		LIGHT_BLUE, 0, LIGHT_RED_DOTS, 0 };

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

Bands band_lookup(float t, float fw_t, float fw_s, float wl, float wr, float dots, float leds) {
	float fixed_w = 0.0;
	float flex_w = 0.0;
	for (int i = 0; i < BAND_COUNT; i++) {
		fixed_w += BAND_W[i];
		flex_w += BAND_FLEX[i];
	}
	float width = wl + wr;
	// Narrower than the fixed bands: squeeze them, no flex.
	float squeeze = width < fixed_w ? width / fixed_w : 1.0;
	float flex_space = max(width - fixed_w, 0.0);
	Bands b;
	b.id = t < -wl ? 0 : BAND_COUNT - 1;
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
	for (int i = 0; i < BAND_COUNT; i++) {
		float w = BAND_W[i] * squeeze + (flex_w > 0.0 ? BAND_FLEX[i] / flex_w * flex_space : 0.0);
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
			if (BAND_TYPE[i] == BT_CHANNEL) {
				bool right_side = t > (x + x1) * 0.5;
				b.plate = right_side ? i + 1 : i - 1;
				b.px0 = right_side ? x1 : prev_x0;
				b.px1 = right_side ? x1 : x;
			}
		}
		// Thin features along s: every band the footprint can reach.
		if (t > x - fw_t && t < x1 + fw_t) {
			if (BAND_TYPE[i] == BT_CHANNEL) {
				b.channel += aa_pulse(x, x1, t, fw_t);
				b.channel_fade = max(b.channel_fade, aa_fade(w, fw_t));
				b.lights += channel_light(BAND_PARAM[i], x, x1, t, fw_t, dots);
			} else if (BAND_TYPE[i] == BT_EDGE) {
				bool outer_left = i == 0;
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
	b.plate = clamp(b.plate, 0, BAND_COUNT - 1);
	b.channel = clamp(b.channel, 0.0, 1.0);
	b.edge_line = clamp(b.edge_line, 0.0, 1.0);
	return b;
}

vec3 debug_hue(float h) {
	return clamp(abs(fract(h + vec3(0.0, 2.0, 1.0) / 3.0) * 6.0 - 3.0) - 1.0, 0.0, 1.0);
}

void vertex() {
	v_st = UV2;
	v_meta = CUSTOM0.xyz;
}

void fragment() {
	float s = v_st.x;
	float t = v_st.y;
	int cls = int(round(v_meta.x));
	float wl = v_meta.y;
	float wr = v_meta.z;
	bool high = track_surface_tier > 0;
	// Derivatives first, in uniform control flow.
	float fw_t = aa_fw(t);
	float fw_s = aa_fw_s(s);
	float q = (s + abs(t)) * 0.70710678;
	// The hazard diagonals: highest contrast, on thin lips: filter twice as hard.
	float fw_q = aa_fw(q) * aa_s_bias * 2.0;

	// The track frame in view space (normal detail and parallax only).
	vec3 n_geo = normalize(NORMAL);
	vec3 fwd = vec3(0.0);
	vec3 right = vec3(0.0);
	if (high) {
		fwd = normalize(TANGENT - n_geo * dot(TANGENT, n_geo));
		right = cross(fwd, n_geo);
	}

	// Panels: snapped per path so the lap is a whole number of panels.
	float pl = path_length > 0.0 ? path_length / max(1.0, round(path_length / panel_len)) : panel_len;

	// Dot rows along s, shared by every channel / edge band.
	float dots_fade;
	float dots = aa_lines(s, light_dot_every, light_dot_len, fw_s, dots_fade);
	float leds_fade;
	float leds = aa_lines(s + led_every * 0.5, led_every, led_size, fw_s, leds_fade);

	Bands b = band_lookup(t, fw_t, fw_s, wl, wr, dots, leds);
	// Lips carry on the nearer edge band's panels.
	int pb = cls == EDGE_SURFACE ? b.plate : (t < 0.0 ? 0 : BAND_COUNT - 1);
	float pbf = float(pb);
	float u = s + env_hash(vec2(pbf * 1.37 + seed, 7.31)) * pl;
	float panel = floor(u / pl);
	float seam_fade;
	float seam = aa_lines(u, pl, seam_width, fw_s, seam_fade);
	float var_fade = aa_fade(pl, fw_s);
	float h_tint = mix(env_hash(vec2(panel, pbf * 13.1 + 1.7 + seed)) * 2.0 - 1.0, 0.0, var_fade);
	float h_rough = mix(env_hash(vec2(panel * 1.91 + 3.3, pbf * 5.7 + seed)) * 2.0 - 1.0, 0.0, var_fade);

	TSurf o;
	o.emission = vec3(0.0);
	o.slope = vec2(0.0);
	o.normal_var = 0.0;
	o.keep = 0.0;
	o.filt = max(seam_fade, var_fade);
	if (cls == EDGE_SURFACE) {
		int bt = BAND_TYPE[pb];
		bool edge_band = bt == BT_EDGE;
		o.albedo = (edge_band ? edge_color : plate_color) * (1.0 + h_tint * panel_tint_var);
		o.rough = clamp((edge_band ? edge_roughness : plate_roughness) + h_rough * panel_rough_var, 0.0, 1.0);
		o.metal = edge_band ? 0.2 : plate_metallic;
		// The plate band's own extent (pb may be a channel's neighbour).
		float px0 = b.px0;
		float px1 = b.px1;
		if (bt == BT_RIBBED) {
			ribs(o, t - px0, fw_t, high);
		} else if (bt == BT_GRATE) {
			vec3 v = normalize(-VERTEX);
			vec3 view_ts = high ? vec3(dot(v, right), dot(v, fwd), dot(v, n_geo)) : vec3(0.0, 0.0, 1.0);
			grate(o, t - px0, px1 - px0, s, fw_t, fw_s, view_ts, high);
		} else if (bt == BT_PLATE && BAND_PARAM[pb] == 1) {
			vents(o, t - px0, px1 - px0, s, fw_t, fw_s, seed);
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
		o.filt = max(o.filt, max(b.channel_fade, max(dots_fade, leds_fade) * step(0.001, dot(b.lights, vec3(1.0)))));
	} else if (cls == EDGE_LIP) {
		hazard(o, q, fw_q);
		o.filt = max(o.filt, 0.0);
	} else {
		o.albedo = underside_color;
		o.rough = 0.8;
		o.metal = 0.0;
		o.filt = 0.0;
		seam = 0.0;
	}

	if (track_surface_debug > 0) {
		vec3 c;
		if (track_surface_debug == 1) {
			// s: red ramp every 10 m (white at s = 0), t: green across, class in blue.
			float ramp = fract(s / 10.0);
			c = vec3(ramp, clamp(0.5 + t / max(2.0 * max(wl, wr), 1.0), 0.0, 1.0), float(cls) * 0.5);
			c = mix(c, vec3(1.0), aa_pulse(-0.25, 0.25, s, fw_s));
		} else if (track_surface_debug == 2) {
			c = cls == EDGE_SURFACE ? debug_hue(float(b.id) / float(BAND_COUNT)) * 0.8
					: (cls == EDGE_LIP ? vec3(0.9) : vec3(0.05));
		} else if (track_surface_debug == 3) {
			c = cls == 2 ? vec3(0.05) : debug_hue(env_hash(vec2(panel, pbf))) * mix(1.0, 0.1, seam);
		} else {
			c = mix(vec3(0.0, 0.8, 0.1), vec3(0.9, 0.05, 0.0), o.filt);
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
		e.along = along_main > 0.5 ? s : -1.0;
		// 0 at the centre line, 1 at the surface edges and beyond.
		float lat = t < 0.0 ? -t / max(wl, 0.01) : t / max(wr, 0.01);
		e.edge = cls == EDGE_SURFACE ? clamp(lat, 0.0, 1.0) : 1.0;
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
		bool bent = high && dot(o.slope, o.slope) > 1e-10;
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
