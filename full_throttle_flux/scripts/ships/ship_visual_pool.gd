@tool
extends Resource
class_name ShipVisualPool

## TEMPORARY -- random visual variants for one ship profile.
##
## Lives OUTSIDE ShipProfile on purpose: ShipProfile.handling_hash() fingerprints
## every bool/int/float on the profile, so adding even an `enabled` flag there
## would change default_racer's hash and orphan every trained line and recording.
##
## Loaded by convention from
##     res://resources/ships/visual_pools/<ship_id>_visuals.tres
## If that file is missing or `enabled` is off, ships spawn exactly as before.
##
## To retire this feature: untick `enabled`, or delete the .tres.

## Master switch. Off = every ship uses the ShipMesh baked into its scene.
@export var enabled: bool = true

## Wrapper scenes, one per model. Each wrapper's ROOT should be a Node3D at
## identity; put scale, offset and orientation on its child. ShipController
## overwrites the ShipMesh pivot's position and rotation every frame, so any
## transform that isn't below the pivot is lost.
## Listing a scene twice doubles its share of the grid.
@export var variants: Array[PackedScene] = []

## 0 = new shuffle every race. Any other value gives the same model order
## every race -- handy for comparing screenshots or captures.
@export var fixed_seed: int = 0


func is_usable() -> bool:
	if not enabled:
		return false
	for v in variants:
		if v != null:
			return true
	return false
