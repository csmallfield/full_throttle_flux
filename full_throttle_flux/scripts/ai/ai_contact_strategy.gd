extends RefCounted
class_name AIContactStrategy
## v34: traffic as strategy. Replaces AIShipAvoidance (kept for A/B under
## FTF_AI_CONTACT=legacy).
##
## Works in spline space: for every other ship it knows the gap along the
## track, the lateral gap, the closing rate and a time-to-collision, and it
## commits to an INTENT for a while so the ship reads as making choices
## rather than twitching:
##
##   FOLLOW    hold the baked line; lift only when the ship ahead is a TTC away
##   OVERTAKE  pick the side with the most room at the next corner, go there
##   DEFEND    a faster ship is coming: cover its side once per straight
##   SHOVE     alongside into a corner with the other ship on the outside:
##             lean on it (the resolver's lateral push does the rest)
##   YIELD     something much faster is arriving: give it the line
##   RECOVER   just been hit: line only until the twitch has settled
##
## It never steers. It biases the LATERAL TARGET the line follower aims at
## (clamped to the measured corridor) and caps the target speed; the existing
## decider does the driving, so there is one controller per axis.

enum Intent { FOLLOW, OVERTAKE, DEFEND, SHOVE, YIELD, RECOVER }
const NAMES := ["FOLLOW", "OVERTAKE", "DEFEND", "SHOVE", "YIELD", "RECOVER"]

# --- Perception ---
var horizon_time: float = 1.5           ## seconds of look-ahead along the track
var lane_width: float = 6.0             ## |lateral gap| within which a ship is "in my way"
var hull_gap: float = 4.6               ## lateral spacing to pass at (two hulls + margin)

# --- Behaviour ---
var follow_ttc: float = 1.1             ## lift when TTC to the ship ahead is below this
var shove_max_closing: float = 6.0      ## only shove a ship running at our speed
var yield_speed_margin: float = 1.02    ## yield only to a ship faster than our class
var overtake_ttc: float = 1.6           ## consider passing when TTC is below this
var overtake_min_closing: float = 3.0   ## ... and we close at least this fast
var overtake_commit: float = 1.2        ## minimum seconds in OVERTAKE
var overtake_stall: float = 3.0         ## give up after this long without gaining
var overtake_cooldown: float = 2.0
var defend_ttc: float = 1.6
var defend_hold: float = 2.0
var defend_cooldown: float = 6.0
var defend_min_corner_distance: float = 60.0   ## never start a block into a braking zone
var shove_window: Vector2 = Vector2(30.0, 120.0)  ## corner-distance window for a shove
var shove_hold: float = 1.2
var shove_cooldown: float = 5.0
var shove_overlap: float = 1.6          ## how far into the other hull we aim
var yield_closing: float = 25.0
var recover_time: float = 1.0
var recover_yaw: float = 0.3
var bias_rate: float = 7.0              ## m/s the lateral bias may move
var bias_rate_shove: float = 5.0        ## slower into a shove: a lean, not a hit

# --- Personality (0..1), layered under skill ---
var aggression: float = 0.5
var patience: float = 0.5
var risk: float = 0.5
var skill_level: float = 1.0

# --- Wiring ---
var ship: ShipController
var helper: TrackSplineHelper
var follower: AILineFollower
var corridor: TrackCorridor
var all_race_ships: Array = []
var race_position: int = 1
var total_racers: int = 1

# --- State ---
var intent: int = Intent.FOLLOW
var intent_time: float = 0.0
var target: ShipController = null        ## the ship the intent is about
var side: float = 0.0                    ## chosen lateral direction (+right)
var lateral_bias: float = 0.0
var speed_cap: float = INF
var _cooldowns := {"overtake": 0.0, "defend": 0.0, "shove": 0.0}
var _best_gap: float = INF              ## overtake stall detection
var _stall_time: float = 0.0
var _hit_timer: float = 0.0
var _beside_time: float = 0.0           ## how long the same ship has been alongside
var _beside_ship: ShipController = null
var _tuck_timer: float = 0.0
var tuck_after: float = 3.0             ## side by side this long with no progress: tuck in
var tuck_time: float = 1.5
var _rng := RandomNumberGenerator.new()

# --- Stats for probes ---
var stats := {"overtakes": 0, "overtakes_done": 0, "defends": 0, "shoves": 0, "yields": 0, "recovers": 0}
var intent_seconds := [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]

