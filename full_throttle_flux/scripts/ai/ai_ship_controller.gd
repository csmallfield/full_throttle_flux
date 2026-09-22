extends Node
class_name AIShipController

## AI Ship Controller
## Main controller that orchestrates AI components and feeds inputs to a ship.
## Can control any ShipController by setting its input values directly.
## Enhanced debug visualization shows racing line and apex positions.
##
## v3 Changes:
## - Added AIShipAvoidance component for ship-to-ship avoidance
## - Avoidance adjustments applied after control decisions
## - Race position updates for position-based aggression
##
## v4 Changes:
## - BakedRacingLine + ShipPerformanceModel integration: initialize() accepts
##   a pre-baked line (RaceMode bakes once and shares it across all AIs);
##   when none is provided and auto_bake_if_missing is on, this controller
##   bakes/loads-from-cache itself (covers time trial testing and the offline tools)
## - Brake output from the decider is now real: the decider merges braking
##   into both airbrake channels (the only actual brake in this physics),
##   and _apply_controls forwards them unchanged

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

## Enable ship avoidance behavior
@export var avoidance_enabled: bool = true

## If initialize() receives no baked racing line, bake one here (or load it
## from the user:// cache). RaceMode passes a shared line, so this mainly
## serves standalone use (time trial AI testing, tools/).
@export var auto_bake_if_missing: bool = true

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
var ship_avoidance: AIShipAvoidance  # NEW: Avoidance component
var baked_line: BakedRacingLine  # v4: optimized line + speed profile
var perf_model: ShipPerformanceModel  # v4: honest ship limits

# ============================================================================
# STATE
# ============================================================================

var is_initialized: bool = false
var track_root: Node = null

# Race position (updated by RaceMode)
var current_race_position: int = 1
var total_race_ships: int = 1

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

func initialize(p_track_root: Node, p_baked_line: BakedRacingLine = null) -> void:
	"""
	Initialize the AI controller with a track.
	Call this after the track scene is loaded.
	RaceMode passes a shared BakedRacingLine; standalone users can rely on
	auto_bake_if_missing (cached after the first bake).
	"""
	track_root = p_track_root
	baked_line = p_baked_line
	
	# Create spline helper
	spline_helper = TrackSplineHelper.new(track_root)
	if not spline_helper.is_valid:
		push_error("AIShipController: Failed to initialize spline helper")
		return
	
	# Performance model from the ship's real profile (honest limits)
	if ship and ship.profile:
		perf_model = ShipPerformanceModel.new(ship.profile)
	else:
		perf_model = null
		push_warning("AIShipController: no ship profile - perf model unavailable, speed targets will use legacy heuristics")
	
	# LINE PRECEDENCE -- a trained line for THIS ship's profile always wins.
	#
	# v15 only looked for a trained line when the caller passed none. RaceMode
	# always passes its own shared bake, so in an actual race the trained and
	# assembled lines were never loaded at all: every AI drove a fresh default
	# bake with default controller params and no style gains. The training
	# tools were measuring an AI that never appeared in the game.
	line_source = ""
	if prefer_trained_line and ship and ship.profile:
		var trained := AILineTrainer.load_trained_line(_guess_track_id(), ship.profile.ship_id)
		if trained != null:
			baked_line = trained
			var current_hash := ship.profile.handling_hash()
			if trained.profile_hash.is_empty():
				line_source = "TRAINED (unverified: predates handling hash)"
			elif trained.profile_hash != current_hash:
				line_source = "TRAINED (STALE: handling changed since training)"
				push_warning("AIShipController: trained line for %s on %s was trained on handling %s, ship is now %s - retrain it" % [
					ship.profile.ship_id, _guess_track_id(), trained.profile_hash, current_hash])
			else:
				line_source = "TRAINED"
	if line_source.is_empty() and baked_line != null:
		line_source = "shared bake (untrained)" if prefer_trained_line else "passed line (tools)"
	
	# Self-bake if no line was provided (cache makes repeats near-free)
	if baked_line == null and auto_bake_if_missing and ship and ship.profile:
		var world: World3D = ship.get_world_3d()
		if world:
			var baker := AIRacingLineBaker.new()
			baked_line = baker.bake(spline_helper, ship.profile, world, _guess_track_id())
			if baked_line != null:
				line_source = "self bake (untrained)"
	if baked_line == null:
		line_source = "centreline fallback (no line)"
	
	# Create line follower
	line_follower = AILineFollower.new()
	line_follower.skill_level = skill_level
	line_follower.initialize(spline_helper, baked_line, perf_model)
	
	# Create control decider
	control_decider = AIControlDecider.new()
	control_decider.initialize(ship, line_follower, perf_model)
	control_decider.set_skill(skill_level)
	
	# Create avoidance component (NEW)
	if avoidance_enabled:
		ship_avoidance = AIShipAvoidance.new()
		ship_avoidance.initialize(ship, skill_level)
	
	# Setup debug visualization
	if debug_draw_enabled:
		_setup_debug_visualization()
	
	# Mark ship as AI controlled
	if ship:
		ship.ai_controlled = true
	
	is_initialized = true
	
	# Print initialization summary
	var avoidance_status := "enabled" if avoidance_enabled else "disabled"
	var ship_id: String = ship.profile.ship_id if ship and ship.profile else "?"
	print("AIShipController: %s on %s -> line: %s (skill %.2f, avoidance %s)" % [
		ship_id, _guess_track_id(), line_source, skill_level, avoidance_status])

