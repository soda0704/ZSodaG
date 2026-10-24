extends Node3D
## Native hinge animations. Runtime only supplies textures and requests states.
signal content_requested(show_map: bool)
signal transition_finished
@onready var animation: AnimationPlayer = $AnimationPlayer
var busy := false
var displaying_map := false
var _target_map := false
var _world_phase := 0

func _ready() -> void:
	animation.animation_finished.connect(_on_animation_finished)
	reset()

func bind_ink(texture: Texture2D, rect: Rect2) -> void:
	for tile in $MapFold.find_children("*", "MeshInstance3D", true, false):
		var material: ShaderMaterial = tile.material_override
		material.set_shader_parameter("ink_texture", texture)
		material.set_shader_parameter("source_rect", Vector4(rect.position.x,rect.position.y,rect.size.x,rect.size.y))

func bind_turn_texture(texture: Texture2D) -> void:
	var material: ShaderMaterial = $TurnPivot/Page.material_override
	material.set_shader_parameter("ink_texture", texture)
	material.set_shader_parameter("source_rect", Vector4(.5,0,.5,1))

func transition_to(show_map: bool) -> void:
	if busy or show_map == displaying_map: return
	busy = true
	_target_map = show_map
	animation.play("page_to_map" if show_map else "fold")

func _on_animation_finished(clip: StringName) -> void:
	if not busy: return
	match clip:
		&"page_to_map":
			displaying_map = true
			content_requested.emit(true)
			animation.play("unfold")
		&"fold":
			content_requested.emit(false)
			animation.play("page_to_notes")
		&"unfold", &"page_to_notes":
			displaying_map = _target_map
			busy = false
			transition_finished.emit()

func reset() -> void:
	busy = false
	displaying_map = false
	_target_map = false
	animation.play("RESET")
	animation.advance(0)
	animation.stop()

func return_to_notes() -> void:
	if not busy:
		transition_to(false)
		return
	_target_map = false
	var at := animation.current_animation_position
	if animation.current_animation == "unfold":
		animation.play("fold")
		animation.seek(1.35-at,true)
	elif animation.current_animation == "page_to_map":
		content_requested.emit(false)
		animation.play("page_to_notes")
		animation.seek(.72-at,true)

func sync_world(show_map: bool, phase: int) -> void:
	if phase != 2:
		if phase != _world_phase: reset()
	elif busy and not show_map and _target_map: return_to_notes()
	elif not busy and displaying_map != show_map: transition_to(show_map)
	_world_phase = phase
