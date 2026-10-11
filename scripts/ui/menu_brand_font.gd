@tool
extends FontVariation
## Read the installed face without redistributing licensed system font files.
## This runtime font and its generated glyph cache must never enter the resource.
func _validate_property(property: Dictionary) -> void:
	if property.name == "base_font":
		property.usage = int(property.usage) & ~PROPERTY_USAGE_STORAGE

func _init() -> void:
	var fallback := SystemFont.new()
	fallback.font_names = PackedStringArray(["Arial", "Bahnschrift"])
	fallback.font_weight = 900
	fallback.multichannel_signed_distance_field = true
	base_font = fallback
	var source := OS.get_environment("WINDIR").path_join("Fonts/ariblk.ttf")
	if OS.get_name() == "Windows" and FileAccess.file_exists(source):
		var installed := FontFile.new()
		if installed.load_dynamic_font(source) == OK:
			installed.multichannel_signed_distance_field = true
			installed.msdf_pixel_range = 16
			installed.msdf_size = 96
			base_font = installed
