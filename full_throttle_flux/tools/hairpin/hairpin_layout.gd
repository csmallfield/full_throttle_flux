extends UtopiaLayout
class_name HairpinLayout
## Hairpin Alley: dense night city. The raceway is an elevated deck threading
## a tight grid of towers; buildings stand right at the walls (lateral 38 m),
## upper floors and sky-bridges oversail the track, seven fully enclosed
## tunnels bore through megablocks, and every corner gets an animated arrow
## billboard on its outside (plus overhead arrow gantries before the big ones).
##
## Shares UtopiaKit / UtopiaLayout helpers (track space, clearance guards).
## Build: godot --path . -s res://tools/hairpin/build_hairpin.gd   (not headless: MultiMesh infill)

const GROUND_Y := -24.0          # street level (lowest road deck is ~14 m above)
const FRONT_LAT := 38.0          # facade line, measured from the centreline
const CITY_C := Vector3(-185.0, 0.0, -390.0)   # densest point of the city

## Fully enclosed tunnels: [from_d, to_d, neon material, label]
const TUNNELS := [
	[380.0, 640.0, "cyan", "GateTunnel"],
	[1080.0, 1320.0, "amber", "MarketBore"],
	[1900.0, 2200.0, "magenta", "TowerBore"],
	[2700.0, 3000.0, "cyan", "LongBore"],
	[3950.0, 4200.0, "amber", "NorthBore"],
	[5080.0, 5380.0, "magenta", "RampBore"],
	[6560.0, 6800.0, "white", "HomeBore"],
]
const NEONS := ["cyan", "magenta", "amber", "white"]
const NEON_COLORS := {"cyan": Color(0.2, 0.9, 1.0), "magenta": Color(1.0, 0.2, 0.7),
	"amber": Color(1.0, 0.58, 0.15), "white": Color(0.85, 0.92, 1.0)}

var corners := []        # [d0, d1, total_deg (+ right), apex_d]
var billboard_spots := []      # world positions of the placed corner boards (for spill lights)
var billboard_spots_col := []
var _curv := PackedFloat32Array()

func _init(kit: UtopiaKit) -> void:
	super(kit)
	k.gen_mesh_dir = "res://scenes/tracks/hairpin_alley/meshes"
	var M := "res://scenes/tracks/hairpin_alley/materials/"
	for pair in [["win", "night_windows"], ["win_tower", "night_windows_tower"], ["concrete", "night_concrete"],
			["ndark", "night_dark"], ["street", "night_street"], ["cyan", "neon_cyan"], ["magenta", "neon_magenta"],
			["amber", "neon_amber"], ["white", "neon_white"], ["red", "beacon_red"], ["screen", "night_screen"]]:
		k.mats[pair[0]] = load(M + pair[1] + ".tres")
	var qpath := "res://scenes/tracks/hairpin_alley/meshes/unit_quad.tres"
	if not ResourceLoader.exists(qpath):
		var q := QuadMesh.new()
		q.size = Vector2.ONE
		ResourceSaver.save(q, qpath)
	k.meshes["quad"] = load(qpath)
	_find_corners()

func district_ids() -> Array:
	return ["ground", "frontage", "infill", "tunnels", "signs", "landmarks", "lights"]

func lighting_params() -> Dictionary:
	return {"sky_preset": "night", "root_name": "HairpinLighting",
		"glow_intensity": 0.85, "glow_bloom": 0.08, "glow_threshold": 0.9,
		"fog_height": 0.0, "fog_height_density": 0.02}

# =============================================================================
# analysis
# =============================================================================

## Signed curvature (deg per m, + = right turn) every 5 m, and the corner list.
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

## _guard without the log line (used for placement searches)
func _guard_quiet(c: Vector3, w: float, dpt: float, b: Basis, bot: float, top: float) -> bool:
	var nx := maxi(2, ceili(w / 8.0))
	var nz := maxi(2, ceili(dpt / 8.0))
	for ix in range(nx + 1):
		for iz in range(nz + 1):
			var p := c + b.x * (w * (float(ix) / nx - 0.5)) + b.z * (dpt * (float(iz) / nz - 0.5))
			var r := near_track(p)
			if r.x < CL and top > r.y - 7.0 and bot < r.y + UtopiaKit.CLEAR_H + 2.0:
				return false
	return true

