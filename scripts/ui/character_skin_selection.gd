class_name NorthernCharacterSelection
extends Control
## Two menu-only bodies with independent lighting and direct character selection.
signal character_selected(variant_id: int)

const PREVIEW_PATHS := ["res://scenes/ui/characters/tactical_a.scn", "res://scenes/ui/characters/tactical_b.scn"]
static var _scenes: Array[PackedScene] = []
static var _requested := false
var choices: Array[TextureButton] = []
var previews: Array[SubViewport] = []
var models: Array[Node3D] = []
var activation_allowed: Callable
var selected_variant := 0
var _highlighted := -1
var _committed := false
var _picking_ready := false
var _pointer_mode := true
var _pointer_position := Vector2.ZERO
var _entrance_time := 0.0
var _exiting := false

static func prepare_previews() -> void:
	if _requested: return
	_requested = true
	for path in PREVIEW_PATHS: ResourceLoader.load_threaded_request(path)

func _ready() -> void:
	selected_variant = GameMenu.get_character_variant_id()
	_pointer_position = get_viewport().get_mouse_position()
	prepare_previews()
	for index in 2:
		var choice: TextureButton = get_node("LeftCharacter" if index == 0 else "RightCharacter")
		var viewport: SubViewport = choice.get_node("Viewport")
		viewport.world_3d = World3D.new()
		viewport.set_meta("ui_presentation", true)
		# The black outfit needs softer fill to read as clearly as the tan outfit.
		var environment: WorldEnvironment = viewport.get_node("Environment")
		environment.environment = environment.environment.duplicate()
		if index == 0:
			environment.environment.ambient_light_energy = .7
			viewport.get_node("KeyLight").light_energy = .9
		choice.material = choice.material.duplicate()
		choices.append(choice)
		previews.append(viewport)
		choice.focus_entered.connect(_focus_character.bind(index))
		choice.focus_exited.connect(_clear_focus.bind(index))
		choice.pressed.connect(select_variant.bind(index))
		choice.resized.connect(_update_preview_sizes)
	_update_preview_sizes.call_deferred()

func _input(event: InputEvent) -> void:
	if _committed or _exiting: return
	if event is InputEventMouseMotion and is_visible_in_tree():
		_pointer_position = event.position
		_pointer_mode = true
		for choice in choices:
			if choice.has_focus(): choice.release_focus()
		_update_hover()

func _focus_character(index: int) -> void:
	if _committed or _exiting: return
	_pointer_mode = false
	_highlighted = index

func _clear_focus(index: int) -> void:
	if not _committed and _highlighted == index: _highlighted = -1

func _update_hover() -> void:
	if _committed: return
	_highlighted = -1
	if not _picking_ready or _committed: return
	# Bars cover the preview; hovering hidden body parts must not highlight them.
	var shell := get_parent()
	if shell is NorthernMenuShell and (shell.top_rail.get_global_rect().has_point(_pointer_position) or shell.bottom_rail.get_global_rect().has_point(_pointer_position)):
		return
	for index in choices.size():
		var point := choices[index].get_global_transform_with_canvas().affine_inverse() * _pointer_position
		if not choices[index].disabled and choices[index]._has_point(point):
			_highlighted = index
			break

func _process(delta: float) -> void:
	if _exiting: return
	if models.size() < 2:
		if _scenes.is_empty():
			for path in PREVIEW_PATHS:
				if ResourceLoader.load_threaded_get_status(path) != ResourceLoader.THREAD_LOAD_LOADED: return
			for path in PREVIEW_PATHS: _scenes.append(ResourceLoader.load_threaded_get(path))
		# Only body, skeleton and Idle; equipment/FP/ragdoll are not menu dependencies.
		for index in 2:
			var model: Node3D = _scenes[index].instantiate()
			previews[index].add_child(model)
			model.rotation.y = deg_to_rad(12.0 if index == 0 else -12.0)
			model.position = Vector3(.14 if index == 0 else -.14, -.035, 0)
			model.get_node("AnimationPlayer").play("Idle")
			models.append(model)
			choices[index].setup(model.get_node("Skeleton3D"), previews[index].get_node("Camera"))
		return
	if not _picking_ready:
		# Slight stagger, easing and an inward slide; no selection during entry.
		_entrance_time += minf(delta, .05)
		for index in choices.size():
			var progress := NorthernMenuStyle.ease(clampf((_entrance_time - index * .09) / .65, 0.0, 1.0))
			choices[index].material.set_shader_parameter("entrance", progress)
			models[index].position = Vector3(lerpf(.14 if index == 0 else -.14, 0.0, progress), lerpf(-.035, 0.0, progress), 0)
		_picking_ready = _entrance_time >= .74
	if _pointer_mode: _update_hover()
	for index in choices.size():
		var material: ShaderMaterial = choices[index].material
		var strength: float = material.get_shader_parameter("highlight")
		material.set_shader_parameter("highlight", lerpf(strength, 1.0 if index == _highlighted else 0.0, 1.0 - exp(-delta * 16.0)))

func select_variant(index: int) -> void:
	if index not in [0, 1] or not _picking_ready or _committed or _exiting or choices[index].disabled:
		return
	if activation_allowed.is_valid() and not activation_allowed.call(): return
	_committed = true
	selected_variant = index
	GameMenu.set_character_variant_id(index)
	set_selection_enabled(false)
	character_selected.emit(index)

func set_selection_enabled(enabled: bool) -> void:
	for choice in choices: choice.disabled = not enabled
	if not enabled: _highlighted = selected_variant if _committed else -1

func animate_out(motion: Tween, duration: float) -> void:
	_exiting = true
	_picking_ready = false
	set_selection_enabled(false)
	for index in choices.size():
		motion.tween_property(choices[index].material, "shader_parameter/entrance", 0.0, duration).set_custom_interpolator(NorthernMenuStyle.ease)
		if index < models.size():
			motion.tween_property(models[index], "position", Vector3(.12 if index == 0 else -.12, -.025, 0), duration).set_custom_interpolator(NorthernMenuStyle.ease)
	motion.tween_property($SelectionShade, "modulate:a", 0.0, duration).set_custom_interpolator(NorthernMenuStyle.ease)

func _update_preview_sizes() -> void:
	for index in choices.size():
		var display_size := choices[index].size
		if display_size.x < 1 or display_size.y < 1: continue
		var factor := minf(1.0, minf(960.0 / display_size.x, 1080.0 / display_size.y))
		previews[index].size = Vector2i(maxi(2, roundi(display_size.x * factor)), maxi(2, roundi(display_size.y * factor)))
