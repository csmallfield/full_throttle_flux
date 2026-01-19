extends Node
class_name AIDebugTester

## AI Debug Tester
## Attach this to a race scene to test AI by pressing a key.
## Press F1 to toggle AI control of the player ship.
## Press F2 to cycle through skill levels.
## Press F3 to toggle debug visualization.

# ============================================================================
# CONFIGURATION
# ============================================================================

@export var ship: ShipController
@export var toggle_key: Key = KEY_F1
@export var skill_key: Key = KEY_F2
@export var debug_key: Key = KEY_F3

# ============================================================================
# STATE
# ============================================================================

var ai_controller: AIShipController
var skill_levels: Array[float] = [0.0, 0.25, 0.5, 0.75, 1.0]
var current_skill_index := 2  # Start at 0.5

# ============================================================================
# INITIALIZATION
# ============================================================================

func _ready() -> void:
	# Wait for scene to be ready
	await get_tree().process_frame
	await get_tree().process_frame
	
	# Find ship if not set
	if not ship:
		ship = _find_ship()
	
	if not ship:
		push_warning("AIDebugTester: No ship found!")
		return
	
	# Create AI controller
	_setup_ai_controller()
	
	print("===========================================")
	print("AI Debug Tester Ready!")
	print("  F1: Toggle AI control")
	print("  F2: Cycle skill level (current: %.2f)" % skill_levels[current_skill_index])
	print("  F3: Toggle debug visualization")
	print("===========================================")

func _find_ship() -> ShipController:
	"""Search for a ShipController in the scene."""
	return _find_node_of_type(get_tree().root, "ShipController") as ShipController

func _find_node_of_type(node: Node, type_name: String) -> Node:
	if node.get_class() == type_name or (node.get_script() and node.get_script().get_global_name() == type_name):
		return node
	for child in node.get_children():
		var found := _find_node_of_type(child, type_name)
		if found:
			return found
	return null

func _setup_ai_controller() -> void:
	"""Create and configure the AI controller."""
	ai_controller = AIShipController.new()
	ai_controller.name = "AIDebugController"
	ai_controller.ship = ship
	ai_controller.skill_level = skill_levels[current_skill_index]
	ai_controller.ai_active = false  # Start disabled
	ai_controller.debug_draw_enabled = false
	ai_controller.debug_print_enabled = false
	
	add_child(ai_controller)
	
	# Wait a frame then initialize
	await get_tree().process_frame
	
	# Find track root (search for node containing Path3D)
	var track_root := _find_track_root()
	if track_root:
		ai_controller.initialize(track_root)
		print("AIDebugTester: AI controller initialized with track '%s'" % track_root.name)
	else:
		push_warning("AIDebugTester: Could not find track root for AI initialization")

func _find_track_root() -> Node:
	"""Find the track scene root."""
	# Search for common track patterns
	var root := get_tree().root
	
	# Look for nodes with Path3D children
	return _find_node_with_path3d(root)

func _find_node_with_path3d(node: Node) -> Node:
	for child in node.get_children():
		if child is Path3D:
			return node
		var found := _find_node_with_path3d(child)
		if found:
			return found
	return null

# ============================================================================
# INPUT HANDLING
# ============================================================================

func _input(event: InputEvent) -> void:
	if not ai_controller:
		return
	
	if event is InputEventKey and event.pressed:
		match event.keycode:
			toggle_key:
				_toggle_ai()
			skill_key:
				_cycle_skill()
			debug_key:
				_toggle_debug()

func _toggle_ai() -> void:
	"""Toggle AI control on/off."""
	ai_controller.toggle_ai()
	
	if ai_controller.ai_active:
		print(">>> AI ENABLED (Skill: %.2f)" % ai_controller.skill_level)
	else:
		print(">>> AI DISABLED - Player control restored")

func _cycle_skill() -> void:
	"""Cycle through skill levels."""
	current_skill_index = (current_skill_index + 1) % skill_levels.size()
	var new_skill := skill_levels[current_skill_index]
	ai_controller.set_skill(new_skill)
	print(">>> AI Skill: %.2f" % new_skill)

func _toggle_debug() -> void:
	"""Toggle debug visualization."""
	ai_controller.debug_draw_enabled = not ai_controller.debug_draw_enabled
	ai_controller.debug_print_enabled = ai_controller.debug_draw_enabled
	
	if ai_controller.debug_draw_enabled:
		print(">>> Debug visualization ENABLED")
		# Re-setup debug visuals
		ai_controller._setup_debug_visualization()
	else:
		print(">>> Debug visualization DISABLED")

# ============================================================================
# HUD OVERLAY
# ============================================================================

func _process(_delta: float) -> void:
	# Could add a HUD overlay here showing AI status
	pass
