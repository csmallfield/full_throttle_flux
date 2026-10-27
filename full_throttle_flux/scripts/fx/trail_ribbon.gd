extends MeshInstance3D
class_name TrailRibbon
## A ribbon that follows where `socket` has BEEN (v35): thrust trails and
## wingtip air streams.
##
## - Samples the socket's world position by DISTANCE (sample_spacing), with a
##   time cap for slow movement, never once per frame: frame-based samples kink
##   at low fps and bunch up at low speed.
## - Centripetal Catmull-Rom through the samples, subdivided, so a hard
##   airbrake turn reads as a curve. The head is pinned to the live socket so
##   the trail never detaches from the nozzle.
## - Ages and lengths taper width and opacity; capped by lifetime AND metres.
##
## v38.1: built on the GPU. v35 rebuilt every ribbon's spline and ArrayMesh in
## GDScript every frame (measured 3.3 ms/frame for a full grid's 32 ribbons on
## a Xeon W-2265, the largest single cost of the race). Now each ribbon keeps
## its samples in a ring buffer and writes them, plus a small header, into its
## row of one shared float texture; all ribbons draw one shared static strip
## and the vertex shader (trail_common.gdshaderinc) does the spline, widths,
## fade and tangent. Per frame the CPU writes ~20 floats per ribbon and
## uploads the texture once. The socket is read where it is DRAWN (the ships
## are physics-interpolated since v37.1).
##
## Driven by ShipFx: intensity, width_scale, length_scale, tint, emitting.
## Call clear() on teleports (respawn).

## Ring buffer size (samples). Samples past the visible length are dropped,
## so this covers the longest trail (air streams: 70 m at 2.5 m spacing).
const MAX_SAMPLES := 48
## Header texels per row; must match trail_common.gdshaderinc.
const HEADER := 5
const ROW_TEXELS := HEADER + MAX_SAMPLES * 2
## Points per spline segment in the shared strip (subdivisions is capped).
const MAX_SUBDIVISIONS := 2

## What the trail follows.
var socket: Node3D

@export_group("Shape")
## Metres. Hard cap on trail length (scaled by length_scale).
@export var max_length: float = 30.0
## Seconds a sample lives (scaled by length_scale).
@export var lifetime: float = 0.45
## Metres between samples.
@export var sample_spacing: float = 1.5
## Seconds: take a sample at least this often, even when barely moving.
@export var max_sample_interval: float = 0.05
## Points inserted between samples by the spline (1 = straight segments).
@export_range(1, 2) var subdivisions: int = 2
@export var width_head: float = 0.55
@export var width_tail: float = 0.1
## Opacity falloff exponent toward the tail (1 = linear).
@export var fade_power: float = 2.2
## Metres over which the head fades in, so it doesn't start as a hard cut.
@export var head_fade: float = 0.5
## A jump bigger than this between two samples is a teleport: start over.
@export var teleport_distance: float = 40.0

# --- Driven every frame by ShipFx -------------------------------------------
var intensity: float = 1.0
var width_scale: float = 1.0
var length_scale: float = 1.0
var tint := Color.WHITE
## False = stop sampling and let the trail age out (head detaches).
var emitting: bool = true

## Profiling: microseconds spent in _process by ALL ribbons this frame.
static var frame_usec: int = 0
static var _frame_usec_frame: int = -1


## Every ribbon's row, the texture they are uploaded to, and the strip they
## all draw. One per process; uploaded just before each frame is drawn. Each
## ribbon writes its own row (a member array, so writes stay in place: packed
## arrays are copy-on-write) and flush() stitches them together natively.
class Store:
	var owners: Array = []     # TrailRibbon or null, by row
	var tex := ImageTexture.new()
	var tex_rows := 0
	var mesh: ArrayMesh
	var materials: Array[Material] = []
	var _empty := PackedFloat32Array()

	func _init() -> void:
		mesh = _strip()
		_empty.resize(ROW_TEXELS * 4)
		RenderingServer.frame_pre_draw.connect(flush)

	func alloc(owner: Node) -> int:
		var row := owners.find(null)
		if row < 0:
			row = owners.size()
			owners.append(owner)
		else:
			owners[row] = owner
		return row

	func release(row: int) -> void:
		owners[row] = null

	func use_material(m: Material) -> void:
		if m is ShaderMaterial and not materials.has(m):
			materials.append(m)
			(m as ShaderMaterial).set_shader_parameter("trail_data", tex)

	func flush() -> void:
		var rows := owners.size()
		if rows == 0:
			return
		var all := PackedFloat32Array()
		for o in owners:
			all.append_array(o._row_data if o != null and is_instance_valid(o) else _empty)
		var img := Image.create_from_data(ROW_TEXELS, rows, false, Image.FORMAT_RGBAF, all.to_byte_array())
		if rows != tex_rows:
			tex.set_image(img)
			tex_rows = rows
		else:
			tex.update(img)

	## Every point of the longest trail twice; UV.x = point index, UV.y = edge.
	static func _strip() -> ArrayMesh:
		var points := MAX_SAMPLES * MAX_SUBDIVISIONS + 1
		var v := PackedVector3Array()
		var n := PackedVector3Array()
		var c := PackedColorArray()
		var uv := PackedVector2Array()
		var uv2 := PackedVector2Array()
		for p in points:
			for edge in [-1.0, 1.0]:
				v.append(Vector3.ZERO)
				n.append(Vector3.FORWARD)
				c.append(Color.WHITE)
				uv.append(Vector2(p, edge))
				uv2.append(Vector2.ZERO)
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = v
		arrays[Mesh.ARRAY_NORMAL] = n
		arrays[Mesh.ARRAY_COLOR] = c
		arrays[Mesh.ARRAY_TEX_UV] = uv
		arrays[Mesh.ARRAY_TEX_UV2] = uv2
		var m := ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLE_STRIP, arrays)
		return m

