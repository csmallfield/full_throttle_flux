extends UtopiaLayout
class_name SwoopyLayout
## Swoopy: a raceway flung across the sky, 500-700 m above an urban centre.
##
## The whole lap rides on a continuous box girder carried by colossal
## supports -- concrete monolith piers on the low sweeps, split piers here and
## there, and battered lattice trestles under the high section (2050-4780,
## where the deck climbs to ~180 m). Neighbouring supports are tied together
## by truss bridges far below the deck, with work platforms hung on them, so
## from any part of the lap you look across a web of scaffolding falling away
## into the haze. A patchy cloud sea floats between the deck and the city.
## On the horizon: impossible megastructures -- needle spires carrying bodies
## that should not stand up.
##
## Shares UtopiaKit / UtopiaLayout helpers (track space, clearance guards).
## Build: godot --path . -s res://tools/swoopy/build_swoopy.gd   (renderer needed for MultiMesh)

const GROUND_Y := -520.0               # city street level
const HIGH := [2050.0, 4780.0]         # trestle section
const GIRDER := [[26.5, -3.6], [23.5, -6.6], [11.0, -12.5], [-11.0, -12.5], [-23.5, -6.6], [-26.5, -3.6]]
const GIRDER_BOT := -12.5
const CAP_H := -16.0                   # bearing plane the support tops are cut to (banked frame)

var corners := []                      # [d0, d1, total_deg (+ right), apex_d]
var piers := []                        # Dictionary per support
var links := []                        # [pier_a, pier_b, y, kind]
var city_c := Vector3.ZERO
var _curv := PackedFloat32Array()
var _max_r := 0.0

func _init(kit: UtopiaKit) -> void:
	super(kit)
	k.gen_mesh_dir = "res://scenes/tracks/swoopy/meshes"
	var M := "res://scenes/tracks/swoopy/materials/"
	for m in ["concrete", "concrete_dk", "steel", "city_a", "city_b", "city_roof", "city_ground", "river",
			"glass", "pale", "beacon", "halo"]:
		k.mats[m] = load(M + m + ".tres")
	var s := Vector3.ZERO
	for p in _pts:
		s += p
	city_c = s / _pts.size()
	city_c.y = 0.0
	for p in _pts:
		_max_r = maxf(_max_r, Vector2(p.x - city_c.x, p.z - city_c.z).length())
	_find_corners()
	_plan_piers()
	_plan_links()

func district_ids() -> Array:
	return ["deck", "piers", "webs", "platforms", "overhead", "city", "needles", "spires", "clouds"]

func lighting_params() -> Dictionary:
	return {"sky_preset": "high_altitude", "root_name": "SwoopyLighting",
		"sun_azim": 205.0, "sun_elev": 33.0,
		"fog_height": -60.0, "fog_height_density": 0.0022,
		"fog_color": Color(0.70, 0.78, 0.88), "aerial": 0.5, "sun_scatter": 0.3,
		"shadow_dist": 1600.0}

# =============================================================================
# analysis helpers
# =============================================================================

func _find_corners() -> void:
	var n := int(k.length / 5.0)
	_curv.resize(n)
	var hd := PackedFloat32Array()
	for i in range(n):
		var t := k.fwd_flat(i * 5.0)
		hd.append(atan2(t.x, -t.z))
	for i in range(n):
		var a := wrapf(hd[(i + 2) % n] - hd[(i - 2 + n) % n], -PI, PI)
		_curv[i] = rad_to_deg(a) / 20.0
	var cur := []
	for i in range(n):
		var c := _curv[i]
		if absf(c) > 0.35:
			if cur.is_empty():
				cur = [i * 5.0, i * 5.0, 0.0, i * 5.0, 0.0]
			cur[1] = i * 5.0
			cur[2] += c * 5.0
			if absf(c) > cur[4]:
				cur[4] = absf(c)
				cur[3] = i * 5.0
		elif not cur.is_empty():
			if absf(cur[2]) >= 45.0:
				corners.append(cur.slice(0, 4))
			cur = []

func tgap(a: float, b: float) -> float:
	var g := absf(fposmod(a, k.length) - fposmod(b, k.length))
	return minf(g, k.length - g)

func bank_sin(d: float) -> float:
	var u := k.track_up(d)
	return sqrt(maxf(0.0, 1.0 - u.y * u.y))

func in_high(d: float) -> bool:
	return d >= HIGH[0] and d <= HIGH[1]

## Every other pass of the track within `radius` (horizontal) of p, at least
## `min_gap` metres away along the lap. Returns the samples as Vector4(x,y,z,d).
func other_passes(p: Vector3, d_self: float, radius: float, min_gap := 150.0) -> Array:
	var out := []
	var cr := ceili(radius / CELL) + 1
	var cx := floori(p.x / CELL)
	var cz := floori(p.z / CELL)
	for dx in range(-cr, cr + 1):
		for dz in range(-cr, cr + 1):
			var key := Vector2i(cx + dx, cz + dz)
			if not _grid.has(key):
				continue
			for i in _grid[key]:
				var q: Vector3 = _pts[i]
				var dd := float(i) * 4.0
				if d_self >= 0.0 and tgap(dd, d_self) < min_gap:
					continue
				if Vector2(q.x - p.x, q.z - p.z).length() < radius:
					out.append(Vector4(q.x, q.y, q.z, dd))
	return out

## Y on the support bearing plane (banked frame h = CAP_H) above world xz.
func cap_plane_y(d: float, xz: Vector3, h := CAP_H) -> float:
	var B := k.frame(d)
	var n := B.y
	var p0 := k.center(d) + n * h
	# n . (p - p0) = 0  ->  y = p0.y - (n.x (x - p0.x) + n.z (z - p0.z)) / n.y
	return p0.y - (n.x * (xz.x - p0.x) + n.z * (xz.z - p0.z)) / n.y

## Underside of the deck girder at (d, lat) -> world point.
func girder_pt(d: float, lat: float, h: float) -> Vector3:
	var B := k.frame(d)
	return k.center(d) + B.x * lat + B.y * h

# =============================================================================
# planning: supports and the links between them
# =============================================================================

func _plan_piers() -> void:
	rng.seed = 5005
	var d := 40.0
	var n := 0
	while d < k.length - 40.0:
		var high := in_high(d)
		var kind := "trestle" if high else ("split" if n % 3 == 1 else "monolith")
		var c := k.center(d)
		var foot := Vector3(c.x, GROUND_Y, c.z)
		var reach := 46.0 if kind == "trestle" else 30.0
		# another pass of the track lower than this deck and close by -> the
		# support would rise through it. Move along and try again.
		var ok := true
		for q in other_passes(c, d, reach + 40.0):
			if q.y < c.y + 40.0:
				ok = false
				break
		if ok:
			piers.append({"d": d, "c": c, "kind": kind, "foot": foot, "id": piers.size(),
				"top": cap_plane_y(d, c), "links": 0})
			n += 1
			d += (128.0 if high else 104.0) + rng.randf_range(-8.0, 8.0)
		else:
			d += 12.0
	print("  piers: %d" % piers.size())

func _plan_links() -> void:
	rng.seed = 7007
	var cand := []
	for i in range(piers.size()):
		for j in range(i + 1, piers.size()):
			var a: Dictionary = piers[i]
			var b: Dictionary = piers[j]
			if tgap(a.d, b.d) < 450.0:
				continue
			var dist := Vector2(a.c.x - b.c.x, a.c.z - b.c.z).length()
			if dist > 110.0 and dist < 360.0:
				cand.append([dist, i, j])
	cand.sort_custom(func(x, y): return x[0] < y[0])
	for cnd in cand:
		var a: Dictionary = piers[cnd[1]]
		var b: Dictionary = piers[cnd[2]]
		if a.links >= 2 or b.links >= 2:
			continue
		var y_hi: float = minf(a.top, b.top) - 55.0 - rng.randf_range(0.0, 40.0)
		var levels := [y_hi]
		if cnd[0] > 170.0:
			levels.append(y_hi - rng.randf_range(150.0, 210.0))
		var placed := false
		for y in levels:
			if _link_clear(a, b, y):
				var kind := "truss" if rng.randf() < 0.7 else "girder"
				links.append([a.id, b.id, y, kind])
				placed = true
		if placed:
			a.links += 1
			b.links += 1
	print("  links: %d" % links.size())

