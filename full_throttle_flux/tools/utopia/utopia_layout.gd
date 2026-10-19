extends RefCounted
class_name UtopiaLayout
## Authored layout for the Utopia greybox city.
## Each district_<id>() builds one scene. Track-space helpers live in UtopiaKit.

const WATER_Y := -40.0
const SPIRE := Vector3(-720.0, 0.0, -70.0)
const DOME := Vector3(-826.0, -40.0, -700.0)
## Authored landmarks the generated fabric must keep away from: [x, z, radius]
const RESERVED := [[-826.0, -700.0, 150.0], [-423.0, -688.0, 120.0], [-262.0, -760.0, 130.0], [82.0, -452.0, 90.0], [315.0, -78.0, 60.0], [150.0, -745.0, 90.0]]
const LOOP_C := Vector3(-282.0, 0.0, -842.0)

var k: UtopiaKit
var rng := RandomNumberGenerator.new()
# track proximity cache
var _pts := PackedVector3Array()
var _grid := {}
const CELL := 60.0

func _init(kit: UtopiaKit) -> void:
	k = kit
	var d := 0.0
	while d < k.length:
		_pts.append(k.center(d))
		d += 4.0
	for i in range(_pts.size()):
		var key := Vector2i(floori(_pts[i].x / CELL), floori(_pts[i].z / CELL))
		if not _grid.has(key):
			_grid[key] = []
		_grid[key].append(i)

func district_ids() -> Array:
	return ["base", "concourse", "terraces", "skyway", "canyon", "corner", "arcade",
		"hairpin", "northloop", "spirerun", "viaduct", "spiral", "eastsweep", "mega"]

func lighting_params() -> Dictionary:
	return {
		"sun_azim": 215.0, "sun_elev": 23.0, "sun_energy": 3.0,
		"ambient": 0.36, "exposure": 0.92, "fill_energy": 0.16,
		"sky_top": Color(0.15, 0.29, 0.52), "sky_horizon": Color(0.93, 0.75, 0.58),
		"fog_color": Color(0.74, 0.70, 0.68),
		"fog_density": 0.00014, "aerial": 0.12, "sun_scatter": 0.3,
		"fog_height": -12.0, "fog_height_density": 0.01,
	}

## Horizontal distance from p to the nearest track centreline sample, plus
## that sample's Y. Searches a 5x5 cell window (~150 m); returns INF if none.
func near_track(p: Vector3) -> Vector2:
	var cx := floori(p.x / CELL)
	var cz := floori(p.z / CELL)
	var best := INF
	var by := 0.0
	for dx in range(-3, 4):
		for dz in range(-3, 4):
			var key := Vector2i(cx + dx, cz + dz)
			if _grid.has(key):
				for i in _grid[key]:
					var q: Vector3 = _pts[i]
					var dd := Vector2(q.x - p.x, q.z - p.z).length()
					if dd < best:
						best = dd
						by = q.y
	return Vector2(best, by)

## Footprint clearance: min distance over centre + corners + edge midpoints.
func footprint_clear(c: Vector3, w: float, dpt: float, b: Basis) -> Vector2:
	var best := Vector2(INF, 0)
	for fx: float in [-0.5, 0.0, 0.5]:
		for fz: float in [-0.5, 0.0, 0.5]:
			var p := c + b.x * (w * fx) + b.z * (dpt * fz)
			var r := near_track(p)
			if r.x < best.x:
				best = r
	return best

# =============================================================================
# BASE: water, spire, radial fabric, far skyline
# =============================================================================

func district_base(root: Node3D) -> void:
	k.box(root, "Water", Vector3(-350, WATER_Y - 1.0, -350), Vector3(9000, 2, 9000), Basis.IDENTITY, "water")
	_spire(k.group(root, "Spire"))
	_fabric(k.group(root, "Fabric"))
	_far_skyline(k.group(root, "FarSkyline"))

func _spire(g: Node3D) -> void:
	var s := Vector3(SPIRE.x, WATER_Y, SPIRE.z)
	# stepped circular podium
	k.cyl(g, "Podium1", s, 120.0, 30.0, "mid")
	k.cyl(g, "Podium2", s + Vector3.UP * 30.0, 92.0, 22.0, "light")
	k.cyl(g, "Podium3", s + Vector3.UP * 52.0, 70.0, 14.0, "mid")
	# four buttress fins
	for i in range(4):
		var b := k.yaw_deg(45.0 + i * 90.0)
		var c := s + b.z * 52.0
		k.block(g, "Fin%d" % i, c + Vector3.UP * 52.0, Vector3(10, 190, 70), b, "light")
	k.cyl(g, "Shaft", s + Vector3.UP * 66.0, 34.0, 300.0, "light", "taper")
	k.cyl(g, "Collar1", s + Vector3.UP * 170.0, 46.0, 8.0, "accent")
	k.cyl(g, "Crown", s + Vector3.UP * 330.0, 58.0, 14.0, "accent")
	k.cyl(g, "CrownGlass", s + Vector3.UP * 344.0, 48.0, 18.0, "dark")
	k.cyl(g, "CrownTop", s + Vector3.UP * 362.0, 54.0, 6.0, "accent")
	k.cyl(g, "Upper", s + Vector3.UP * 368.0, 16.0, 120.0, "light", "taper")
	k.cyl(g, "Needle", s + Vector3.UP * 488.0, 4.0, 140.0, "light", "cone")

const SPOKE_HALF := 34.0   # half-width of the 8 radial avenues (left open: canals)
const STREET := 22.0       # gap between blocks inside a sector

func _fabric(g: Node3D) -> void:
	## Planned radial city around the Spire: 8 open avenues, concentric bands.
	##   A  downtown towers      175..420
	##   B  courtyard blocks     455..700   cornice ~ y 30
	##   C  courtyard blocks     735..985   cornice ~ y 14
	##   D  low terraces        1020..1320
	rng.seed = 7041
	var bands := [
		{"r0": 175.0, "r1": 290.0, "kind": "tower", "cell": 120.0},
		{"r0": 310.0, "r1": 420.0, "kind": "tower", "cell": 130.0},
		{"r0": 455.0, "r1": 700.0, "kind": "court", "cell": 150.0, "top": 30.0},
		{"r0": 735.0, "r1": 985.0, "kind": "court", "cell": 160.0, "top": 14.0},
		{"r0": 1020.0, "r1": 1320.0, "kind": "terrace", "cell": 170.0, "top": -4.0},
	]
	var n := 0
	for band in bands:
		var bg := k.group(g, "Band_%s_%d" % [band["kind"], int(band["r0"])])
		var r0: float = band["r0"]
		var r1: float = band["r1"]
		var rm := (r0 + r1) * 0.5
		for sector in range(8):
			var a0 := TAU * sector / 8.0 + SPOKE_HALF / rm
			var a1 := TAU * (sector + 1) / 8.0 - SPOKE_HALF / rm
			var cells := maxi(1, roundi((a1 - a0) * rm / float(band["cell"])))
			for ci in range(cells):
				var ca0 := lerpf(a0, a1, float(ci) / cells) + (0.0 if ci == 0 else 0.5 * STREET / rm)
				var ca1 := lerpf(a0, a1, float(ci + 1) / cells) - (0.0 if ci == cells - 1 else 0.5 * STREET / rm)
				match band["kind"]:
					"tower":
						_tower_cell(bg, "T%03d" % n, r0, r1, ca0, ca1)
					"court":
						_court_cell(bg, "C%03d" % n, r0, r1, ca0, ca1, band["top"])
					"terrace":
						_terrace_cell(bg, "R%03d" % n, r0, r1, ca0, ca1, band["top"])
				n += 1