static var _store: Store

# The ring buffer, also kept here for trimming and the CPU reference.
var _pos := PackedVector3Array()
var _time := PackedFloat64Array()
var _odo := PackedFloat64Array()
var _count := 0
var _newest := -1
var _now: float = 0.0
var _row := -1
## This ribbon's row of the shared texture (see Store).
var _row_data := PackedFloat32Array()
var _head := Vector3.INF
var _has_head := false
var _live := false


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	if _store == null:
		_store = Store.new()
	_row_data.resize(ROW_TEXELS * 4)
	_row = _store.alloc(self)
	mesh = _store.mesh
	_store.use_material(material_override)
	set_instance_shader_parameter("trail_row", float(_row))
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_pos.resize(MAX_SAMPLES)
	_time.resize(MAX_SAMPLES)
	_odo.resize(MAX_SAMPLES)
	visible = false


func _exit_tree() -> void:
	if _store and _row >= 0:
		_store.release(_row)
		_row = -1


func _enter_tree() -> void:
	if _store and _row < 0 and is_node_ready():
		_row = _store.alloc(self)
		set_instance_shader_parameter("trail_row", float(_row))


func clear() -> void:
	_count = 0
	_newest = -1
	_head = Vector3.INF


## Built points, head first (CPU reference of what the shader draws; for
## tests and the debug overlay).
func trail_points() -> PackedVector3Array:
	var out := PackedVector3Array()
	var m := _ctrl_count()
	if m < 2 or intensity <= 0.001:
		return out
	var sub := clampi(subdivisions, 1, MAX_SUBDIVISIONS)
	var max_len := maxf(max_length * length_scale, 0.1)
	for q in (m - 1) * sub + 1:
		var i := mini(q / sub, m - 1)
		var s := q - i * sub
		var p: Vector3
		if s == 0 or i >= m - 1:
			p = _ctrl(i)
		else:
			var p1 := _ctrl(i)
			var p2 := _ctrl(i + 1)
			var p0 := _ctrl(i - 1) if i > 0 else p1 * 2.0 - p2
			var p3 := _ctrl(i + 2) if i + 2 < m else p2 * 2.0 - p1
			p = _catmull_rom(p0, p1, p2, p3, float(s) / sub)
		var along := lerpf(_ctrl_along(i), _ctrl_along(mini(i + 1, m - 1)), float(s) / sub)
		if along > max_len:
			break
		out.append(p)
	return out


func point_count() -> int:
	return trail_points().size()


## World position of the head the shader was last given (the live socket).
func head_position() -> Vector3:
	return _head if _has_head else (_pos[_newest] if _count > 0 else Vector3.INF)