## A link at height y must pass well under every other pass of the track it
## crosses, and must not clip any other support.
func _link_clear(a: Dictionary, b: Dictionary, y: float) -> bool:
	var p0 := Vector3(a.c.x, y, a.c.z)
	var p1 := Vector3(b.c.x, y, b.c.z)
	var L := p0.distance_to(p1)
	var steps := int(L / 10.0)
	for s in range(steps + 1):
		var p := p0.lerp(p1, float(s) / steps)
		var r := near_track(p)
		if r.x < 45.0 and y > r.y - 30.0:
			return false
	for o in piers:
		if o.id == a.id or o.id == b.id:
			continue
		var q := Vector2(o.c.x, o.c.z)
		var s2 := Geometry2D.get_closest_point_to_segment(q, Vector2(p0.x, p0.z), Vector2(p1.x, p1.z))
		if q.distance_to(s2) < 34.0 and y < o.top:
			return false
	return true

# =============================================================================
# DECK: the continuous box girder under the road (chunked, ~400 m each)
# =============================================================================

func district_deck(root: Node3D) -> void:
	var g := k.group(root, "Girder")
	var chunk := 400.0
	var d0 := 0.0
	var ci := 0
	while d0 < k.length - 0.1:
		var d1 := minf(d0 + chunk, k.length)
		var m := SwoopyMesher.new()
		var prev := []
		var d := d0
		while true:
			var dd := minf(d, d1)
			var ring := []
			for p in GIRDER:
				ring.append(girder_pt(dd, p[0], p[1]))
			if not prev.is_empty():
				var cc := k.center(dd)
				for i in range(ring.size()):
					var j := (i + 1) % ring.size()
					var mid: Vector3 = (ring[i] + ring[j] + prev[i] + prev[j]) * 0.25
					var mat := "concrete" if i == 2 else "concrete_dk"
					m.quad(mat, prev[i], prev[j], ring[j], ring[i], mid - (cc + k.frame(dd).y * -7.0))
			prev = ring
			if dd >= d1:
				break
			d += 4.0
		# underside diaphragm ribs every 16 m: rhythm seen from below / afar
		var r := ceilf(d0 / 16.0) * 16.0
		while r < d1:
			var B := k.frame(r)
			m.box(girder_pt(r, 0.0, GIRDER_BOT - 0.7), Vector3(21.0, 1.4, 1.6), B, "concrete_dk")
			r += 16.0
		m.commit(k, g, "Girder%02d" % ci, "girder_%02d" % ci)
		ci += 1
		d0 = d1

# =============================================================================
# PIERS: monolith / split / trestle supports, one merged mesh each
# =============================================================================

func district_piers(root: Node3D) -> void:
	var g := k.group(root, "Supports")
	for p in piers:
		var m := SwoopyMesher.new()
		match p.kind:
			"monolith":
				_monolith(m, p)
			"split":
				_split(m, p)
			"trestle":
				_trestle(m, p)
		_bearing(m, p)
		m.commit(k, g, "%s_%04d" % [p.kind.capitalize(), int(p.d)], "pier_%04d" % int(p.d))

## Cap/bearing block rolled with the deck, flush under the girder.
func _bearing(m: SwoopyMesher, p: Dictionary) -> void:
	var d: float = p.d
	var B := k.frame(d)
	var w := 40.0 if p.kind == "trestle" else 28.0
	var dp := 28.0 if p.kind == "trestle" else 15.0
	m.box(girder_pt(d, 0.0, GIRDER_BOT - 2.2), Vector3(w, 4.4, dp), B, "concrete")
	# bearing pads
	for s: float in [-1.0, 1.0]:
		m.box(girder_pt(d, s * 8.0, GIRDER_BOT - 0.5), Vector3(4.0, 1.0, 5.0), B, "steel")

## Shaft whose top face is cut to the (banked) bearing plane.
func _cut_shaft(m: SwoopyMesher, d: float, base: Vector3, w0: float, d0: float, w1: float, d1: float,
		top_plane_h: float, mat: String, top_c := Vector3.INF) -> void:
	var yb := k.yaw_at(d)
	var x := yb.x
	var z := yb.z
	var tc := base if top_c == Vector3.INF else top_c
	var bot := []
	var top := []
	for corner: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		bot.append(base + x * corner.x * w0 * 0.5 + z * corner.y * d0 * 0.5)
		var t := tc + x * corner.x * w1 * 0.5 + z * corner.y * d1 * 0.5
		t.y = cap_plane_y(d, t, top_plane_h)
		top.append(t)
	m.hexa(mat, bot, top)

func _monolith(m: SwoopyMesher, p: Dictionary) -> void:
	var d: float = p.d
	var yb := k.yaw_at(d)
	var foot: Vector3 = p.foot
	var top: float = p.top
	var H := top - GROUND_Y
	# footing: stepped plinth
	m.block(foot, 74.0, 46.0, GROUND_Y + 6.0, yb, "concrete_dk")
	m.block(foot, 56.0, 34.0, GROUND_Y + 20.0, yb, "concrete")
	_cut_shaft(m, d, foot + Vector3.UP * 20.0, 40.0, 24.0, 17.0, 11.0, CAP_H + 0.5, "concrete")
	# collars where the shaft steps (reads as scale at distance)
	for f: float in [0.36, 0.7]:
		var y := GROUND_Y + 20.0 + (H - 20.0) * f
		var w := lerpf(40.0, 17.0, f) + 4.0
		var dp := lerpf(24.0, 11.0, f) + 4.0
		m.block(Vector3(foot.x, y, foot.z), w, dp, y + 7.0, yb, "concrete_dk")

func _split(m: SwoopyMesher, p: Dictionary) -> void:
	var d: float = p.d
	var yb := k.yaw_at(d)
	var foot: Vector3 = p.foot
	var top: float = p.top
	var H := top - GROUND_Y
	var ys := GROUND_Y + H * 0.6
	m.block(foot, 70.0, 44.0, GROUND_Y + 6.0, yb, "concrete_dk")
	m.shaft(foot + Vector3.UP * 6.0, 38.0, 22.0, 24.0, 13.0, ys, yb, "concrete")
	m.block(Vector3(foot.x, ys, foot.z), 28.0, 16.0, ys + 10.0, yb, "concrete_dk")
	# two raking legs up to the deck
	var tops := []
	for s: float in [-1.0, 1.0]:
		var a := Vector3(foot.x, ys + 8.0, foot.z) + yb.x * s * 7.0
		var t := k.center(d) + k.right_flat(d) * s * 14.0
		t.y = cap_plane_y(d, t, CAP_H + 1.0)
		tops.append(t)
		m.beam(a, t, 9.0, 10.0, "concrete", yb.z)
	# tie beam at 70 % of the legs
	var la: Vector3 = Vector3(foot.x, ys + 8.0, foot.z) + yb.x * -7.0
	var lb: Vector3 = Vector3(foot.x, ys + 8.0, foot.z) + yb.x * 7.0
	m.beam(la.lerp(tops[0], 0.72), lb.lerp(tops[1], 0.72), 5.0, 6.0, "concrete_dk", yb.z)

