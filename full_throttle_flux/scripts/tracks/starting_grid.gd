@tool
extends Node3D
class_name StartingGrid

## Starting Grid Component
## Place as child of track scene. Add Marker3D children for grid positions.
## The mode controller uses this to position ships at race start.

# ============================================================================
# CONFIGURATION
# ============================================================================

@export_group("Grid Setup")

## Grid formation pattern
enum GridFormation { SINGLE_FILE, STAGGERED, SIDE_BY_SIDE }
@export var formation: GridFormation = GridFormation.SINGLE_FILE

## Spacing between grid slots (meters)
@export var slot_spacing: float = 15.0

## Lateral offset for staggered formation
@export var stagger_offset: float = 3.0

# ============================================================================
# GRID SLOTS
# ============================================================================

## Returns the transform for a given grid position (0-indexed)
## Position 0 = pole position (first place)
func get_start_transform(position_index: int) -> Transform3D:
	var slots = _get_slot_markers()
	
	# If we have manually placed markers, use them
	if position_index < slots.size():
		return slots[position_index].global_transform
	
	# Otherwise, generate position procedurally
	return _generate_slot_transform(position_index)

## Returns how many grid positions are available
func get_grid_capacity() -> int:
	var manual_slots = _get_slot_markers().size()
	if manual_slots > 0:
		return manual_slots
	# Default capacity if no manual slots
	return 8

## Returns the pole position (first place start)
func get_pole_position() -> Transform3D:
	return get_start_transform(0)

# ============================================================================
# INTERNAL
# ============================================================================

func _get_slot_markers() -> Array[Marker3D]:
	var markers: Array[Marker3D] = []
	for child in get_children():
		if child is Marker3D:
			markers.append(child)
	# Sort by name (Slot1, Slot2, etc.) or by position
	markers.sort_custom(_sort_by_name)
	return markers

func _sort_by_name(a: Marker3D, b: Marker3D) -> bool:
	return a.name.naturalnocasecmp_to(b.name) < 0

func _generate_slot_transform(index: int) -> Transform3D:
	var local_pos := Vector3.ZERO
	
	match formation:
		GridFormation.SINGLE_FILE:
			local_pos.z = index * slot_spacing
		GridFormation.STAGGERED:
			local_pos.z = index * slot_spacing
			local_pos.x = stagger_offset if index % 2 == 1 else -stagger_offset
		GridFormation.SIDE_BY_SIDE:
			var row = index / 2
			var side = index % 2
			local_pos.z = row * slot_spacing
			local_pos.x = stagger_offset if side == 1 else -stagger_offset
	
	var slot_transform = global_transform
	slot_transform.origin += global_transform.basis * local_pos
	return slot_transform

# ============================================================================
# EDITOR VISUALIZATION
# ============================================================================

func _ready() -> void:
	if Engine.is_editor_hint():
		_update_debug_visuals()

func _update_debug_visuals() -> void:
	# Could add editor gizmos here in the future
	pass
