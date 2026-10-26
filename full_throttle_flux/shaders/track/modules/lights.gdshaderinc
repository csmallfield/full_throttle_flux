// v38 phase 2: guide lights in the channels and LED dots on the edge bands
// (refs 2, 5, 9: lights live in the channels, not on the plates; blue on the
// racing surface, red toward the edge).
//
// These are thin features along s, so the band lookup evaluates them for
// EVERY channel / edge band whose footprint the pixel touches (not just the
// band under the pixel centre): far away a strip narrower than a pixel
// still adds exactly its coverage, so the glow stays steady under bloom.
// Dot rows fade to a dimmed continuous strip (their duty cycle).
//
// Living lights (phase 5): dot rows and LED rows flow along the track at
// light_flow m/s, and brighter pulses run down the blue strips at
// light_pulse_speed. Both only move the filtered patterns' phase (wrapped to
// each pattern's period, so precision holds after hours of TIME): nothing
// new to alias, and a distant row is still its steady average.
//
// HDR: coverage is filtered before tonemapping, so a sub-pixel strip at full
// energy would still tonemap almost as bright as a resolved one (distant
// lights too bright, and swimming as coverage shifts). As a light shrinks
// below a few pixels its energy eases to light_far_energy, the "dimmed
// average" the design asks for.

group_uniforms lights;
uniform vec3 light_blue : source_color = vec3(0.15, 0.55, 1.0);
uniform vec3 light_red : source_color = vec3(1.0, 0.09, 0.05);
uniform vec3 light_white : source_color = vec3(1.0, 0.96, 0.9);
uniform float light_energy : hint_range(0.0, 16.0) = 3.0;
// Energy of lights too small to resolve (see above).
uniform float light_far_energy : hint_range(0.0, 16.0) = 0.8;
// Share of a channel's width the strip fills.
uniform float light_strip : hint_range(0.05, 1.0) = 0.45;
// Red channel dots.
uniform float light_dot_every : hint_range(0.2, 10.0) = 2.0;
uniform float light_dot_len : hint_range(0.02, 5.0) = 0.45;
// Edge band LED row: distance from the outer edge, dot size, spacing.
uniform float led_inset : hint_range(0.0, 3.0) = 0.45;
uniform float led_size : hint_range(0.02, 0.5) = 0.14;
uniform float led_every : hint_range(0.2, 10.0) = 1.6;
uniform float led_energy : hint_range(0.0, 16.0) = 2.0;
// Living lights (phase 5): flow along the track, m/s (0 = still).
uniform float light_flow : hint_range(0.0, 120.0) = 24.0;
// Pulses along the blue strips: speed, spacing, length, extra brightness.
uniform float light_pulse_speed : hint_range(0.0, 400.0) = 90.0;
uniform float light_pulse_every : hint_range(5.0, 500.0) = 60.0;
uniform float light_pulse_len : hint_range(0.5, 50.0) = 8.0;
uniform float light_pulse_gain : hint_range(0.0, 4.0) = 1.2;
group_uniforms;

const int LIGHT_NONE = 0;
const int LIGHT_RED_DOTS = 1;
const int LIGHT_BLUE = 2;

// Emission of a channel light in band [x0, x1] for a pixel at t.
// `dots` = the red dot row along s, `pulse` the blue strips' brightness
// (both shared by all channels, worked out once per pixel).
vec3 channel_light(int kind, float x0, float x1, float t, float fw_t, float dots, float pulse) {
	if (kind == LIGHT_NONE) {
		return vec3(0.0);
	}
	float c = (x0 + x1) * 0.5;
	float hw = (x1 - x0) * light_strip * 0.5;
	float strip = aa_pulse(c - hw, c + hw, t, fw_t);
	float energy = mix(light_energy, min(light_far_energy, light_energy), aa_fade(hw * 2.0, fw_t));
	if (kind == LIGHT_RED_DOTS) {
		return light_red * energy * strip * dots;
	}
	return light_blue * energy * strip * pulse;
}

// LED row of an edge band [x0, x1]; `outer_left` = its outer edge is x0.
// `fw` = the larger footprint (the dots are small in both directions).
vec3 edge_leds(float x0, float x1, bool outer_left, float t, float fw_t, float fw, float leds) {
	float c = outer_left ? x0 + led_inset : x1 - led_inset;
	float energy = mix(led_energy, min(light_far_energy, led_energy), aa_fade(led_size, fw));
	return light_white * energy * aa_pulse(c - led_size * 0.5, c + led_size * 0.5, t, fw_t) * leds;
}
