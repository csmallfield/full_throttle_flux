extends Node
class_name AIShipController

## AI Ship Controller
## Main controller that orchestrates AI components and feeds inputs to a ship.
## Can control any ShipController by setting its input values directly.
## Enhanced debug visualization shows racing line and apex positions.
##
## v2 Changes:
## - Properly propagates skill level to control_decider
## - Better debug output showing hint weight and data source

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
@export_range(0.0, 1.0) var skill_level: float = 1.0

## Enable AI control (can be toggled at runtime)
@export var ai_active: bool = true

@export_group("Debug")

## Show debug visualization (target position, racing line)
@export var debug_draw_enabled: bool = false

## Print debug info to console
@export var debug_print_enabled: bool = false

## Height offset for debug target marker (makes it visible above track)
@export var debug_marker_height: float = 3.0

## Number of preview points for racing line
@export var debug_preview_points: int = 15

## Preview distance for racing line (meters)
@export var debug_preview_distance: float = 120.0

# ============================================================================
# COMPONENTS
# ============================================================================

var spline_helper: TrackSplineHelper
var line_follower: AILineFollower
var control_decider: AIControlDecider
var track_ai_data: TrackAIData

# ============================================================================
# STATE
# ============================================================================

var is_initialized: bool = false
var track_root: Node = null

# Debug visualization
var debug_target_marker: MeshInstance3D
var debug_apex_marker: MeshInstance3D
var debug_centerline_marker: MeshInstance3D
var debug_line_markers: Array[MeshInstance3D] = []
var debug_immediate_draw: ImmediateMesh
var debug_mesh_instance: MeshInstance3D

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
	# Skip if already initialized (e.g., by RaceMode)
	if is_initialized:
		return
	
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
	track_ai_data = p_track_ai_data
	
	# Create spline helper
	spline_helper = TrackSplineHelper.new(track_root)
	if not spline_helper.is_valid:
		push_error("AIShipController: Failed to initialize spline helper")
		return
	
	# Create line follower
	line_follower = AILineFollower.new()
	line_follower.skill_level = skill_level
	line_follower.initialize(spline_helper, track_ai_data)
	
	# Create control decider
	control_decider = AIControlDecider.new()
	control_decider.initialize(ship, line_follower)
	control_decider.set_skill(skill_level)  # Propagate skill to control decider
	
	# Setup debug visualization
	if debug_draw_enabled:
		_setup_debug_visualization()
	
	# Mark ship as AI controlled
	if ship:
		ship.ai_controlled = true
	
	is_initialized = true
	
	# Print initialization summary
	var data_status := "geometric fallback"
	if track_ai_data and track_ai_data.has_recorded_data():
		var best_info := track_ai_data.get_best_lap_info()
		if best_info.exists:
			data_status = "%d laps (best: %.2fs)" % [track_ai_data.recorded_laps.size(), best_info.time]
		else:
			data_status = "%d laps" % track_ai_data.recorded_laps.size()
	
	print("AIShipController: Initialized (skill: %.2f, data: %s)" % [skill_level, data_status])

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
	if control_decider:
		control_decider.set_skill(skill_level)
	
	# Print current hint weight for debugging
	if control_decider:
		print("AIShipController: Skill=%.2f, HintWeight=%.0f%%" % [skill_level, control_decider.hint_weight * 100.0])

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
	# Clean up any existing markers first
	_cleanup_debug_markers()
	
	# Target position marker (YELLOW - where AI is steering toward)
	debug_target_marker = _create_sphere_marker(Color.YELLOW, 1.0)
	debug_target_marker.name = "AITargetMarker"
	get_tree().root.add_child(debug_target_marker)
	
	# Apex marker (RED - calculated apex position)
	debug_apex_marker = _create_sphere_marker(Color.RED, 1.5)
	debug_apex_marker.name = "AIApexMarker"
	get_tree().root.add_child(debug_apex_marker)
	
	# Centerline reference marker (CYAN - centerline at target distance)
	debug_centerline_marker = _create_sphere_marker(Color.CYAN, 0.8)
	debug_centerline_marker.name = "AICenterlineMarker"
	get_tree().root.add_child(debug_centerline_marker)
	
	# Racing line preview markers (GREEN gradient)
	for i in range(debug_preview_points):
		var t: float = float(i) / float(debug_preview_points - 1)
		var color: Color = Color.GREEN.lerp(Color.LIME, t)
		var marker := _create_sphere_marker(color, 0.5)
		marker.name = "AILineMarker_%d" % i
		get_tree().root.add_child(marker)
		debug_line_markers.append(marker)
	
	# ImmediateMesh for drawing lines
	debug_immediate_draw = ImmediateMesh.new()
	debug_mesh_instance = MeshInstance3D.new()
	debug_mesh_instance.name = "AIDebugLines"
	debug_mesh_instance.mesh = debug_immediate_draw
	
	var line_material := StandardMaterial3D.new()
	line_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	line_material.albedo_color = Color.YELLOW
	line_material.vertex_color_use_as_albedo = true
	debug_mesh_instance.material_override = line_material
	
	get_tree().root.add_child(debug_mesh_instance)
	
	print("AIShipController: Debug visualization created")
	print("  RED = apex position, YELLOW = steering target")
	print("  CYAN = centerline reference, GREEN = racing line preview")

