extends Node
class_name ShipContactResolver
## v34: central ship-to-ship contact resolver.
##
## Ships no longer collide with each other inside move_and_slide() (layer 2 is
## removed from their mask, see ShipController._setup_ship_collision_layer).
## Instead this node runs once per physics tick AFTER every ship has moved
## (process_physics_priority 100) and resolves every touching pair with
## ShipContactRules: symmetric, order-independent, both ships displaced.
##
## Self-installing: ShipController._ready() calls ensure(); the first ship in a
## tree creates the resolver under the root. Ships are found through the
## "ship_contacts" group, so every mode and headless tool is covered with no
## wiring. Stateless apart from per-pair "touching" flags (for one feedback
## event per contact episode).
##
## FTF_CONTACT=legacy in the environment keeps the old per-ship impulse path
## (ships collide in move_and_slide again) for A/B runs of the probes.

const GROUP := "ship_contacts"
const NODE_NAME := "ShipContactResolver"

static var _mode_checked := false
static var _legacy := false

## True when the legacy per-ship path is active instead of this resolver.
static func legacy_mode() -> bool:
	if not _mode_checked:
		_mode_checked = true
		_legacy = OS.get_environment("FTF_CONTACT") == "legacy"
	return _legacy

static var _instance: ShipContactResolver = null

static func ensure(tree: SceneTree) -> ShipContactResolver:
	if legacy_mode() or tree == null:
		return null
	# Several ships become ready in the same frame, before a deferred
	# add_child lands, so the guard is a static reference, not a tree lookup.
	if is_instance_valid(_instance):
		return _instance
	var r := ShipContactResolver.new()
	r.name = NODE_NAME
	_instance = r
	tree.root.add_child.call_deferred(r)
	return r

static func current() -> ShipContactResolver:
	return _instance if is_instance_valid(_instance) else null

## Capsule per ship: [radius, half-segment length, local centre, local axis].
var _capsules: Dictionary = {}
## "idA:idB" -> true while the pair is touching.
var _touching: Dictionary = {}
## Stats for probes.
var contacts_total := 0
var hits_total := 0
var max_hit_speed := 0.0

func _ready() -> void:
	process_physics_priority = 100
	process_mode = Node.PROCESS_MODE_ALWAYS

func _physics_process(delta: float) -> void:
	var nodes := get_tree().get_nodes_in_group(GROUP)
	var ships: Array[ShipController] = []
	for n in nodes:
		if n is ShipController and n.is_inside_tree() and n.profile != null:
			ships.append(n)
	if ships.size() < 2:
		return
	var seen := {}
	for i in ships.size():
		for j in range(i + 1, ships.size()):
			var a := ships[i]
			var b := ships[j]
			var key := "%d:%d" % [a.get_instance_id(), b.get_instance_id()]
			seen[key] = true
			var c := _test_pair(a, b)
			if c.is_empty():
				_touching.erase(key)
				continue
			var was: bool = _touching.get(key, false)
			_touching[key] = true
			contacts_total += 1 if not was else 0
			var hit: float = ShipContactRules.resolve(a, b, c.normal, c.point, c.depth, delta, not was)
			if hit > 0.0:
				max_hit_speed = maxf(max_hit_speed, hit)
			# One feedback event per episode, on the first hit of the episode.
			if hit > 0.0 and not was:
				hits_total += 1
				var min_fb: float = minf(a.profile.ship_collision_feedback_min_speed,
						b.profile.ship_collision_feedback_min_speed)
				if hit >= min_fb:
					a.notify_ship_contact(b, hit)
					b.notify_ship_contact(a, hit)
	# Prune pairs of freed ships.
	for key in _touching.keys():
		if not seen.has(key):
			_touching.erase(key)

## True while the pair was touching at the last resolve.
func is_touching(a: ShipController, b: ShipController) -> bool:
	return _touching.get("%d:%d" % [a.get_instance_id(), b.get_instance_id()], false) \
			or _touching.get("%d:%d" % [b.get_instance_id(), a.get_instance_id()], false)

