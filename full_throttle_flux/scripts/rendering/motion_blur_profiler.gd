extends Node
class_name MotionBlurProfiler
## Profiling hook for MotionBlurEffect on real hardware.
## Add it anywhere in a running scene (tools/dev/mb_profile.gd does this for
## you). It turns on the effect's GPU timestamps, averages the per-pass GPU
## times plus the viewport's whole-frame GPU time, and prints a line every
## `print_every` seconds. The same "MB ..." timestamps appear in the editor's
## Debugger > Visual Profiler.
## Blur on/off and debug views are GraphicsSettings' F6 / Shift+F6; switching
## the blur starts a new averaging window so on and off never mix.

@export var print_every := 2.0

var _acc := {}
var _since := 0.0
var _vp := RID()
var _last := {}
var _blur_was := true

const SEGMENTS := [
	["prep", "MB begin", "MB prep"],
	["tile_max", "MB prep", "MB tile max"],
	["neighbour", "MB tile max", "MB neighbour max"],
	["gather", "MB neighbour max", "MB gather"],
	["total", "MB begin", "MB gather"],
]


func _ready() -> void:
	MotionBlurEffect.profile_gpu = true
	_blur_was = MotionBlurEffect.user_enabled
	_vp = get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(_vp, true)


func _exit_tree() -> void:
	MotionBlurEffect.profile_gpu = false


## Averages since the last report: {segment: ms}, plus "frame_gpu_ms",
## "frame_cpu_ms", "frames".
func report() -> Dictionary:
	return _last


func reset() -> void:
	_acc.clear()
	_since = 0.0


func _process(delta: float) -> void:
	if MotionBlurEffect.user_enabled != _blur_was:
		_blur_was = MotionBlurEffect.user_enabled
		reset()
	var rd := RenderingServer.get_rendering_device()
	if rd == null:
		return
	var ts := {}
	for i in range(rd.get_captured_timestamps_count()):
		var n := rd.get_captured_timestamp_name(i)
		if n.begins_with("MB ") and not ts.has(n):
			ts[n] = rd.get_captured_timestamp_gpu_time(i)
	for seg in SEGMENTS:
		if ts.has(seg[1]) and ts.has(seg[2]):
			_add(seg[0], float(ts[seg[2]] - ts[seg[1]]) / 1000.0)   # us -> ms
	_add("frame_gpu_ms", RenderingServer.viewport_get_measured_render_time_gpu(_vp))
	_add("frame_cpu_ms", delta * 1000.0)
	_since += delta
	if _since >= print_every:
		print("MBPROF ", JSON.stringify(flush()))


## Closes the current averaging window and returns it (see report()).
func flush() -> Dictionary:
	_last = {}
	for k in _acc:
		_last[k] = _acc[k][0] / maxf(_acc[k][1], 1.0)
	_last["frames"] = int(_acc.get("frame_cpu_ms", [0, 0])[1])
	_last["blur_on"] = MotionBlurEffect.user_enabled
	reset()
	return _last


func _add(key: String, v: float) -> void:
	var a: Array = _acc.get(key, [0.0, 0.0])
	a[0] += v
	a[1] += 1.0
	_acc[key] = a
