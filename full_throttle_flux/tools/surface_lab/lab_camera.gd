extends Node3D
## Surface Lab cameras, all along the track's MainSpline:
##   FLY    free: hold the right mouse button to look, WASD + Q/E to move,
##          Shift for fast, the wheel changes speed
##   GLIDE  the chase pose sliding round the lap at a set speed, no physics
##   CHASE  a real AI ship on its trained line with the game's chase camera

enum Mode { FLY, GLIDE, CHASE }

const SHIP_PROFILE := "res://resources/ships/default_racer.tres"

var track: Node
var spline: Path3D
var mode := Mode.GLIDE
var glide_speed := 60.0
var glide_paused := false
var d := 200.0
var fly_speed := 30.0
## The circuits' road sits off their spline by groundGeo's transform
## (EnvironmentState.road_xf); identity on builder tracks.
var road_xf := Transform3D.IDENTITY

var cam: Camera3D
var _chase: Node3D
var _chase_ship: Node3D
var _looking := false
var _yaw := 0.0
var _pitch := 0.0
var _d_wait := 0.0


func setup(p_track: Node, p_spline: Path3D) -> void:
	track = p_track
	spline = p_spline
	cam = Camera3D.new()
	cam.far = 4000.0
	cam.near = 0.3
	cam.fov = 80.0
	add_child(cam)
	cam.make_current()
	_place_pose(d)


func length() -> float:
	return spline.curve.get_baked_length()


func set_mode(m: Mode) -> void:
	if m == mode:
		return
	_looking = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if mode == Mode.CHASE:
		_stop_chase()
		cam.make_current()
	if m == Mode.FLY:
		var e := cam.global_transform.basis.get_euler()
		_pitch = e.x
		_yaw = e.y
	mode = m
	if m == Mode.CHASE:
		_start_chase()


## Moves the view to `to` metres along the lap.
func jump(to: float) -> void:
	if mode == Mode.CHASE:
		set_mode(Mode.GLIDE)
	d = fposmod(to, length())
	_place_pose(d)
	if mode == Mode.FLY:
		var e := cam.global_transform.basis.get_euler()
		_pitch = e.x
		_yaw = e.y


func _process(delta: float) -> void:
	match mode:
		Mode.GLIDE:
			if not glide_paused:
				d = fposmod(d + glide_speed * delta, length())
			_place_pose(d)
		Mode.FLY:
			_fly(delta)
			_track_d(delta, cam.global_position)
		Mode.CHASE:
			if is_instance_valid(_chase_ship):
				_track_d(delta, _chase_ship.global_position)


## The distance along the lap nearest `pos`, ten times a second.
func _track_d(delta: float, pos: Vector3) -> void:
	_d_wait -= delta
	if _d_wait <= 0.0:
		_d_wait = 0.1
		d = spline.curve.get_closest_offset(spline.global_transform.affine_inverse() * (road_xf.affine_inverse() * pos))


func _place_pose(at: float) -> void:
	var curve := spline.curve
	var frame := func(x: float) -> Transform3D:
		return road_xf * spline.global_transform * TrackRoadSegment.frame_at(curve, fposmod(x, curve.get_baked_length()))
	var here: Transform3D = frame.call(at)
	var pos: Vector3 = (frame.call(at - 9.0) as Transform3D).origin + here.basis.y * 3.2
	var target: Vector3 = (frame.call(at + 25.0) as Transform3D).origin + here.basis.y * 1.0
	cam.global_transform = Transform3D(Basis.looking_at(target - pos, here.basis.y), pos)


func _fly(delta: float) -> void:
	if not _looking:
		return
	var dir := Vector3.ZERO
	dir.z += float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W))
	dir.x += float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A))
	dir.y += float(Input.is_physical_key_pressed(KEY_E)) - float(Input.is_physical_key_pressed(KEY_Q))
	var fast := 4.0 if Input.is_physical_key_pressed(KEY_SHIFT) else 1.0
	cam.global_position += cam.global_transform.basis * dir.normalized() * fly_speed * fast * delta


func is_looking() -> bool:
	return _looking


## From the lab: the 3D view's own input (the UI hasn't taken the event).
func view_input(event: InputEvent) -> void:
	if mode != Mode.FLY:
		return
	var b := event as InputEventMouseButton
	if b:
		if b.button_index == MOUSE_BUTTON_RIGHT:
			_looking = b.pressed
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if b.pressed else Input.MOUSE_MODE_VISIBLE
		elif b.pressed and b.button_index == MOUSE_BUTTON_WHEEL_UP:
			fly_speed = minf(fly_speed * 1.25, 400.0)
		elif b.pressed and b.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			fly_speed = maxf(fly_speed / 1.25, 2.0)
	var m := event as InputEventMouseMotion
	if m and _looking:
		_yaw -= m.relative.x * 0.003
		_pitch = clampf(_pitch - m.relative.y * 0.003, -1.5, 1.5)
		cam.global_transform.basis = Basis.from_euler(Vector3(_pitch, _yaw, 0.0))


## As gfx_bench: one AI ship on the trained line, the real chase camera.
func _start_chase() -> void:
	var track_id := AILineTrainer.track_id_for(track)
	var profile := load(SHIP_PROFILE) as ShipProfile
	var line := ResourceLoader.load(AILineTrainer.trained_path(track_id, profile.ship_id), "",
			ResourceLoader.CACHE_MODE_IGNORE) as BakedRacingLine
	_chase = Node3D.new()
	add_child(_chase)
	var ship := AILineTrainer.spawn_ship(profile)
	_chase.add_child(ship)
	_chase_ship = ship
	var grid := track.find_child("StartingGrid", true, false)
	if grid and grid.has_method("get_pole_position"):
		ship.global_transform = grid.get_pole_position()
	ship.ai_controlled = true
	var ai := AIShipController.new()
	ai.ship = ship
	ai.skill_level = 1.0
	ai.avoidance_enabled = false
	_chase.add_child(ai)
	ai.prefer_trained_line = false
	if line:
		ai.initialize(track, line)
	var chase_cam: AGCamera2097 = (load("res://scripts/ag_camera_2097.gd") as GDScript).new()
	chase_cam.intro_enabled = false
	_chase.add_child(chase_cam)
	chase_cam.ship = ship
	ship.camera = chase_cam
	if chase_cam.has_method("set_track"):
		chase_cam.call("set_track", track)
	chase_cam.make_current()


func _stop_chase() -> void:
	if is_instance_valid(_chase):
		_chase.queue_free()
	_chase = null
	_chase_ship = null