## Battered lattice trestle: four concrete legs, steel ring beams and X braces.
func _trestle(m: SwoopyMesher, p: Dictionary) -> void:
	var d: float = p.d
	var yb := k.yaw_at(d)
	var foot: Vector3 = p.foot
	var top: float = p.top
	var H := top - GROUND_Y
	var legs_b := []
	var legs_t := []
	for corner: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		legs_b.append(foot + yb.x * corner.x * 44.0 + yb.z * corner.y * 30.0)
		var t := Vector3(foot.x, 0, foot.z) + yb.x * corner.x * 16.0 + yb.z * corner.y * 11.0
		t.y = cap_plane_y(d, t, CAP_H + 1.0)
		legs_t.append(t)
		m.block(legs_b[-1], 14.0, 14.0, GROUND_Y + 12.0, yb, "concrete_dk")
		m.beam(legs_b[-1], t, 7.0, 7.0, "concrete", yb.z)
	var nlev := maxi(4, int(round(H / 72.0)))
	var prev := []
	for li in range(nlev + 1):
		var f := float(li) / nlev
		if li == nlev:
			f = 0.985
		var ring := []
		for c in range(4):
			ring.append((legs_b[c] as Vector3).lerp(legs_t[c], f))
		if li > 0:
			for c in range(4):
				m.beam(ring[c], ring[(c + 1) % 4], 3.6, 3.6, "steel")
		if not prev.is_empty():
			for c in range(4):
				var c2 := (c + 1) % 4
				m.beam(prev[c], ring[c2], 2.2, 2.2, "steel")
				m.beam(prev[c2], ring[c], 2.2, 2.2, "steel")
		# a working floor every third level
		if li > 0 and li < nlev and li % 3 == 0:
			var ctr: Vector3 = (ring[0] + ring[2]) * 0.5
			var w := (ring[0] as Vector3).distance_to(ring[1])
			var dp := (ring[1] as Vector3).distance_to(ring[2])
			m.box(ctr + Vector3.DOWN * 1.5, Vector3(w + 6.0, 3.0, dp + 6.0), yb, "concrete_dk")
		prev = ring

# =============================================================================
# WEBS: truss bridges + girders between supports, with hung platforms
# =============================================================================

func district_webs(root: Node3D) -> void:
	var g := k.group(root, "Links")
	rng.seed = 8118
	var pi := 0
	for L in links:
		var a: Dictionary = piers[L[0]]
		var b: Dictionary = piers[L[1]]
		var y: float = L[2]
		var p0 := Vector3(a.c.x, y, a.c.z)
		var p1 := Vector3(b.c.x, y, b.c.z)
		var m := SwoopyMesher.new()
		if L[3] == "truss":
			m.truss(p0, p1, 12.0, 3.4, 24.0, "steel")
		else:
			m.beam(p0 + Vector3.DOWN * 5.0, p1 + Vector3.DOWN * 5.0, 9.0, 10.0, "concrete")
		# collars where it lands on a support
		for e in [p0, p1]:
			m.box(e + Vector3.DOWN * 6.0, Vector3(16.0, 16.0, 16.0), Basis.IDENTITY, "concrete_dk")
		var span := p0.distance_to(p1)
		if span > 160.0 and rng.randf() < 0.55:
			_platform(m, p0.lerp(p1, rng.randf_range(0.38, 0.62)), (p1 - p0).normalized(), y - (12.0 if L[3] == "truss" else 10.0))
			pi += 1
		m.commit(k, g, "Link_%04d_%04d_%d" % [int(a.d), int(b.d), int(absf(y))], "link_%d_%d_%d" % [L[0], L[1], int(absf(y))])
	print("  hung platforms: %d" % pi)

## Work platform slung under/on a link: slab, sheds, tanks, a mast.
func _platform(m: SwoopyMesher, c: Vector3, dir: Vector3, deck_y: float) -> void:
	var f := Vector3(dir.x, 0, dir.z).normalized()
	var b := Basis(f.cross(Vector3.UP).normalized(), Vector3.UP, f)
	var base := Vector3(c.x, deck_y, c.z)
	m.box(base + Vector3.DOWN * 2.0, Vector3(54.0, 4.0, 78.0), b, "concrete")
	m.box(base + Vector3.DOWN * 5.0, Vector3(46.0, 2.0, 70.0), b, "concrete_dk")
	var kind := rng.randi() % 3
	match kind:
		0:  # hangar + tanks
			m.block(base + b.z * -14.0, 34.0, 30.0, deck_y + 15.0, b, "pale")
			for t in range(3):
				m.prism(base + b.x * (-14.0 + t * 14.0) + b.z * 22.0, 5.5, 5.5, 12.0, 12, "concrete")
		1:  # stacked containers / blocks
			for t in range(5):
				var off := b.x * rng.randf_range(-18, 18) + b.z * rng.randf_range(-30, 30)
				m.block(base + off, rng.randf_range(8, 14), rng.randf_range(10, 22), deck_y + rng.randf_range(4, 16), b, "concrete_dk" if t % 2 else "pale")
		2:  # landing pad + control hut
			m.prism(base + b.z * 12.0, 20.0, 20.0, 0.8, 24, "pale")
			m.block(base + b.z * -26.0, 16.0, 12.0, deck_y + 9.0, b, "concrete")
	# mast with beacon
	var mb := base + b.x * 22.0 + b.z * 34.0
	m.prism(mb, 1.2, 0.5, 46.0, 6, "steel")
	m.box(mb + Vector3.UP * 46.5, Vector3(2.0, 2.0, 2.0), Basis.IDENTITY, "beacon")
	# hanger rods up to the link
	for s: float in [-1.0, 1.0]:
		for t: float in [-1.0, 1.0]:
			var q := base + b.x * s * 25.0 + b.z * t * 36.0
			m.beam(q, Vector3(c.x, deck_y + 12.0, c.z) + b.z * t * 36.0, 1.2, 1.2, "steel")

# =============================================================================
# PLATFORMS: service decks cantilevered off the supports + the start stands
# =============================================================================

func district_platforms(root: Node3D) -> void:
	var g := k.group(root, "ServiceDecks")
	rng.seed = 9229
	var used := []
	var n := 0
	for p in piers:
		var d: float = p.d
		if tgap(d, 0.0) < 380.0 or bank_sin(d) > 0.2:
			continue
		var close := false
		for u in used:
			if tgap(u, d) < 600.0:
				close = true
		if close:
			continue
		# pick the side with open air
		var best_s := 0.0
		for s: float in [1.0, -1.0]:
			var probe := k.at(d, s * 110.0)
			if other_passes(probe, d, 150.0, 200.0).is_empty():
				best_s = s
				break
		if best_s == 0.0:
			continue
		used.append(d)
		var m := SwoopyMesher.new()
		_service_deck(m, p, best_s)
		m.commit(k, g, "ServiceDeck_%04d" % int(d), "deck_%04d" % int(d))
		n += 1
	print("  service decks: %d" % n)
	var sg := k.group(root, "StartStands")
	var m2 := SwoopyMesher.new()
	_start_stands(m2)
	m2.commit(k, sg, "StartStands", "start_stands")

func _service_deck(m: SwoopyMesher, p: Dictionary, s: float) -> void:
	var d: float = p.d
	var yb := k.yaw_at(d)
	var c := k.center(d)
	var top := c.y - 13.0       # deck surface: visible just over the wall line
	var xs := k.right_flat(d) * s
	var inner := 30.0
	var outer := 128.0
	var mid := (inner + outer) * 0.5
	var slab_c := Vector3(c.x, top, c.z) + xs * mid
	m.box(slab_c + Vector3.DOWN * 2.5, Vector3(outer - inner, 5.0, 84.0), yb, "concrete")
	m.box(slab_c + Vector3.DOWN * 7.0, Vector3(outer - inner - 10.0, 4.0, 70.0), yb, "concrete_dk")
	# raking struts back to the support
	for t: float in [-1.0, 1.0]:
		var e := Vector3(c.x, top - 9.0, c.z) + xs * (outer - 8.0) + yb.z * t * 34.0
		m.beam(e, Vector3(c.x, top - 120.0, c.z) + yb.z * t * 6.0, 5.0, 5.0, "steel")
		var e2 := Vector3(c.x, top - 9.0, c.z) + xs * (mid) + yb.z * t * 34.0
		m.beam(e2, Vector3(c.x, top - 70.0, c.z) + yb.z * t * 6.0, 4.0, 4.0, "steel")
	# edge railing posts (rhythm along the outer edge)
	for i in range(9):
		var q := Vector3(c.x, top, c.z) + xs * (outer - 1.0) + yb.z * (-40.0 + i * 10.0)
		m.block(q, 0.6, 0.6, top + 2.4, yb, "steel")
	m.box(Vector3(c.x, top + 2.4, c.z) + xs * (outer - 1.0), Vector3(0.5, 0.5, 82.0), yb, "steel")
	var kind := int(p.d / 7.0) % 3
	var at := func(lat: float, along: float) -> Vector3:
		return Vector3(c.x, top, c.z) + xs * lat + yb.z * along
	match kind:
		0:  # hangar + tower
			m.block(at.call(84.0, -8.0), 40.0, 52.0, top + 16.0, yb, "pale")
			m.block(at.call(84.0, -8.0), 36.0, 2.0, top + 14.0, yb, "concrete_dk")
			m.prism(at.call(118.0, 34.0), 4.0, 3.2, 44.0, 8, "concrete")
			m.block(at.call(118.0, 34.0) + Vector3.UP * 44.0, 13.0, 13.0, top + 52.0, yb, "glass")
			m.box(at.call(118.0, 34.0) + Vector3.UP * 53.0, Vector3(1.6, 1.6, 1.6), Basis.IDENTITY, "beacon")
		1:  # landing pads
			for t: float in [-1.0, 1.0]:
				m.prism(at.call(78.0, t * 20.0), 17.0, 17.0, 0.8, 24, "pale")
				m.prism(at.call(78.0, t * 20.0) + Vector3.UP * 0.8, 12.0, 12.0, 0.2, 24, "concrete_dk")
			m.block(at.call(116.0, 0.0), 14.0, 30.0, top + 7.0, yb, "concrete")
		2:  # tank farm + antenna array
			for i in range(3):
				for j in range(2):
					m.prism(at.call(64.0 + i * 18.0, -18.0 + j * 18.0), 7.0, 7.0, 13.0, 14, "pale")
			for i in range(3):
				var a: Vector3 = at.call(118.0, -30.0 + i * 30.0)
				m.prism(a, 0.8, 0.3, 32.0 + i * 8.0, 6, "steel")
				m.box(a + Vector3.UP * (32.5 + i * 8.0), Vector3(1.4, 1.4, 1.4), Basis.IDENTITY, "beacon")

