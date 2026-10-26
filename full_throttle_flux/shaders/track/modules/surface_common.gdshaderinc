// v38 phase 2: what every track surface module writes into. Modules never
// touch the shader's outputs: they modulate a TSurf, the main shader
// resolves it (normal from slope, Toksvig roughness, weather) once.
//
// Rules for a module (see surface_aa.gdshaderinc):
//   * derivatives come in as footprints (fw_s, fw_t, ...) computed at the
//     top of fragment(); a module never calls dFdx / fwidth itself
//   * every pattern is box-filtered and fades to its average
//   * normal detail goes into `slope` and fades BEFORE the albedo does; the
//     slope variance it loses goes into `normal_var` (roughness keeps the
//     energy: Toksvig-style)
//   * record how far it faded in `filt` (the filter-level debug view)
//   * mark recesses in `recess` (filtered coverage, like everything else)
//   * no colour in the boost pads' range (orange, about 20-40 degrees hue)

struct TSurf {
	vec3 albedo;
	float rough;
	float metal;
	vec3 emission;
	vec2 slope;        // height gradient (dh/dt, dh/ds), metres per metre
	float normal_var;  // slope variance filtered away, for roughness
	float keep;        // 0..1: how much of the look survives snow / dust
	float recess;      // 0..1: how sunken this is (channels, holes, grooves,
	                   // seams): grime and water collect here first (phase 4)
	float filt;        // 0 = full detail .. 1 = all averaged
};

void ts_filt(inout TSurf o, float f) {
	o.filt = max(o.filt, f);
}
