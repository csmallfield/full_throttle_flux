extends RefCounted
class_name ShipVisuals

## TEMPORARY -- swaps a ship's visual model for a ShipVisualPool variant.
##
## Call on a freshly instantiated ship BEFORE add_child(), so that
## ShipController._find_child_nodes() caches the new ShipMesh in _ready().
## Calling it later still works (ship_mesh is reassigned), but logs a warning
## because the first frames will have run on the old mesh.

const MESH_NODE := "ShipMesh"


## Replaces the ship's ShipMesh with a clean identity pivot holding `variant`.
## The old ShipMesh -- including its transform -- is discarded, so the variant
## scene must carry its own scale and placement. Returns false and leaves the
## ship untouched if anything is wrong.
static func swap_mesh(ship: Node, variant: PackedScene) -> bool:
	if ship == null or variant == null:
		return false
	
	var model := variant.instantiate() as Node3D
	if model == null:
		push_warning("ShipVisuals: %s is not a Node3D scene" % variant.resource_path)
		return false
	
	if ship.is_inside_tree():
		push_warning("ShipVisuals: swapping mesh on %s after add_child(); swap before adding it" % ship.name)
	
	var index := -1
	var old := ship.get_node_or_null(MESH_NODE)
	if old:
		index = old.get_index()
		ship.remove_child(old)
		old.free()
	
	var pivot := Node3D.new()
	pivot.name = MESH_NODE
	pivot.add_child(model)
	ship.add_child(pivot)
	if index >= 0:
		ship.move_child(pivot, index)
	
	# Only matters if called late; before _ready() this is overwritten with
	# the same node anyway.
	if ship is ShipController:
		(ship as ShipController).ship_mesh = pivot
	
	return true