func _capsule(s: ShipController) -> Array:
	var id := s.get_instance_id()
	if _capsules.has(id):
		return _capsules[id]
	var found: Array = [1.0, 2.0, Vector3.ZERO, Vector3.FORWARD]
	for child in s.get_children():
		if child is CollisionShape3D and child.shape is CapsuleShape3D:
			var cs: CollisionShape3D = child
			var cap: CapsuleShape3D = cs.shape
			var t: Transform3D = cs.transform
			var axis: Vector3 = t.basis.y
			var axis_scale: float = axis.length()
			var radial_scale: float = 0.5 * (t.basis.x.length() + t.basis.z.length())
			found = [cap.radius * radial_scale, maxf(cap.height * 0.5 - cap.radius, 0.0) * axis_scale,
					t.origin, axis.normalized()]
			break
	_capsules[id] = found
	return found

## Capsule-capsule overlap in world space. Returns {} or {normal, point, depth}
## with the normal from B to A projected into the shared track plane.
func _test_pair(a: ShipController, b: ShipController) -> Dictionary:
	var ca := _capsule(a)
	var cb := _capsule(b)
	var ta: Transform3D = a.global_transform
	var tb: Transform3D = b.global_transform
	var axa: Vector3 = ta.basis * ca[3]
	var axb: Vector3 = tb.basis * cb[3]
	var oa: Vector3 = ta * ca[2]
	var ob: Vector3 = tb * cb[2]
	var pa0: Vector3 = oa - axa * ca[1]
	var pa1: Vector3 = oa + axa * ca[1]
	var pb0: Vector3 = ob - axb * cb[1]
	var pb1: Vector3 = ob + axb * cb[1]
	# Cheap reject: bounding spheres.
	var reach: float = ca[1] + ca[0] + cb[1] + cb[0]
	if oa.distance_squared_to(ob) > reach * reach:
		return {}
	var cp := _closest_points(pa0, pa1, pb0, pb1)
	var qa: Vector3 = cp[0]
	var qb: Vector3 = cp[1]
	var d: Vector3 = qa - qb
	var rsum: float = ca[0] + cb[0]
	if d.length_squared() >= rsum * rsum:
		return {}
	var up: Vector3 = (ta.basis.y + tb.basis.y).normalized()
	var dp: Vector3 = d - up * d.dot(up)
	var n: Vector3
	if dp.length() < 0.05:
		# Stacked or dead-centre: separate sideways relative to A.
		n = ta.basis.x
		n -= up * n.dot(up)
		n = n.normalized()
		if (qa - qb).dot(n) < 0.0:
			n = -n
	else:
		n = dp.normalized()
	var depth: float = rsum - dp.length()
	var point: Vector3 = qb + d * (cb[0] / rsum)
	return {"normal": n, "point": point, "depth": depth}

## Closest points between segments p0-p1 and q0-q1 (Ericson 5.1.9).
static func _closest_points(p0: Vector3, p1: Vector3, q0: Vector3, q1: Vector3) -> Array:
	var d1 := p1 - p0
	var d2 := q1 - q0
	var r := p0 - q0
	var a := d1.dot(d1)
	var e := d2.dot(d2)
	var f := d2.dot(r)
	var s := 0.0
	var t := 0.0
	if a <= 1e-6 and e <= 1e-6:
		return [p0, q0]
	if a <= 1e-6:
		t = clampf(f / e, 0.0, 1.0)
	else:
		var c := d1.dot(r)
		if e <= 1e-6:
			s = clampf(-c / a, 0.0, 1.0)
		else:
			var bb := d1.dot(d2)
			var denom := a * e - bb * bb
			if denom > 1e-6:
				s = clampf((bb * f - c * e) / denom, 0.0, 1.0)
			t = (bb * s + f) / e
			if t < 0.0:
				t = 0.0
				s = clampf(-c / a, 0.0, 1.0)
			elif t > 1.0:
				t = 1.0
				s = clampf((bb - c) / a, 0.0, 1.0)
	return [p0 + d1 * s, q0 + d2 * t]