func _reserved(c: Vector3, r: float) -> bool:
	for z in RESERVED:
		if Vector2(c.x - z[0], c.z - z[1]).length() < z[2] + r:
			return true
	return false

func _polar(r: float, a: float, y := WATER_Y) -> Vector3:
	return Vector3(SPIRE.x + cos(a) * r, y, SPIRE.z + sin(a) * r)

## Oriented bar between two ground points, given depth and top. Respects track clearance.
func _bar(g: Node3D, name: String, p0: Vector3, p1: Vector3, depth: float, top: float, mat: String) -> void:
	var dir := Vector3(p1.x - p0.x, 0, p1.z - p0.z)
	var len := dir.length()
	if len < 6.0:
		return
	var b := Basis.looking_at(dir / len, Vector3.UP)  # -Z along the bar
	var c := (p0 + p1) * 0.5
	c.y = WATER_Y
	if _reserved(c, len * 0.5):
		return
	var clear := footprint_clear(c, depth + 8.0, len + 8.0, b)
	if clear.x < 40.0:
		return
	if clear.x < 85.0:
		top = minf(top, clear.y - 14.0)
	if top - WATER_Y < 8.0:
		return
	k.block_to(g, name, c, depth, len, top, b, mat)

func _court_cell(g: Node3D, name: String, r0: float, r1: float, a0: float, a1: float, top_y: float) -> void:
	var cg := k.group(g, name)
	var dpt := 18.0
	var top := top_y + rng.randf_range(-6.0, 6.0)
	var mat := "light" if rng.randf() < 0.7 else "mid"
	# inner + outer arc bars (split into chords so they follow the curve)
	for side in [0, 1]:
		var r := (r0 + dpt * 0.5) if side == 0 else (r1 - dpt * 0.5)
		var segs := maxi(1, int((a1 - a0) * r / 70.0))
		for i in range(segs):
			var aa := lerpf(a0, a1, float(i) / segs)
			var ab := lerpf(a0, a1, float(i + 1) / segs)
			_bar(cg, "Arc%d_%d" % [side, i], _polar(r, aa), _polar(r, ab), dpt, top, mat)
	# radial bars
	for side in [0, 1]:
		var a := a0 + (dpt * 0.5 / r0) if side == 0 else a1 - (dpt * 0.5 / r0)
		_bar(cg, "Rad%d" % side, _polar(r0 + dpt, a), _polar(r1 - dpt, a), dpt, top - 4.0, mat)
	# occasional corner tower accent
	if rng.randf() < 0.35:
		var corner := _polar(r1 - 22.0, a0 + 22.0 / r1)
		var clear := near_track(corner)
		if clear.x > 110.0:
			var tt := top + rng.randf_range(50.0, 130.0)
			if rng.randf() < 0.5:
				k.block_to(cg, "Accent", corner, 30.0, 30.0, tt, Basis.looking_at((SPIRE - corner) * Vector3(1, 0, 1), Vector3.UP), "accent")
			else:
				k.cyl(cg, "Accent", corner, 16.0, tt - WATER_Y, "accent")

func _tower_cell(g: Node3D, name: String, r0: float, r1: float, a0: float, a1: float) -> void:
	var cg := k.group(g, name)
	var am := (a0 + a1) * 0.5
	var rm := (r0 + r1) * 0.5
	var c := _polar(rm, am)
	var b := Basis.looking_at(Vector3(SPIRE.x - c.x, 0, SPIRE.z - c.z).normalized(), Vector3.UP)
	var w := minf((a1 - a0) * r0, r1 - r0) * 0.86
	if _reserved(c, w * 0.7):
		return
	var clear := footprint_clear(c, w, w, b)
	if clear.x < 60.0:
		return
	var pod_top := WATER_Y + rng.randf_range(22.0, 38.0)
	k.block_to(cg, "Podium", c, w, w, pod_top, b, "mid")
	# heights: taller on the inner ring, and on cells next to avenues framing the spire
	var h := rng.randf_range(150.0, 230.0) + (120.0 if r0 < 200.0 else 0.0)
	if clear.x < 140.0:
		h = minf(h, 120.0)
	var top := pod_top + h
	var tw := w * rng.randf_range(0.42, 0.55)
	match rng.randi() % 3:
		0:
			k.block_to(cg, "Shaft", Vector3(c.x, pod_top, c.z), tw, tw, top, b, "light")
			k.block_to(cg, "Crown", Vector3(c.x, top, c.z), tw * 0.7, tw * 0.7, top + 24.0, b, "accent")
			k.block_to(cg, "Glaze", Vector3(c.x, top - 46.0, c.z), tw + 1.0, tw * 0.6, top - 10.0, b, "dark")
		1:
			k.cyl(cg, "Shaft", Vector3(c.x, pod_top, c.z), tw * 0.5, h, "light", "taper")
			k.cyl(cg, "Disc", Vector3(c.x, pod_top + h * 0.72, c.z), tw * 0.62, 6.0, "accent")
		2:
			var t1 := pod_top + h * 0.55
			k.block_to(cg, "Lower", Vector3(c.x, pod_top, c.z), tw * 1.25, tw, t1, b, "light")
			k.block_to(cg, "Upper", Vector3(c.x, t1, c.z), tw * 0.8, tw * 0.8, top, b, "accent")
			k.block_to(cg, "Slot", Vector3(c.x, pod_top + 10.0, c.z), tw * 1.3, 4.0, t1 - 10.0, b, "dark")

func _terrace_cell(g: Node3D, name: String, r0: float, r1: float, a0: float, a1: float, top_y: float) -> void:
	var cg := k.group(g, name)
	var steps := 3
	for i in range(steps):
		var rr0 := lerpf(r0, r1, float(i) / steps)
		var rr1 := lerpf(r0, r1, float(i + 1) / steps) - 6.0
		var segs := maxi(1, int((a1 - a0) * rr1 / 60.0))
		for sgi in range(segs):
			var aa := lerpf(a0, a1, float(sgi) / segs)
			var ab := lerpf(a0, a1, float(sgi + 1) / segs)
			var rm := (rr0 + rr1) * 0.5
			_bar(cg, "Step%d_%d" % [i, sgi], _polar(rm, aa), _polar(rm, ab), rr1 - rr0, top_y - i * 9.0, "floor" if i == steps - 1 else "light")

func _far_skyline(g: Node3D) -> void:
	## Distant island clusters on the horizon -- silhouettes only.
	rng.seed = 99
	var clusters := [[200.0, 2300.0], [250.0, 2000.0], [300.0, 2600.0], [20.0, 2200.0], [100.0, 2500.0], [150.0, 1900.0], [340.0, 2100.0]]
	var n := 0
	for cl in clusters:
		var a := deg_to_rad(cl[0])
		var cc := Vector3(-350 + cos(a) * cl[1], WATER_Y, -350 + sin(a) * cl[1])
		var cg := k.group(g, "Island%d" % n)
		k.cyl(cg, "Base", cc, 260.0, 12.0, "floor", "cyl16")
		for i in range(rng.randi_range(7, 13)):
			var off := Vector3(rng.randf_range(-190, 190), 12.0, rng.randf_range(-190, 190))
			var h := rng.randf_range(70.0, 300.0) * (1.0 - off.length() / 400.0)
			if rng.randf() < 0.35:
				k.cyl(cg, "T%02d" % i, cc + off, rng.randf_range(16, 30), h, "mid", "cyl16")
			else:
				k.block(cg, "T%02d" % i, cc + off, Vector3(rng.randf_range(36, 70), h, rng.randf_range(36, 70)), k.yaw_deg(cl[0]), "mid")
		n += 1

