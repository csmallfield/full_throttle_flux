extends Node
## Autoload (v35): builds the GPUParticles3D nodes the FX need at STARTUP and
## lends them to each race.
##
## Why: GPUParticles3D's constructor draws one number from Godot's GLOBAL
## random generator to seed itself. The AI uses the global generator too
## (randf() for its line wobble, route bias, shortcut rolls), and ai_race_probe
## seeds it right before launching a race. A particle node created during race
## setup therefore shifts every AI roll after it: same handling, different
## race, and the probe checksum no longer matches. Built here, before anything
## seeds the generator, the FX leave the AI's random stream untouched.
##
## FxPools (and later the spark and weather systems) call take() / give_back().
## Running out falls back to building one on the spot, with a warning.

## Phase 2 uses 6 (carriers + puffs per look); the rest is for sparks and weather.
const COUNT := 16

static var _stash: Array[GPUParticles3D] = []
static var _built: bool = false
## Set once the autoload is going away (quit): nodes handed back after that are
## freed instead of stashed, so nothing leaks at exit.
static var _closed: bool = false


func _ready() -> void:
	build()


func _exit_tree() -> void:
	_release()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE or what == NOTIFICATION_WM_CLOSE_REQUEST:
		_release()


## Nodes still in the stash were never in the tree: free them ourselves so the
## engine doesn't report them as leaked at exit.
static func _release() -> void:
	_closed = true
	for p in _stash:
		if is_instance_valid(p):
			p.free()
	_stash.clear()


## Safe to call more than once; only the first call builds.
static func build() -> void:
	if _built:
		return
	_built = true
	for i in COUNT:
		var p := GPUParticles3D.new()
		p.emitting = false
		_stash.append(p)


static func take() -> GPUParticles3D:
	if _stash.is_empty():
		push_warning("FxPrewarm: out of prewarmed particle nodes; building one now (shifts the global RNG; raise COUNT)")
		var p := GPUParticles3D.new()
		p.emitting = false
		return p
	return _stash.pop_back()


static func give_back(p: GPUParticles3D) -> void:
	if p == null or not is_instance_valid(p):
		return
	var parent := p.get_parent()
	if parent:
		parent.remove_child(p)
	if _closed:
		p.free()
		return
	p.emitting = false
	p.process_material = null
	p.draw_pass_1 = null
	_stash.append(p)


static func available() -> int:
	return _stash.size()