func _process(delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	var f := Engine.get_process_frames()
	if f != _frame_usec_frame:
		_frame_usec_frame = f
		frame_usec = 0
	_now += delta
	_live = emitting and socket != null and is_instance_valid(socket)
	var at := socket.get_global_transform_interpolated().origin if _live else Vector3.ZERO
	if _live:
		_sample(at)
	_trim()
	_write(at)
	frame_usec += Time.get_ticks_usec() - t0


func _sample(p: Vector3) -> void:
	var odo := 0.0
	if _count > 0:
		var last := _pos[_newest]
		var d2 := p.distance_squared_to(last)
		if d2 > teleport_distance * teleport_distance:
			clear()
		elif d2 < sample_spacing * sample_spacing and _now - _time[_newest] < max_sample_interval:
			return
		else:
			odo = _odo[_newest] + sqrt(d2)
	_newest = (_newest + 1) % MAX_SAMPLES
	_count = mini(_count + 1, MAX_SAMPLES)
	_pos[_newest] = p
	_time[_newest] = _now
	_odo[_newest] = odo
	var o := (HEADER + _newest * 2) * 4
	_row_data[o] = p.x
	_row_data[o + 1] = p.y
	_row_data[o + 2] = p.z
	_row_data[o + 3] = _now
	_row_data[o + 4] = odo


## Drop samples past their life, and those beyond the visible length (one is
## kept past it so the spline still reaches the end).
func _trim() -> void:
	var life := lifetime * length_scale
	var max_len := max_length * length_scale
	while _count > 0:
		var oldest := (_newest - _count + 1 + MAX_SAMPLES) % MAX_SAMPLES
		if _now - _time[oldest] > life:
			_count -= 1
			continue
		if _count >= 2:
			var second := (oldest + 1) % MAX_SAMPLES
			if _odo[_newest] - _odo[second] >= max_len:
				_count -= 1
				continue
		break


func _write(head: Vector3) -> void:
	_has_head = _live and (_count == 0 or head.distance_squared_to(_pos[_newest]) >= 1e-6)
	_head = head
	var show := intensity > 0.001 and _ctrl_count() >= 2
	if show != visible:
		visible = show
	if not show:
		return
	var life := maxf(lifetime * length_scale, 1e-3)
	var max_len := maxf(max_length * length_scale, 0.1)
	var head_odo := 0.0
	if _count > 0:
		head_odo = _odo[_newest] + (head.distance_to(_pos[_newest]) if _has_head else 0.0)
	_row_data[0] = head.x
	_row_data[1] = head.y
	_row_data[2] = head.z
	_row_data[3] = (1.0 if _has_head else 2.0) if _live else 0.0
	_row_data[4] = tint.r
	_row_data[5] = tint.g
	_row_data[6] = tint.b
	_row_data[7] = tint.a * intensity
	_row_data[8] = _now
	_row_data[9] = 1.0 / life
	_row_data[10] = 1.0 / max_len
	_row_data[11] = width_scale
	_row_data[12] = _count
	_row_data[13] = maxi(_newest, 0)
	_row_data[14] = clampi(subdivisions, 1, MAX_SUBDIVISIONS)
	_row_data[15] = head_odo
	_row_data[16] = width_head
	_row_data[17] = width_tail
	_row_data[18] = fade_power
	_row_data[19] = head_fade
	# Culling: the strip's vertices are made in the shader, so say where it is.
	var c := head if _has_head else _pos[_newest]
	var r := max_len + maxf(width_head, width_tail) * width_scale + 1.0
	custom_aabb = AABB(c - Vector3(r, r, r), Vector3(r, r, r) * 2.0)


func _ctrl_count() -> int:
	return _count + (1 if _has_head else 0)


## Control point k, head first.
func _ctrl(k: int) -> Vector3:
	if _has_head:
		if k == 0:
			return _head
		k -= 1
	return _pos[(_newest - k + MAX_SAMPLES) % MAX_SAMPLES]


## Distance of control point k from the head.
func _ctrl_along(k: int) -> float:
	if _count == 0:
		return 0.0
	var head_odo := _odo[_newest] + (_head.distance_to(_pos[_newest]) if _has_head else 0.0)
	if _has_head:
		if k == 0:
			return 0.0
		k -= 1
	return head_odo - _odo[(_newest - k + MAX_SAMPLES) % MAX_SAMPLES]


## Centripetal Catmull-Rom (alpha 0.5, Barry-Goldman): no cusps or loops at
## uneven sample spacing. trail_common.gdshaderinc has the same.
static func _catmull_rom(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: float) -> Vector3:
	var t0 := 0.0
	var t1 := t0 + maxf(sqrt(p0.distance_to(p1)), 1e-4)
	var t2 := t1 + maxf(sqrt(p1.distance_to(p2)), 1e-4)
	var t3 := t2 + maxf(sqrt(p2.distance_to(p3)), 1e-4)
	var tt := lerpf(t1, t2, t)
	var a1 := p0 * ((t1 - tt) / (t1 - t0)) + p1 * ((tt - t0) / (t1 - t0))
	var a2 := p1 * ((t2 - tt) / (t2 - t1)) + p2 * ((tt - t1) / (t2 - t1))
	var a3 := p2 * ((t3 - tt) / (t3 - t2)) + p3 * ((tt - t2) / (t3 - t2))
	var b1 := a1 * ((t2 - tt) / (t2 - t0)) + a2 * ((tt - t0) / (t2 - t0))
	var b2 := a2 * ((t3 - tt) / (t3 - t1)) + a3 * ((tt - t1) / (t3 - t1))
	return b1 * ((t2 - tt) / (t2 - t1)) + b2 * ((tt - t1) / (t2 - t1))