func initialize(p_ship: ShipController, p_helper: TrackSplineHelper, p_follower: AILineFollower,
		p_skill: float, track_root: Node) -> void:
	ship = p_ship
	helper = p_helper
	follower = p_follower
	skill_level = p_skill
	corridor = TrackCorridor.new(helper, ship.get_world_3d(), track_root)
	# Deterministic personality per ship name, so a field has characters and
	# a probe run is repeatable.
	_rng.seed = hash(ship.name)
	aggression = clampf(_rng.randf_range(0.25, 0.85) * lerpf(0.6, 1.0, skill_level), 0.0, 1.0)
	patience = _rng.randf_range(0.2, 0.8)
	risk = clampf(_rng.randf_range(0.2, 0.8) * lerpf(0.5, 1.0, skill_level), 0.0, 1.0)
	horizon_time *= lerpf(0.8, 1.0, skill_level)
	ship.ship_collision.connect(_on_hit)

func set_skill(skill: float) -> void:
	skill_level = clampf(skill, 0.0, 1.0)

func set_race_ships(ships: Array) -> void:
	all_race_ships = ships

func update_race_position(position: int, total: int) -> void:
	race_position = position
	total_racers = total

## hits taken per intent: [count, max impact]
var hits_by_intent := [[0, 0.0], [0, 0.0], [0, 0.0], [0, 0.0], [0, 0.0], [0, 0.0]]

func _on_hit(_other: ShipController, impact: float) -> void:
	hits_by_intent[intent][0] += 1
	hits_by_intent[intent][1] = maxf(hits_by_intent[intent][1], impact)
	if impact >= 6.0:
		_hit_timer = recover_time

# ============================================================================
# MAIN UPDATE: call before the decider; writes follower.lateral_bias / speed_cap
# ============================================================================

