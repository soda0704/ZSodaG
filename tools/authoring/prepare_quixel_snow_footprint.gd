extends SceneTree
## Packs the supplied Quixel sejl3ui Texture Set ZIP as Godot decal textures.

const PREFIX := "Snow_Footprint_sejl3ui_2K_"
const DEST := "res://assets/environments/snow/quixel_sejl3ui/"

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var archive := ZIPReader.new()
	if args.size() != 1 or archive.open(args[0]) != OK:
		push_error("Pass the Quixel sejl3ui 2K ZIP after --.")
		quit(1)
		return
	var maps: Dictionary[String, Image] = {}
	for channel in ["BaseColor", "Opacity", "Normal", "AO", "Roughness"]:
		var source := Image.new()
		if source.load_jpg_from_buffer(archive.read_file(PREFIX + channel + ".jpg")) != OK \
				or source.get_size() != Vector2i(2048, 1024):
			push_error("Missing or invalid map: " + channel)
			quit(1)
			return
		source.rotate_90(COUNTERCLOCKWISE)
		maps[channel] = source
	archive.close()

	var albedo := Image.create_empty(1024, 2048, false, Image.FORMAT_RGBA8)
	var normal := Image.create_empty(1024, 2048, false, Image.FORMAT_RGBA8)
	var orm := Image.create_empty(1024, 2048, false, Image.FORMAT_RGB8)
	for y in 2048:
		for x in 1024:
			var alpha := smoothstep(0.02, 1.0, maps["Opacity"].get_pixel(x, y).r)
			var shade := maps["BaseColor"].get_pixel(x, y).get_luminance()
			albedo.set_pixel(x, y, Color(shade * 0.98, shade, shade * 1.025, alpha))
			var source_normal := maps["Normal"].get_pixel(x, y)
			var rotated_normal := Color(1.0 - source_normal.g, source_normal.r, source_normal.b, 1.0)
			normal.set_pixel(x, y, Color(0.5, 0.5, 1.0).lerp(rotated_normal, alpha))
			orm.set_pixel(x, y, Color(maps["AO"].get_pixel(x, y).r, maps["Roughness"].get_pixel(x, y).r, 0.0))
	if DirAccess.make_dir_recursive_absolute(DEST) != OK:
		quit(1)
		return
	for entry in [[albedo, "albedo"], [normal, "normal"], [orm, "orm"]]:
		var map: Image = entry[0]
		if map.generate_mipmaps(entry[1] == "normal") != OK or map.compress(Image.COMPRESS_BPTC) != OK \
				or ResourceSaver.save(ImageTexture.create_from_image(map), DEST + entry[1] + ".res", ResourceSaver.FLAG_COMPRESS) != OK:
			push_error("Could not pack Quixel map: " + str(entry[1]))
			quit(1)
			return
		print("QUIXEL FOOTPRINT: ", entry[1], " ", map.get_size())
	quit()
