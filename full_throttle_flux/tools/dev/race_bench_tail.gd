extends Node
## race_bench helper: runs last in every physics tick (highest
## process_physics_priority) and marks the end of the _physics_process scripts.

var bench: Node


func _physics_process(_delta: float) -> void:
	bench._scripts_done()