# =============================================================================
# SHARED HELPERS
# =============================================================================

const CL := 37.0  # lateral guard for anything at road height

func ty(d: float) -> float:
	return k.center(d).y

func bank_extra(d: float) -> float:
	var u := k.track_up(d)
	return 34.0 * sqrt(maxf(0.0, 1.0 - u.y * u.y))

## Clear height above the road over a window (incl. banking lift at the walls).
func clear_y(d0: float, d1: float, margin := 4.0) -> float:
	var m := -INF
	var d := d0
	while d <= d1:
		m = maxf(m, ty(d) + bank_extra(d))
		d += 4.0
	return m + UtopiaKit.CLEAR_H + margin

## Footprint guard: false if a solid from bot..top would sit in the race envelope.
func _guard(name: String, c: Vector3, w: float, dpt: float, b: Basis, bot: float, top: float) -> bool:
	var nx := maxi(2, ceili(w / 12.0))
	var nz := maxi(2, ceili(dpt / 12.0))
	for ix in range(nx + 1):
		for iz in range(nz + 1):
			var p := c + b.x * (w * (float(ix) / nx - 0.5)) + b.z * (dpt * (float(iz) / nz - 0.5))
			var r := near_track(p)
			if r.x < CL and top > r.y - 7.0 and bot < r.y + UtopiaKit.CLEAR_H + 2.0:
				print("  GUARD skip %s/%s (%.0f m from track)" % [k.current_district, name, r.x])
				return false
	return true

## Track-aligned block at (d, lat): `along` runs with the track, `across` perpendicular.
func tb(g: Node, name: String, d: float, lat: float, along: float, across: float, top_y: float,
		mat := "light", bot_y := WATER_Y, yaw := 0.0) -> MeshInstance3D:
	var b := k.yaw_at(d, yaw)
	var base := k.at_y(d, lat, bot_y)
	if not _guard(name, base, across, along, b, bot_y, top_y):
		return null
	return k.block_to(g, name, base, across, along, top_y, b, mat)

## World block (base point) with guard.
func wb(g: Node, name: String, base: Vector3, w: float, dpt: float, top_y: float, b := Basis.IDENTITY, mat := "light") -> MeshInstance3D:
	if not _guard(name, base, w, dpt, b, base.y, top_y):
		return null
	return k.block_to(g, name, base, w, dpt, top_y, b, mat)

## Cylinder with guard (circular footprint test).
func wc(g: Node, name: String, base: Vector3, r: float, top_y: float, mat := "light", key := "cyl") -> MeshInstance3D:
	for i in range(17):
		var p := base if i == 16 else base + Vector3(cos(TAU * i / 16.0), 0, sin(TAU * i / 16.0)) * r
		var q := near_track(p)
		if q.x < CL and top_y > q.y - 7.0 and base.y < q.y + UtopiaKit.CLEAR_H + 2.0:
			print("  GUARD skip %s/%s (%.0f m from track)" % [k.current_district, name, q.x])
			return null
	return k.cyl(g, name, base, r, top_y - base.y, mat, key)

## Arch over the track with the rise solved for clearance.
func arch_auto(g: Node, name: String, d: float, hs: float, thick: float, depth: float,
		spring_y: float, mat := "light", extra := 6.0, pier_to := WATER_Y) -> Node3D:
	var need := clear_y(d - depth, d + depth, extra) - spring_y
	var f := sqrt(maxf(1.0 - pow((CL - 2.0) / hs, 2.0), 0.05))
	return k.arch_over(g, name, d, hs, need / f, thick, depth, spring_y, pier_to, mat)

## Tower composition on a base point. style: "slab", "round", "stepped", "needle"
func tower(g: Node, name: String, base: Vector3, w: float, top: float, b: Basis, style: String, main := "light") -> void:
	var tg := k.group(g, name)
	var h := top - base.y
	match style:
		"slab":
			k.block_to(tg, "Shaft", base, w, w * 0.45, top, b, main)
			k.block_to(tg, "Fin", base + b.x * (w * 0.5 + 2.0), 4.0, w * 0.5, top + 14.0, b, "accent")
			k.block_to(tg, "Glaze", base + b.z * (w * 0.23), w * 0.82, 1.5, top - 8.0, b, "dark")
		"round":
			k.cyl(tg, "Shaft", base, w * 0.5, h, main)
			k.cyl(tg, "Band1", base + Vector3.UP * h * 0.62, w * 0.5 + 3.0, 5.0, "accent")
			k.cyl(tg, "Top", base + Vector3.UP * h, w * 0.32, 22.0, "mid")
		"stepped":
			var t1 := base.y + h * 0.5
			var t2 := base.y + h * 0.8
			k.block_to(tg, "T1", base, w, w, t1, b, main)
			k.block_to(tg, "T2", Vector3(base.x, t1, base.z), w * 0.72, w * 0.72, t2, b, "mid")
			k.block_to(tg, "T3", Vector3(base.x, t2, base.z), w * 0.46, w * 0.46, top, b, main)
		"needle":
			k.cyl(tg, "Shaft", base, w * 0.5, h * 0.82, main, "taper")
			k.cyl(tg, "Pod", base + Vector3.UP * h * 0.74, w * 1.1, 10.0, "accent")
			k.cyl(tg, "Spike", base + Vector3.UP * h * 0.82, w * 0.12, h * 0.18, main, "cone")

## A pylon at d must not land on a lower pass of the track (the stacked
## section where 4530-4620 runs alongside 5030-5115).
func _pylon_ok(d: float) -> bool:
	var c := k.center(d)
	for i in range(_pts.size()):
		var dd := float(i) * 4.0
		var gap := absf(dd - d)
		gap = minf(gap, k.length - gap)
		if gap < 150.0:
			continue
		var q: Vector3 = _pts[i]
		if q.y < c.y and Vector2(q.x - c.x, q.z - c.z).length() < 48.0:
			return false
	return true

# =============================================================================
# CONCOURSE  5650 .. 6014 .. 300   (final + start straight, heading west)
# Waterfront boulevard. Right = north = monumental city, left = south = bay.
# =============================================================================