func _cleanup_debug_markers() -> void:
	"""Remove existing debug markers to prevent duplicates."""
	if debug_target_marker and is_instance_valid(debug_target_marker):
		debug_target_marker.queue_free()
		debug_target_marker = null
	if debug_apex_marker and is_instance_valid(debug_apex_marker):
		debug_apex_marker.queue_free()
		debug_apex_marker = null
	if debug_centerline_marker and is_instance_valid(debug_centerline_marker):
		debug_centerline_marker.queue_free()
		debug_centerline_marker = null
	if debug_mesh_instance and is_instance_valid(debug_mesh_instance):
		debug_mesh_instance.queue_free()
		debug_mesh_instance = null
	debug_immediate_draw = null
	
	for marker in debug_line_markers:
		if is_instance_valid(marker):
			marker.queue_free()
	debug_line_markers.clear()

func _create_sphere_marker(color: Color, radius: float) -> MeshInstance3D:
	"""Helper to create a colored sphere marker."""
	var marker := MeshInstance3D.new()
	
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	marker.mesh = sphere
	
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 2.0
	marker.material_override = material
	
	return marker

func _update_debug_visualization() -> void:
	"""Update debug visualization positions."""
	if not line_follower:
		return
	
	var target: Dictionary = line_follower.get_target_position(
		ship.velocity.length() if ship else 0.0,
		ship.get_max_speed() if ship else 100.0
	)
	
	# Update target marker (where AI is steering toward)
	if debug_target_marker and is_instance_valid(debug_target_marker):
		var target_world_pos: Vector3 = target.world_position
		target_world_pos.y += debug_marker_height
		debug_target_marker.global_position = target_world_pos
		debug_target_marker.visible = true
	
	# Update apex marker (RED - calculated apex of upcoming corner)
	if debug_apex_marker and is_instance_valid(debug_apex_marker):
		var apex_pos: Vector3 = line_follower.get_apex_world_position()
		apex_pos.y += debug_marker_height + 1.0
		debug_apex_marker.global_position = apex_pos
		# Always visible, but dim on straights
		debug_apex_marker.visible = true
		var has_corner: bool = line_follower.get_max_upcoming_curvature() > 0.1
		if debug_apex_marker.material_override:
			debug_apex_marker.material_override.emission_energy_multiplier = 3.0 if has_corner else 0.5
	
	# Update centerline reference (CYAN - shows where centerline is at the target lookahead)
	if debug_centerline_marker and is_instance_valid(debug_centerline_marker):
		var lookahead: float = target.lookahead_used if target.has("lookahead_used") else 50.0
		var centerline_pos: Vector3 = line_follower.get_centerline_position_at_distance(lookahead)
		centerline_pos.y += debug_marker_height
		debug_centerline_marker.global_position = centerline_pos
		debug_centerline_marker.visible = true
	
	# Update racing line preview
	var preview: Array[Dictionary] = line_follower.get_racing_line_preview(
		debug_preview_points,
		debug_preview_distance
	)
	
	for i in range(min(preview.size(), debug_line_markers.size())):
		var marker: MeshInstance3D = debug_line_markers[i]
		if not is_instance_valid(marker):
			continue
		var point: Dictionary = preview[i]
		var pos: Vector3 = point.world_position
		pos.y += debug_marker_height - 1.0
		marker.global_position = pos
		marker.visible = true
		
		# Highlight apex points
		if point.is_apex:
			marker.scale = Vector3(2.0, 2.0, 2.0)
		else:
			marker.scale = Vector3(1.0, 1.0, 1.0)
	
	# Draw connecting lines using ImmediateMesh
	_draw_debug_lines(target, preview)

