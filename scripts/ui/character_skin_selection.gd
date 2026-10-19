class_name NorthernCharacterSelection
extends Control
## Transparent preview of the production world model, clipped below menu rails.

const VARIANTS := [preload("res://assets/config/characters/tactical_a.tres"), preload("res://assets/config/characters/tactical_b.tres")]
var option: OptionButton
var preview: SubViewport
var model: Node3D
var camera: Camera3D
var _distance := 1.55
var _rotation := -0.25
var _dragging := false

func _ready() -> void:
	option = $SkinOption
	preview = $Preview/Viewport
	preview.world_3d = World3D.new()
	$Preview.resized.connect(_update_preview_size)
	_update_preview_size.call_deferred()
	preview.set_meta("ui_presentation", true)
	camera = $Preview/Viewport/Camera
	$Preview.gui_input.connect(_preview_input)
	option.select(GameMenu.get_character_variant_id())
	option.item_selected.connect(_on_skin_selected)
	_update_camera()
	_show_variant(option.get_selected_id())

func _update_camera() -> void:
	camera.position = Vector3(0, 1.45, -_distance)
	camera.look_at(Vector3(0, 1.44, 0))

func _on_skin_selected(index: int) -> void:
	var variant_id := option.get_item_id(index)
	GameMenu.set_character_variant_id(variant_id)
	_show_variant(variant_id)

func _show_variant(variant_id: int) -> void:
	if is_instance_valid(model):
		model.hide()
		model.queue_free()
	model = VARIANTS[clampi(variant_id, 0, 1)].body_scene.instantiate()
	preview.add_child(model)
	model.rotation.y = _rotation
	model.get_node("Skeleton3D/RightHand/Equipment").hide()
	for modifier in model.get_node("Skeleton3D").get_children():
		if modifier is SkeletonModifier3D:
			modifier.active = false
	model.get_node("AnimationPlayer").play("Idle")

func _preview_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_dragging = event.pressed
		elif event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			_distance = clampf(_distance + (-0.09 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 0.09), 1.05, 1.85)
			_update_camera()
	elif event is InputEventMouseMotion and _dragging:
		_rotation += event.relative.x * 0.008
		model.rotation.y = _rotation

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_dragging = false

func _update_preview_size() -> void:
	var display_size: Vector2 = $Preview.size
	if display_size.x < 1 or display_size.y < 1: return
	var factor := minf(2.0, minf(3840.0 / display_size.x, 2160.0 / display_size.y))
	preview.size = Vector2i(maxi(2, roundi(display_size.x * factor)), maxi(2, roundi(display_size.y * factor)))