func district_concourse(root: Node3D) -> void:
	# --- the four rings (moved from the track scene, same transforms) ---
	var rings := k.group(root, "Rings")
	var tm := TorusMesh.new()
	tm.inner_radius = 5.312
	tm.outer_radius = 8.859
	tm.rings = 48
	tm.ring_segments = 20
	for i in range(4):
		var x: float = [75.66658, 121.32084, 171.89388, 213.60025][i]
		var mi := MeshInstance3D.new()
		mi.name = "Ring%d" % (i + 1)
		mi.mesh = tm
		mi.material_override = k.mats["accent"]
		mi.transform = Transform3D(Basis(Vector3(0, 8, 0), Vector3(-8, 0, 0), Vector3(0, 0, 8)), Vector3(x, 10.877743, -3.7573605))
		rings.add_child(mi)

	# --- promenade decks just below road level ---
	var deck := k.group(root, "Promenade")
	wb(deck, "DeckN", Vector3(-10.0, WATER_Y, -84.0), 520.0, 84.0, -7.0, Basis.IDENTITY, "floor")
	wb(deck, "DeckS", Vector3(-20.0, WATER_Y, 56.0), 560.0, 30.0, -9.0, Basis.IDENTITY, "floor")

	# --- north facade: civic slabs on pilotis, rhythm broken by two gaps
	#     that open views to the Spire ---
	var north := k.group(root, "NorthFacades")
	var xs := [300.0, 225.0, 150.0, 30.0, -45.0, -230.0, -305.0]
	var hs := [95.0, 140.0, 118.0, 165.0, 128.0, 150.0, 110.0]
	for i in range(xs.size()):
		var x: float = xs[i]
		var top: float = hs[i]
		var sg := k.group(north, "Block%02d" % i)
		wb(sg, "Podium", Vector3(x, WATER_Y, -112.0), 66.0, 52.0, -7.0, Basis.IDENTITY, "mid")
		for cx: float in [-27.0, -9.0, 9.0, 27.0]:
			wb(sg, "Col%d" % int(cx + 30), Vector3(x + cx, -7.0, -92.0), 2.5, 2.5, 24.0, Basis.IDENTITY, "light")
		wb(sg, "Lobby", Vector3(x, -7.0, -120.0), 58.0, 30.0, 24.0, Basis.IDENTITY, "dark")
		wb(sg, "Slab", Vector3(x, 24.0, -112.0), 66.0, 46.0, top, Basis.IDENTITY, "light")
		wb(sg, "Cornice", Vector3(x, top, -112.0), 70.0, 50.0, top + 3.0, Basis.IDENTITY, "accent")
		wb(sg, "Crown", Vector3(x + 10.0 * (i % 2 * 2 - 1), top + 3.0, -122.0), 30.0, 22.0, top + 26.0 + (i % 3) * 12.0, Basis.IDENTITY, "mid")
	# sky-bridges tying the slabs together above the gaps
	wb(north, "SkyBridgeA", Vector3(90.0, 96.0, -104.0), 60.0, 12.0, 104.0, Basis.IDENTITY, "accent")
	wb(north, "SkyBridgeB", Vector3(-137.0, 70.0, -104.0), 120.0, 12.0, 78.0, Basis.IDENTITY, "accent")

	# --- south: low pavilions on the bay -- keep water and sky open ---
	var south := k.group(root, "BayFront")
	for i in range(5):
		var x := 320.0 - i * 140.0
		if absf(x + 120.0) < 50.0:
			continue
		wb(south, "Pavilion%d" % i, Vector3(x, WATER_Y, 84.0), 54.0, 26.0, -9.0, Basis.IDENTITY, "light")
		wb(south, "Canopy%d" % i, Vector3(x, -9.0, 84.0), 70.0, 40.0, -6.0, Basis.IDENTITY, "accent")
		wb(south, "Mast%d" % i, Vector3(x + 30.0, -6.0, 98.0), 2.0, 2.0, 30.0, Basis.IDENTITY, "light")

	# --- the Gate: twin towers + a bridging hall the track runs beneath ---
	var gate := k.group(root, "Gate")
	var gx := -120.0
	wb(gate, "TowerN", Vector3(gx, WATER_Y, -82.0), 58.0, 58.0, 236.0, Basis.IDENTITY, "light")
	wb(gate, "TowerNCrown", Vector3(gx, 236.0, -82.0), 40.0, 40.0, 262.0, Basis.IDENTITY, "accent")
	wb(gate, "TowerS", Vector3(gx, WATER_Y, 80.0), 58.0, 58.0, 196.0, Basis.IDENTITY, "light")
	wb(gate, "TowerSCrown", Vector3(gx, 196.0, 80.0), 40.0, 40.0, 214.0, Basis.IDENTITY, "accent")
	var by := clear_y(70.0, 170.0, 10.0)
	k.block_to(gate, "Hall", Vector3(gx, by, 0.0), 46.0, 112.0, by + 34.0, Basis.IDENTITY, "light")
	k.block_to(gate, "HallGlaze", Vector3(gx, by + 6.0, 0.0), 48.0, 104.0, by + 28.0, Basis.IDENTITY, "dark")
	k.block_to(gate, "HallSoffit", Vector3(gx, by - 3.0, 0.0), 40.0, 108.0, by, Basis.IDENTITY, "mid")
	k.block_to(gate, "SkyBridge", Vector3(gx, 150.0, 0.0), 18.0, 112.0, 157.0, Basis.IDENTITY, "accent")


# =============================================================================
# TERRACES  300 .. 700   (left bend, dip to -12, climb)
# Right = north: a great stepped terrace climbing away from the track.
# Left = south: water, with an arcade of tall water-arches over the dip.
# =============================================================================

func district_terraces(root: Node3D) -> void:
	var terr := k.group(root, "TerraceHill")
	# five tiers stepping back and up, following the bend
	for i in range(5):
		var lat := 44.0 + i * 26.0
		var top := -10.0 + i * 16.0
		var d := 330.0
		var j := 0
		while d < 690.0:
			tb(terr, "Tier%d_%02d" % [i, j], d + 20.0, lat + 13.0, 42.0, 26.0, top, "light" if i % 2 == 0 else "mid")
			# planter lip (accent line catching the sun)
			tb(terr, "Lip%d_%02d" % [i, j], d + 20.0, lat + 1.0, 42.0, 2.0, top + 3.0, "accent", top)
			d += 44.0
			j += 1
	# crown building on the terrace
	tower(terr, "CrownTower", k.at_y(520.0, 190.0, 54.0), 46.0, 210.0, k.yaw_at(520.0), "stepped")
	# water arches over the dip
	var arches := k.group(root, "WaterArches")
	var ds := [450.0, 520.0, 590.0]
	for i in range(ds.size()):
		arch_auto(arches, "Arch%d" % i, ds[i], 60.0 - i * 4.0, 7.0, 12.0, WATER_Y, "accent", 8.0 + i * 6.0)
	# lone slender towers standing in the bay (left side)
	var bay := k.group(root, "BayTowers")
	tower(bay, "Needle1", k.at_y(420.0, -170.0, WATER_Y), 18.0, 150.0, Basis.IDENTITY, "needle")
	tower(bay, "Needle2", k.at_y(560.0, -230.0, WATER_Y), 22.0, 210.0, Basis.IDENTITY, "needle")
	tower(bay, "Round1", k.at_y(660.0, -140.0, WATER_Y), 30.0, 120.0, Basis.IDENTITY, "round")

# =============================================================================
# SKYWAY  700 .. 1300   (climb to 53, banked right-hander)
# Open and high. Viaduct pylons into the water, the city falls away to the
# right revealing the Spire; a sky-bridge frames the crest.
# =============================================================================

