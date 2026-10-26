// v38 track surface, phase 1 (foundation): the industrial road surface for
// builder tracks (TrackRoadSegment road segments; walls keep the grid).
//
// Coordinates (TrackRoadSegment writes them, see its header):
//   s = UV2.x    metres along the path
//   t = UV2.y    metres across from the centre line, +x = right, measured on
//                the actual (widened) vertex
//   CUSTOM0      (edge class, left half width, right half width): 0 driving
//                surface, 1 lip, 2 underside / sides / caps
// The cross-section is a band table across t (hard-coded below until the
// profile resources of phase 3): fixed bands stack inward from each real
// edge, flex bands share what's left, so a width key only changes the flex
// lane. Plate and edge bands are split into panels by transverse seams every
// panel_len metres (snapped per path so the lap is a whole number of panels),
// each band's seams offset by a hash so they never line up across lanes, and
// a per-panel hash drives a small tint and roughness variation.
//
// Every pattern goes through surface_aa.gdshaderinc (see there): box-filtered
// coverage, the average once a feature drops below ~2 px, detail along s
// filtered hardest. Weather comes from env_surface.gdshaderinc as on the
// grid; EnvSurfaces recognises this shader and fills along_main.
//
// Debug views (key 9, global track_surface_debug): 1 s/t, 2 band ids,
// 3 panel ids, 4 filter level (green = full detail, red = faded to average).
// Quality tier (Shift+9, global track_surface_tier): 0 low, 1 high; both look
// the same in phase 1 (low will drop normal detail, parallax and decals).
shader_type spatial;

#include "res://shaders/env/env_surface.gdshaderinc"
#include "res://shaders/track/surface_aa.gdshaderinc"

global uniform int track_surface_debug;
global uniform int track_surface_tier;

// Set per mesh: the path's length (TrackRoadSegment) and whether s is
// distance along MainSpline, so the weather zone mask applies (EnvSurfaces).
instance uniform float path_length = 0.0;
instance uniform float along_main = 0.0;

group_uniforms materials;
// Phase 1 placeholder palette: neutral plates, the look comes in phase 2.
uniform vec3 plate_color : source_color = vec3(0.24, 0.25, 0.27);
uniform float plate_roughness : hint_range(0.0, 1.0) = 0.5;
uniform float plate_metallic : hint_range(0.0, 1.0) = 0.5;
uniform vec3 edge_color : source_color = vec3(0.36, 0.34, 0.30);
uniform float edge_roughness : hint_range(0.0, 1.0) = 0.55;
uniform vec3 channel_color : source_color = vec3(0.06, 0.065, 0.07);
uniform float channel_roughness : hint_range(0.0, 1.0) = 0.8;
uniform vec3 underside_color : source_color = vec3(0.08, 0.08, 0.09);
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

// --- the cross-section (phase 1: hard-coded) -------------------------------
const int BT_PLATE = 0;
const int BT_CHANNEL = 1;
const int BT_EDGE = 2;
const int BAND_COUNT = 9;
// Left to right. Width in metres; flex bands (weight > 0) share the space the
// fixed bands leave.
const int BAND_TYPE[9] = { BT_EDGE, BT_CHANNEL, BT_PLATE, BT_CHANNEL, BT_PLATE,
		BT_CHANNEL, BT_PLATE, BT_CHANNEL, BT_EDGE };
const float BAND_W[9] = { 1.5, 0.4, 6.0, 0.3, 0.0, 0.3, 6.0, 0.4, 1.5 };
const float BAND_FLEX[9] = { 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0 };

const int EDGE_SURFACE = 0;
const int EDGE_LIP = 1;

varying vec2 v_st;
varying vec3 v_meta;

struct Bands {
	int id;           // band under t
	int plate;        // the plate/edge band whose panels t uses (a channel's nearer neighbour)
	float channel;    // filtered channel coverage
	float channel_fade;
};

