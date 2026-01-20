extends Node
class_name AIShipController

## AI Ship Controller
## Main controller that orchestrates AI components and feeds inputs to a ship.
## Can control any ShipController by setting its input values directly.

# ============================================================================
# SIGNALS
# ============================================================================

signal ai_enabled()
signal ai_disabled()

# ============================================================================
# CONFIGURATION
# ============================================================================

@export_group("AI Settings")

## The ship this AI controls
@export var ship: ShipController

## AI skill level (0.0 = easy, 1.0 = expert)
@export_range(0.0, 1.0) var skill_level: float = 0.5

## Enable AI control (can be toggled at runtime)
@export var ai_active: bool = true

@export_group("Debug")

## Show debug visualization (target position, racing line)
@export var debug_draw_enabled: bool = false

## Print debug info to console
@export var debug_print_enabled: bool = false

## Height offset for debug target marker (makes it visible above track)
@export var debug_marker_height: float = 3.0

# ============================================================================
# COMPONENTS
# ============================================================================

var spline_helper: TrackSplineHelper
var line_follower: AILineFollower
var control_decider: AIControlDecider

# ============================================================================
# STATE
# ============================================================================

var is_initialized: bool = false
var track_root: Node = null

# Debug visualization
var debug_target_marker: MeshInstance3D

# ============================================================================
# INITIALIZATION
# ============================================================================

func _ready() -> void:
	# Wait a frame for scene to be fully loaded
	await get_tree().process_frame
	
	# Auto-initialize if ship is set
	if ship:
		_auto_initialize()

func _auto_initialize() -> void:
	"""Try to automatically find track and initialize."""
	# Find the track root (usually the parent of RaceLauncher or similar)
	track_root = _find_track_root()
	
	if track_root:
		initialize(track_root)
	else:
		push_warning("AIShipController: Could not auto-find track root. Call initialize() manually.")

func _find_track_root() -> Node:
	"""Search for the track scene in the tree."""
	# Look for common track parent patterns
	var current := get_parent()
	while current:
		# Check if this node has a Path3D child (track spline)
		for child in current.get_children():
			if child is Path3D:
				return current
			# Also check one level deeper
			for grandchild in child.get_children():
				if grandchild is Path3D:
					return child
		current = current.get_parent()
	
	# Fallback: search from root
	return _search_for_path3d(get_tree().root)

func _search_for_path3d(node: Node) -> Node:
	"""Recursively search for a node containing Path3D."""
	for child in node.get_children():
		if child is Path3D:
			return node
		var found := _search_for_path3d(child)
		if found:
			return found
	return null

func initialize(p_track_root: Node, p_track_ai_data: TrackAIData = null) -> void:
	"""
	Initialize the AI controller with a track.
	Call this after the track scene is loaded.
	"""
	track_root = p_track_root
	
	# Create spline helper
	spline_helper = TrackSplineHelper.new(track_root)
	if not spline_helper.is_valid:
		push_error("AIShipController: Failed to initialize spline helper")
		return
	
	# Create line follower
	line_follower = AILineFollower.new()
	line_follower.skill_level = skill_level
	line_follower.initialize(spline_helper, p_track_ai_data)
	
	# Create control decider
	control_decider = AIControlDecider.new()
	control_decider.initialize(ship, line_follower)
	
	# Setup debug visualization
	if debug_draw_enabled:
		_setup_debug_visualization()
	
	# Mark ship as AI controlled
	if ship:
		ship.ai_controlled = true
	
	is_initialized = true
	print("AIShipController: Initialized successfully (skill: %.2f)" % skill_level)

# ============================================================================
# MAIN UPDATE LOOP
# ============================================================================

func _physics_process(delta: float) -> void:
	if not is_initialized or not ai_active or not ship:
		return
	
	# Update line follower with current position
	line_follower.update_position(ship.global_position)
	
	# Get control decisions
	var controls := control_decider.decide_controls(delta)
	
	# Apply controls to ship
	_apply_controls(controls)
	
	# Debug
	if debug_draw_enabled:
		_update_debug_visualization()
	
	if debug_print_enabled and Engine.get_physics_frames() % 30 == 0:
		_print_debug_info()

func _apply_controls(controls: Dictionary) -> void:
	"""Apply calculated controls to the ship."""
	ship.throttle_input = controls.throttle
	ship.steer_input = controls.steer
	ship.airbrake_left = controls.airbrake_left
	ship.airbrake_right = controls.airbrake_right
	
	# Note: We don't have a brake input in the current ship controller
	# Braking is handled via reduced throttle and airbrakes

# ============================================================================
# PUBLIC API
# ============================================================================

func enable_ai() -> void:
	"""Enable AI control."""
	ai_active = true
	if ship:
		ship.ai_controlled = true
	ai_enabled.emit()
	print("AIShipController: AI enabled")

func disable_ai() -> void:
	"""Disable AI control, allow player input."""
	ai_active = false
	if ship:
		ship.ai_controlled = false
	ai_disabled.emit()
	print("AIShipController: AI disabled")

func toggle_ai() -> void:
	"""Toggle AI control on/off."""
	if ai_active:
		disable_ai()
	else:
		enable_ai()

func set_skill(new_skill: float) -> void:
	"""Update skill level at runtime."""
	skill_level = clamp(new_skill, 0.0, 1.0)
	if line_follower:
		line_follower.set_skill(skill_level)

func get_current_spline_offset() -> float:
	"""Get the AI's current position on the track (0-1)."""
	if line_follower:
		return line_follower.get_current_spline_offset()
	return 0.0

func get_distance_to_finish() -> float:
	"""Get remaining distance to complete current lap."""
	if line_follower:
		return line_follower.get_distance_to_finish()
	return 0.0

# ============================================================================
# DEBUG VISUALIZATION
# ============================================================================

func _setup_debug_visualization() -> void:
	"""Create debug visualization objects."""
	# Target position marker
	debug_target_marker = MeshInstance3D.new()
	debug_target_marker.name = "AITargetMarker"
	
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	debug_target_marker.mesh = sphere
	
	var material := StandardMaterial3D.new()
	material.albedo_color = Color.YELLOW
	material.emission_enabled = true
	material.emission = Color.YELLOW
	material.emission_energy_multiplier = 2.0
	debug_target_marker.material_override = material
	
	get_tree().root.add_child(debug_target_marker)

func _update_debug_visualization() -> void:
	"""Update debug visualization positions."""
	if not debug_target_marker or not line_follower:
		return
	
	var target: Dictionary = line_follower.get_target_position(
		ship.velocity.length() if ship else 0.0,
		ship.get_max_speed() if ship else 100.0
	)
	
	var target_world_pos: Vector3 = target.world_position
	# Add vertical offset so marker is visible above track
	target_world_pos.y += debug_marker_height
	debug_target_marker.global_position = target_world_pos

func _print_debug_info() -> void:
	"""Print debug information to console."""
	if not line_follower or not control_decider:
		return
	
	print("=== AI Debug ===")
	print("  ", line_follower.get_debug_info())
	print("  ", control_decider.get_debug_info())
	print("  Ship speed: %.1f / %.1f" % [ship.velocity.length(), ship.get_max_speed()])

# ============================================================================
# CLEANUP
# ============================================================================

func _exit_tree() -> void:
	if debug_target_marker and is_instance_valid(debug_target_marker):
		debug_target_marker.queue_free()
