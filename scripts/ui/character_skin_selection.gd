extends PanelContainer
## Main-menu selection and an isolated preview of the actual world model.

const VARIANTS := [
	preload("res://assets/config/characters/tactical_a.tres"),
	preload("res://assets/config/characters/tactical_b.tres"),
]

@onready var option: OptionButton = $Content/SkinOption
@onready var preview: SubViewport = $Content/Preview/Viewport
var model: Node3D


func _ready() -> void:
	preview.set_meta("ui_presentation", true)
	for variant in VARIANTS:
		option.add_item(variant.display_name, variant.variant_id)
	option.select(GameMenu.get_character_variant_id())
	option.item_selected.connect(_on_skin_selected)
	_setup_preview()
	_show_variant(option.get_selected_id())


func _setup_preview() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.14, 0.17, 0.20)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.78, 0.85, 0.92)
	environment.ambient_light_energy = 1.0
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	preview.add_child(world_environment)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-35, 155, 0)
	key.light_energy = 2.0
	preview.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-20, -35, 0)
	fill.light_color = Color(0.65, 0.78, 1.0)
	fill.light_energy = 1.2
	preview.add_child(fill)
	var camera := Camera3D.new()
	preview.add_child(camera)
	camera.position = Vector3(0, 1.1, -2.7)
	camera.look_at(Vector3(0, 1.0, 0))
	camera.fov = 42.0
	camera.environment = environment
	camera.current = true


func _on_skin_selected(index: int) -> void:
	var variant_id := option.get_item_id(index)
	GameMenu.set_character_variant_id(variant_id)
	_show_variant(variant_id)


func _show_variant(variant_id: int) -> void:
	if is_instance_valid(model):
		model.hide()
		model.queue_free()
	model = VARIANTS[variant_id].body_scene.instantiate()
	preview.add_child(model)
	model.rotation.y = -0.25
	model.get_node("Skeleton3D/RightHand/Equipment").hide()
	for modifier in model.get_node("Skeleton3D").get_children():
		if modifier is SkeletonModifier3D:
			modifier.active = false
	model.get_node("AnimationPlayer").play("Idle")