Bands band_lookup(float t, float fw_t, float wl, float wr) {
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
	b.plate = b.id;
	b.channel = 0.0;
	b.channel_fade = 0.0;
	float x = -wl;
	for (int i = 0; i < BAND_COUNT; i++) {
		float w = BAND_W[i] * squeeze + (flex_w > 0.0 ? BAND_FLEX[i] / flex_w * flex_space : 0.0);
		float x1 = x + w;
		if (t >= x && t < x1) {
			b.id = i;
			b.plate = BAND_TYPE[i] != BT_CHANNEL ? i : (t > (x + x1) * 0.5 ? i + 1 : i - 1);
		}
		if (BAND_TYPE[i] == BT_CHANNEL) {
			b.channel += aa_pulse(x, x1, t, fw_t);
			b.channel_fade = max(b.channel_fade, aa_fade(w, fw_t));
		}
		x = x1;
	}
	b.plate = clamp(b.plate, 0, BAND_COUNT - 1);
	b.channel = clamp(b.channel, 0.0, 1.0);
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
	// Derivatives first, in uniform control flow.
	float fw_t = aa_fw(t);
	float fw_s = aa_fw_s(s);

	// Panels: snapped per path so the lap is a whole number of panels.
	float pl = path_length > 0.0 ? path_length / max(1.0, round(path_length / panel_len)) : panel_len;

	Bands b = band_lookup(t, fw_t, wl, wr);
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

	vec3 albedo;
	float rough;
	float metal;
	if (cls == EDGE_SURFACE || cls == EDGE_LIP) {
		bool edge_band = cls == EDGE_LIP || BAND_TYPE[pb] == BT_EDGE;
		albedo = edge_band ? edge_color : plate_color;
		rough = edge_band ? edge_roughness : plate_roughness;
		metal = edge_band ? plate_metallic * 0.5 : plate_metallic;
		albedo *= 1.0 + h_tint * panel_tint_var;
		rough = clamp(rough + h_rough * panel_rough_var, 0.0, 1.0);
		albedo *= mix(1.0, seam_dark, seam);
		rough = mix(rough, seam_roughness, seam);
		if (cls == EDGE_SURFACE) {
			albedo = mix(albedo, channel_color, b.channel);
			rough = mix(rough, channel_roughness, b.channel);
			metal = mix(metal, 0.2, b.channel);
		}
	} else {
		albedo = underside_color;
		rough = 0.8;
		metal = 0.0;
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
			float f = max(max(seam_fade, var_fade), b.channel_fade * (cls == EDGE_SURFACE ? 1.0 : 0.0));
			c = mix(vec3(0.0, 0.8, 0.1), vec3(0.9, 0.05, 0.0), f);
		}
		ALBEDO = vec3(0.0);
		ROUGHNESS = 1.0;
		METALLIC = 0.0;
		SPECULAR = 0.0;
		EMISSION = c;
	} else {
		EnvSurface e;
		e.albedo = albedo;
		e.roughness = rough;
		e.metallic = metal;
		e.specular = 0.5;
		e.emission = vec3(0.0);
		e.world_pos = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
		e.world_normal = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
		e.along = along_main > 0.5 ? s : -1.0;
		// 0 at the centre line, 1 at the surface edges and beyond.
		float lat = t < 0.0 ? -t / max(wl, 0.01) : t / max(wr, 0.01);
		e.edge = cls == EDGE_SURFACE ? clamp(lat, 0.0, 1.0) : 1.0;
		e.is_wall = 0.0;
		e.keep = max(b.channel, seam) * 0.8;
		env_surface_apply(e, TIME);

		ALBEDO = e.albedo;
		ROUGHNESS = e.roughness;
		METALLIC = e.metallic;
		SPECULAR = e.specular;
		EMISSION = e.emission;
		if (dot(e.normal_offset, e.normal_offset) > 1e-8) {
			vec3 nw = normalize(e.world_normal + e.normal_offset);
			NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);
		}
	}
}
