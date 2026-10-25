extends Resource
class_name FxSettings
## Environment FX quality and per-ship level of detail (v35).
##
## One shared instance: FxSettings.active(). FX ask it two things:
##   pick(low, medium, high)       a budget for the current quality tier
##   lod_for(ship, camera)         how much this ship gets this frame
## The camera's own target always gets FULL, so the player never loses detail.

enum Quality { LOW, MEDIUM, HIGH }

## FULL = everything, NEAR = trails + dust, FAR = thrust glow only, OFF = nothing.
enum Lod { FULL, NEAR, FAR, OFF }

const SAVE_PATH := "user://fx_settings.tres"

@export var quality: Quality = Quality.HIGH

@export_group("LOD distances (metres from the camera, HIGH quality)")
## Inside this: NEAR (the camera target is always FULL).
@export var near_distance: float = 80.0
## Inside this: FAR.
@export var far_distance: float = 250.0
## Beyond this: OFF.
@export var off_distance: float = 700.0

static var _active: FxSettings


static func active() -> FxSettings:
	if _active == null:
		if ResourceLoader.exists(SAVE_PATH):
			_active = load(SAVE_PATH) as FxSettings
		if _active == null:
			_active = FxSettings.new()
	return _active


func save() -> void:
	ResourceSaver.save(self, SAVE_PATH)


## The value for the current quality tier.
func pick(low: Variant, medium: Variant, high: Variant) -> Variant:
	match quality:
		Quality.LOW:
			return low
		Quality.MEDIUM:
			return medium
	return high


## LOD distances shrink on lower tiers.
func distance_scale() -> float:
	return float(pick(0.5, 0.75, 1.0))


func lod_for(ship: Node3D, camera: Camera3D) -> Lod:
	if ship == null:
		return Lod.OFF
	if camera == null:
		return Lod.NEAR
	if "ship" in camera and camera.get("ship") == ship:
		return Lod.FULL
	var d := ship.global_position.distance_to(camera.global_position)
	var s := distance_scale()
	if d < near_distance * s:
		return Lod.NEAR
	if d < far_distance * s:
		return Lod.FAR
	if d < off_distance * s:
		return Lod.FAR if quality == Quality.HIGH else Lod.OFF
	return Lod.OFF