func district_skyway(root: Node3D) -> void:
	k.pylons(root, "Pylons", 720.0, 1420.0, 64.0, 8.0, "mid", _pylon_ok)
	# two tall, thin parabolic arches springing from the water over the climb
	var tall := k.group(root, "SkyArches")
	arch_auto(tall, "SkyArch1", 800.0, 72.0, 5.0, 6.0, WATER_Y, "accent", 30.0)
	arch_auto(tall, "SkyArch2", 905.0, 72.0, 5.0, 6.0, WATER_Y, "accent", 52.0)
	var crest := 1110.0
	var g := k.group(root, "CrestFrame")
	var by := clear_y(crest - 40.0, crest + 40.0, 18.0)
	var b := k.yaw_at(crest)
	# inside tower (right) and outside tower (left)
	tower(g, "InnerTower", k.at_y(crest, 92.0, WATER_Y), 50.0, by + 150.0, b, "slab")
	tower(g, "OuterTower", k.at_y(crest, -86.0, WATER_Y), 34.0, by + 70.0, b, "round")
	var bridge_len := 92.0 + 86.0
	var mid := (k.at_y(crest, 92.0, by) + k.at_y(crest, -86.0, by)) * 0.5
	k.block_to(g, "SkyBridge", mid + Vector3.DOWN * 10.0, bridge_len, 16.0, by + 2.0, b, "accent")
	k.block_to(g, "SkyBridgeGlaze", mid + Vector3.DOWN * 8.0, bridge_len - 4.0, 17.0, by - 1.0, b, "dark")
	# outside of the sweep: needles in the water for parallax
	var outer := k.group(root, "OuterNeedles")
	var ns := [[800.0, -150.0, 170.0], [920.0, -210.0, 240.0], [1010.0, -130.0, 140.0], [1210.0, -170.0, 200.0], [1330.0, -120.0, 150.0]]
	for i in range(ns.size()):
		tower(outer, "Needle%d" % i, k.at_y(ns[i][0], ns[i][1], WATER_Y), 16.0 + i % 2 * 6.0, ns[i][2], Basis.IDENTITY, "needle")
	# inside: low stepped quay blocks so the view to the Spire stays open
	var quay := k.group(root, "InnerQuay")
	var d := 760.0
	var j := 0
	while d < 1300.0:
		tb(quay, "Quay%02d" % j, d, 60.0, 50.0, 30.0, ty(d) - 12.0, "floor")
		d += 60.0
		j += 1

# =============================================================================
# CANYON  1300 .. 1900  (descent north, chicane at the bottom)
# Tall walls both sides, sky-bridges stacked overhead, and the chicane runs
# through a ribbed tunnel inside a megablock ("The Atrium").
# =============================================================================

func district_canyon(root: Node3D) -> void:
	var walls := k.group(root, "Walls")
	var d := 1320.0
	var i := 0
	var tops := [150.0, 210.0, 120.0, 180.0, 240.0, 140.0, 190.0]
	while d < 1600.0:
		var tl: float = tops[i % tops.size()]
		var tr: float = tops[(i + 3) % tops.size()]
		tb(walls, "L%02d" % i, d, -62.0, 50.0, 40.0, tl, "light" if i % 2 == 0 else "mid")
		tb(walls, "R%02d" % i, d + 26.0, 64.0, 50.0, 44.0, tr, "mid" if i % 2 == 0 else "light")
		d += 58.0
		i += 1
	# stacked sky-bridges across the canyon at different heights
	var br := k.group(root, "SkyBridges")
	var spans := [[1360.0, 60.0], [1420.0, 96.0], [1470.0, 44.0], [1530.0, 128.0], [1560.0, 70.0]]
	for j in range(spans.size()):
		var dd: float = spans[j][0]
		var y := maxf(spans[j][1], clear_y(dd - 10.0, dd + 10.0, 10.0))
		k.bridge_over(br, "Bridge%d" % j, dd, y, 132.0, 10.0 + (j % 2) * 6.0, 5.0, "accent", (j % 3 - 1) * 8.0)
	# the Atrium: ribbed tunnel through the chicane
	var t0 := 1625.0
	var t1 := 1790.0
	var atr := k.group(root, "Atrium")
	k.tunnel(atr, "Tunnel", t0, t1, 38.0, 28.0, 16.0, "mid")
	var roof_y := k.max_y(t0, t1) + 28.0 + 12.0
	var c0 := k.center(t0)
	var c1 := k.center(t1)
	var mid := (c0 + c1) * 0.5
	var along := Vector3(c1.x - c0.x, 0, c1.z - c0.z)
	var b := Basis.looking_at(along.normalized(), Vector3.UP)
	k.block_to(atr, "Mass", Vector3(mid.x, roof_y, mid.z), 150.0, along.length() + 10.0, roof_y + 60.0, b, "light")
	k.block_to(atr, "MassCrown", Vector3(mid.x, roof_y + 60.0, mid.z), 90.0, along.length() - 40.0, roof_y + 84.0, b, "mid")
	wb(atr, "FlankL", Vector3(mid.x, WATER_Y, mid.z) - b.x * 80.0, 42.0, along.length(), roof_y + 60.0, b, "light")
	wb(atr, "FlankR", Vector3(mid.x, WATER_Y, mid.z) + b.x * 80.0, 42.0, along.length(), roof_y + 60.0, b, "light")
	# portal frames at the mouths
	for e: float in [t0, t1]:
		var pb := k.yaw_at(e)
		var pc := k.center(e)
		k.block_to(atr, "Portal%d" % int(e), Vector3(pc.x, pc.y + 28.0 + 6.0, pc.z), 120.0, 8.0, roof_y + 66.0, pb, "accent")
	# exit vista towers
	tower(root, "ExitTowerL", k.at_y(1860.0, -80.0, WATER_Y), 40.0, 170.0, k.yaw_at(1860.0), "stepped")
	tower(root, "ExitTowerR", k.at_y(1880.0, 76.0, WATER_Y), 30.0, 230.0, k.yaw_at(1880.0), "round")

# =============================================================================
# CORNER  1900 .. 2300  (climb to 25, banked right turn to heading east)
# A civic dome sits inside the corner; a tall colonnade (stoa) wraps the
# outside so columns whip past through the turn.
# =============================================================================

func district_corner(root: Node3D) -> void:
	var dome := k.group(root, "Dome")
	var dc := DOME
	k.cyl(dome, "Plinth", dc, 110.0, 34.0, "mid")
	k.cyl(dome, "Drum", dc + Vector3.UP * 34.0, 82.0, 48.0, "light")
	k.cyl(dome, "Gallery", dc + Vector3.UP * 82.0, 86.0, 4.0, "accent")
	k.dome(dome, "Shell", dc + Vector3.UP * 86.0, 80.0, "light", 0.85)
	k.cyl(dome, "Lantern", dc + Vector3.UP * (86.0 + 80.0 * 0.85 - 4.0), 12.0, 26.0, "accent")
	var stoa := k.group(root, "Stoa")
	var d := 1990.0
	var i := 0
	var top := k.max_y(1990.0, 2320.0) + 46.0
	while d < 2320.0:
		tb(stoa, "Col%02d" % i, d, -46.0, 4.0, 4.0, top, "light", WATER_Y)
		d += 14.0
		i += 1
	k.ribbon(stoa, "Entablature", 1985.0, 2325.0, -52.0, -42.0, 0.0, 6.0, "accent", 5.0, top + 6.0)
	# backdrop: stepped blocks behind the stoa
	var back := k.group(root, "Backdrop")
	d = 2000.0
	i = 0
	while d < 2300.0:
		tb(back, "B%02d" % i, d, -100.0 - (i % 2) * 20.0, 60.0, 50.0, top + 30.0 + (i % 3) * 30.0, "mid")
		d += 66.0
		i += 1

# =============================================================================
# ARCADE  2300 .. 2900  (eastbound boulevard, then right turn south)
# A run of identical arches marches over the track; then a slab building on
# pilotis straddles the bend.
# =============================================================================

