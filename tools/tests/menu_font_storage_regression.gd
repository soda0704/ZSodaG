extends SceneTree
## Generated MSDF atlases and the Windows font file must not be saved in the theme.

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var font := load("res://scenes/ui/menu_brand_font.tres") as FontVariation
	var path := "user://menu_font_storage_%d.tres" % OS.get_process_id()
	for size in range(16, 96, 4):
		font.get_string_size("NORTHERN LAB", HORIZONTAL_ALIGNMENT_LEFT, -1, size)
	var result := ResourceSaver.save(font, path)
	var text := FileAccess.get_file_as_string(path)
	var valid := result == OK and text.length() < 2048 and not "base_font =" in text
	valid = valid and not "PackedByteArray" in text and "menu_brand_font.gd" in text
	var restored := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as FontVariation
	valid = valid and restored != null and restored.get_font_name() == font.get_font_name()
	valid = valid and restored.spacing_glyph == -4 and restored.spacing_top == -22
	DirAccess.remove_absolute(path)
	print("PASS" if valid else "FAIL", " menu font stays compact after editor save and retains its face (", text.length(), " bytes)")
	quit(0 if valid else 1)
