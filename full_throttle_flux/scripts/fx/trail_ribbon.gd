extends MeshInstance3D
class_name TrailRibbon
## A ribbon that follows where `socket` has BEEN (v35): thrust trails and
## wingtip air streams.
##
## - Samples the socket's world position by DISTANCE (sample_spacing), with a
##   time cap for slow movement, never once per frame: frame-based samples kink
##   at low fps and bunch up at low speed.
## - Centripetal Catmull-Rom through the samples, subdivided at build time, so
##   a hard airbrake turn reads as a curve. The head is pinned to the live
##   socket so the trail never detaches from the nozzle.
## - Built every frame in world space as an ArrayMesh of centre points; the
##   shader (trail_common.gdshaderinc) turns it to face whichever camera draws.
## - Ages and lengths taper width and opacity; capped by lifetime AND metres.
##
## Driven by ShipFx: intensity, width_scale, length_scale, tint, emitting.
## Call clear() on teleports (respawn).

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
@export_range(1, 8) var subdivisions: int = 2
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

var _pos := PackedVector3Array()    # oldest first
var _time := PackedFloat64Array()
var _now: float = 0.0
var _array_mesh: ArrayMesh

# Scratch, reused every frame
var _cp := PackedVector3Array()
var _cp_age := PackedFloat32Array()
var _pts := PackedVector3Array()
var _ages := PackedFloat32Array()
var _v := PackedVector3Array()
var _n := PackedVector3Array()
var _c := PackedColorArray()
var _uv := PackedVector2Array()
var _uv2 := PackedVector2Array()
var _arrays: Array = []


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	_array_mesh = ArrayMesh.new()
	mesh = _array_mesh
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	# Points are world space and the strip grows sideways in the shader.
	extra_cull_margin = 4.0
	_arrays.resize(Mesh.ARRAY_MAX)


func clear() -> void:
	_pos.clear()
	_time.clear()
	if _array_mesh:
		_array_mesh.clear_surfaces()


func point_count() -> int:
	return _pts.size()


## World position of the newest built point (the head), for tests.
func head_position() -> Vector3:
	return _pts[0] if not _pts.is_empty() else Vector3.INF


func _process(delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	var f := Engine.get_process_frames()
	if f != _frame_usec_frame:
		_frame_usec_frame = f
		frame_usec = 0
	_now += delta
	_sample()
	_trim()
	_build()
	frame_usec += Time.get_ticks_usec() - t0


func _sample() -> void:
	if not emitting or socket == null or not is_instance_valid(socket):
		return
	var p := socket.global_position
	if not _pos.is_empty():
		var last := _pos[_pos.size() - 1]
		var d2 := p.distance_squared_to(last)
		if d2 > teleport_distance * teleport_distance:
			clear()
		elif d2 < sample_spacing * sample_spacing and _now - _time[_time.size() - 1] < max_sample_interval:
			return
	_pos.append(p)
	_time.append(_now)


func _trim() -> void:
	var life := lifetime * length_scale
	var drop := 0
	while drop < _time.size() and _now - _time[drop] > life:
		drop += 1
	if drop > 0:
		_pos = _pos.slice(drop)
		_time = _time.slice(drop)


func _build() -> void:
	var life := maxf(lifetime * length_scale, 1e-3)
	var max_len := maxf(max_length * length_scale, 0.1)

	# Control points, newest (head) first.
	_cp.clear()
	_cp_age.clear()
	var live := emitting and socket != null and is_instance_valid(socket)
	if live:
		_cp.append(socket.global_position)
		_cp_age.append(0.0)
	for i in range(_pos.size() - 1, -1, -1):
		var p := _pos[i]
		if not _cp.is_empty() and p.distance_squared_to(_cp[_cp.size() - 1]) < 1e-6:
			continue
		_cp.append(p)
		_cp_age.append(float(_now - _time[i]))
	if _cp.size() < 2 or intensity <= 0.001:
		_pts.clear()
		_array_mesh.clear_surfaces()
		return

	# Spline through the control points, cut at max_len.
	_pts.clear()
	_ages.clear()
	var n := _cp.size()
	var total := 0.0
	var prev := _cp[0]
	_pts.append(prev)
	_ages.append(_cp_age[0])
	var done := false
	for i in n - 1:
		var p1 := _cp[i]
		var p2 := _cp[i + 1]
		var p0 := _cp[i - 1] if i > 0 else p1 * 2.0 - p2
		var p3 := _cp[i + 2] if i + 2 < n else p2 * 2.0 - p1
		for s in range(1, subdivisions + 1):
			var t := float(s) / subdivisions
			var q := _catmull_rom(p0, p1, p2, p3, t) if subdivisions > 1 else p1.lerp(p2, t)
			var seg := prev.distance_to(q)
			if total + seg >= max_len:
				var k := (max_len - total) / maxf(seg, 1e-6)
				_pts.append(prev.lerp(q, k))
				_ages.append(lerpf(_cp_age[i], _cp_age[i + 1], t))
				total = max_len
				done = true
				break
			total += seg
			_pts.append(q)
			_ages.append(lerpf(_cp_age[i], _cp_age[i + 1], t))
			prev = q
		if done:
			break

	var m := _pts.size()
	if m < 2:
		_array_mesh.clear_surfaces()
		return
	var vc := m * 2
	_v.resize(vc)
	_n.resize(vc)
	_c.resize(vc)
	_uv.resize(vc)
	_uv2.resize(vc)
	var along := 0.0
	for j in m:
		if j > 0:
			along += _pts[j].distance_to(_pts[j - 1])
		var a := _pts[j - 1] if j > 0 else _pts[j]
		var b := _pts[j + 1] if j + 1 < m else _pts[j]
		var tang := a - b
		if tang.length_squared() < 1e-10:
			tang = Vector3.FORWARD
		var life01 := clampf(maxf(_ages[j] / life, along / max_len), 0.0, 1.0)
		var fade := pow(1.0 - life01, fade_power)
		if live and head_fade > 0.0:
			fade *= smoothstep(0.0, head_fade, along)
		var col := Color(tint.r, tint.g, tint.b, tint.a * intensity * fade)
		var w := lerpf(width_head, width_tail, life01) * width_scale
		var k := j * 2
		for e in 2:
			_v[k + e] = _pts[j]
			_n[k + e] = tang
			_c[k + e] = col
			_uv[k + e] = Vector2(along, -1.0 if e == 0 else 1.0)
			_uv2[k + e] = Vector2(w, life01)
	_arrays[Mesh.ARRAY_VERTEX] = _v
	_arrays[Mesh.ARRAY_NORMAL] = _n
	_arrays[Mesh.ARRAY_COLOR] = _c
	_arrays[Mesh.ARRAY_TEX_UV] = _uv
	_arrays[Mesh.ARRAY_TEX_UV2] = _uv2
	_array_mesh.clear_surfaces()
	_array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLE_STRIP, _arrays)


## Centripetal Catmull-Rom (alpha 0.5, Barry-Goldman): no cusps or loops at
## uneven sample spacing.
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