func district_arcade(root: Node3D) -> void:
	var arc := k.group(root, "Arcade")
	var d := 2380.0
	var i := 0
	while d <= 2560.0:
		var sy := ty(d) + 4.0
		tb(arc, "PodL%d" % i, d, -54.0, 30.0, 26.0, sy, "mid")
		tb(arc, "PodR%d" % i, d, 54.0, 30.0, 26.0, sy, "mid")
		arch_auto(arc, "Arch%d" % i, d, 48.0, 6.0, 9.0, sy, "light", 8.0, sy)
		d += 45.0
		i += 1
	# flanking blocks
	var fl := k.group(root, "Flanks")
	d = 2340.0
	i = 0
	while d < 2620.0:
		tb(fl, "N%02d" % i, d, -96.0, 44.0, 40.0, 60.0 + (i % 3) * 22.0, "light")
		tb(fl, "S%02d" % i, d + 20.0, 100.0, 44.0, 44.0, 80.0 + ((i + 1) % 3) * 30.0, "light" if i % 2 else "mid")
		d += 52.0
		i += 1
	# pilotis slab over the bend
	var pil := k.group(root, "PilotisHall")
	var p0 := 2660.0
	var p1 := 2770.0
	var c0 := k.center(p0)
	var c1 := k.center(p1)
	var mid := (c0 + c1) * 0.5
	var along := Vector3(c1.x - c0.x, 0, c1.z - c0.z)
	var b := Basis.looking_at(along.normalized(), Vector3.UP)
	var under := clear_y(p0 - 20.0, p1 + 20.0, 8.0)
	k.block_to(pil, "Slab", Vector3(mid.x, under, mid.z), 150.0, along.length() + 30.0, under + 26.0, b, "light")
	k.block_to(pil, "Band", Vector3(mid.x, under + 26.0, mid.z), 140.0, along.length() + 20.0, under + 30.0, b, "dark")
	k.block_to(pil, "Roof", Vector3(mid.x, under + 30.0, mid.z), 150.0, along.length() + 30.0, under + 34.0, b, "accent")
	var cols := 0
	for fz in range(-2, 3):
		for fx: float in [-1.0, 1.0]:
			var p := Vector3(mid.x, WATER_Y, mid.z) + b.x * (fx * 66.0) + b.z * (fz * (along.length() + 20.0) / 4.0)
			if wc(pil, "Pilotis%d" % cols, p, 3.2, under, "light") != null:
				cols += 1

# =============================================================================
# HAIRPIN  2900 .. 3150  (slow left hairpin around (-425,-680))
# A pivot tower at the apex carries a huge cantilevered canopy over the turn.
# =============================================================================

func district_hairpin(root: Node3D) -> void:
	var g := k.group(root, "Pivot")
	var c := Vector3(-423.0, WATER_Y, -688.0)   # centre of the largest clear circle (r 59)
	var r := 20.0
	var cy := clear_y(2900.0, 3160.0, 30.0)
	wc(g, "Stem", c, r, cy, "light")
	k.cyl(g, "Collar", Vector3(c.x, cy - 10.0, c.z), r + 6.0, 10.0, "accent")
	k.cyl(g, "Canopy", Vector3(c.x, cy, c.z), 92.0, 5.0, "light", "cyl")
	k.cyl(g, "CanopyEdge", Vector3(c.x, cy + 5.0, c.z), 94.0, 3.0, "accent")
	k.cyl(g, "Upper", Vector3(c.x, cy + 8.0, c.z), r * 0.8, 150.0, "light", "taper")
	k.cyl(g, "Disc", Vector3(c.x, cy + 120.0, c.z), 30.0, 6.0, "accent")
	# ring of low pavilions framing the outside of the hairpin
	var ring := k.group(root, "Circus")
	for i in range(14):
		var a := deg_to_rad(120.0 + i * 15.0)
		var p := c + Vector3(cos(a), 0, sin(a)) * 160.0
		wb(ring, "Bay%02d" % i, p, 30.0, 26.0, 20.0 + (i % 2) * 18.0, Basis.looking_at(Vector3(cos(a), 0, sin(a)), Vector3.UP), "light")

# =============================================================================
# NORTH LOOP  3150 .. 3850  (north, clockwise loop, back south)
# A cluster of towers in the loop core; a bridge from the core leaps over
# the track at the top of the loop. Outside: terraces stepping down to water.
# =============================================================================

func district_northloop(root: Node3D) -> void:
	var core := k.group(root, "Core")
	tower(core, "CoreSlab", Vector3(-300.0, WATER_Y, -840.0), 52.0, 300.0, k.yaw_deg(12.0), "slab")
	tower(core, "CoreRound", Vector3(-250.0, WATER_Y, -760.0), 40.0, 220.0, Basis.IDENTITY, "round")
	tower(core, "CoreStep", Vector3(-286.0, WATER_Y, -700.0), 52.0, 150.0, k.yaw_deg(-8.0), "stepped")
	wb(core, "CorePodium", Vector3(-282.0, WATER_Y, -780.0), 100.0, 200.0, -12.0, Basis.IDENTITY, "mid")
	# bridge from core tower over the loop top to an outer tower
	var bd := 3520.0
	var by := clear_y(bd - 30.0, bd + 30.0, 30.0)
	var outer_p := k.at_y(bd, -110.0, WATER_Y)
	tower(core, "OuterTower", outer_p, 36.0, by + 60.0, k.yaw_at(bd), "round")
	var core_p := Vector3(-300.0, by, -840.0)
	var span := Vector3(outer_p.x - core_p.x, 0, outer_p.z - core_p.z)
	var b := Basis.looking_at(span.normalized(), Vector3.UP)
	k.block_to(core, "LoopBridge", Vector3((core_p.x + outer_p.x) * 0.5, by, (core_p.z + outer_p.z) * 0.5), 14.0, span.length(), by + 8.0, b, "accent")
	# the Halo: a horizontal ring hovering over the loop, hung from the core
	var halo := k.group(root, "Halo")
	var tmh := TorusMesh.new()
	tmh.inner_radius = 150.0
	tmh.outer_radius = 158.0
	tmh.rings = 128
	tmh.ring_segments = 12
	var hy := clear_y(3300.0, 3800.0, 70.0)
	k.mesh_node(halo, "Ring", tmh, Transform3D(Basis.IDENTITY, Vector3(LOOP_C.x, hy, LOOP_C.z)), "accent")
	for i in range(4):
		var a := deg_to_rad(20.0 + i * 90.0)
		var rim := Vector3(LOOP_C.x + cos(a) * 154.0, hy, LOOP_C.z + sin(a) * 154.0)
		var hub := Vector3(-300.0, hy + 90.0, -840.0)
		var v := hub - rim
		var sb := Basis.looking_at(v.normalized(), Vector3.UP if absf(v.normalized().y) < 0.95 else Vector3.RIGHT)
		k.box(halo, "Stay%d" % i, (hub + rim) * 0.5, Vector3(1.6, 1.6, v.length()), sb, "light")
	# outside terraces (north side of the loop)
	var ter := k.group(root, "OuterTerraces")
	var d := 3380.0
	var i := 0
	while d < 3700.0:
		for s in range(3):
			tb(ter, "T%02d_%d" % [i, s], d, -50.0 - s * 24.0, 44.0, 22.0, ty(d) - 10.0 + s * 12.0, "light" if s % 2 == 0 else "mid")
		d += 46.0
		i += 1
	# west side of the northbound run: tall slabs
	var west := k.group(root, "WestSlabs")
	d = 3180.0
	i = 0
	while d < 3400.0:
		tb(west, "W%02d" % i, d, -70.0, 50.0, 40.0, 90.0 + (i % 3) * 40.0, "light" if i % 2 else "mid")
		d += 60.0
		i += 1

# =============================================================================
# SPIRE RUN  3850 .. 4150  (SW, the Spire ahead-right)
# Square portals telescope down the run; low edges keep the Spire in view.
# =============================================================================

