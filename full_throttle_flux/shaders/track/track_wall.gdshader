// v38 phase 5: the walls of builder tracks join the track surface system
// (TrackRoadSegment wall segments; junctions keep the grid).
//
// Coordinates (TrackRoadSegment, see its header): s = UV2.x along the path,
// CUSTOM0 = (edge class, -, -, height in the section). The inner face
// (EDGE_FACE) carries the look, from the road up:
//   kick band   hazard diagonals at the foot (0 .. wall_kick m)
//   panels      seams every wall_panel_len (snapped per path, like the
//               road's) and at wall_rows heights, a tint per panel
//   light strip a blue guide strip at wall_strip_h, with the road's pulses
//   LED row     white dots near the top, flowing like the road's
//   wear        grime splashed up from the road (high tier: the detail
//               texture), weather run-off from env_surface
// Tops (EDGE_LIP: facing up) are a lighter cap; outer faces and the
// underside stay dark. Same AA discipline and shared modules as the road:
// box-filtered patterns, fading to their average below ~2 px.
shader_type spatial;

#include "res://shaders/env/env_surface.gdshaderinc"
#include "res://shaders/track/surface_aa.gdshaderinc"
#include "res://shaders/track/modules/surface_common.gdshaderinc"
#include "res://shaders/track/modules/lights.gdshaderinc"
#include "res://shaders/track/modules/edges.gdshaderinc"
#include "res://shaders/track/modules/wear.gdshaderinc"

global uniform int track_surface_debug;
global uniform int track_surface_tier;

instance uniform float path_length = 0.0;
instance uniform float along_main = 0.0;

group_uniforms wall;
uniform vec3 wall_color : source_color = vec3(0.075, 0.08, 0.095);
uniform float wall_roughness : hint_range(0.0, 1.0) = 0.5;
uniform float wall_metallic : hint_range(0.0, 1.0) = 0.45;
uniform vec3 wall_cap_color : source_color = vec3(0.26, 0.27, 0.29);
uniform vec3 wall_outer_color : source_color = vec3(0.05, 0.052, 0.06);
uniform float wall_panel_len : hint_range(1.0, 20.0) = 5.0;
// Horizontal seams (heights above the road, m).
uniform vec2 wall_rows = vec2(0.9, 3.4);
uniform float wall_seam_width : hint_range(0.0, 0.2) = 0.04;
uniform float wall_tint_var : hint_range(0.0, 0.5) = 0.1;
// Hazard band at the foot.
uniform float wall_kick : hint_range(0.0, 2.0) = 0.8;
// Guide strip height and thickness; LED row height.
uniform float wall_strip_h : hint_range(0.0, 8.0) = 1.6;
uniform float wall_strip_w : hint_range(0.01, 0.5) = 0.1;
uniform float wall_led_h : hint_range(0.0, 8.0) = 5.4;
// Grime splashed up from the road, metres.
uniform float wall_grime_h : hint_range(0.0, 4.0) = 1.8;
group_uniforms;

const int EDGE_LIP = 1;
const int EDGE_FACE = 3;

varying vec2 v_sh;     // (s, height)
varying float v_cls;

void vertex() {
	v_sh = vec2(UV2.x, CUSTOM0.w);
	v_cls = CUSTOM0.x;
}

