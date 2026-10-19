// Utopia sky, clouds at half resolution. See utopia_sky_common.gdshaderinc.
shader_type sky;
render_mode use_half_res_pass;
#define CLOUDS_LOWRES
#define CLOUD_PASS AT_HALF_RES_PASS
#define CLOUD_TEX HALF_RES_COLOR
#include "res://scenes/tracks/utopia/sky/utopia_sky_common.gdshaderinc"
