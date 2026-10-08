class_name JournalPhotoCard
extends Button

@export var item_id: StringName
@onready var picture: TextureRect = $Content/Picture
@onready var caption: Label = $Content/Caption
@onready var detail: Label = $Content/Detail

func _ready() -> void:
	if item_id == &"" and picture.texture != null:
		item_id = StringName(picture.texture.resource_path.get_file().get_basename())
	resized.connect(_update_pivot)
	_update_pivot()

func _update_pivot() -> void:
	pivot_offset = size * 0.5

func set_note(note: String) -> void:
	detail.text = note