## Vary the controller's technique around the lap from the baked line's style
## gains. A no-op when the line carries none, which is the case for any line
## that has not been through tools/style_search.
func _apply_style_gains() -> void:
	if baked_line == null or not baked_line.has_style_gains():
		return
	var offset: float = line_follower.current_spline_offset
	control_decider.max_corner_airbrake = baked_line.get_style_airbrake_at(offset)
	control_decider.corner_steer_reserve = baked_line.get_style_reserve_at(offset)
	control_decider.steering_sensitivity = baked_line.get_style_sensitivity_at(offset)
	line_follower.baked_steer_lookahead_max = baked_line.get_style_lookahead_at(offset)
	if control_decider.perf_model:
		control_decider.perf_model.corner_airbrake_application = \
				control_decider.max_corner_airbrake

## When true (the default, and what races want), a trained line for this
## ship's profile replaces whatever line the caller passed. The offline tools
## MUST set this false: they pass the exact line they are testing, and v16/v17
## silently swapped it for the existing trained line -- whose per-sample style
## gains then overwrote four of the style parameters under test every frame.
@export var prefer_trained_line: bool = true

## Where this AI's racing line came from. Shown by the debug spectator so it
## is never ambiguous which AI you are watching.
var line_source: String = ""


func _guess_track_id() -> String:
	"""Stable track id for the bake cache and trained-line lookup.

	Uses the scene file name, not the root node name: several tracks in this
	project share a root node name (see AILineTrainer.track_id_for).
	"""
	return AILineTrainer.track_id_for(track_root)

# ============================================================================
# RACE SHIP REGISTRATION (Called by RaceMode)
# ============================================================================

func set_race_ships(ships: Array[ShipController]) -> void:
	"""
	Register all ships in the race for avoidance awareness.
	Call this from RaceMode after spawning all ships.
	"""
	if ship_avoidance:
		ship_avoidance.set_race_ships(ships)
	total_race_ships = ships.size()

func update_race_position(position: int, total: int = -1) -> void:
	"""
	Update this AI's race position for aggression scaling.
	Call this from RaceMode's position tracking.
	"""
	current_race_position = position
	if total > 0:
		total_race_ships = total
	
	if ship_avoidance:
		ship_avoidance.update_race_position(position, total_race_ships)

# ============================================================================
# MAIN UPDATE LOOP
# ============================================================================

func _physics_process(delta: float) -> void:
	if not is_initialized or not ai_active or not ship:
		return
	
	# Update line follower with current position
	line_follower.update_position(ship.global_position)
	
	# Apply per-sample style gains before deciding, so the controller uses
	# the technique that measured fastest for THIS part of the track.
	_apply_style_gains()
	
	# Get base control decisions (racing line following)
	var controls := control_decider.decide_controls(delta)
	
	# Apply avoidance adjustments (NEW)
	if ship_avoidance and avoidance_enabled:
		ship_avoidance.update(delta)
		controls = ship_avoidance.adjust_controls(controls)
	
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
	
	# Braking is executed through the airbrake channels: the decider merges
	# its brake command into BOTH airbrakes (dual airbrakes are the only real
	# brake in this ship physics). controls.brake is kept for telemetry.

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
	if ship_avoidance:
		ship_avoidance.set_skill(skill_level)
	
	# Print current hint weight for debugging
	if control_decider:
		print("AIShipController: Skill=%.2f, HintWeight=%.0f%%" % [skill_level, control_decider.hint_weight * 100.0])

func set_avoidance_enabled(enabled: bool) -> void:
	"""Enable or disable ship avoidance at runtime."""
	avoidance_enabled = enabled
	
	if enabled and not ship_avoidance and ship:
		ship_avoidance = AIShipAvoidance.new()
		ship_avoidance.initialize(ship, skill_level)

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

func is_avoiding_ship() -> bool:
	"""Check if AI is currently making avoidance maneuvers."""
	if ship_avoidance:
		return ship_avoidance.is_avoiding()
	return false

func get_nearest_ship_distance() -> float:
	"""Get distance to nearest other ship."""
	if ship_avoidance:
		return ship_avoidance.get_nearest_ship_distance()
	return INF

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
	
	var data_source := line_source
	
	print("=== AI Debug (skill=%.2f, source=%s) ===" % [skill_level, data_source])
	print("  ", line_follower.get_debug_info())
	print("  ", control_decider.get_debug_info())
	if ship_avoidance:
		print("  ", ship_avoidance.get_debug_info())
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