func _draw_debug_lines(target: Dictionary, preview: Array[Dictionary]) -> void:
	"""Draw lines between debug points."""
	if not debug_immediate_draw:
		return
	
	debug_immediate_draw.clear_surfaces()
	debug_immediate_draw.surface_begin(Mesh.PRIMITIVE_LINES)
	
	# Draw line from ship to target
	if ship:
		var ship_pos: Vector3 = ship.global_position
		ship_pos.y += debug_marker_height
		var target_pos: Vector3 = target.world_position
		target_pos.y += debug_marker_height
		
		debug_immediate_draw.surface_set_color(Color.YELLOW)
		debug_immediate_draw.surface_add_vertex(ship_pos)
		debug_immediate_draw.surface_add_vertex(target_pos)
	
	# Draw racing line preview
	for i in range(preview.size() - 1):
		var p1: Vector3 = preview[i].world_position
		var p2: Vector3 = preview[i + 1].world_position
		p1.y += debug_marker_height - 1.0
		p2.y += debug_marker_height - 1.0
		
		var color: Color = Color.GREEN
		if preview[i].is_apex or preview[i + 1].is_apex:
			color = Color.RED
		
		debug_immediate_draw.surface_set_color(color)
		debug_immediate_draw.surface_add_vertex(p1)
		debug_immediate_draw.surface_add_vertex(p2)
	
	# Draw lateral offset indicator (line from centerline to racing line at target)
	if debug_centerline_marker and debug_target_marker:
		var center: Vector3 = debug_centerline_marker.global_position
		var racing: Vector3 = debug_target_marker.global_position
		
		debug_immediate_draw.surface_set_color(Color.MAGENTA)
		debug_immediate_draw.surface_add_vertex(center)
		debug_immediate_draw.surface_add_vertex(racing)
	
	debug_immediate_draw.surface_end()

func _print_debug_info() -> void:
	"""Print debug information to console."""
	if not line_follower or not control_decider:
		return
	
	var data_source := "geometric"
	if track_ai_data and track_ai_data.has_recorded_data():
		if skill_level >= 0.95 and track_ai_data.use_single_lap_for_expert:
			data_source = "SINGLE BEST LAP"
		else:
			data_source = "blended (%d laps)" % track_ai_data.recorded_laps.size()
	
	print("=== AI Debug (skill=%.2f, source=%s) ===" % [skill_level, data_source])
	print("  ", line_follower.get_debug_info())
	print("  ", control_decider.get_debug_info())
	print("  Ship speed: %.1f / %.1f (%.0f%%)" % [
		ship.velocity.length(), 
		ship.get_max_speed(),
		(ship.velocity.length() / ship.get_max_speed()) * 100.0
	])

# ============================================================================
# CLEANUP
# ============================================================================

func _exit_tree() -> void:
	_cleanup_debug_markers()
