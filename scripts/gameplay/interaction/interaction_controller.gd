class_name InteractionController
extends RayCast3D

@export var actor_path: NodePath
@export var prompt_label_path: NodePath

@onready var actor: Node = get_node(actor_path)
@onready var prompt_label: Label = get_node(prompt_label_path) as Label

var _current_target: Node


func _ready() -> void:
	prompt_label.visible = false


func _physics_process(_delta: float) -> void:
	refresh_target()


func try_interact() -> bool:
	force_raycast_update()
	refresh_target()

	if not is_instance_valid(_current_target):
		return false

	_current_target.call("interact", actor)
	set_target(null)
	return true


func refresh_target() -> void:
	var candidate := get_collider() as Node if is_colliding() else null

	if candidate != null and not candidate.has_method("interact"):
		candidate = null

	if candidate == _current_target:
		if is_instance_valid(_current_target):
			refresh_prompt()
		return

	set_target(candidate)


func set_target(target: Node) -> void:
	_current_target = target

	if not is_instance_valid(_current_target):
		prompt_label.visible = false
		prompt_label.text = ""
		return

	refresh_prompt()


func refresh_prompt() -> void:
	if not is_instance_valid(_current_target):
		return

	var prompt := "Взаимодействовать"

	if _current_target.has_method("get_interaction_prompt"):
		prompt = str(_current_target.call("get_interaction_prompt"))

	var next_text := "[E] %s" % prompt
	if prompt_label.text != next_text:
		prompt_label.text = next_text
	prompt_label.visible = true