void fragment() {
	float s = v_sh.x;
	float h = v_sh.y;
	int cls = int(round(v_cls));
	bool high = track_surface_tier > 0;
	float fw_s = aa_fw_s(s);
	float fw_h = aa_fw(h);
	vec2 dx = dFdx(vec2(h, s));
	vec2 dy = dFdy(vec2(h, s));
	float q = (s + h) * 0.70710678;
	float fw_q = aa_fw(q) * aa_s_bias * 2.0;

	float pl = path_length > 0.0 ? path_length / max(1.0, round(path_length / wall_panel_len)) : wall_panel_len;
	float dot_phase = mod(TIME * light_flow, led_every);
	float pulse_phase = mod(TIME * light_pulse_speed, light_pulse_every);

	TSurf o;
	o.emission = vec3(0.0);
	o.slope = vec2(0.0);
	o.normal_var = 0.0;
	o.keep = 0.0;
	o.recess = 0.0;
	o.filt = 0.0;
	float seam = 0.0;
	if (cls == EDGE_FACE) {
		float sf;
		float vseam = aa_lines(s, pl, wall_seam_width, fw_s, sf);
		float hseam = max(aa_pulse(wall_rows.x - wall_seam_width * 0.5, wall_rows.x + wall_seam_width * 0.5, h, fw_h),
				aa_pulse(wall_rows.y - wall_seam_width * 0.5, wall_rows.y + wall_seam_width * 0.5, h, fw_h));
		seam = max(vseam, hseam);
		float panel = floor(s / pl);
		float var_fade = aa_fade(pl, fw_s);
		float tint = mix(env_hash(vec2(panel, 4.7)) * 2.0 - 1.0, 0.0, var_fade);
		o.albedo = wall_color * (1.0 + tint * wall_tint_var);
		o.rough = wall_roughness;
		o.metal = wall_metallic;
		o.filt = max(sf, var_fade);
		o.albedo *= mix(1.0, 0.35, seam);
		o.recess = seam * 0.8;
		// Hazard kick band at the foot.
		float kick = aa_pulse(-10.0, wall_kick, h, fw_h);
		if (kick > 0.0) {
			TSurf hz = o;
			hazard(hz, q, fw_q);
			o.albedo = mix(o.albedo, hz.albedo, kick);
			o.rough = mix(o.rough, hz.rough, kick);
			o.metal = mix(o.metal, hz.metal, kick);
			o.filt = max(o.filt, hz.filt * kick);
		}
		// Guide strip with the road's pulses, LED row flowing.
		float strip = aa_pulse(wall_strip_h - wall_strip_w * 0.5, wall_strip_h + wall_strip_w * 0.5, h, fw_h);
		float pf;
		float pulse = 1.0 + light_pulse_gain * aa_lines(s - pulse_phase, light_pulse_every, light_pulse_len, fw_s, pf);
		float energy = mix(light_energy, min(light_far_energy, light_energy), aa_fade(wall_strip_w, fw_h));
		o.emission += light_blue * energy * strip * pulse;
		float lf;
		float leds = aa_lines(s - dot_phase, led_every, led_size, fw_s, lf)
				* aa_pulse(wall_led_h - led_size * 0.5, wall_led_h + led_size * 0.5, h, fw_h);
		float led_e = mix(led_energy, min(light_far_energy, led_energy), aa_fade(led_size, max(fw_s, fw_h)));
		o.emission += light_white * led_e * leds;
		o.keep = max(o.keep, max(strip, max(leds, kick)));
		// Grime splashed up from the road.
		float g = wear_age * (1.0 - smoothstep(0.0, wall_grime_h, h)) * grime_amount;
		if (high) {
			vec2 uv = vec2(s, h) / wear_grime_scale;
			vec4 tex = textureGrad(wear_detail, uv, vec2(dx.y, dx.x) / wear_grime_scale,
					vec2(dy.y, dy.x) / wear_grime_scale);
			g *= 0.4 + tex.r * 1.2;
		}
		o.albedo = mix(o.albedo, grime_color, clamp(g * (1.0 - strip), 0.0, 0.85));
		o.rough = clamp(o.rough + g * 0.3, 0.0, 1.0);
	} else if (cls == EDGE_LIP) {
		o.albedo = wall_cap_color;
		o.rough = 0.6;
		o.metal = 0.3;
	} else {
		o.albedo = wall_outer_color;
		o.rough = 0.7;
		o.metal = 0.2;
	}

	if (track_surface_debug > 0) {
		vec3 c;
		if (track_surface_debug == 1) {
			c = vec3(fract(s / 10.0), clamp(h / 8.0, 0.0, 1.0), float(cls) / 3.0);
		} else if (track_surface_debug == 4) {
			c = mix(vec3(0.0, 0.8, 0.1), vec3(0.9, 0.05, 0.0), o.filt);
		} else {
			// The other views are about the road: the walls show their class.
			c = cls == EDGE_FACE ? vec3(0.15, 0.15, 0.2) : (cls == EDGE_LIP ? vec3(0.4) : vec3(0.05));
		}
		ALBEDO = vec3(0.0);
		ROUGHNESS = 1.0;
		METALLIC = 0.0;
		SPECULAR = 0.0;
		EMISSION = c;
	} else {
		EnvSurface e;
		e.albedo = o.albedo;
		e.roughness = o.rough;
		e.metallic = o.metal;
		e.specular = 0.5;
		e.emission = o.emission;
		e.world_pos = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
		e.world_normal = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
		e.along = along_main > 0.5 ? s : -1.0;
		e.edge = 1.0;
		e.is_wall = 1.0;
		e.keep = o.keep;
		e.recess = o.recess;
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
