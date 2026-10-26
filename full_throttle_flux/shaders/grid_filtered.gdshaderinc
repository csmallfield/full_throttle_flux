// v37 filtered road/wall grid, shared by shaders/grid_shader.gdshader and the
// race-time weather wrapper shaders/env/track_surface.gdshader (v38: the
// wrapper had kept the v36 fixed-pixel grid, so every race went back to the
// aliasing grid once EnvSurfaces swapped it in). One copy, so they can't
// drift apart again.
//
// Lines have a width in METRES (line_width_m). Where a line would be thinner
// than line_scale_px pixels it's drawn at that width but dimmed to its true
// coverage, and where the cells shrink below a couple of pixels the grid
// fades into its average colour. far_glow puts back some of the distant
// brightness the aliasing used to add, without the shimmer.
// (Ben Golus, "The Best Darn Grid Shader (Yet)", 2023.)

uniform vec4 grid_color : source_color = vec4(0.0, 0.8, 1.0, 1.0);
uniform vec4 background_color : source_color = vec4(0.05, 0.05, 0.1, 1.0);
// Metres per cell (UV * 100 = metres, see TrackRoadSegment.u_distance).
uniform float grid_size : hint_range(0.1, 10.0) = 2.0;
// A major line every N cells.
uniform float major_grid_every : hint_range(1.0, 20.0) = 2.0;
// Line widths in metres.
uniform float line_width_m : hint_range(0.0, 1.0) = 0.015;
uniform float major_line_width_m : hint_range(0.0, 2.0) = 0.06;
// How strongly the lines tint the background.
uniform float minor_strength : hint_range(0.0, 1.0) = 0.3;
uniform float major_strength : hint_range(0.0, 1.0) = 0.6;
// Thinnest a line is drawn, in pixels (thinner lines are dimmed instead).
uniform float line_scale_px : hint_range(0.5, 3.0) = 1.0;
// Tint toward grid_color where the cells are too small to resolve.
uniform float far_glow : hint_range(0.0, 1.0) = 0.3;

// Coverage of grid lines (0..1) at cell coordinate `uv`; `lw` = line width
// as a fraction of a cell.
float pristine_grid(vec2 uv, vec2 lw) {
	lw = clamp(lw, vec2(0.0), vec2(1.0));
	vec4 ddxy = vec4(dFdx(uv), dFdy(uv));
	vec2 deriv = vec2(length(ddxy.xz), length(ddxy.yw)) * line_scale_px;
	bvec2 invert = greaterThan(lw, vec2(0.5));
	vec2 target = mix(lw, vec2(1.0) - lw, invert);
	vec2 draw = clamp(target, deriv, vec2(0.5));
	vec2 aa = max(deriv, vec2(0.000001)) * 1.5;
	vec2 g = abs(fract(uv) * 2.0 - 1.0);
	g = mix(vec2(1.0) - g, g, invert);
	vec2 grid2 = smoothstep(draw + aa, draw - aa, g);
	grid2 *= clamp(target / draw, 0.0, 1.0);
	grid2 = mix(grid2, target, clamp(deriv * 2.0 - 1.0, 0.0, 1.0));
	grid2 = mix(grid2, vec2(1.0) - grid2, invert);
	return mix(grid2.x, 1.0, grid2.y);
}

struct GridLook {
	vec3 color;
	float minor;   // line coverage 0..1
	float major;
};

// The grid at metres `pos` (UV * 100).
GridLook grid_look(vec2 pos) {
	GridLook g;
	vec2 cell_uv = pos / grid_size;
	float major_size = grid_size * major_grid_every;
	g.minor = pristine_grid(cell_uv, vec2(line_width_m / grid_size));
	g.major = pristine_grid(pos / major_size, vec2(major_line_width_m / major_size));
	// Cells narrower than ~2-3 px: fade toward the glow tint.
	vec2 cw = fwidth(cell_uv);
	float far = clamp(max(cw.x, cw.y) * 2.0 - 0.5, 0.0, 1.0);
	vec3 color = background_color.rgb;
	color = mix(color, grid_color.rgb, g.minor * minor_strength);
	color = mix(color, grid_color.rgb, g.major * major_strength);
	g.color = mix(color, grid_color.rgb, far * far_glow);
	return g;
}
