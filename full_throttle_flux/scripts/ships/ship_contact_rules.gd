extends RefCounted
class_name ShipContactRules
## v34: the ship-to-ship contact response, as pure rules on two ShipControllers.
## Host-independent: the central ShipContactResolver calls this once per
## touching pair per tick. The legacy per-ship path in ShipController is kept
## only as a fallback (FTF_CONTACT=legacy) and does NOT use these rules.
##
## All numbers come from the ships' profiles (mass, exchange, restitution ramp,
## yaw gain, tangent damping, lean push). See ShipProfile "Ship Collision".
##
## Conventions: `n` is the unit contact normal from B to A, already projected
## into the shared track plane (the resolver never produces a vertical
## component, so the hover spring is never fought). `point` is the contact
## point in world space, `depth` the planar penetration in metres.

## Minimum |closing| for a "hit" (feedback + yaw) as opposed to touching.
const TOUCH_SPEED := 1.0

## Resolve one touching pair. `fresh` is true on the first tick of a contact
## episode: only then does a hit twitch the hulls (a ship pressing into another
## for several ticks keeps closing a little each tick through grip, and
## re-kicking it every tick spun ships into the wall). Returns the closing
## speed (>= 0) of the hit for feedback, or 0.0 when only touching.
static func resolve(a: ShipController, b: ShipController, n: Vector3, point: Vector3,
		depth: float, dt: float, fresh: bool) -> float:
	var pa: ShipProfile = a.profile
	var pb: ShipProfile = b.profile
	var ma: float = maxf(pa.mass, 0.01)
	var mb: float = maxf(pb.mass, 0.01)
	var wa: float = 1.0 / ma
	var wb: float = 1.0 / mb
	var wsum: float = wa + wb

	# --- Position: share the separation by inverse mass (the heavy ship moves less).
	if depth > 0.0:
		var corr: float = depth * 0.5 * (pa.ship_collision_separation + pb.ship_collision_separation)
		a.global_position += n * corr * (wa / wsum)
		b.global_position -= n * corr * (wb / wsum)

	var rel: Vector3 = a.velocity - b.velocity
	var closing: float = rel.dot(n)   # negative = A moving into B
	var hit_speed := 0.0

	# --- Normal impulse: a FRACTION of the closing speed, with restitution that
	# ramps in from zero so a brush doesn't bounce and a hit does.
	if closing < -TOUCH_SPEED:
		var speed: float = -closing
		var e_lo: float = 0.5 * (pa.ship_collision_bounce_from + pb.ship_collision_bounce_from)
		var e_hi: float = 0.5 * (pa.ship_collision_bounce_full + pb.ship_collision_bounce_full)
		var ramp: float = clampf((speed - e_lo) / maxf(e_hi - e_lo, 0.01), 0.0, 1.0)
		var e: float = 0.5 * (pa.ship_collision_restitution + pb.ship_collision_restitution) * ramp
		var k: float = 0.5 * (pa.ship_collision_exchange + pb.ship_collision_exchange)
		var j: float = (1.0 + e) * speed * k / wsum   # impulse magnitude (mass units)
		var cap: float = minf(pa.ship_collision_max_impulse, pb.ship_collision_max_impulse)
		j = minf(j, cap / maxf(wa, wb))              # cap the larger velocity change
		a.velocity += n * (j * wa)
		b.velocity -= n * (j * wb)
		_allow_overspeed(a)
		_allow_overspeed(b)

		hit_speed = speed
	
	# --- Angular, on the impact tick only: lever arm from each ship's centre
	# to the contact point, about its own up. Off-centre hits twitch the hull;
	# the roll spring and the driver's steering then have to catch it.
	if fresh and hit_speed > 0.0:
		var speed: float = hit_speed
		var k: float = 0.5 * (pa.ship_collision_exchange + pb.ship_collision_exchange)
		var j: float = speed * k / wsum
		var up_a: Vector3 = a.global_transform.basis.y
		var up_b: Vector3 = b.global_transform.basis.y
		var ra: Vector3 = point - a.global_position
		var rb: Vector3 = point - b.global_position
		var ia: float = ma * pa.ship_collision_yaw_radius * pa.ship_collision_yaw_radius
		var ib: float = mb * pb.ship_collision_yaw_radius * pb.ship_collision_yaw_radius
		a.contact_yaw_rate += pa.ship_collision_yaw_gain * ra.cross(n * j).dot(up_a) / ia
		b.contact_yaw_rate += pb.ship_collision_yaw_gain * rb.cross(-n * j).dot(up_b) / ib
		a.contact_yaw_rate = clampf(a.contact_yaw_rate, -pa.ship_collision_yaw_max, pa.ship_collision_yaw_max)
		b.contact_yaw_rate = clampf(b.contact_yaw_rate, -pb.ship_collision_yaw_max, pb.ship_collision_yaw_max)

	# --- While touching: damp relative TANGENTIAL velocity in the track plane,
	# so side-by-side ships lean on each other instead of bouncing, ...
	if depth > 0.0:
		var up: Vector3 = (a.global_transform.basis.y + b.global_transform.basis.y).normalized()
		var vt: Vector3 = rel - n * closing
		vt -= up * vt.dot(up)
		var damp: float = 0.5 * (pa.ship_collision_tangent_damping + pb.ship_collision_tangent_damping)
		var f: float = 1.0 - exp(-damp * dt)
		var jt: Vector3 = vt * f / wsum
		a.velocity -= jt * wa
		b.velocity += jt * wb

		# ... and let the ship on the throttle LEAN on the other: it nudges the
		# leader forward a little and pays for it with drag of its own.
		for pair in [[a, b, -n], [b, a, n]]:
			var pusher: ShipController = pair[0]
			var other: ShipController = pair[1]
			var into: Vector3 = pair[2]           # direction from pusher toward other
			var fwd: Vector3 = -pusher.global_transform.basis.z
			var lean: float = fwd.dot(into)       # 1 = pushing straight into them
			if lean < 0.3 or pusher.throttle_input < 0.05:
				continue
			var pp: ShipProfile = pusher.profile
			var gain: float = pp.ship_collision_push_gain * pusher.throttle_input * lean
			var thrust: float = pusher.get_thrust_power()
			var m_ratio: float = pp.mass / maxf(other.profile.mass, 0.01)
			other.velocity += into * (gain * thrust * m_ratio * dt)
			var drag: float = pp.ship_collision_push_drag * lean * dt
			var s: float = pusher.velocity.length()
			if s > drag:
				pusher.velocity *= (s - drag) / s
	return hit_speed

## A hit can put a ship over max_speed. Hand the excess to the soft limiter's
## overspeed allowance so it bleeds off at overspeed_damping instead of being
## clamped away next tick (which would make the hit ship feel glued).
static func _allow_overspeed(s: ShipController) -> void:
	var over: float = s.velocity.length() - s.get_max_speed()
	if over > s.get_boost_overspeed():
		s.set_boost_overspeed(over)
