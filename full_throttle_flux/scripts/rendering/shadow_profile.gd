@tool
extends Resource
class_name ShadowProfile
## Shared directional-shadow settings (v37), applied to every shadow-casting
## DirectionalLight3D of a track when it loads (GraphicsSettings.apply_track).
## One profile for every track (resources/rendering/shadow_profile_default.tres);
## a TrackProfile can name its own (Swoopy reaches further).
##
## Cascade splits are in METRES, not the light's 0..1 fractions, so a profile
## that only changes max_distance keeps the near cascades where they were.
##
## Why the first split matters: shadow bias is scaled by each cascade's texel
## size, so the further cascades push shadows off small casters (poles,
## greebles, railings) altogether. They then "form" as they cross into the
## first cascade. v36 tracks had that boundary at 42 m (Utopia's 0.03 of
## 1400 m), which is the 50-70 m band where shadows appeared to grow in.

## Shadows end here (fading out over the last part, see fade_start).
@export_range(50.0, 4000.0, 10.0, "suffix:m") var max_distance := 1300.0
## Where cascade 1 ends / 2 ends / 3 ends.
@export_range(5.0, 2000.0, 1.0, "suffix:m") var split_1_m := 80.0
@export_range(10.0, 3000.0, 1.0, "suffix:m") var split_2_m := 230.0
@export_range(20.0, 4000.0, 1.0, "suffix:m") var split_3_m := 560.0
## Fraction of max_distance where the fade-out starts (lower = a longer,
## softer fade instead of a visible band).
@export_range(0.0, 1.0, 0.01) var fade_start := 0.65
## Blend across cascade boundaries instead of a hard step.
@export var blend_splits := true
@export_group("Bias")
## Leave each light's own bias as it is (off: use the values below).
@export var keep_light_bias := false
@export var bias := 0.04
@export var normal_bias := 1.2
## Penumbra size from the sun's angular size (PCSS); 0 = sharp edges. < 0 =
## keep the light's own value.
@export var angular_distance := -1.0
@export var shadow_blur := 1.0


## Applies the profile to one light.
func apply(light: DirectionalLight3D) -> void:
	if light == null or not light.shadow_enabled:
		return
	var md := maxf(max_distance, 1.0)
	light.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	light.directional_shadow_max_distance = md
	var s1 := clampf(split_1_m / md, 0.001, 0.999)
	var s2 := clampf(split_2_m / md, s1 + 0.001, 0.999)
	var s3 := clampf(split_3_m / md, s2 + 0.001, 0.999)
	light.directional_shadow_split_1 = s1
	light.directional_shadow_split_2 = s2
	light.directional_shadow_split_3 = s3
	light.directional_shadow_fade_start = fade_start
	light.directional_shadow_blend_splits = blend_splits
	if not keep_light_bias:
		light.shadow_bias = bias
		light.shadow_normal_bias = normal_bias
	if angular_distance >= 0.0:
		light.light_angular_distance = angular_distance
	light.shadow_blur = shadow_blur


## Applies to every shadow-casting DirectionalLight3D under `root`. Returns
## how many lights it changed.
func apply_tree(root: Node) -> int:
	var n := 0
	if root is DirectionalLight3D and (root as DirectionalLight3D).shadow_enabled:
		apply(root)
		n += 1
	for c in root.get_children():
		n += apply_tree(c)
	return n