## Grandstands either side of the start, on decks cantilevered off the girder.
func _start_stands(m: SwoopyMesher) -> void:
	for s: float in [1.0, -1.0]:
		var free := other_passes(k.at(0.0, s * 120.0), 0.0, 160.0, 300.0).is_empty()
		var y0 := k.center(0.0).y
		var d := -230.0
		while d < 150.0:
			var c := k.center(d)
			var yb := k.yaw_at(d)
			var xs := k.right_flat(d) * s
			var top := c.y - 9.0
			var w := 20.0
			if free:
				# deck from 39 m out, stands rising away from the track
				m.box(Vector3(c.x, top - 2.0, c.z) + xs * 84.0, Vector3(90.0, 4.0, w + 0.5), yb, "concrete")
				for t in range(7):
					var lat := 52.0 + t * 6.0
					m.block(Vector3(c.x, top, c.z) + xs * lat, 6.2, w - 1.0, c.y - 4.0 + t * 3.4, yb, "pale" if t % 2 == 0 else "concrete")
				# back wall + roof canopy cantilevered toward the track
				m.block(Vector3(c.x, top, c.z) + xs * 96.0, 4.0, w, c.y + 32.0, yb, "concrete_dk")
				var ra := Vector3(c.x, c.y + 32.0, c.z) + xs * 96.0
				var rb := Vector3(c.x, c.y + 26.0, c.z) + xs * 46.0
				m.beam(ra, rb, w - 2.0, 1.6, "pale", Vector3.UP)
			else:
				# narrow side: a run of pit-style signal pylons
				m.block(Vector3(c.x, c.y - 30.0, c.z) + xs * 44.0, 3.0, 3.0, c.y + 18.0, yb, "steel")
				m.box(Vector3(c.x, c.y + 18.0, c.z) + xs * 44.0, Vector3(5.0, 3.0, 5.0), yb, "pale")
			d += w

# =============================================================================
# OVERHEAD: scaffolding that straddles the deck and rises above it, so the
# lap threads THROUGH the structure instead of riding on top of it.
#   gallery    portal frames every 34 m + longitudinal lattice: a see-through tube
#   upperdeck  frames carrying a working platform over the road (shade + roof)
#   towers     two giant scaffold towers either side, sky-bridges overhead
# Outboard legs stand at lat +/-46 (outside the 37 m guard) and run all the
# way down to the city. Every overhead member is at or above clear_y() + 8.
# =============================================================================

const LEG_LAT := 46.0
var clusters := []      # [d_start, kind, n, spacing]

func _cluster_ok(d0: float, n: int, sp: float, kind: String, top_extra: float) -> bool:
	for i in range(n):
		var d := d0 + i * sp
		if absf(curv_at(d)) > (0.5 if kind == "upperdeck" else 0.9):
			return false
		if kind == "upperdeck" and bank_sin(d) > 0.3:
			return false
		var top := clear_y(d - 12.0, d + 12.0, 8.0) + top_extra
		for s: float in [-1.0, 1.0]:
			var leg := k.at(d, s * (LEG_LAT + (8.0 if kind == "towers" else 0.0)))
			for q in other_passes(leg, d, 58.0, 120.0):
				if q.y < top + 30.0:
					return false
		for p in piers:   # don't land a leg on a pier's own footprint
			if tgap(p.d, d) > 200.0 and Vector2(p.c.x - k.center(d).x, p.c.z - k.center(d).z).length() < 70.0:
				return false
	return true

func curv_at(d: float) -> float:
	return _curv[int(fposmod(d, k.length) / 5.0) % _curv.size()]

func _plan_clusters() -> void:
	var kinds := ["gallery", "catwalks", "towers"]
	var spec := {"gallery": [7, 34.0, 18.0], "upperdeck": [4, 42.0, 6.0], "catwalks": [3, 85.0, 30.0], "towers": [2, 30.0, 210.0]}
	# pass 1: the upper decks need straight, flat deck -- claim those spots first
	var ups := []
	var du := 600.0
	while du < k.length - 400.0:
		var sp0: Array = spec["upperdeck"]
		if _cluster_ok(du, sp0[0], sp0[1], "upperdeck", sp0[2]):
			ups.append([du, "upperdeck", sp0[0], sp0[1]])
			du += 2100.0
		else:
			du += 25.0
	var d := 220.0
	var ki := 0
	while d < k.length - 300.0:
		var near_up := false
		for u in ups:
			if d > u[0] - 380.0 and d < u[0] + 300.0:
				near_up = true
		if near_up:
			d += 25.0
			continue
		var found := false
		for t in range(kinds.size()):
			var kind: String = kinds[(ki + t) % kinds.size()]
			var sp: Array = spec[kind]
			if not clusters.is_empty() and clusters[-1][1] == kind:
				continue
			if kind == "towers" and clusters.filter(func(c): return c[1] == "towers").size() >= 5:
				continue
			if _cluster_ok(d, sp[0], sp[1], kind, sp[2]):
				clusters.append([d, kind, sp[0], sp[1]])
				ki += t + 1
				d += 480.0
				found = true
				break
		if not found:
			d += 25.0
	clusters.append_array(ups)
	clusters.sort_custom(func(x, y): return x[0] < y[0])
	print("  overhead clusters: ", clusters.map(func(c): return "%s@%d" % [c[1], int(c[0])]))

func district_overhead(root: Node3D) -> void:
	if clusters.is_empty():
		_plan_clusters()
	var g := k.group(root, "Overhead")
	rng.seed = 6116
	for c in clusters:
		var m := SwoopyMesher.new()
		call("_oh_" + c[1], m, c[0], c[2], c[3])
		m.commit(k, g, "%s_%04d" % [c[1].capitalize(), int(c[0])], "oh_%s_%04d" % [c[1], int(c[0])])

## One outboard leg from the city to top_y, tied back to the girder under the deck.
func _leg(m: SwoopyMesher, d: float, s: float, top_y: float, w := 8.0, lat := LEG_LAT) -> Vector3:
	var p := k.at_y(d, s * lat, GROUND_Y)
	var yb := k.yaw_at(d)
	m.block(p, w * 2.0, w * 2.0, GROUND_Y + 10.0, yb, "concrete_dk")
	m.block(p, w, w, top_y, yb, "concrete")
	# tie strut to the girder flank, below the road
	var gp := girder_pt(d, s * 22.0, -8.0)
	m.beam(Vector3(p.x, gp.y - 6.0, p.z), gp, 3.0, 3.0, "steel")
	return Vector3(p.x, top_y, p.z)

