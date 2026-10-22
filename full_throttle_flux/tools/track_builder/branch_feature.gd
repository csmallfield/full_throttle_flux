@tool
extends Node3D
class_name BranchFeature
## A split track (v34): a second route that leaves the main track and rejoins
## it, as on Fork Lab. Racers (and the AI) choose.
##
## Draw the route by hand as the BranchBase child (an OPEN Path3D) from a point
## on the main track to a later point on it. The builder snaps its ends onto
## the main track: over the first and last `junction_blend` metres the branch
## eases from the main centre line into the curve you drew, so the two roads
## split and rejoin as a Y. Keyed bank on the main track is faded out across
## both junctions (TrackJunction needs them flat and level; the validator
## checks the grade, which comes from your curves).
##
## Keys and features for the branch go under this node: BankKeys, WidthKeys
## and JumpFeatures here apply to the branch (a risky shortcut over a jump).

@export var branch_name: String = "Shortcut":
	set(v):
		branch_name = v
		_changed()
## Length over which each end eases from the main centre line into the drawn
## curve. The junction itself ends where the two centre lines are 62 m apart.
@export_range(80.0, 400.0, 5.0, "suffix:m") var junction_blend: float = 150.0:
	set(v):
		junction_blend = v
		_changed()
@export var enabled: bool = true:
	set(v):
		enabled = v
		_changed()


func base_path() -> Path3D:
	return get_node_or_null("BranchBase") as Path3D


func builder() -> Node:
	var n := get_parent()
	while n:
		if n is TrackBuilder:
			return n
		n = n.get_parent()
	return null


func _ready() -> void:
	if Engine.is_editor_hint():
		var p := base_path()
		if p and p.curve and not p.curve.changed.is_connected(_changed):
			p.curve.changed.connect(_changed)


func _changed() -> void:
	if not Engine.is_editor_hint() or not is_inside_tree():
		return
	var b := builder()
	if b:
		b.mark_dirty()