func curv_at(d: float) -> float:
	return _curv[int(fposmod(d, k.length) / 5.0) % _curv.size()]

func in_tunnel(d: float, margin := 0.0) -> bool:
	for t in TUNNELS:
		if d >= t[0] - margin and d <= t[1] + margin:
			return true
	return false

func road_y(d: float) -> float:
	return k.center(d).y + 2.0

func rand_neon() -> String:
	return NEONS[rng.randi() % NEONS.size()]

func screen(g: Node, name: String, c: Vector3, size: Vector2, facing: Vector3, color: Color, arrow := 0.0, seed := 0.0) -> MeshInstance3D:
	## Quad whose front (+Z) faces `facing` (a direction toward the viewer).
	var f := Vector3(facing.x, 0.0, facing.z).normalized()
	var b := Basis.looking_at(-f, Vector3.UP).scaled_local(Vector3(size.x, size.y, 1.0))
	var mi := k._mi(g, name, "quad", Transform3D(b, c), "screen")
	mi.set_instance_shader_parameter("screen_color", color)
	mi.set_instance_shader_parameter("arrow_dir", arrow)
	mi.set_instance_shader_parameter("pattern_seed", seed)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi

# =============================================================================
# GROUND: street plane + deck pylons
# =============================================================================

func district_ground(root: Node3D) -> void:
	k.box(root, "Street", Vector3(-185, GROUND_Y - 1.0, -395), Vector3(6000, 2, 5000), Basis.IDENTITY, "street")
	k.pylons(root, "DeckPylons", 0.0, k.length - 20.0, 46.0, 6.0, "concrete", func(d: float) -> bool:
		# no pylon caps in the tightest hairpins: the 44 m cap would reach the
		# other side of the corner
		return _pylon_ok(d) and absf(curv_at(d)) < 0.9)

# =============================================================================
# FRONTAGE: buildings lining both sides of the deck, track-aligned
# =============================================================================

## Office-scale lots: 60-120 m along the track, 50-90 m deep. Corner insides
## still get the small 22 x 24 m blocks (the hairpin eyes are too tight).
const LOT_ALONG := Vector2(60.0, 120.0)
const LOT_DEPTH := Vector2(50.0, 90.0)
const MAX_RECESS := 14.0   # how far a lot may sit back to clear the inside of a curve

## Zones along one side of the track, as [from_d, to_d, rank]; where they
## overlap the highest rank wins. Lots are cut at zone edges, never dropped whole.
const Z_FREE := 0
const Z_LOW := 1      # outside of a corner: low shop podiums under the billboard's sight-line
const Z_TIGHT := 2    # inside of a tight corner: small blocks only
const Z_SKIP := 3     # tunnel megablocks, the billboard's own pad

func _side_zones(side: float) -> Array:
	var iv := []
	for t in TUNNELS:
		iv.append([t[0] - 12.0, t[1] + 12.0, Z_SKIP])
	for c in corners:
		var outside := -1.0 if c[2] > 0.0 else 1.0
		if side == outside:
			iv.append([c[0] - 60.0, c[1] + 20.0, Z_LOW])
			iv.append([c[0] - 15.0, c[3] + 15.0, Z_SKIP])   # the board searches d0..apex
	var run0 := -1.0
	var n := _curv.size()
	for j in range(n + 1):
		var c := _curv[j] if j < n else 0.0
		var tight := signf(c) == side and absf(c) > 0.35
		if tight and run0 < 0.0:
			run0 = j * 5.0
		elif not tight and run0 >= 0.0:
			iv.append([run0 - 10.0, j * 5.0 + 10.0, Z_TIGHT])
			run0 = -1.0
	return iv

func _zone_at(iv: Array, d: float) -> int:
	var z := Z_FREE
	for v in iv:
		if d >= v[0] and d < v[1]:
			z = maxi(z, v[2])
	return z

## Next zone edge after d (the zone is constant until then).
func _zone_end(iv: Array, d: float) -> float:
	var e := k.length
	for v in iv:
		for x: float in [v[0], v[1]]:
			if x > d + 0.01 and x < e:
				e = x
	return e

