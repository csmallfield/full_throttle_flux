// Utopia sky, clouds at quarter resolution. See utopia_sky_common.gdshaderinc.
shader_type sky;
render_mode use_quarter_res_pass;
#define CLOUDS_LOWRES
#define CLOUD_PASS AT_QUARTER_RES_PASS
#define CLOUD_TEX QUARTER_RES_COLOR
#include "res://scenes/tracks/utopia/sky/utopia_sky_common.gdshaderinc"
