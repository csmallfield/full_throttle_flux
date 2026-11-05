extends SceneTree
## Generates the PLACEHOLDER surface mask textures: seamlessly tiling 512 x 512
## greyscale images in resources/track_surface/mask_textures:
##   noise_soft     large soft clouds
##   noise_fine     fine grain
##   noise_blotch   hard-ish patches on a clear background
##   noise_speckle  scattered pits
##   noise_streak   long streaks along +V (along the track)
##
##   godot --headless --path . -s res://tools/track_surface/make_mask_noises.gd
##
## Any tiling greyscale image dropped in that folder shows up in Surface Lab's
## texture pickers. Import with mipmaps on and no VRAM compression, as linear
## data (copy an existing .import).

const DIR := "res://resources/track_surface/mask_textures"
const SIZE := 512


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	_save("noise_soft", func(u: float, v: float, _x: int, _y: int) -> float:
		return _stretch(_fbm(u, v, 4, 4, 101), 0.2, 0.8))
	_save("noise_fine", func(u: float, v: float, _x: int, _y: int) -> float:
		return _stretch(_fbm(u, v, 48, 3, 202), 0.2, 0.8))
	_save("noise_blotch", func(u: float, v: float, _x: int, _y: int) -> float:
		return smoothstep(0.52, 0.62, _fbm(u, v, 6, 4, 303)))
	_save("noise_speckle", func(_u: float, _v: float, x: int, y: int) -> float:
		return 1.0 if _hash(x, y, 404) > 0.975 else 0.0)
	_save("noise_streak", func(u: float, v: float, _x: int, _y: int) -> float:
		return _stretch(_fbm_aniso(u, v, 96, 3, 505), 0.25, 0.75))
	quit(0)


func _save(name: String, f: Callable) -> void:
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_L8)
	for y in SIZE:
		for x in SIZE:
			var l: float = f.call(float(x) / SIZE, float(y) / SIZE, x, y)
			img.set_pixel(x, y, Color(l, l, l))
	var path := "%s/%s.png" % [DIR, name]
	print("MASKNOISE %s %s" % [path, error_string(img.save_png(path))])


static func _stretch(x: float, lo: float, hi: float) -> float:
	return clampf((x - lo) / (hi - lo), 0.0, 1.0)


static func _hash(x: int, y: int, s: int) -> float:
	var h := (x * 374761393 + y * 668265263 + s * 1274126177) & 0x7fffffff
	h = ((h ^ (h >> 13)) * 1274126177) & 0x7fffffff
	return float(h ^ (h >> 16) & 0xffff) / 2147483647.0


## Tiling value noise, `cx` x `cy` lattice cells across the tile.
static func _value(u: float, v: float, cx: int, cy: int, s: int) -> float:
	var x := u * cx
	var y := v * cy
	var ix := int(floor(x))
	var iy := int(floor(y))
	var fx := x - ix
	var fy := y - iy
	fx = fx * fx * (3.0 - 2.0 * fx)
	fy = fy * fy * (3.0 - 2.0 * fy)
	var a := _hash(posmod(ix, cx), posmod(iy, cy), s)
	var b := _hash(posmod(ix + 1, cx), posmod(iy, cy), s)
	var c := _hash(posmod(ix, cx), posmod(iy + 1, cy), s)
	var d := _hash(posmod(ix + 1, cx), posmod(iy + 1, cy), s)
	return lerpf(lerpf(a, b, fx), lerpf(c, d, fx), fy)


static func _fbm(u: float, v: float, cells: int, octaves: int, s: int) -> float:
	var sum := 0.0
	var amp := 0.5
	var total := 0.0
	for i in octaves:
		sum += _value(u, v, cells << i, cells << i, s + i) * amp
		total += amp
		amp *= 0.5
	return sum / total


## As _fbm, with far fewer cells along V: streaks.
static func _fbm_aniso(u: float, v: float, cells: int, octaves: int, s: int) -> float:
	var sum := 0.0
	var amp := 0.5
	var total := 0.0
	for i in octaves:
		sum += _value(u, v, cells << i, 2 << i, s + i) * amp
		total += amp
		amp *= 0.5
	return sum / total