func district_frontage(root: Node3D) -> void:
	rng.seed = 6061
	var tally := {"skip_m": 0.0, "corner_inside": 0, "no_fit": 0, "spire": 0, "lots": 0, "low": 0}
	for side: float in [-1.0, 1.0]:
		var sg := k.group(root, "Left" if side < 0.0 else "Right")
		var iv := _side_zones(side)
		var d := 0.0
		var i := 0
		while d < k.length - 20.0:
			var zone := _zone_at(iv, d)
			var zend := _zone_end(iv, d)
			if zone == Z_SKIP:
				tally.skip_m += zend - d
				d = zend
				continue
			if zone == Z_TIGHT:
				# inside of a corner: short, narrow blocks so they don't fan into each other
				var sd := d + 14.0
				while sd < zend - 8.0:
					var ry0 := road_y(sd)
					var t0 := ry0 + 18.0 + pow(rng.randf(), 1.4) * 120.0
					var lat0 := side * (FRONT_LAT + 12.0 + rng.randf_range(0.0, 4.0))
					if tb(sg, "B%03d" % i, sd, lat0, 22.0, 24.0, t0, "win_tower" if t0 - ry0 > 90.0 else "win", GROUND_Y) != null:
						i += 1
						tally.corner_inside += 1
					sd += 28.0
				d = zend + 6.0
				continue
			# mostly service alleys, now and then a plaza-wide gap
			var gap := rng.randf_range(8.0, 22.0) if rng.randf() < 0.8 else rng.randf_range(30.0, 45.0)
			var along := minf(rng.randf_range(LOT_ALONG.x, LOT_ALONG.y), zend - d - 4.0)
			if along < 30.0:
				d = zend   # too short for a lot: leave it as an alley
				continue
			var lot0 := d
			# a straight box on a gentle curve bows toward the inside: shorten
			# the lot until the bow fits, and push it out by that much
			var tight := _inside_curv(lot0, lot0 + along, side)
			var R := 57.3 / maxf(tight, 0.001)
			along = minf(along, sqrt(8.0 * R * MAX_RECESS))
			d += along + gap
			var recess := along * along / (8.0 * R) if tight > 0.0 else 0.0
			var dc := lot0 + along * 0.5
			var low := zone == Z_LOW
			var ry := road_y(dc)
			var dens := clampf(1.0 - Vector2(k.center(dc).x - CITY_C.x, k.center(dc).z - CITY_C.z).length() / 1100.0, 0.25, 1.0)
			var depth := rng.randf_range(LOT_DEPTH.x, LOT_DEPTH.y)
			var front := FRONT_LAT + recess + rng.randf_range(0.0, 4.0)
			# deep lots hit the other leg of a hairpin: try shallower, then shorter
			var fit := _fit_lot(dc, side, front, along, depth)
			if fit == Vector2.ZERO:
				print("  GUARD skip frontage lot %s d=%.0f" % ["L" if side < 0.0 else "R", dc])
				tally.no_fit += 1
				continue
			var lc := k.at_y(dc, side * (front + fit.y * 0.5), 0.0)
			if Vector2(lc.x - CITY_C.x, lc.z - CITY_C.z).length() < 70.0 + fit.length() * 0.5:
				tally.spire += 1
				continue   # leave the core spire's plaza open
			_frontage_lot(sg, "B%03d" % i, dc, side, front, fit.x, fit.y, ry, dens, low)
			tally.lots += 1
			if low:
				tally.low += 1
			i += 1
	print("  frontage lots: ", tally)
	# sky-bridges and oversailing upper floors on the straighter bits
	var br := k.group(root, "Oversail")
	rng.seed = 6062
	var dd := 60.0
	var j := 0
	while dd < k.length:
		dd += rng.randf_range(90.0, 220.0)
		if in_tunnel(dd, 40.0) or absf(curv_at(dd)) > 0.25:
			continue
		var y := clear_y(dd - 12.0, dd + 12.0, 6.0)
		if rng.randf() < 0.55:
			var by := y + rng.randf_range(0.0, 45.0)
			k.bridge_over(br, "SkyBridge%02d" % j, dd, by + 7.0, 2.0 * (FRONT_LAT + 18.0), rng.randf_range(9.0, 16.0), 7.0, "win", rng.randf_range(-6.0, 6.0))
			k.bridge_over(br, "SkyBridgeTrim%02d" % j, dd, by + 0.6, 2.0 * (FRONT_LAT + 18.0), 0.6, 0.5, rand_neon())
		else:
			var side := -1.0 if rng.randf() < 0.5 else 1.0
			# an upper block cantilevering over the wall, 22+ m up
			tb(br, "Cantilever%02d" % j, dd, side * 34.0, rng.randf_range(24.0, 40.0), 24.0, y + rng.randf_range(16.0, 34.0), "win", y)
		j += 1