func update(delta: float) -> void:
	for k in _cooldowns:
		_cooldowns[k] = maxf(0.0, _cooldowns[k] - delta)
	_hit_timer = maxf(0.0, _hit_timer - delta)
	intent_time += delta
	intent_seconds[intent] += delta

	if not ship or not helper or not helper.is_valid or all_race_ships.size() < 2:
		_settle(0.0, INF, delta, bias_rate)
		return

	var my_offset: float = follower.get_current_spline_offset()
	var my_lat: float = helper.calculate_lateral_offset(ship.global_position, my_offset, true)
	AIFieldSense.publish(ship, my_offset, my_lat, helper)
	var me: Dictionary = AIFieldSense.state_of(ship, helper)
	var v: float = maxf(me.speed, 1.0)
	var track_len: float = helper.total_length
	var lim: Vector2 = corridor.limits(my_offset)
	var line_lat: float = follower.baked_line.get_lateral_at(my_offset) if follower.has_baked_line() else 0.0

	# --- Perceive: nearest relevant ship ahead and behind ---
	var lead: Dictionary = {}
	var threat: Dictionary = {}
	var beside: Dictionary = {}
	var reach: float = v * horizon_time
	for o in all_race_ships:
		var other := o as ShipController
		if other == null or other == ship or not is_instance_valid(other):
			continue
		var st: Dictionary = AIFieldSense.state_of(other, helper)
		var ds: float = AIFieldSense.along(my_offset, st.offset, track_len)   # + = ahead of me
		var dlat: float = st.lat - my_lat
		var closing: float = me.s_speed - st.s_speed                          # + = I gain on it
		var rec := {"ship": other, "ds": ds, "dlat": dlat, "closing": closing, "lat": st.lat,
				"s_speed": st.s_speed, "ttc": (ds / closing) if (ds > 0.0 and closing > 0.1) else INF}
		if ds > 0.0 and ds < reach and absf(dlat) < lane_width:
			if lead.is_empty() or ds < lead.ds:
				lead = rec
		elif ds <= 0.0 and -ds < reach and absf(dlat) < lane_width and closing < -0.1:
			rec.ttc = -ds / -closing
			if threat.is_empty() or rec.ttc < threat.ttc:
				threat = rec
		if absf(ds) < 7.0 and absf(dlat) < lane_width and absf(dlat) > 0.5:
			if beside.is_empty() or absf(ds) < absf(beside.ds):
				beside = rec

	# Side-by-side stalemate clock.
	if not beside.is_empty() and beside.ship == _beside_ship:
		_beside_time += delta
	else:
		_beside_time = 0.0
		_beside_ship = beside.ship if not beside.is_empty() else null
	_tuck_timer = maxf(0.0, _tuck_timer - delta)
	
	# --- Corner context (signed: + = left turn) ---
	var kappa_ahead: float = follower.cached_max_curvature_signed
	var corner_distance: float = follower.cached_corner_distance
	var in_corner: bool = absf(kappa_ahead) > 0.01

	# --- Intent transitions ---
	var want_bias: float = 0.0
	var want_cap: float = INF
	var rate: float = bias_rate

	if _hit_timer > 0.0 or absf(ship.contact_yaw_rate) > recover_yaw:
		_switch(Intent.RECOVER, null)

	match intent:
		Intent.RECOVER:
			if _hit_timer <= 0.0 and absf(ship.contact_yaw_rate) <= recover_yaw and intent_time > 0.3:
				_switch(Intent.FOLLOW, null)
		Intent.FOLLOW:
			if not threat.is_empty() and -threat.closing > yield_closing \
					and threat.s_speed > ship.get_max_speed() * yield_speed_margin:
				_switch(Intent.YIELD, threat.ship)
				side = -signf(threat.dlat) if absf(threat.dlat) > 0.3 else -signf(line_lat if absf(line_lat) > 0.1 else 1.0)
				stats.yields += 1
			elif not lead.is_empty() and lead.ttc < overtake_ttc and lead.closing > overtake_min_closing \
					and (corner_distance > v * 0.8 or lead.closing > 8.0) \
					and _cooldowns.overtake <= 0.0 and _rng.randf() < lerpf(0.4, 1.0, aggression):
				side = _pick_side(lead, kappa_ahead)
				if side != 0.0:
					_switch(Intent.OVERTAKE, lead.ship)
					_best_gap = lead.ds
					_stall_time = 0.0
					stats.overtakes += 1
			elif not beside.is_empty() and in_corner and corner_distance > shove_window.x \
					and corner_distance < shove_window.y and _cooldowns.shove <= 0.0 \
					and absf(beside.closing) < shove_max_closing \
					and _other_is_outside(beside, kappa_ahead) and _rng.randf() < aggression * risk:
				side = signf(beside.dlat)
				_switch(Intent.SHOVE, beside.ship)
				stats.shoves += 1
			elif not threat.is_empty() and threat.ttc < defend_ttc and _cooldowns.defend <= 0.0 \
					and beside.is_empty() \
					and corner_distance > defend_min_corner_distance and race_position < total_racers \
					and _rng.randf() < lerpf(0.2, 0.9, aggression * (1.0 - patience * 0.5)):
				_switch(Intent.DEFEND, threat.ship)
				stats.defends += 1
		Intent.OVERTAKE:
			var t: Dictionary = _find(lead, beside, target)
			if t.is_empty() or t.ds < -8.0:
				if not t.is_empty() or intent_time > overtake_commit:
					stats.overtakes_done += 1 if (not t.is_empty() and t.ds < -8.0) else 0
					_cooldowns.overtake = overtake_cooldown
					_switch(Intent.FOLLOW, null)
			else:
				if t.ds < _best_gap - 0.5:
					_best_gap = t.ds
					_stall_time = 0.0
				else:
					_stall_time += delta
				if intent_time > overtake_commit and (_stall_time > overtake_stall * lerpf(0.7, 1.4, patience) \
						or t.closing < -2.0):
					_cooldowns.overtake = overtake_cooldown * lerpf(0.7, 2.0, patience)
					_switch(Intent.FOLLOW, null)
		Intent.DEFEND:
			if intent_time > defend_hold or threat.is_empty() or corner_distance < 25.0:
				_cooldowns.defend = defend_cooldown
				_switch(Intent.FOLLOW, null)
		Intent.SHOVE:
			if intent_time > shove_hold or beside.is_empty() or beside.ship != target \
					or absf(beside.closing) > shove_max_closing * 1.5:
				_cooldowns.shove = shove_cooldown
				_switch(Intent.FOLLOW, null)
		Intent.YIELD:
			if threat.is_empty() or intent_time > 2.0:
				_switch(Intent.FOLLOW, null)

	# --- Intent outputs ---
	match intent:
		Intent.FOLLOW:
			want_bias = 0.0
			# Give room to a ship alongside: the line would otherwise lead us
			# straight back into it.
			if not beside.is_empty() and absf(beside.dlat) < hull_gap:
				want_bias = -signf(beside.dlat) * (hull_gap - absf(beside.dlat))
			if not lead.is_empty() and lead.ttc < follow_ttc:
				var urgency: float = clampf(1.0 - lead.ttc / follow_ttc, 0.0, 1.0)
				want_cap = maxf(lead.s_speed * lerpf(0.98, 0.90, urgency), 10.0)
			# Side by side for seconds and the other is (even slightly) ahead:
			# the one behind tucks in rather than leaning on them forever.
			if not beside.is_empty() and beside.ds > 0.0 and _beside_time > tuck_after * lerpf(0.6, 1.4, patience) \
					and _tuck_timer <= 0.0:
				_tuck_timer = tuck_time
				_beside_time = 0.0
			if _tuck_timer > 0.0 and not beside.is_empty():
				want_cap = maxf(beside.s_speed - 4.0, 10.0)
		Intent.OVERTAKE:
			var t: Dictionary = _find(lead, beside, target)
			if not t.is_empty():
				want_bias = (t.lat + side * hull_gap) - line_lat
				# Still behind it in its lane: don't ram it while moving over.
				if t.ds > 0.0 and absf(t.dlat) < hull_gap * 0.7 and t.ttc < 0.5:
					want_cap = maxf(t.s_speed, 10.0)
		Intent.DEFEND:
			if not threat.is_empty():
				want_bias = (threat.lat - line_lat)
				want_bias = clampf(want_bias, -4.0, 4.0)
		Intent.SHOVE:
			if not beside.is_empty():
				want_bias = (beside.lat - side * shove_overlap) - line_lat
				rate = bias_rate_shove
				want_cap = maxf(beside.s_speed + 2.0, 10.0)   # lean, never ram
		Intent.YIELD:
			want_bias = side * 3.0
		Intent.RECOVER:
			# Line only -- but a ship alongside (usually the one we just touched)
			# is heading for the same line; keep giving it room or the second
			# hit is the big one.
			want_bias = 0.0
			if not beside.is_empty() and absf(beside.dlat) < hull_gap:
				want_bias = -signf(beside.dlat) * (hull_gap - absf(beside.dlat))
			if not lead.is_empty() and lead.ttc < follow_ttc:
				want_cap = maxf(lead.s_speed * 0.92, 10.0)

	# Clamp the aimed lateral to the corridor (bias is relative to the line).
	var aimed: float = clampf(line_lat + want_bias, lim.x, lim.y)
	want_bias = aimed - line_lat
	_settle(want_bias, want_cap, delta, rate)

