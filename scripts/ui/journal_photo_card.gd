class_name JournalPhotoCard
extends Button

var picture: TextureRect
var caption: Label
var detail: Label
var item_id: StringName

func setup(id: StringName, title: String, photo_path: String, handwritten: Font) -> void:
	item_id = id
	custom_minimum_size = Vector2(272, 260)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var paper := StyleBoxFlat.new()
		paper.bg_color = Color("eee9d9") if state != "hover" else Color("fff9e7")
		paper.set_corner_radius_all(2)
		paper.shadow_color = Color(0.08, 0.06, 0.035, 0.3)
		paper.shadow_size = 5
		paper.shadow_offset = Vector2(2, 4)
		if state == "focus" or state == "pressed":
			if state == "focus":
				paper.bg_color = Color.TRANSPARENT
			paper.set_border_width_all(2)
			paper.border_color = Color("8c5836")
		add_theme_stylebox_override(state, paper)
	var content := VBoxContainer.new()
	add_child(content)
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content.offset_left = 11
	content.offset_top = 11
	content.offset_right = -11
	content.offset_bottom = -10
	content.add_theme_constant_override("separation", 4)
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	picture = TextureRect.new()
	picture.custom_minimum_size = Vector2(0, 170)
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if ResourceLoader.exists(photo_path):
		picture.texture = load(photo_path)
	content.add_child(picture)
	caption = Label.new()
	caption.text = title
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.add_theme_font_override("font", handwritten)
	caption.add_theme_font_size_override("font_size", 22)
	caption.add_theme_color_override("font_color", Color("332c23"))
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(caption)
	detail = Label.new()
	detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	detail.add_theme_font_size_override("font_size", 17)
	detail.add_theme_color_override("font_color", Color("76664e"))
	detail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(detail)
	resized.connect(func(): pivot_offset = size * 0.5)

func set_note(note: String) -> void:
	detail.text = note