## Side-wall scaffolding between two consecutive legs, from y0 up to y1.
func _side_brace(m: SwoopyMesher, a: Vector3, b: Vector3, y0: float, y1: float, panel := 60.0) -> void:
	var n := maxi(1, int((y1 - y0) / panel))
	for i in range(n):
		var ya := y0 + (y1 - y0) * i / n
		var yb2 := y0 + (y1 - y0) * (i + 1) / n
		m.beam(Vector3(a.x, ya, a.z), Vector3(b.x, yb2, b.z), 1.8, 1.8, "steel")
		m.beam(Vector3(b.x, ya, b.z), Vector3(a.x, yb2, a.z), 1.8, 1.8, "steel")
		m.beam(Vector3(a.x, yb2, a.z), Vector3(b.x, yb2, b.z), 2.6, 2.6, "steel")

func _oh_gallery(m: SwoopyMesher, d0: float, n: int, sp: float) -> void:
	var prev := []
	for i in range(n):
		var d := d0 + i * sp
		var top := clear_y(d - 12.0, d + 12.0, 8.0)
		var tops := []
		for s: float in [-1.0, 1.0]:
			tops.append(_leg(m, d, s, top + 18.0, 6.0))
		var l: Vector3 = tops[0]
		var r: Vector3 = tops[1]
		# cross truss: chords at top and top+12 with diagonals
		var lo_l := Vector3(l.x, top, l.z)
		var lo_r := Vector3(r.x, top, r.z)
		m.beam(lo_l, lo_r, 2.6, 2.6, "steel")
		m.beam(Vector3(l.x, top + 12.0, l.z), Vector3(r.x, top + 12.0, r.z), 2.6, 2.6, "steel")
		var segs := 6
		for j in range(segs):
			var a := lo_l.lerp(lo_r, float(j) / segs)
			var b := lo_l.lerp(lo_r, float(j + 1) / segs)
			m.beam(a + Vector3.UP * (12.0 if j % 2 else 0.0), b + Vector3.UP * (0.0 if j % 2 else 12.0), 1.6, 1.6, "steel")
		# knee braces into the legs
		for e in [[lo_l, 1.0], [lo_r, -1.0]]:
			var base: Vector3 = e[0]
			var dir := (lo_r - lo_l).normalized() * float(e[1])
			m.beam(base + Vector3.DOWN * 14.0, base + dir * 14.0, 1.6, 1.6, "steel")
		var cur := [l, r]
		if not prev.is_empty():
			for s in range(2):
				var a: Vector3 = prev[s]
				var b: Vector3 = cur[s]
				_side_brace(m, Vector3(a.x, a.y - 18.0, a.z), Vector3(b.x, b.y - 18.0, b.z), a.y - 18.0 - 90.0, minf(a.y, b.y) - 18.0, 30.0)
				_side_brace(m, Vector3(a.x, GROUND_Y, a.z), Vector3(b.x, GROUND_Y, b.z), GROUND_Y + 40.0, a.y - 110.0, 80.0)
				m.beam(a + Vector3.DOWN * 6.0, b + Vector3.DOWN * 6.0, 2.4, 2.4, "steel")
			# longitudinal lattice over the road (two chords)
			var pa: Vector3 = prev[0]; var pb: Vector3 = prev[1]
			for f: float in [0.33, 0.67]:
				m.beam(pa.lerp(pb, f) + Vector3.DOWN * 6.0, l.lerp(r, f) + Vector3.DOWN * 6.0, 1.8, 1.8, "steel")
		prev = cur

func _oh_upperdeck(m: SwoopyMesher, d0: float, n: int, sp: float) -> void:
	var tops := []
	var top := -INF
	for i in range(n):
		var d := d0 + i * sp
		top = maxf(top, clear_y(d - 16.0, d + 16.0, 8.0))
	for i in range(n):
		var d := d0 + i * sp
		var yb := k.yaw_at(d)
		var pair := []
		for s: float in [-1.0, 1.0]:
			pair.append(_leg(m, d, s, top + 6.0, 9.0))
		# deep transfer girder under the platform
		m.beam(Vector3(pair[0].x, top + 3.0, pair[0].z), Vector3(pair[1].x, top + 3.0, pair[1].z), 6.0, 6.0, "concrete_dk", Vector3.UP)
		tops.append(pair)
		if i > 0:
			for s in range(2):
				var a: Vector3 = tops[i - 1][s]
				var b: Vector3 = pair[s]
				_side_brace(m, Vector3(a.x, GROUND_Y, a.z), Vector3(b.x, GROUND_Y, b.z), GROUND_Y + 40.0, top - 30.0, 70.0)
	# the platform slab, following the track in segments
	var dm := d0 + (n - 1) * sp * 0.5
	var yb0 := k.yaw_at(dm)
	for i in range(n - 1):
		var da := d0 + i * sp
		var db := da + sp
		var ca := k.center(da); var cb := k.center(db)
		var mid := (ca + cb) * 0.5
		var f := Vector3(cb.x - ca.x, 0, cb.z - ca.z)
		var b := Basis.looking_at(f.normalized(), Vector3.UP)
		m.box(Vector3(mid.x, top + 8.5, mid.z), Vector3(LEG_LAT * 2.0 + 30.0, 5.0, f.length() + 1.0), b, "concrete")
		m.box(Vector3(mid.x, top + 5.6, mid.z), Vector3(LEG_LAT * 2.0 + 16.0, 0.8, f.length() - 6.0), b, "concrete_dk")
	# what lives up there
	var cm := k.center(dm)
	var base := Vector3(cm.x, top + 11.0, cm.z)
	var x := yb0.x
	var z := yb0.z
	m.block(base + x * -20.0, 46.0, 70.0, top + 30.0, yb0, "pale")
	m.block(base + x * -20.0 + z * 36.0, 38.0, 2.0, top + 27.0, yb0, "concrete_dk")
	for t in range(3):
		m.prism(base + x * 34.0 + z * (-30.0 + t * 20.0), 7.0, 7.0, 14.0, 14, "pale")
	# crane: mast + jib swung out over the void
	var cb2 := base + x * 52.0 + z * 40.0
	m.block(cb2, 4.0, 4.0, top + 74.0, yb0, "steel")
	m.beam(Vector3(cb2.x, top + 74.0, cb2.z) - x * 20.0, Vector3(cb2.x, top + 74.0, cb2.z) + x * 70.0, 2.4, 3.0, "steel")
	m.beam(Vector3(cb2.x, top + 86.0, cb2.z), Vector3(cb2.x, top + 74.0, cb2.z) + x * 60.0, 0.6, 0.6, "steel")
	m.block(Vector3(cb2.x, top + 74.0, cb2.z) - x * 18.0, 7.0, 7.0, top + 80.0, yb0, "concrete_dk")
	m.box(Vector3(cb2.x, top + 87.0, cb2.z), Vector3(1.5, 1.5, 1.5), Basis.IDENTITY, "beacon")

## Light catwalk trusses high over the road between slim outboard masts.
func _oh_catwalks(m: SwoopyMesher, d0: float, n: int, sp: float) -> void:
	for i in range(n):
		var d := d0 + i * sp
		var y := clear_y(d - 10.0, d + 10.0, 14.0) + float(i % 2) * 12.0
		var pl := _leg(m, d, -1.0, y + 26.0, 4.0)
		var pr := _leg(m, d, 1.0, y + 26.0, 4.0)
		m.truss(Vector3(pl.x, y + 7.0, pl.z), Vector3(pr.x, y + 7.0, pr.z), 7.0, 1.6, 9.0, "steel")
		m.box(Vector3((pl.x + pr.x) * 0.5, y + 7.6, (pl.z + pr.z) * 0.5), Vector3(4.0, 0.5, pl.distance_to(pr)),
			Basis.looking_at((pr - pl).normalized(), Vector3.UP), "concrete_dk")
		# pipe bundle hung under the walk
		for t: float in [-1.2, 1.2]:
			var off := k.fwd_flat(d) * t
			m.beam(Vector3(pl.x, y - 1.2, pl.z) + off, Vector3(pr.x, y - 1.2, pr.z) + off, 1.0, 1.0, "pale")
		for e in [pl, pr]:
			m.box(e + Vector3.UP * 1.0, Vector3(1.4, 1.4, 1.4), Basis.IDENTITY, "beacon")

