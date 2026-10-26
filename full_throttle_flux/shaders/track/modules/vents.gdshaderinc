// v38 phase 2: vents. Boxes of transverse louvre slots in a plate band.
// Until the phase 3 zone strip places them, a hash does: one chance per
// vent_every metres of path. The slots repeat along s, the axis that
// compresses most, so they're the first thing to fade to their average.

group_uniforms vents;
uniform float vent_every : hint_range(20.0, 1000.0) = 140.0;
// Share of those stretches that get a vent.
uniform float vent_chance : hint_range(0.0, 1.0) = 0.55;
uniform float vent_length : hint_range(1.0, 20.0) = 5.0;
uniform float vent_width : hint_range(1.0, 20.0) = 7.0;
uniform float vent_slot_pitch : hint_range(0.05, 1.0) = 0.3;
uniform float vent_slot : hint_range(0.01, 0.9) = 0.14;
uniform float vent_frame : hint_range(0.0, 0.5) = 0.12;
uniform vec3 vent_frame_color : source_color = vec3(0.34, 0.35, 0.37);
uniform vec3 vent_slot_color : source_color = vec3(0.012, 0.012, 0.014);
// Faint heat in the slots (red, clear of the boost pads' orange).
uniform vec3 vent_glow : source_color = vec3(0.9, 0.1, 0.04);
// Off by default (the doc calls it optional). It fades out with the slots:
// averaged from afar, a glowing box reads as a solid red pad, a gameplay
// marker, which the surface must never look like.
uniform float vent_glow_energy : hint_range(0.0, 4.0) = 0.0;
group_uniforms;

// `u` metres from the band's left edge, `w` the band width.
void vents(inout TSurf o, float u, float w, float s, float fw_t, float fw_s, float seed_v) {
	float z = floor(s / vent_every);
	if (env_hash(vec2(z, 41.3 + seed_v)) > vent_chance) {
		return;
	}
	float s0 = z * vent_every + env_hash(vec2(z, 7.9 + seed_v)) * (vent_every - vent_length);
	float c = w * 0.5;
	float hw = min(vent_width, w - 1.0) * 0.5;
	float box = aa_pulse(s0, s0 + vent_length, s, fw_s) * aa_pulse(c - hw, c + hw, u, fw_t);
	if (box <= 0.0) {
		return;
	}
	float inner = aa_pulse(s0 + vent_frame, s0 + vent_length - vent_frame, s, fw_s)
			* aa_pulse(c - hw + vent_frame, c + hw - vent_frame, u, fw_t);
	float f;
	float slot = aa_lines(s - s0, vent_slot_pitch, vent_slot, fw_s, f) * inner;
	ts_filt(o, f * inner);
	vec3 col = mix(vent_frame_color, vent_slot_color, slot);
	o.albedo = mix(o.albedo, col, box);
	o.rough = mix(o.rough, mix(0.35, 0.9, slot), box);
	o.metal = mix(o.metal, mix(0.7, 0.1, slot), box);
	o.emission += vent_glow * vent_glow_energy * slot * (1.0 - f);
	o.keep = max(o.keep, box * 0.6);
	o.recess = max(o.recess, slot);
}