func district_spirerun(root: Node3D) -> void:
	var g := k.group(root, "Portals")
	var ds := [3950.0, 4010.0, 4070.0, 4130.0]
	for i in range(ds.size()):
		var d: float = ds[i]
		var b := k.yaw_at(d)
		var top := clear_y(d - 8.0, d + 8.0, 8.0 + i * 3.0)
		var pg := k.group(g, "Portal%d" % i)
		for s: float in [-1.0, 1.0]:
			var p := k.at_y(d, s * 44.0, WATER_Y)
			k.block_to(pg, "Pier%s" % ("L" if s < 0 else "R"), p, 8.0, 8.0, top + 10.0, b, "light")
		k.block_to(pg, "Lintel", k.at_y(d, 0.0, top), 96.0, 8.0, top + 10.0, b, "light")
		k.block_to(pg, "LintelGlow", k.at_y(d, 0.0, top - 0.6), 80.0, 1.0, top, b, "glow")
	# low flanking podiums
	var fl := k.group(root, "Flanks")
	var d := 3880.0
	var i := 0
	while d < 4160.0:
		tb(fl, "L%02d" % i, d, -70.0, 50.0, 40.0, ty(d) + 14.0 + (i % 2) * 10.0, "mid")
		tb(fl, "R%02d" % i, d, 70.0, 50.0, 40.0, ty(d) + 8.0, "light")
		d += 56.0
		i += 1

# =============================================================================
# VIADUCT  4150 .. 4700  (left turn climbing to 24, east, crest at 40)
# The track rises on pylons and passes straight through a tall slab building.
# =============================================================================

func district_viaduct(root: Node3D) -> void:
	k.pylons(root, "Pylons", 4220.0, 4760.0, 60.0, 7.0, "mid", _pylon_ok)
	# the building the track tunnels through
	var t0 := 4360.0
	var t1 := 4440.0
	var bg := k.group(root, "ThroughBuilding")
	k.tunnel(bg, "Bore", t0, t1, 41.0, 36.0, 14.0, "mid")
	var c0 := k.center(t0)
	var c1 := k.center(t1)
	var mid := (c0 + c1) * 0.5
	var along := Vector3(c1.x - c0.x, 0, c1.z - c0.z)
	var b := Basis.looking_at(along.normalized(), Vector3.UP)
	var roof := k.max_y(t0, t1) + 36.0 + 12.0
	var len := along.length() + 6.0
	k.block_to(bg, "Upper", Vector3(mid.x, roof, mid.z), 130.0, len, 190.0, b, "light")
	k.block_to(bg, "UpperGlaze", Vector3(mid.x, roof + 20.0, mid.z) + b.z * (len * 0.5 + 0.5), 110.0, 1.5, 170.0, b, "dark")
	k.block_to(bg, "UpperGlazeB", Vector3(mid.x, roof + 20.0, mid.z) - b.z * (len * 0.5 + 0.5), 110.0, 1.5, 170.0, b, "dark")
	k.block_to(bg, "Crown", Vector3(mid.x, 190.0, mid.z), 80.0, len - 20.0, 206.0, b, "accent")
	var low := k.min_y(t0 - 40.0, t1 + 40.0) - 8.0
	k.block_to(bg, "Lower", Vector3(mid.x, WATER_Y, mid.z), 130.0, len, low, b, "mid")
	wb(bg, "WingL", Vector3(mid.x, WATER_Y, mid.z) - b.x * 64.0, 40.0, len, roof + 10.0, b, "light")
	wb(bg, "WingR", Vector3(mid.x, WATER_Y, mid.z) + b.x * 64.0, 40.0, len, roof + 10.0, b, "light")
	# companion towers along the climb
	var tw := k.group(root, "Companions")
	tower(tw, "C1", k.at_y(4250.0, -80.0, WATER_Y), 36.0, 160.0, k.yaw_at(4250.0), "round")
	tower(tw, "C2", k.at_y(4540.0, 84.0, WATER_Y), 44.0, 220.0, k.yaw_at(4540.0), "slab")
	tower(tw, "C3", k.at_y(4620.0, -90.0, WATER_Y), 30.0, 140.0, k.yaw_at(4620.0), "needle")

# =============================================================================
# SPIRAL  4650 .. 5100  (crest, plunge and left spiral around (80,-450))
# A drum tower stands in the eye of the spiral; the track corkscrews round it.
# =============================================================================

func district_spiral(root: Node3D) -> void:
	var g := k.group(root, "Drum")
	var c := Vector3(80.0, WATER_Y, -452.0)
	var r := 30.0
	wc(g, "Core", c, r, -20.0, "mid")
	# above the highest pass, the drum can widen into a crown
	var cy := clear_y(4600.0, 4800.0, 20.0)
	k.cyl(g, "Shaft", Vector3(c.x, -20.0, c.z), 26.0, cy - (-20.0), "light")
	for i in range(4):
		k.cyl(g, "Ring%d" % i, Vector3(c.x, -10.0 + i * 16.0, c.z), 28.0, 3.0, "accent")
	k.cyl(g, "Crown", Vector3(c.x, cy, c.z), 70.0, 22.0, "light")
	k.cyl(g, "CrownGlaze", Vector3(c.x, cy + 22.0, c.z), 62.0, 14.0, "dark")
	k.cyl(g, "CrownRoof", Vector3(c.x, cy + 36.0, c.z), 72.0, 4.0, "accent")
	k.cyl(g, "Mast", Vector3(c.x, cy + 40.0, c.z), 4.0, 90.0, "light", "cone")
	# twin beacons dead ahead of the crest
	var bea := k.group(root, "CrestBeacons")
	tower(bea, "BeaconA", Vector3(112.0, WATER_Y, -770.0), 30.0, 320.0, Basis.IDENTITY, "needle")
	tower(bea, "BeaconB", Vector3(196.0, WATER_Y, -735.0), 40.0, 250.0, k.yaw_deg(20.0), "slab")
	k.block_to(bea, "BeaconLink", Vector3(154.0, 150.0, -752.0), 8.0, 92.0, 158.0, Basis.looking_at(Vector3(84, 0, 35).normalized(), Vector3.UP), "accent")
	# plunge portal at the bottom of the drop
	var pd := 4835.0
	var pb := k.yaw_at(pd)
	var top := clear_y(pd - 10.0, pd + 10.0, 10.0)
	var pg := k.group(root, "PlungePortal")
	for s: float in [-1.0, 1.0]:
		k.block_to(pg, "Pier%s" % ("L" if s < 0 else "R"), k.at_y(pd, s * 46.0, WATER_Y), 12.0, 12.0, top + 60.0, pb, "light")
	k.block_to(pg, "Head", k.at_y(pd, 0.0, top), 104.0, 12.0, top + 12.0, pb, "accent")

# =============================================================================
# EAST SWEEP  5100 .. 5750  (fast right sweep along the sea, then U-turn)
# Seaward: towers on piers linked by bridges, and a great ring monument.
# Inside the U-turn: a lighthouse.
# =============================================================================

