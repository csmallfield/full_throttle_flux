extends RefCounted
class_name GreebleUpright
## Upright and surface offset for greeble rules (v36). Shared by
## TrackGreebles (Track Builder tracks) and UtopiaZoneDresser (the circuits),
## so a rule means the same on both.
##
## Frames here are a rule's INWARD frame: +Y = road normal, +X = toward the
## track centre, -Z along the track (the right-hand side is turned 180° about
## Y). Pieces turn about their attachment point (the origin).

## Unit normal of the surface a layer sits on: + = away from it.
static func surface_normal(layer: String, inward: Basis) -> Vector3:
	match layer:
		"wall_face":
			return inward.x.normalized()      # the inner face looks at the track
		"outside":
			return -inward.x.normalized()     # the outer face looks away from it
	return inward.y.normalized()


## The up the rule aims for, before the upright blend: world up, or the road's
## up with only its bank or only its slope removed.
static func target_up(axes: String, n: Vector3, along: Vector3) -> Vector3:
	match axes:
		"bank":
			# Keep the slope: the up of a level-banked frame along the track.
			var right := along.cross(Vector3.UP)
			if right.length_squared() < 0.0001:
				return n
			return right.normalized().cross(along).normalized()
		"slope":
			# Keep the bank: drop the part of the normal that leans along the
			# horizontal direction of travel.
			var h := Vector3(along.x, 0.0, along.z)
			if h.length_squared() < 0.0001:
				return n
			h = h.normalized()
			var u := n - h * n.dot(h)
			return u.normalized() if u.length_squared() > 0.0001 else n
	return Vector3.UP


## [ok, basis] for a rule: `inward` turned toward the rule's upright target.
## ok = false when the road tilts past upright_limit_deg from the target (or
## is upside down): leave the piece out.
static func orient(rule: UtopiaGreebleRule, inward: Basis) -> Array:
	if rule.upright <= 0.0 or rule.layer == "overhead":
		return [true, inward]
	var n := inward.y.normalized()
	if n.dot(Vector3.UP) <= 0.0 and rule.upright_axes != "slope":
		return [false, inward]
	var target := target_up(rule.upright_axes, n, -inward.z.normalized())
	if rad_to_deg(n.angle_to(target)) > rule.upright_limit_deg:
		return [false, inward]
	var u := n.slerp(target, rule.upright).normalized()
	if n.angle_to(u) < 0.0001:
		return [true, inward]
	return [true, Basis(Quaternion(n, u)) * inward]


## How far to sink a piece (along its new up) so that no corner of its base
## (the mesh's footprint at y = 0) sits above the surface plane through the
## attachment point. `b` is the final, scaled basis; `n` the surface's up
## before upright.
static func embed_depth(b: Basis, aabb: AABB, n: Vector3) -> float:
	var up := b.y.normalized()
	var k := up.dot(n)
	if k < 0.05:
		return 0.0
	var worst := 0.0
	for x: float in [aabb.position.x, aabb.end.x]:
		for z: float in [aabb.position.z, aabb.end.z]:
			worst = maxf(worst, (b * Vector3(x, 0.0, z)).dot(n))
	return worst / k