## Strongest same-side (inside) curvature over a lot, deg/m; 0 if it only bends away.
func _inside_curv(d0: float, d1: float, side: float) -> float:
	var m := 0.0
	var d := d0
	while d <= d1:
		var c := curv_at(d)
		if signf(c) == side:
			m = maxf(m, absf(c))
		d += 5.0
	return m

## Largest (along, depth) footprint that clears every pass from street to
## a tall top; ZERO if even a 30 x 28 m lot won't fit.
func _fit_lot(dc: float, side: float, front: float, along: float, depth: float) -> Vector2:
	var b := k.yaw_at(dc)
	for a: float in [along, along * 0.7, 30.0]:
		for dp: float in [depth, depth * 0.7, 40.0, 28.0]:
			if a < 30.0 or dp < 28.0:
				continue
			var base := k.at_y(dc, side * (front + dp * 0.5), GROUND_Y)
			if _guard_quiet(base, dp, a, b, GROUND_Y, road_y(dc) + 400.0):
				return Vector2(a, dp)
	return Vector2.ZERO

## One frontage lot: a podium over the whole footprint plus (usually) a
## tower on part of it -- the street wall reads as one big office block.
func _frontage_lot(g: Node, name: String, d: float, side: float, front: float, along: float, depth: float,
		ry: float, dens: float, low: bool) -> void:
	var b := k.yaw_at(d)
	var fwd := k.fwd_flat(d)
	var face := k.right_flat(d) * (-side)                 # toward the track
	var lat := side * (front + depth * 0.5)
	var base := k.at_y(d, lat, GROUND_Y)
	var pod_top := ry + rng.randf_range(10.0, 28.0)
	if low:
		# outside of a corner: the billboard reads above low shop podiums
		pod_top = ry + rng.randf_range(4.0, 8.0)
	elif rng.randf() < 0.25:
		pod_top = ry + rng.randf_range(30.0, 60.0)        # one big mid-rise slab, no tower
	if wb(g, name, base, depth, along, pod_top, b, "win") == null:
		return
	var top := pod_top
	var t_along := along
	var t_depth := depth
	var t_base := base
	if not low and pod_top - ry < 30.0 and rng.randf() < 0.85:
		t_along = along * rng.randf_range(0.45, 0.8)
		t_depth = depth * rng.randf_range(0.5, 0.85)
		# flush with the facade (a straight street wall) or set back from it
		var setback := 0.0 if rng.randf() < 0.5 else rng.randf_range(6.0, minf(15.0, depth - t_depth))
		var slide := rng.randf_range(-0.5, 0.5) * (along - t_along)
		t_base = base + face * (depth * 0.5 - t_depth * 0.5 - setback) + fwd * slide
		top = ry + 40.0 + pow(rng.randf(), 1.5) * 190.0 * dens
		var mat := "win_tower" if top - ry > 90.0 else "win"
		var tw := wb(g, name + "_Tower", Vector3(t_base.x, pod_top, t_base.z), t_depth, t_along, top, b, mat)
		if tw == null:
			top = pod_top
			t_along = along
			t_depth = depth
			t_base = base
	# signs hang on the podium facade, below its roof
	var face_c := base + face * (depth * 0.5 + 0.25)
	var r := rng.randf()
	if r < 0.3 and pod_top - ry > 16.0:
		# vertical blade sign on the facade
		var h := minf(rng.randf_range(12.0, 26.0), pod_top - ry - 4.0)
		var y0 := ry + rng.randf_range(4.0, maxf(4.0, pod_top - ry - h - 2.0))
		var off := fwd * rng.randf_range(-along * 0.4, along * 0.4)
		var bc := Vector3(face_c.x, y0, face_c.z) + off + face * 0.6
		if _guard(name + "_Blade", bc, 4.0, 4.0, b, y0, y0 + h):
			k.box(g, name + "_Blade", bc + Vector3.UP * h * 0.5, Vector3(1.0, h, 4.0), b, ["cyan", "magenta", "amber"][rng.randi() % 3])
	elif r < 0.55 and pod_top - ry > 14.0:
		# ad screen facing the track
		var w := minf(along * 0.5, rng.randf_range(16.0, 30.0))
		var y1 := ry + rng.randf_range(4.0, maxf(4.0, pod_top - ry - w * 0.5 - 2.0)) + w * 0.25
		var off2 := fwd * rng.randf_range(-along * 0.3, along * 0.3)
		screen(g, name + "_Ad", Vector3(face_c.x, y1, face_c.z) + off2 + face * 0.3, Vector2(w, w * 0.5), face, NEON_COLORS[rand_neon()], 0.0, rng.randf() * 10.0)
	if rng.randf() < 0.35:
		# neon crown line on the highest roof
		k.block_to(g, name + "_Crown", Vector3(t_base.x, top, t_base.z), t_depth + 0.6, t_along + 0.6, top + 0.8, b, rand_neon())
	if top - ry > 110.0:
		k.box(g, name + "_Beacon", Vector3(t_base.x, top + 1.5, t_base.z), Vector3(2, 2, 2), b, "red")