func _settle(want_bias: float, want_cap: float, delta: float, rate: float) -> void:
	lateral_bias = move_toward(lateral_bias, want_bias, rate * delta)
	speed_cap = want_cap
	if follower:
		follower.lateral_bias = lateral_bias
		follower.speed_cap = speed_cap

func _switch(new_intent: int, t: ShipController) -> void:
	if new_intent != intent:
		intent = new_intent
		intent_time = 0.0
		if new_intent == Intent.RECOVER:
			stats.recovers += 1
	target = t

func _find(lead: Dictionary, beside: Dictionary, t: ShipController) -> Dictionary:
	if t == null or not is_instance_valid(t):
		return {}
	if not lead.is_empty() and lead.ship == t:
		return lead
	if not beside.is_empty() and beside.ship == t:
		return beside
	# Re-measure the target directly (it may have left the lane band).
	var me: Dictionary = AIFieldSense.state_of(ship, helper)
	var st: Dictionary = AIFieldSense.state_of(t, helper)
	var ds: float = AIFieldSense.along(me.offset, st.offset, helper.total_length)
	if absf(ds) > 60.0:
		return {}
	return {"ship": t, "ds": ds, "dlat": st.lat - me.lat, "closing": me.s_speed - st.s_speed,
			"lat": st.lat, "s_speed": st.s_speed, "ttc": INF}

## Which side to pass a ship on: the one with more corridor room at its
## position, with a preference for the inside of the next corner.
func _pick_side(lead: Dictionary, kappa: float) -> float:
	var me: Dictionary = AIFieldSense.state_of(ship, helper)
	var lead_offset: float = fposmod(me.offset + lead.ds / helper.total_length, 1.0)
	var lim: Vector2 = corridor.limits(lead_offset)
	var room_left: float = lead.lat - lim.x
	var room_right: float = lim.y - lead.lat
	var inside: float = -signf(kappa) if absf(kappa) > 0.005 else 0.0   # + = right
	if inside > 0.0:
		room_right += 2.0
	elif inside < 0.0:
		room_left += 2.0
	# A little stickiness toward the side we are already on.
	if lead.dlat > 1.0:
		room_left += 1.5
	elif lead.dlat < -1.0:
		room_right += 1.5
	if maxf(room_left, room_right) < hull_gap:
		return 0.0
	return 1.0 if room_right >= room_left else -1.0

func _other_is_outside(beside: Dictionary, kappa: float) -> bool:
	var inside: float = -signf(kappa)   # lateral direction of the inside (+ = right)
	return signf(beside.dlat) == -inside

func intent_name() -> String:
	return NAMES[intent]

func get_debug_info() -> String:
	return "Intent: %s (%.1fs) bias=%.1f cap=%s aggr=%.2f" % [intent_name(), intent_time, lateral_bias,
			("%.0f" % speed_cap) if speed_cap < INF else "-", aggression]