func _oh_towers(m: SwoopyMesher, d0: float, n: int, sp: float) -> void:
	var dm := d0 + sp * 0.5
	var yb := k.yaw_at(dm)
	var road := k.center(dm).y
	var top := road + 150.0 + rng.randf_range(0.0, 50.0)
	var clear := clear_y(dm - 20.0, dm + 20.0, 8.0)
	var tw := 26.0
	var cores := []
	for s: float in [-1.0, 1.0]:
		var c := k.at_y(dm, s * (LEG_LAT + 8.0 + tw * 0.5 - 4.0), GROUND_Y)
		cores.append(c)
		# four battered posts + rings + braces: a scaffold tower 700 m tall
		var posts_b := []
		var posts_t := []
		for corner: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
			var ob := c + yb.x * corner.x * tw + yb.z * corner.y * tw
			var ot := c + yb.x * corner.x * tw * 0.5 + yb.z * corner.y * tw * 0.5
			ot.y = top
			posts_b.append(ob)
			posts_t.append(ot)
			m.block(ob, 16.0, 16.0, GROUND_Y + 10.0, yb, "concrete_dk")
			m.beam(ob, ot, 6.0, 6.0, "concrete", yb.z)
		var nl := int((top - GROUND_Y) / 50.0)
		var prev := []
		for li in range(1, nl + 1):
			var f := float(li) / nl
			var ring := []
			for q in range(4):
				ring.append((posts_b[q] as Vector3).lerp(posts_t[q], f))
			for q in range(4):
				m.beam(ring[q], ring[(q + 1) % 4], 2.8, 2.8, "steel")
			if not prev.is_empty():
				for q in range(4):
					m.beam(prev[q], ring[(q + 1) % 4], 1.6, 1.6, "steel")
			prev = ring
		# working floors on the tower (cantilevered outward, away from the road)
		for hh: float in [40.0, 95.0, 140.0]:
			var y := road + hh
			if y > top - 6.0:
				continue
			var fc := Vector3(c.x, y, c.z) + yb.x * s * 14.0
			m.box(fc, Vector3(tw * 2.2, 4.0, tw * 2.2), yb, "concrete")
			m.block(fc + yb.x * s * 10.0 + Vector3.UP * 2.0, 18.0, 24.0, y + 12.0, yb, "pale")
		m.box(Vector3(c.x, top + 1.0, c.z), Vector3(tw * 1.4, 3.0, tw * 1.4), yb, "concrete")
		m.prism(Vector3(c.x, top + 2.0, c.z), 1.2, 0.4, 40.0, 6, "steel")
		m.box(Vector3(c.x, top + 43.0, c.z), Vector3(2.0, 2.0, 2.0), Basis.IDENTITY, "beacon")
	# sky-bridges over the road
	var a: Vector3 = cores[0]
	var b: Vector3 = cores[1]
	for y: float in [maxf(clear, road + 60.0), road + 118.0]:
		if y > top - 8.0:
			continue
		m.truss(Vector3(a.x, y + 10.0, a.z), Vector3(b.x, y + 10.0, b.z), 10.0, 2.8, 14.0, "steel")
		m.box(Vector3((a.x + b.x) * 0.5, y + 11.5, (a.z + b.z) * 0.5), Vector3(a.distance_to(b), 2.0, 12.0), Basis.looking_at((b - a).normalized(), Vector3.UP) * Basis(Vector3.UP, PI * 0.5), "concrete")
	# the low gate frame you actually fly through
	for i in range(n):
		var d := d0 + i * sp
		var t := clear_y(d - 12.0, d + 12.0, 8.0)
		var pl := _leg(m, d, -1.0, t + 3.0, 6.0)
		var pr := _leg(m, d, 1.0, t + 3.0, 6.0)
		m.beam(Vector3(pl.x, t, pl.z), Vector3(pr.x, t, pr.z), 4.0, 5.0, "concrete_dk")

# =============================================================================
# CITY: the urban centre 520 m below (MultiMesh tiles, no shadows)
# =============================================================================

