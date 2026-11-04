extends SceneTree
## Pack the CC0 Snow 02 maps into two BC7 textures with mipmaps.
## Source: https://polyhaven.com/a/snow_02 (Rob Tuytel, 2 m tile).
## Download the 2K PNGs into tools/.local/snow-material-review/source/:
## snow_02_diff_2k.png, normal_download.png (nor_gl), rough_download.png (Rough).
const SOURCE := "res://tools/.local/snow-material-review/source/snow_02_"
const DEST := "res://assets/environments/snow/entry_trial/"

func _initialize() -> void:
	var old: Texture2D = load("res://assets/environments/snow/terrain_snow_albedo.res")
	print("OLD SNOW ", old.get_width(), "x", old.get_height())
	var diffuse := Image.load_from_file(SOURCE + "diff_2k.png")
	var normal := Image.load_from_file("res://tools/.local/snow-material-review/source/normal_download.png")
	var rough := Image.load_from_file("res://tools/.local/snow-material-review/source/rough_download.png")
	if diffuse == null or normal == null or rough == null:
		quit(1)
		return
	diffuse.convert(Image.FORMAT_RGBA8)
	normal.convert(Image.FORMAT_RGBA8)
	rough.convert(Image.FORMAT_L8)
	var data := normal.get_data()
	var rough_data := rough.get_data()
	for i in rough_data.size():
		data[i * 4 + 3] = rough_data[i]
	normal = Image.create_from_data(normal.get_width(), normal.get_height(), false, Image.FORMAT_RGBA8, data)
	DirAccess.make_dir_recursive_absolute(DEST)
	for pair in [[diffuse, "snow_02_albedo.res"], [normal, "snow_02_normal_rough.res"]]:
		var image: Image = pair[0]
		image.generate_mipmaps()
		var error := image.compress(Image.COMPRESS_BPTC)
		if error != OK:
			push_error("BC7 compression failed: " + str(error))
			quit(1)
			return
		var texture := ImageTexture.create_from_image(image)
		if ResourceSaver.save(texture, DEST + pair[1], ResourceSaver.FLAG_COMPRESS) != OK:
			quit(1)
			return
		print("PACKED ", pair[1], " ", image.get_width(), "x", image.get_height(), " format=", image.get_format(), " bytes=", image.get_data_size())
	quit()
