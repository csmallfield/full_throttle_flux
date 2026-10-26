shader_type spatial;
// Track grid (road and walls), v37: a filtered grid.
//
// v36 drew every line a fixed 1-2 PIXELS wide at any distance. Far away and
// at grazing angles that packs several lines into each pixel: moire, lines
// crawling as the camera moves, and a road that brightens toward the
// horizon. MSAA can't touch it (it only smooths geometry edges).
//
// The grid itself lives in grid_filtered.gdshaderinc (v38), shared with the
// race-time weather wrapper shaders/env/track_surface.gdshader.

#include "res://shaders/grid_filtered.gdshaderinc"

void fragment() {
	GridLook g = grid_look(UV * 100.0);
	ALBEDO = g.color;
	ROUGHNESS = 0.8;
	METALLIC = 0.0;
}
