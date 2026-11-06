// Surface mask: one or two tiling textures combined into one value per pixel,
// which each band turns into roughness, metallic and specular by its own
// amount. It doesn't depend on the profile, so a zone blend still samples it
// only once. High tier only: the low tier has no texture lookups here.
//
// The result is centred on the mask's mean, so it's the same on average whether
// the texture is resolved or filtered flat: mipmaps can't shift the far road,
// and the low tier (no detail, delta 0) matches the high tier's overall look.
// mask_bias is the one deliberate overall shift, applied in both tiers.
//
// A TrackSurfaceMask writes all of these, so edit a recipe rather than these.

group_uniforms mask;
// 0 off, 1 A only, 2 A x B, 3 B masks A (B scales how much A shows).
uniform int mask_mode = 0;
uniform sampler2D mask_a : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D mask_b : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
// Which channel to read, as a unit vector.
uniform vec4 mask_a_channel = vec4(1.0, 0.0, 0.0, 0.0);
uniform vec4 mask_b_channel = vec4(1.0, 0.0, 0.0, 0.0);
// Metres per tile (across, along) and offset in metres (across, along).
uniform vec2 mask_a_tile = vec2(7.3, 7.3);
uniform vec2 mask_b_tile = vec2(31.0, 31.0);
uniform vec2 mask_a_offset = vec2(0.0);
uniform vec2 mask_b_offset = vec2(0.0);
// The texture channel's average (TrackSurfaceMask measures it).
uniform float mask_a_mean = 0.5;
uniform float mask_b_mean = 0.5;
uniform float mask_contrast = 1.0;
uniform float mask_bias = 0.0;
// What a full mask does to a band with mask amount 1.
uniform float mask_rough = 0.0;
uniform float mask_metal = 0.0;
uniform float mask_spec = 0.0;
group_uniforms;

// A tile length along the path snapped so the lap is a whole number of tiles:
// no jump in the pattern at the start line.
vec2 mask_tile(vec2 tile, float path_len) {
	vec2 t = max(tile, vec2(0.01));
	if (path_len > 0.0) {
		t.y = path_len / max(1.0, round(path_len / t.y));
	}
	return t;
}

float mask_layer(sampler2D tex, vec4 channel, vec2 tile, vec2 offset, vec2 st, vec2 dx, vec2 dy) {
	return dot(textureGrad(tex, (st + offset) / tile, dx / tile, dy / tile), channel);
}

// The mask at (t, s), centred on its mean. `dx`, `dy` = screen gradients of (t, s).
float surface_mask(float t, float s, vec2 dx, vec2 dy, float fw, float path_len) {
	vec2 st = vec2(t, s);
	vec2 tile_a = mask_tile(mask_a_tile, path_len);
	float a = mask_layer(mask_a, mask_a_channel, tile_a, mask_a_offset, st, dx, dy);
	float v = a;
	float mean = mask_a_mean;
	float size = min(tile_a.x, tile_a.y);
	if (mask_mode >= 2) {
		vec2 tile_b = mask_tile(mask_b_tile, path_len);
		float b = mask_layer(mask_b, mask_b_channel, tile_b, mask_b_offset, st, dx, dy);
		size = min(size, min(tile_b.x, tile_b.y));
		if (mask_mode == 2) {
			v = a * b;
			mean = mask_a_mean * mask_b_mean;
		} else {
			v = mask_a_mean + (a - mask_a_mean) * b;
		}
	}
	// Contrast goes back to 1 as the texture's features shrink below a pixel:
	// clipping filtered values would no longer average out.
	float c = mix(mask_contrast, 1.0, aa_fade(size / 16.0, fw));
	return clamp((v - mean) * c, -mean, 1.0 - mean);
}
