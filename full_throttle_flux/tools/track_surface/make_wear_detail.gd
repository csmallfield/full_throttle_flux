extends SceneTree
## v38 phase 4: generates the PLACEHOLDER wear detail texture the track
## surface samples (shaders/track/modules/wear.gdshaderinc), a seamlessly
## tiling 512 x 512 RGBA:
##   R  grime: tileable fbm, mid grey on average
##   G  scratches: thin streaks along +V (the shader maps V along the track,
##      so they run with the direction of travel), of many lengths
##   B  stains: soft low-frequency blotches
##   A  speckle: fine pitting
##
##   godot --headless --path . -s res://tools/track_surface/make_wear_detail.gd
##
## Replace OUT with a hand-made texture of the same layout whenever you like
## (keep it tiling, linear data, with mipmaps): nothing else changes.

const OUT := "res://resources/track_surface/wear_detail.png"
const SIZE := 512
const SEED := 3801


func _initialize() -> void:
	var t0 := Time.get_ticks_msec()
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var scratch := _scratches()
	for y in SIZE:
		for x in SIZE:
			var u := float(x) / SIZE
			var v := float(y) / SIZE
			var grime := _fbm(u, v, 8, 5, 11)
			var stain := smoothstep(0.52, 0.78, _fbm(u, v, 3, 3, 23))
			var speck := 1.0 if _hash(x, y, 37) > 0.985 else 0.0
			img.set_pixel(x, y, Color(grime, scratch[y * SIZE + x], stain, speck))
	DirAccess.make_dir_recursive_absolute(OUT.get_base_dir())
	var err := img.save_png(OUT)
	print("WEARDETAIL %s %s in %d ms" % [OUT, error_string(err), Time.get_ticks_msec() - t0])
	quit(0 if err == OK else 1)


## Streaks along +V: random positions, lengths (mostly short, some across
## the whole tile), slight drift, soft edges, wrapping both ways.
static func _scratches() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(SIZE * SIZE)
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	for k in 1600:
		var x := rng.randf() * SIZE
		var y0 := rng.randi() % SIZE
		var length := int(clampf(-log(maxf(rng.randf(), 1e-4)) * 90.0, 12.0, SIZE))
		var width := rng.randf_range(0.5, 1.4)
		var strength := rng.randf_range(0.25, 1.0)
		var drift := rng.randf_range(-0.04, 0.04)
		for i in length:
			var y := (y0 + i) % SIZE
			var cx := x + drift * i
			# Fade in and out along the streak.
			var along := sin(PI * float(i) / length)
			for dx in range(-2, 3):
				var px := int(floor(cx)) + dx
				var d := absf(float(px) + 0.5 - cx)
				var cov := clampf(width - d + 0.5, 0.0, 1.0)
				if cov <= 0.0:
					continue
				var idx := y * SIZE + posmod(px, SIZE)
				out[idx] = maxf(out[idx], cov * strength * along)
	return out


## Tileable value noise: `cells` lattice cells across the tile, `octaves`
## doubling each time, normalised to about 0..1.
static func _fbm(u: float, v: float, cells: int, octaves: int, salt: int) -> float:
	var sum := 0.0
	var amp := 0.5
	var norm := 0.0
	var c := cells
	for o in octaves:
		sum += amp * _vnoise(u * c, v * c, c, salt + o * 7)
		norm += amp
		amp *= 0.5
		c *= 2
	return sum / norm


static func _vnoise(x: float, y: float, period: int, salt: int) -> float:
	var ix := int(floor(x))
	var iy := int(floor(y))
	var fx := x - ix
	var fy := y - iy
	fx = fx * fx * (3.0 - 2.0 * fx)
	fy = fy * fy * (3.0 - 2.0 * fy)
	var a := _hash(posmod(ix, period), posmod(iy, period), salt)
	var b := _hash(posmod(ix + 1, period), posmod(iy, period), salt)
	var c := _hash(posmod(ix, period), posmod(iy + 1, period), salt)
	var d := _hash(posmod(ix + 1, period), posmod(iy + 1, period), salt)
	return lerpf(lerpf(a, b, fx), lerpf(c, d, fx), fy)


static func _hash(x: int, y: int, salt: int) -> float:
	var h := (x * 374761393 + y * 668265263 + salt * 1442695041 + SEED) & 0x7fffffff
	h = ((h ^ (h >> 13)) * 1274126177) & 0x7fffffff
	return float(h ^ (h >> 16)) / float(0x7fffffff)
