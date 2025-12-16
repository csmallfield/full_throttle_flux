@tool
extends Path3D

@export var track_width := 30.0
@export var wall_height := 8.0
@export var wall_thickness := 2.0
@export var collision_segments := 200
@export var regenerate_collision := false:
	set(value):
		if value and Engine.is_editor_hint():
			generate_collision()
			regenerate_collision = false

func generate_collision():
	# Remove ALL old collision children
	for child in get_children():
		if child.name == "TrackCollision":
			child.queue_free()
	
	if not curve or curve.get_point_count() < 2:
		print("Track: No valid curve")
		return
	
	# Create single static body for all collision
	var static_body = StaticBody3D.new()
	static_body.name = "TrackCollision"
	static_body.collision_layer = 2  # Layer 2
	static_body.collision_mask = 0   # Doesn't detect anything
	add_child(static_body)
	
	if Engine.is_editor_hint():
		static_body.owner = get_tree().edited_scene_root
	
	print("Generating track collision...")
	
	# Generate floor collision
	var floor_shape = generate_floor_mesh()
	if floor_shape:
		var floor_collision = CollisionShape3D.new()
		floor_collision.name = "FloorCollision"
		floor_collision.shape = floor_shape
		static_body.add_child(floor_collision)
		if Engine.is_editor_hint():
			floor_collision.owner = get_tree().edited_scene_root
		print("Floor collision created")
	
	# Generate wall collisions
	var left_wall_shape = generate_wall_mesh(true)
	if left_wall_shape:
		var left_collision = CollisionShape3D.new()
		left_collision.name = "LeftWallCollision"
		left_collision.shape = left_wall_shape
		static_body.add_child(left_collision)
		if Engine.is_editor_hint():
			left_collision.owner = get_tree().edited_scene_root
		print("Left wall collision created")
	
	var right_wall_shape = generate_wall_mesh(false)
	if right_wall_shape:
		var right_collision = CollisionShape3D.new()
		right_collision.name = "RightWallCollision"
		right_collision.shape = right_wall_shape
		static_body.add_child(right_collision)
		if Engine.is_editor_hint():
			right_collision.owner = get_tree().edited_scene_root
		print("Right wall collision created")
	
	print("Track collision generation complete!")

func generate_floor_mesh() -> ConcavePolygonShape3D:
	var faces = PackedVector3Array()
	var half_width = track_width / 2.0
	var length = curve.get_baked_length()
	
	for i in range(collision_segments):
		var t1 = float(i) / float(collision_segments)
		var t2 = float(i + 1) / float(collision_segments)
		
		var d1 = t1 * length
		var d2 = t2 * length
		
		var pos1 = curve.sample_baked(d1)
		var pos2 = curve.sample_baked(d2)
		
		var forward1 = (curve.sample_baked(d1 + 0.1) - pos1).normalized()
		var forward2 = (curve.sample_baked(d2 + 0.1) - pos2).normalized()
		
		var up1 = curve.sample_baked_up_vector(d1)
		var up2 = curve.sample_baked_up_vector(d2)
		
		var right1 = forward1.cross(up1).normalized()
		var right2 = forward2.cross(up2).normalized()
		
		# Four corners of this segment
		var p1_left = pos1 + right1 * -half_width
		var p1_right = pos1 + right1 * half_width
		var p2_left = pos2 + right2 * -half_width
		var p2_right = pos2 + right2 * half_width
		
		# Two triangles per segment
		# Triangle 1
		faces.append(p1_left)
		faces.append(p2_left)
		faces.append(p1_right)
		
		# Triangle 2
		faces.append(p1_right)
		faces.append(p2_left)
		faces.append(p2_right)
	
	var shape = ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	return shape

func generate_wall_mesh(is_left: bool) -> ConcavePolygonShape3D:
	var faces = PackedVector3Array()
	var half_width = track_width / 2.0
	var side = -1.0 if is_left else 1.0
	var length = curve.get_baked_length()
	
	for i in range(collision_segments):
		var t1 = float(i) / float(collision_segments)
		var t2 = float(i + 1) / float(collision_segments)
		
		var d1 = t1 * length
		var d2 = t2 * length
		
		var pos1 = curve.sample_baked(d1)
		var pos2 = curve.sample_baked(d2)
		
		var forward1 = (curve.sample_baked(d1 + 0.1) - pos1).normalized()
		var forward2 = (curve.sample_baked(d2 + 0.1) - pos2).normalized()
		
		var up1 = curve.sample_baked_up_vector(d1)
		var up2 = curve.sample_baked_up_vector(d2)
		
		var right1 = forward1.cross(up1).normalized()
		var right2 = forward2.cross(up2).normalized()
		
		# Wall positions
		var base1 = pos1 + right1 * (half_width * side)
		var top1 = base1 + up1 * wall_height
		var base2 = pos2 + right2 * (half_width * side)
		var top2 = base2 + up2 * wall_height
		
		# Two triangles for wall segment
		# Triangle 1
		faces.append(base1)
		faces.append(base2)
		faces.append(top1)
		
		# Triangle 2
		faces.append(top1)
		faces.append(base2)
		faces.append(top2)
	
	var shape = ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	return shape
