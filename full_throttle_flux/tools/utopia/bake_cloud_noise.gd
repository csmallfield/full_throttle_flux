extends SceneTree
## Converts the raw volumes written by gen_cloud_noise.py into ImageTexture3D
## resources the sky shader samples:
##   sky/cloud_shape_128.res, sky/cloud_detail_64.res
##   python3 tools/utopia/gen_cloud_noise.py
##   godot --path . -s res://tools/utopia/bake_cloud_noise.gd   (NOT --headless:
##   the dummy renderer drops texture data, the .res would save empty)

const DIR := "res://scenes/tracks/utopia/sky/"

func _initialize() -> void:
	for spec in [["cloud_shape_128", 128], ["cloud_detail_64", 64]]:
		var s: int = spec[1]
		var raw := FileAccess.get_file_as_bytes(DIR + spec[0] + ".raw")
		if raw.size() != s * s * s:
			push_error("%s.raw missing or wrong size (run gen_cloud_noise.py)" % spec[0])
			quit(1)
			return
		var imgs: Array[Image] = []
		for z in range(s):
			imgs.append(Image.create_from_data(s, s, false, Image.FORMAT_L8, raw.slice(z * s * s, (z + 1) * s * s)))
		var tex := ImageTexture3D.new()
		tex.create(Image.FORMAT_L8, s, s, s, false, imgs)
		ResourceSaver.save(tex, DIR + spec[0] + ".res", ResourceSaver.FLAG_COMPRESS)
		print("baked ", spec[0])
	print("NOISE OK")
	quit()