func district_city(root: Node3D) -> void:
	rng.seed = 4114
	var ground := k.box(root, "Ground", Vector3(city_c.x, GROUND_Y - 3.0, city_c.z), Vector3(16000.0, 6.0, 16000.0), Basis.IDENTITY, "city_ground")
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var river := _river_pts()
	var rm := SwoopyMesher.new()
	for i in range(river.size() - 1):
		var a: Vector3 = river[i]
		var b: Vector3 = river[i + 1]
		rm.beam(a + Vector3.UP * 0.3, b + Vector3.UP * 0.3, 190.0, 0.6, "river")
	rm.commit(k, root, "River", "river", false)
	var noise := FastNoiseLite.new()
	noise.seed = 77
	noise.frequency = 0.0011
	var chunks := {}
	var rot := Basis(Vector3.UP, deg_to_rad(16.0))
	var pitch := 72.0
	var R := 4200.0
	var n := int(R / pitch)
	var count := 0
	for ix in range(-n, n + 1):
		for iz in range(-n, n + 1):
			var local := Vector3(ix * pitch, 0, iz * pitch)
			var c := city_c + rot * local
			c.y = GROUND_Y
			var r := Vector2(c.x - city_c.x, c.z - city_c.z).length()
			if r > R:
				continue
			# avenues every 6th row/column
			if ix % 6 == 0 or iz % 7 == 0:
				continue
			if _near_river(c, river, 120.0) or _near_foot(c, 62.0):
				continue
			var dens := 1.0 - smoothstep(R * 0.55, R, r)
			if rng.randf() > 0.25 + 0.7 * dens:
				continue
			var nv := noise.get_noise_2d(c.x, c.z) * 0.5 + 0.5
			var core := 1.0 - smoothstep(300.0, 2600.0, r)
			var blk := pitch - 18.0
			if rng.randf() < 0.1 + 0.32 * core * nv:
				# tower on a podium
				var h := lerpf(70.0, 250.0, pow(rng.randf(), 1.6) * (0.4 + 0.6 * core))
				_mm(chunks, c, Vector3(blk, rng.randf_range(10, 22), blk), rot, "city_b")
				var tw := rng.randf_range(20.0, 34.0)
				_mm(chunks, c, Vector3(tw, h, tw * rng.randf_range(0.7, 1.3)), rot, "city_a")
				count += 2
			else:
				# block: 1-4 mid-rise volumes
				var parts := 1 + rng.randi() % 4
				var sub := blk / 2.0
				for pi in range(parts):
					var off := Vector3((pi % 2 - 0.5) * sub, 0, (pi / 2 - 0.5) * sub) if parts > 1 else Vector3.ZERO
					var sz := Vector3(sub if parts > 1 else blk, lerpf(10.0, 55.0, nv) * rng.randf_range(0.5, 1.4), sub if parts > 2 else blk)
					_mm(chunks, c + rot * off, sz, rot, "city_a" if rng.randf() < 0.55 else "city_b")
					count += 1
	for key in chunks:
		var arr: Array = chunks[key]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = k.meshes["box"]
		mm.instance_count = arr.size()
		for i in range(arr.size()):
			mm.set_instance_transform(i, arr[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Tile_%s_%s" % [key[0], key[1]]
		mmi.multimesh = mm
		mmi.material_override = k.mats[key[1]]
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mmi)
	print("  city blocks: %d in %d tiles" % [count, chunks.size()])

func _mm(chunks: Dictionary, base: Vector3, size: Vector3, b: Basis, mat: String) -> void:
	var tile := "%d_%d" % [floori(base.x / 1100.0), floori(base.z / 1100.0)]
	var key := [tile, mat]
	if not chunks.has(key):
		chunks[key] = []
	chunks[key].append(Transform3D(b.scaled_local(size), base + Vector3.UP * size.y * 0.5))

func _river_pts() -> Array:
	var pts := []
	for i in range(41):
		var t := float(i) / 40.0
		var x := lerpf(-4600.0, 4600.0, t)
		var z := 520.0 * sin(t * 5.2 + 0.6) + 260.0 * sin(t * 11.0)
		var p := city_c + Basis(Vector3.UP, deg_to_rad(-28.0)) * Vector3(x, 0, z + 900.0)
		p.y = GROUND_Y
		pts.append(p)
	return pts

func _near_river(c: Vector3, river: Array, w: float) -> bool:
	for i in range(river.size() - 1):
		var a: Vector3 = river[i]
		var b: Vector3 = river[i + 1]
		var q := Geometry2D.get_closest_point_to_segment(Vector2(c.x, c.z), Vector2(a.x, a.z), Vector2(b.x, b.z))
		if q.distance_to(Vector2(c.x, c.z)) < w:
			return true
	return false

func _near_foot(c: Vector3, r: float) -> bool:
	for p in piers:
		var rr := r + (30.0 if p.kind == "trestle" else 0.0)
		if Vector2(p.c.x - c.x, p.c.z - c.z).length() < rr:
			return true
	return false

# =============================================================================
# NEEDLES: slender towers rising from the city to around deck height
# (mid-ground parallax between the track and the megastructures)
# =============================================================================

func district_needles(root: Node3D) -> void:
	rng.seed = 3113
	var g := k.group(root, "Needles")
	var kinds := ["discs", "stack", "fork", "blade"]
	var placed := 0
	var tries := 0
	var spots := []
	while placed < 11 and tries < 600:
		tries += 1
		var a := rng.randf() * TAU
		var r := rng.randf_range(_max_r + 250.0, _max_r + 1200.0)
		var c := city_c + Vector3(cos(a) * r, 0, sin(a) * r)
		c.y = GROUND_Y
		if near_track(c).x < 240.0 or _near_foot(c, 140.0):
			continue
		var bad := false
		for s in spots:
			if (s as Vector3).distance_to(c) < 520.0:
				bad = true
		if bad:
			continue
		spots.append(c)
		var top := rng.randf_range(60.0, 460.0)
		var m := SwoopyMesher.new()
		var kind: String = kinds[placed % kinds.size()]
		_needle(m, kind, c, top)
		m.box(Vector3(c.x, top + 2.0, c.z), Vector3(2.5, 2.5, 2.5), Basis.IDENTITY, "beacon")
		m.commit(k, g, "Needle%02d_%s" % [placed, kind.capitalize()], "needle_%02d" % placed, false)
		placed += 1
	print("  needles: %d" % placed)

func _needle(m: SwoopyMesher, kind: String, c: Vector3, top: float) -> void:
	var H := top - GROUND_Y
	var b := Basis(Vector3.UP, rng.randf() * TAU)
	m.block(c, 90.0, 90.0, GROUND_Y + 34.0, b, "city_b")
	match kind:
		"discs":   # shaft carrying broad glass discs
			m.prism(c, 20.0, 9.0, H * 0.9, 12, "pale", b)
			for f: float in [0.55, 0.7, 0.82]:
				var y := GROUND_Y + H * f
				var rr := 58.0 - f * 30.0
				m.prism(Vector3(c.x, y, c.z), rr, rr, 9.0, 24, "glass", b)
				m.prism(Vector3(c.x, y + 9.0, c.z), rr, rr * 0.7, 4.0, 24, "pale", b)
			m.prism(Vector3(c.x, GROUND_Y + H * 0.9, c.z), 9.0, 0.0, H * 0.1, 8, "pale", b)
		"stack":   # tapering drums separated by dark glazed gaps
			var y := GROUND_Y + 34.0
			var n := 7
			for i in range(n):
				var h := (top - y) / (n - i) * 0.8
				var r0 := lerpf(34.0, 10.0, float(i) / n)
				var r1 := lerpf(34.0, 10.0, float(i + 1) / n)
				m.prism(Vector3(c.x, y, c.z), r0, r1, h, 10, "pale", b)
				m.prism(Vector3(c.x, y + h, c.z), r1 * 0.8, r1 * 0.8, h * 0.18, 10, "glass", b)
				y += h * 1.18
			m.prism(Vector3(c.x, y, c.z), 6.0, 0.0, maxf(top - y, 10.0), 6, "pale", b)
		"fork":    # one trunk splitting into three prongs
			var ys := GROUND_Y + H * 0.58
			m.prism(c, 26.0, 16.0, ys - GROUND_Y, 10, "concrete", b)
			for i in range(3):
				var a := TAU * i / 3.0
				var tip := Vector3(c.x, top - i * 24.0, c.z) + (b * Vector3(cos(a), 0, sin(a))) * 38.0
				m.beam(Vector3(c.x, ys, c.z), tip, 8.0, 8.0, "pale", Vector3.FORWARD)
			m.prism(Vector3(c.x, ys - 8.0, c.z), 30.0, 30.0, 10.0, 16, "glass", b)
		"blade":   # a thin slab, notched near the top
			var w := 70.0
			m.block(c, w, 16.0, GROUND_Y + H * 0.72, b, "pale")
			m.block(Vector3(c.x, GROUND_Y + H * 0.72, c.z), w, 10.0, GROUND_Y + H * 0.76, b, "glass")
			m.block(Vector3(c.x, GROUND_Y + H * 0.76, c.z) + b.x * w * 0.25, w * 0.5, 16.0, top, b, "pale")
			m.block(Vector3(c.x, GROUND_Y + H * 0.76, c.z) - b.x * w * 0.3, w * 0.12, 6.0, top - 30.0, b, "steel")

# =============================================================================
# SPIRES: the impossible megastructures on the horizon
# =============================================================================

const SPIRE_FAR := 3900.0     # keep every top inside the race camera's far plane (4000 m)

func district_spires(root: Node3D) -> void:
	var g := k.group(root, "Megastructures")
	var designs := ["halo", "orb", "inverted", "cantilever", "twin", "balanced", "levitate", "cluster"]
	rng.seed = 2552
	for i in range(designs.size()):
		var a := TAU * (float(i) + rng.randf_range(-0.18, 0.18)) / designs.size() + 0.4
		var r := rng.randf_range(_max_r + 900.0, _max_r + 1500.0)
		var c := city_c + Vector3(cos(a) * r, 0, sin(a) * r)
		c.y = GROUND_Y
		# farthest track point from here -> tallest top the far plane allows
		var dmax := 0.0
		for p in _pts:
			dmax = maxf(dmax, Vector2(p.x - c.x, p.z - c.z).length())
		var top_max := sqrt(maxf(SPIRE_FAR * SPIRE_FAR - dmax * dmax, 0.0)) - 20.0
		var H := minf(rng.randf_range(1500.0, 1850.0), top_max - GROUND_Y)
		var sg := k.group(g, "Spire_%s" % designs[i].capitalize())
		var m := SwoopyMesher.new()
		call("_spire_" + designs[i], m, sg, c, H)
		m.box(c + Vector3.UP * (H + 4.0), Vector3(6, 6, 6), Basis.IDENTITY, "beacon")
		m.commit(k, sg, "Body", "spire_%s" % designs[i], false)
		print("  spire %-10s r=%5.0f  H=%5.0f  top_y=%5.0f" % [designs[i], r, H, GROUND_Y + H])

func _ball(g: Node, name: String, c: Vector3, r: float, mat: String, squash := 1.0) -> void:
	var mi := k.sphere(g, name, c, r, mat, squash)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _ring(g: Node, name: String, c: Vector3, r: float, tube: float, mat: String, tilt := 0.0) -> void:
	var key := "torus_%d_%d" % [int(r), int(tube)]
	if not k.meshes.has(key):
		var t := TorusMesh.new()
		t.inner_radius = r - tube
		t.outer_radius = r + tube
		t.rings = 96
		t.ring_segments = 16
		var path := "%s/gen_spires_%s.tres" % [k.gen_mesh_dir, key]
		ResourceSaver.save(t, path)
		k.meshes[key] = load(path)
	var mi := MeshInstance3D.new()
	mi.name = name
	mi.mesh = k.meshes[key]
	mi.material_override = k.mats[mat]
	mi.transform = Transform3D(Basis(Vector3.RIGHT, deg_to_rad(tilt)), c)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	g.add_child(mi)

## Needle with a free-floating halo ring (no connection at all).
func _spire_halo(m: SwoopyMesher, g: Node, c: Vector3, H: float) -> void:
	m.block(c, 160.0, 160.0, GROUND_Y + 60.0, Basis.IDENTITY, "concrete_dk")
	m.prism(c, 52.0, 9.0, H, 16, "pale")
	_ring(g, "Halo", c + Vector3.UP * H * 0.58, 300.0, 18.0, "halo")
	_ring(g, "HaloUpper", c + Vector3.UP * H * 0.76, 190.0, 12.0, "pale", 7.0)

## A colossal sphere skewered two-thirds of the way up a thin needle.
func _spire_orb(m: SwoopyMesher, g: Node, c: Vector3, H: float) -> void:
	m.block(c, 140.0, 140.0, GROUND_Y + 50.0, Basis.IDENTITY, "concrete_dk")
	m.prism(c, 36.0, 6.0, H, 14, "pale")
	var oc := c + Vector3.UP * H * 0.6
	_ball(g, "Orb", oc, 210.0, "glass")
	m.prism(oc + Vector3.UP * -195.0, 120.0, 0.0, 190.0, 16, "pale", Basis(Vector3.RIGHT, PI))
	m.prism(oc + Vector3.UP * -10.0, 224.0, 224.0, 20.0, 32, "pale")

## Inverted mountain: a 560 m wide stepped crown balanced on a slender stem.
func _spire_inverted(m: SwoopyMesher, g: Node, c: Vector3, H: float) -> void:
	m.block(c, 120.0, 120.0, GROUND_Y + 40.0, Basis.IDENTITY, "concrete_dk")
	var stem := H * 0.6
	m.prism(c, 30.0, 22.0, stem, 12, "concrete")
	var y := GROUND_Y + stem
	var steps := 7
	for s in range(steps):
		var r0 := lerpf(24.0, 270.0, float(s) / steps)
		var r1 := lerpf(24.0, 270.0, float(s + 1) / steps)
		var h := (H * 0.32) / steps
		m.prism(Vector3(c.x, y, c.z), r0, r1, h, 24, "pale" if s % 2 == 0 else "concrete")
		y += h
	m.prism(Vector3(c.x, y, c.z), 270.0, 250.0, 14.0, 24, "glass")
	for t in range(5):
		var a := TAU * t / 5.0
		var p := Vector3(c.x + cos(a) * 150.0, y + 14.0, c.z + sin(a) * 150.0)
		m.prism(p, 14.0, 6.0, H * 0.08 + t * 12.0, 8, "pale")

## Slabs cantilevered off a thin core, twisting as they climb.
func _spire_cantilever(m: SwoopyMesher, g: Node, c: Vector3, H: float) -> void:
	m.block(c, 110.0, 110.0, GROUND_Y + 40.0, Basis.IDENTITY, "concrete_dk")
	m.prism(c, 34.0, 18.0, H, 12, "concrete")
	for s in range(6):
		var f := 0.32 + s * 0.11
		var b := Basis(Vector3.UP, deg_to_rad(28.0 * s))
		var y := GROUND_Y + H * f
		var len := 340.0 - s * 26.0
		m.box(Vector3(c.x, y, c.z) + b.x * (len * 0.5 - 30.0), Vector3(len, 46.0, 90.0), b, "glass" if s % 2 else "pale")

## Two needles with an enormous mass slung between them.
func _spire_twin(m: SwoopyMesher, g: Node, c: Vector3, H: float) -> void:
	var b := Basis(Vector3.UP, 0.7)
	for s: float in [-1.0, 1.0]:
		var p := c + b.x * s * 190.0
		m.block(p, 90.0, 90.0, GROUND_Y + 40.0, b, "concrete_dk")
		m.prism(p, 30.0, 8.0, H * (1.0 if s > 0 else 0.9), 12, "pale")
	var y := GROUND_Y + H * 0.62
	m.box(Vector3(c.x, y, c.z), Vector3(330.0, 150.0, 120.0), b, "glass")
	m.box(Vector3(c.x, y + 82.0, c.z), Vector3(350.0, 14.0, 130.0), b, "pale")
	m.box(Vector3(c.x, y - 82.0, c.z), Vector3(300.0, 14.0, 110.0), b, "pale")
	for s: float in [-1.0, 1.0]:
		for t: float in [-1.0, 1.0]:
			m.beam(Vector3(c.x, y + 90.0, c.z) + b.x * s * 150.0 + b.z * t * 50.0, Vector3(c.x, GROUND_Y + H * 0.85, c.z) + b.x * s * 186.0, 3.0, 3.0, "steel")

## Leaning monolith with a cube balanced on one vertex at its tip.
func _spire_balanced(m: SwoopyMesher, g: Node, c: Vector3, H: float) -> void:
	var lean := Basis(Vector3.FORWARD, deg_to_rad(8.0))
	var shaft_h := H * 0.78
	m.block(c, 130.0, 100.0, GROUND_Y + 30.0, Basis.IDENTITY, "concrete_dk")
	m.box(c + lean.y * shaft_h * 0.5, Vector3(90.0, shaft_h, 60.0), lean, "pale")
	var tip := c + lean.y * shaft_h
	var cube := 180.0
	# rotate a cube so its body diagonal stands vertical
	var diag := Vector3(1, 1, 1).normalized()
	var q := Quaternion(diag, Vector3.UP)
	var b := Basis(q)
	m.box(tip + Vector3.UP * cube * sqrt(3.0) * 0.5, Vector3(cube, cube, cube), b, "glass")

## A needle that stops short, and a giant ovoid hovering above its point.
func _spire_levitate(m: SwoopyMesher, g: Node, c: Vector3, H: float) -> void:
	m.block(c, 120.0, 120.0, GROUND_Y + 40.0, Basis.IDENTITY, "concrete_dk")
	var stem := H * 0.62
	m.prism(c, 40.0, 4.0, stem, 14, "pale")
	var oc := c + Vector3.UP * (stem + 70.0 + 190.0)
	_ball(g, "Ovoid", oc, 150.0, "pale", 1.3)
	_ball(g, "MoonA", oc + Vector3(260.0, 60.0, 40.0), 40.0, "glass")
	_ball(g, "MoonB", oc + Vector3(-200.0, -120.0, 150.0), 26.0, "glass")
	_ring(g, "Belt", oc, 210.0, 6.0, "halo", 14.0)

## Cluster of very slender needles bound by floating rings.
func _spire_cluster(m: SwoopyMesher, g: Node, c: Vector3, H: float) -> void:
	m.block(c, 200.0, 200.0, GROUND_Y + 50.0, Basis.IDENTITY, "concrete_dk")
	var hs := [1.0, 0.82, 0.68, 0.74, 0.58]
	for i in range(hs.size()):
		var a := TAU * i / hs.size()
		var p := c + Vector3(cos(a), 0, sin(a)) * (0.0 if i == 0 else 64.0)
		m.prism(p, 22.0 if i == 0 else 14.0, 3.0, H * hs[i], 10, "pale" if i % 2 == 0 else "concrete")
	for f: float in [0.35, 0.5, 0.62]:
		_ring(g, "Band%d" % int(f * 100), c + Vector3.UP * H * f, 100.0, 7.0, "pale")

# =============================================================================
# CLOUDS: two patchy cloud decks between the raceway and the city
# =============================================================================

func district_clouds(root: Node3D) -> void:
	var M := "res://scenes/tracks/swoopy/materials/"
	var upper: ShaderMaterial = load(M + "cloud_sea.tres")
	upper.set_shader_parameter("plane_center", Vector2(city_c.x, city_c.z))
	ResourceSaver.save(upper, M + "cloud_sea.tres")
	var lower: ShaderMaterial = upper.duplicate()
	lower.set_shader_parameter("coverage", 0.40)
	lower.set_shader_parameter("seed_offset", 3.7)
	lower.set_shader_parameter("brightness", 1.1)
	ResourceSaver.save(lower, M + "cloud_sea_low.tres")
	var pm := PlaneMesh.new()
	pm.size = Vector2(13000.0, 13000.0)
	ResourceSaver.save(pm, k.gen_mesh_dir + "/gen_clouds_plane.tres")
	pm = load(k.gen_mesh_dir + "/gen_clouds_plane.tres")
	for pair in [["CloudDeckUpper", -235.0, M + "cloud_sea.tres"], ["CloudDeckLower", -320.0, M + "cloud_sea_low.tres"]]:
		var mi := MeshInstance3D.new()
		mi.name = pair[0]
		mi.mesh = pm
		mi.material_override = load(pair[2])
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position = Vector3(city_c.x, pair[1], city_c.z)
		root.add_child(mi)