# =============================================================================
# INFILL: the rest of the city as chunked MultiMeshes (no shadows, cheap)
# =============================================================================

func district_infill(root: Node3D) -> void:
	rng.seed = 6063
	var chunks := {}   # [tile, mat] -> Array[Transform3D]
	# office-scale city blocks: 60-80 m footprints in the core, 105-140 m outside
	_grid_fill(chunks, Rect2(-1250, -1250, 2100, 1650), 100.0, 80.0, 1.0)     # dense core
	_grid_fill(chunks, Rect2(-2400, -2300, 4300, 3700), 180.0, 140.0, 0.55)   # outer skyline
	var box_mesh: Mesh = k.meshes["box"]
	for key in chunks:
		var arr: Array = chunks[key]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = box_mesh
		mm.instance_count = arr.size()
		for i in range(arr.size()):
			mm.set_instance_transform(i, arr[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Tile_%s_%s" % [key[0], key[1]]
		mmi.multimesh = mm
		mmi.material_override = k.mats[key[1]]
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mmi)

func _grid_fill(chunks: Dictionary, rect: Rect2, cell: float, block: float, height_k: float) -> void:
	var x := rect.position.x
	while x < rect.end.x:
		var z := rect.position.y
		while z < rect.end.y:
			var c := Vector3(x + cell * 0.5, GROUND_Y, z + cell * 0.5)
			z += cell
			# the dense core owns its own rect
			if height_k < 1.0 and Rect2(-1250, -1250, 2100, 1650).has_point(Vector2(c.x, c.z)):
				continue
			if rng.randf() < 0.08:
				continue   # small plazas
			var w0 := block * rng.randf_range(0.75, 1.0)
			var d0 := block * rng.randf_range(0.75, 1.0)
			var b := Basis(Vector3.UP, deg_to_rad(rng.randf_range(-3.0, 3.0)))
			# keep the footprint's edge 60 m off every pass; between hairpin legs
			# shrink the block rather than leave a hole in the skyline
			var w := 0.0
			var dpt := 0.0
			var nt := Vector2.ZERO
			for s: float in [1.0, 0.7, 0.5]:
				nt = footprint_clear(c, w0 * s, d0 * s, b)
				if nt.x >= 60.0:
					w = w0 * s
					dpt = d0 * s
					break
			if w == 0.0:
				continue
			var dist := Vector2(c.x - CITY_C.x, c.z - CITY_C.z).length()
			var dens := clampf(1.0 - dist / 1500.0, 0.12, 1.0)
			var top := GROUND_Y + 25.0 + pow(rng.randf(), 1.6) * 260.0 * dens * height_k
			if nt.x < 150.0:
				top = minf(top, nt.y + 150.0)
			if not _guard("infill", c, w, dpt, b, GROUND_Y, top):
				continue
			var mat := "win_tower" if top - GROUND_Y > 120.0 else "win"
			_chunk(chunks, c, mat, Transform3D(b.scaled_local(Vector3(w, top - GROUND_Y, dpt)), c + Vector3.UP * (top - GROUND_Y) * 0.5))
			# setback tier on tall blocks
			if top - GROUND_Y > 90.0 and rng.randf() < 0.6:
				var t2 := top + rng.randf_range(15.0, 60.0)
				_chunk(chunks, c, mat, Transform3D(b.scaled_local(Vector3(w * 0.6, t2 - top, dpt * 0.6)), c + Vector3.UP * ((top + t2) * 0.5 - GROUND_Y)))
		x += cell

func _chunk(chunks: Dictionary, c: Vector3, mat: String, xf: Transform3D) -> void:
	var key := [str(int(floor(c.x / 600.0))) + "x" + str(int(floor(c.z / 600.0))), mat]
	if not chunks.has(key):
		chunks[key] = []
	chunks[key].append(xf)

# =============================================================================
# TUNNELS: fully enclosed bores through megablocks
# =============================================================================

func _max_bank(d0: float, d1: float) -> float:
	var m := 0.0
	var d := d0
	while d <= d1:
		m = maxf(m, acos(clampf(k.track_up(d).y, -1.0, 1.0)))
		d += 5.0
	return m

func district_tunnels(root: Node3D) -> void:
	rng.seed = 6064
	for t in TUNNELS:
		var d0: float = t[0]
		var d1: float = t[1]
		var neon: String = t[2]
		var g := k.group(root, t[3])
		var hw := 40.0
		var ceil_h := 24.0 + 34.0 * sin(_max_bank(d0, d1)) + 4.0
		k.tunnel(g, "Bore", d0, d1, hw, ceil_h, 14.0, "ndark", neon, "concrete")
		# continuous neon edge lines along both walls at road height + 8
		k.ribbon_wall(g, "NeonL", d0, d1, -hw + 0.2, 0.4, 8.0, 8.6, neon)
		k.ribbon_wall(g, "NeonR", d0, d1, hw - 0.2, 0.4, 8.0, 8.6, neon)
		# the megablock: mass over the roof in track-aligned slices + side masses
		var d := d0 - 10.0
		var i := 0
		while d < d1 + 10.0:
			var seg := rng.randf_range(24.0, 40.0)
			var dc := d + seg * 0.5
			var roof := k.max_y(d, d + seg) + ceil_h + 6.0
			var top := roof + rng.randf_range(25.0, 150.0)
			var b := k.yaw_at(dc)
			tb(g, "Over%02d" % i, dc, 0.0, seg + 2.0, 2.0 * hw + 16.0, top, "win_tower" if top - roof > 90.0 else "win", roof)
			for s: float in [-1.0, 1.0]:
				tb(g, "Side%02d%s" % [i, "L" if s < 0 else "R"], dc, s * (hw + 20.0), seg + 2.0, 32.0, roof + rng.randf_range(0.0, 30.0), "win", GROUND_Y)
			d += seg
			i += 1
		# portals: thick frame + neon outline + sign over each mouth
		for e: float in [d0, d1]:
			var pb := k.yaw_at(e)
			var c := k.center(e)
			var roof_e := c.y + ceil_h + 6.0
			var into := 1.0 if e == d0 else -1.0
			var face := -k.fwd_flat(e) * into           # toward the approaching ship
			k.block_to(g, "Portal%d" % int(e), Vector3(c.x, roof_e - 4.0, c.z) + face * 1.5, 2.0 * hw + 30.0, 5.0, roof_e + 16.0, pb, "concrete")
			k.block_to(g, "PortalNeon%d" % int(e), Vector3(c.x, roof_e - 4.6, c.z) + face * 4.2, 2.0 * hw, 0.6, roof_e - 3.8, pb, neon)
			screen(g, "PortalSign%d" % int(e), Vector3(c.x, roof_e + 6.0, c.z) + face * 4.2, Vector2(46.0, 10.0), face, NEON_COLORS[neon], 0.0, rng.randf() * 10.0)

# =============================================================================
# SIGNS: arrow billboards on the outside of every corner + arrow gantries
# =============================================================================

func district_signs(root: Node3D) -> void:
	rng.seed = 6065
	var n := 0
	for c in corners:
		var d0: float = c[0]
		var d1: float = c[1]
		var total: float = c[2]
		var apex: float = c[3]
		var right := total > 0.0
		var outside := -1.0 if right else 1.0
		var arrow := 1.0 if right else -1.0
		var col: Color = NEON_COLORS[["magenta", "cyan", "amber"][n % 3]]
		var g := k.group(root, "Corner%02d_%s%d" % [n, "R" if right else "L", absi(int(total))])
		# billboard: on the outside of the corner, a bit before the apex, facing
		# the ship on approach so it sits dead ahead as you brake. Search for a
		# clear spot: step outward / along the corner; last resort, lift it
		# above the race envelope so it can oversail the outer wall.
		var size := Vector2(60.0, 20.0) if absf(total) > 90.0 else Vector2(46.0, 16.0)
		var placed := false
		for lift: bool in [false, true]:
			for latm: float in [44.0, 52.0, 62.0, 74.0, 88.0]:
				for frac: float in [0.5, 0.3, 0.7, 0.15]:
					if placed:
						break
					var bd := lerpf(d0, apex, frac)
					var lat := outside * latm
					var ry := road_y(bd)
					var bottom := ry + 10.0
					if lift:
						bottom = clear_y(bd - 30.0, bd + 30.0, 4.0)
					var pos := k.at_y(bd, lat, bottom + size.y * 0.5)
					var viewer := k.at_y(d0 - 160.0, 0.0, road_y(d0 - 160.0) + 6.0)
					var face := (viewer - pos)
					face.y = 0.0
					face = face.normalized()
					var fb := Basis.looking_at(-face, Vector3.UP)
					var base := k.at_y(bd, lat, GROUND_Y)
					# board itself, then the two legs down to the street
					if not _guard_quiet(base, size.x, 6.0, fb, bottom, bottom + size.y + 2.0):
						continue
					var legs_ok := true
					for s: float in [-0.35, 0.35]:
						if not _guard_quiet(base + fb.x * (s * size.x), 3.0, 3.0, fb, GROUND_Y, bottom):
							legs_ok = false
					if not legs_ok:
						continue
					k.block_to(g, "Frame", pos - face * 1.4 + Vector3.DOWN * (size.y * 0.5 + 1.0), size.x + 2.0, 2.0, bottom + size.y + 1.0, fb, "ndark")
					for s: float in [-0.35, 0.35]:
						k.block_to(g, "Leg%d" % int(s * 10), base + fb.x * (s * size.x) - face * 1.4, 2.0, 2.0, bottom, fb, "concrete")
					screen(g, "Screen", pos, size, face, col, arrow)
					k.block_to(g, "TopNeon", pos + Vector3.UP * (size.y * 0.5 + 1.0) - face * 0.6, size.x + 2.0, 0.6, pos.y + size.y * 0.5 + 1.6, fb, "white")
					billboard_spots.append(pos)
					placed = true
		if not placed:
			print("  billboard: no clear spot for corner %d" % n)
		else:
			billboard_spots_col.append(col)
		# overhead arrow gantry before the big corners
		if absf(total) > 90.0:
			var gd := d0 - 120.0
			if not in_tunnel(gd, 20.0):
				var gy := clear_y(gd - 6.0, gd + 6.0, 3.0)
				var gb := k.yaw_at(gd)
				# legs just outside the wall, guarded (banked sections and nearby passes)
				var legs_ok := true
				for s: float in [-1.0, 1.0]:
					if not _guard("GantryLeg", k.at_y(gd, s * 39.0, GROUND_Y), 2.6, 2.6, gb, GROUND_Y, gy + 7.0):
						legs_ok = false
				if legs_ok:
					for s: float in [-1.0, 1.0]:
						k.block_to(g, "GantryLeg%s" % ("L" if s < 0 else "R"), k.at_y(gd, s * 39.0, GROUND_Y), 2.6, 2.6, gy + 7.0, gb, "concrete")
					k.block_to(g, "GantryBeam", k.at_y(gd, 0.0, gy + 5.0), 82.0, 2.4, gy + 7.0, gb, "concrete")
					var gface := -k.fwd_flat(gd)
					screen(g, "GantryScreen", k.at_y(gd, 0.0, gy + 2.5) + gface * 1.4, Vector2(30.0, 5.0), gface, col, arrow)
		n += 1

# =============================================================================
# LANDMARKS: towers in the eyes of the big hairpins + the city core spire
# =============================================================================

func district_landmarks(root: Node3D) -> void:
	rng.seed = 6066
	var i := 0
	for c in corners:
		if absf(c[2]) < 110.0:
			continue
		# inside of the corner at the apex
		var inside := 1.0 if c[2] > 0.0 else -1.0
		var apex: float = c[3]
		var p := k.at_y(apex, inside * 70.0, GROUND_Y)
		var nt := near_track(p)
		if nt.x < 44.0:
			continue
		var r := clampf(nt.x - 40.0, 10.0, 26.0)
		var top := road_y(apex) + rng.randf_range(160.0, 260.0)
		var g := k.group(root, "Pin%02d" % i)
		wc(g, "Shaft", p, r, top, "win_tower")
		k.cyl(g, "Ring1", Vector3(p.x, road_y(apex) + 30.0, p.z), r + 1.2, 1.2, NEONS[i % 4])
		k.cyl(g, "Ring2", Vector3(p.x, top - 20.0, p.z), r + 1.2, 1.2, NEONS[i % 4])
		k.cyl(g, "Crown", Vector3(p.x, top, p.z), r * 0.6, 30.0, "concrete", "taper")
		k.cyl(g, "Mast", Vector3(p.x, top + 30.0, p.z), 1.0, 40.0, "concrete", "cone")
		k.box(g, "Beacon", Vector3(p.x, top + 70.0, p.z), Vector3(2.5, 2.5, 2.5), Basis.IDENTITY, "red")
		i += 1
	# the core spire: the tallest thing in the city, seen from most of the lap
	var s := k.group(root, "CoreSpire")
	var cc := Vector3(CITY_C.x, GROUND_Y, CITY_C.z)
	var nt2 := near_track(cc)
	if nt2.x > 60.0:
		wb(s, "Base", cc, 70.0, 70.0, 60.0, Basis.IDENTITY, "win")
		wc(s, "Shaft", cc + Vector3.UP * (60.0 - GROUND_Y), 26.0, 440.0, "win_tower")
		for h: float in [120.0, 220.0, 320.0, 420.0]:
			k.cyl(s, "Band%d" % int(h), Vector3(cc.x, h, cc.z), 27.5, 2.0, "cyan")
		k.cyl(s, "Top", Vector3(cc.x, 440.0, cc.z), 16.0, 60.0, "concrete", "taper")
		k.cyl(s, "Needle", Vector3(cc.x, 500.0, cc.z), 2.0, 120.0, "concrete", "cone")
		k.box(s, "Beacon", Vector3(cc.x, 622.0, cc.z), Vector3(3, 3, 3), Basis.IDENTITY, "red")

# =============================================================================
# LIGHTS: street lights over the deck, tunnel lights, coloured spill from signs
# =============================================================================

func district_lights(root: Node3D) -> void:
	var st := k.group(root, "DeckLights")
	var d := 0.0
	var i := 0
	while d < k.length:
		if not in_tunnel(d, 8.0):
			var side := -1.0 if i % 2 == 0 else 1.0
			var f := k.frame(d)
			var p := k.center(d) + f.y * 13.0 + f.x * side * 18.0
			var warm := Color(1.0, 0.74, 0.5)
			_omni(st, "L%03d" % i, p, warm, 18.0, 60.0)
		d += 34.0
		i += 1
	var tl := k.group(root, "TunnelLights")
	for t in TUNNELS:
		var ceil_h := 24.0 + 34.0 * sin(_max_bank(t[0], t[1])) + 4.0
		var col: Color = NEON_COLORS[t[2]].lerp(Color.WHITE, 0.45)
		var td: float = t[0] + 10.0
		var j := 0
		while td < t[1]:
			_omni(tl, "%s_%02d" % [t[3], j], k.center(td) + k.frame(td).y * (ceil_h - 4.0), col, 16.0, 50.0)
			td += 28.0
			j += 1
	var sl := k.group(root, "SignSpill")
	if billboard_spots.is_empty():
		# lights built on their own: place the boards in a throwaway node first
		var tmp := Node3D.new()
		district_signs(tmp)
		tmp.free()
	for n in range(billboard_spots.size()):
		var p: Vector3 = billboard_spots[n]
		# a little in front of the board, toward the road, at mid height
		var nt := near_track(p)
		_omni(sl, "Spill%02d" % n, p.lerp(Vector3(p.x, nt.y + 16.0, p.z), 0.5), billboard_spots_col[n], 40.0, 90.0)

func _omni(g: Node, name: String, p: Vector3, col: Color, energy: float, rng_m: float) -> void:
	var l := OmniLight3D.new()
	l.name = name
	l.position = p
	l.light_color = col
	l.light_energy = energy
	l.omni_range = rng_m
	l.omni_attenuation = 1.0
	l.shadow_enabled = false
	l.light_specular = 0.4
	l.distance_fade_enabled = true
	l.distance_fade_begin = 700.0
	l.distance_fade_length = 200.0
	g.add_child(l)