func district_eastsweep(root: Node3D) -> void:
	# THE CRESCENT: one continuous curved range on the inside of the sweep,
	# fins at a steady rhythm lead the eye round the bend.
	var cr := k.group(root, "Crescent")
	var c0 := 5130.0
	var c1 := 5560.0
	k.ribbon_wall(cr, "Range", c0, c1, 78.0, 34.0, WATER_Y, 50.0, "light", 5.0, false)
	k.ribbon_wall(cr, "Glazing", c0 + 4.0, c1 - 4.0, 60.0, 1.0, 14.0, 44.0, "dark", 5.0, false)
	k.ribbon(cr, "Cornice", c0 - 2.0, c1 + 2.0, 57.0, 97.0, 0.0, 4.0, "accent", 5.0, 54.0)
	k.ribbon(cr, "Attic", c0 + 20.0, c1 - 20.0, 72.0, 92.0, 0.0, 10.0, "mid", 5.0, 64.0)
	var d := c0 + 6.0
	var i := 0
	while d < c1 - 4.0:
		tb(cr, "Fin%02d" % i, d, 59.0, 2.0, 3.5, 54.0, "light", 4.0)
		d += 14.0
		i += 1
	# a single tower rises from the crescent's mid-point
	tower(cr, "CrescentTower", k.at_y(5350.0, 96.0, 50.0), 40.0, 200.0, k.yaw_at(5350.0), "slab")
	# SEAWARD COLONNADE: columns and a light entablature on the breakwater
	var col := k.group(root, "SeaColonnade")
	k.ribbon(col, "Mole", 5110.0, 5580.0, -78.0, -38.0, -10.0, 31.0, "floor", 5.0)
	k.ribbon(col, "Entablature", 5120.0, 5570.0, -50.0, -40.0, 30.0, 3.0, "accent", 5.0)
	d = 5124.0
	i = 0
	while d < 5570.0:
		tb(col, "Col%02d" % i, d, -45.0, 2.4, 2.4, ty(d) + 27.0, "light", ty(d) - 10.0)
		d += 16.0
		i += 1
	# far sea towers: horizon accents only, no clutter
	var sea := k.group(root, "SeaTowers")
	tower(sea, "FarA", k.at_y(5420.0, -360.0, WATER_Y), 46.0, 260.0, k.yaw_at(5420.0), "needle")
	tower(sea, "FarB", k.at_y(5560.0, -420.0, WATER_Y), 50.0, 190.0, k.yaw_at(5560.0), "round")
	tower(sea, "FarC", k.at_y(5280.0, -460.0, WATER_Y), 60.0, 150.0, k.yaw_at(5280.0), "stepped")
	# the great ring standing in the sea, facing the sweep
	var mon := k.group(root, "SeaRing")
	var t := TorusMesh.new()
	t.inner_radius = 196.0
	t.outer_radius = 214.0
	t.rings = 128
	t.ring_segments = 20
	var rc := Vector3(720.0, WATER_Y + 205.0, -30.0)
	var face := Vector3(260.0 - rc.x, 0, -300.0 - rc.z).normalized()   # look back up the sweep
	var rb := Basis.looking_at(face, Vector3.UP) * Basis(Vector3.RIGHT, PI * 0.5)
	k.mesh_node(mon, "Ring", t, Transform3D(rb, rc), "accent")
	k.block_to(mon, "Plinth", Vector3(rc.x, WATER_Y, rc.z), 70.0, 34.0, WATER_Y + 12.0, Basis.looking_at(face, Vector3.UP), "mid")
	# lighthouse in the eye of the U-turn
	var lh := k.group(root, "Lighthouse")
	var lp := Vector3(315.0, WATER_Y, -78.0)   # largest clear circle in the U-turn (r 82)
	wc(lh, "Shaft", lp, 11.0, 150.0, "light")
	k.cyl(lh, "Lamp", lp + Vector3.UP * 190.0, 16.0, 14.0, "glow")
	k.cyl(lh, "Cap", lp + Vector3.UP * 204.0, 20.0, 4.0, "accent")
	k.cyl(lh, "Gallery", lp + Vector3.UP * 186.0, 20.0, 4.0, "accent")
	k.cyl(lh, "Neck", lp + Vector3.UP * 150.0, 8.0, 36.0, "light")

# =============================================================================
# MEGA  distant megastructures, 2-3.3 km out, for parallax against the city.
# All within ~3.5 km of the track points that see them: the race camera's far
# plane is Godot's default 4000 m (AGCamera2097 doesn't set it).
# =============================================================================

func district_mega(root: Node3D) -> void:
	# M1 -- the Continuous Monument: a 2.8 km slab on legs along the south horizon
	var cm := k.group(root, "ContinuousMonument")
	var cz := 1950.0
	k.block_to(cm, "Slab", Vector3(-900.0, 560.0, cz), 2800.0, 170.0, 740.0, Basis.IDENTITY, "far")
	k.block_to(cm, "Band", Vector3(-900.0, 610.0, cz - 86.0), 2760.0, 4.0, 690.0, Basis.IDENTITY, "dark")
	k.block_to(cm, "Soffit", Vector3(-900.0, 546.0, cz), 2780.0, 150.0, 560.0, Basis.IDENTITY, "far")
	for i in range(8):
		var x := -2200.0 + i * 370.0
		k.block_to(cm, "Leg%d" % i, Vector3(x, WATER_Y, cz), 80.0, 130.0, 546.0, Basis.IDENTITY, "far")
	# M2 -- arcology: stepped pyramid on the western horizon
	var ar := k.group(root, "Arcology")
	var ac := Vector3(-2750.0, WATER_Y, 220.0)
	var w := 1000.0
	var y := WATER_Y
	for i in range(9):
		var h := 130.0 - i * 6.0
		k.block_to(ar, "Tier%d" % i, Vector3(ac.x, y, ac.z), w, w, y + h, k.yaw_deg(18.0), "far" if i % 2 == 0 else "far")
		k.block_to(ar, "Glaze%d" % i, Vector3(ac.x, y + h * 0.3, ac.z), w + 2.0, w * 0.6, y + h * 0.75, k.yaw_deg(18.0), "dark")
		y += h
		w *= 0.78
	k.cyl(ar, "Crown", Vector3(ac.x, y, ac.z), 50.0, 320.0, "far", "taper")
	# M3 -- twin megatowers joined by a sky-bridge, north
	var tw := k.group(root, "TwinTowers")
	# on the canyon's sightline (1300-1600 runs NNE), so the slot frames them
	var ta := Vector3(-170.0, WATER_Y, -2935.0)
	var tb2 := Vector3(300.0, WATER_Y, -2745.0)
	tower(tw, "TowerA", ta, 200.0, 1500.0, k.yaw_deg(15.0), "slab", "far")
	tower(tw, "TowerB", tb2, 230.0, 1700.0, k.yaw_deg(15.0), "stepped", "far")
	var span := Vector3(tb2.x - ta.x, 0, tb2.z - ta.z)
	k.block_to(tw, "SkyBridge", (ta + tb2) * 0.5 + Vector3.UP * (1150.0 - WATER_Y), 80.0, span.length(), 1230.0, Basis.looking_at(span.normalized(), Vector3.UP), "accent")
	# M4 -- the sea arch: a 1.4 km arch standing in the eastern sea
	var sa := k.group(root, "SeaArch")
	var am := k.arch_mesh(600.0, 950.0, 70.0, 90.0, 40)
	var face := Vector3(-1.0, 0.0, 0.25).normalized()
	k.mesh_node(sa, "Arch", am, Transform3D(Basis.looking_at(face, Vector3.UP), Vector3(2650.0, WATER_Y, -700.0)), "accent")
	# M5 -- needle cluster, north-east
	var nd := k.group(root, "Needles")
	tower(nd, "N1", Vector3(1450.0, WATER_Y, -2350.0), 120.0, 1500.0, Basis.IDENTITY, "needle", "far")
	tower(nd, "N2", Vector3(1700.0, WATER_Y, -2150.0), 95.0, 1150.0, Basis.IDENTITY, "needle", "far")
	tower(nd, "N3", Vector3(1250.0, WATER_Y, -2100.0), 80.0, 950.0, Basis.IDENTITY, "needle", "far")
	k.cyl(nd, "Base", Vector3(1480.0, WATER_Y, -2200.0), 380.0, 30.0, "floor", "cyl16")
