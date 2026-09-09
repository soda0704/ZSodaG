class_name DayTwoTerminal
extends StaticBody3D

@export var is_key_terminal: bool = false
@onready var status: Label3D = $Status
@onready var key_visual: MeshInstance3D = $Key
@onready var screen: MeshInstance3D = $Screen
var _controller: BaseGameplayController
var _material: StandardMaterial3D
var _animation: Tween
var _previous_stage: int = -1


func _ready() -> void:
	_controller = get_tree().get_first_node_in_group("base_gameplay_controller") as BaseGameplayController
	_material = screen.get_active_material(0).duplicate() as StandardMaterial3D
	screen.material_override = _material
	if _controller != null:
		_controller.snapshot_changed.connect(_on_snapshot_changed)
		_on_snapshot_changed(_controller.get_snapshot())


func get_interaction_prompt() -> String:
	if _controller == null or _controller.day_index < 2:
		return "Задание будет доступно на второй день"
	if _controller.day_index > 2:
		return "Ключ доставлен. Конец доступного прототипа"
	match _controller.quest_stage:
		BaseGameplayController.QuestStage.OFFERED:
			return "Сначала получите задание в центральном хабе" if is_key_terminal else "Получить задание: ключ шифрования"
		BaseGameplayController.QuestStage.ACCEPTED:
			return "Извлечь ключ в общий сюжетный слот" if is_key_terminal else "Найдите ключ в хранилище данных на −1"
		BaseGameplayController.QuestStage.COLLECTED:
			return "Ключ у команды — вернитесь в хаб" if is_key_terminal else "Передать ключ и завершить задание"
		BaseGameplayController.QuestStage.DELIVERED:
			return "Ключ доставлен. Можно завершить день"
	return "Терминал недоступен"


func network_interact(peer_id: int, interactor: Node) -> void:
	if (
		_controller == null or not multiplayer.is_server()
		or not interactor is Node3D
		or int(interactor.get("owner_peer_id")) != peer_id
		or (interactor as Node3D).global_position.distance_to(global_position) > 4.0
	):
		return
	var stage := _controller.quest_stage
	if is_key_terminal:
		if stage == BaseGameplayController.QuestStage.ACCEPTED:
			_controller.advance_quest_authoritative(peer_id, stage)
	elif stage in [BaseGameplayController.QuestStage.OFFERED, BaseGameplayController.QuestStage.COLLECTED]:
		_controller.advance_quest_authoritative(peer_id, stage)


func _on_snapshot_changed(_snapshot: Dictionary) -> void:
	var stage := int(_controller.quest_stage)
	status.text = ("ХРАНИЛИЩЕ ДАННЫХ · −1" if is_key_terminal else "ЗАДАНИЯ ЭКСПЕДИЦИИ") + "\n" + get_interaction_prompt()
	var show_key := (
		is_key_terminal and stage in [1, 2]
		or not is_key_terminal and stage == 4
	)
	var target_scale := Vector3.ONE if show_key else Vector3.ONE * 0.001
	var color := Color(0.08, 0.9, 0.4) if stage == 4 else Color(0.12, 0.55, 1.0)
	if stage == 0:
		color = Color(0.15, 0.18, 0.2)
	if is_instance_valid(_animation):
		_animation.kill()
	if _previous_stage == -1 or _previous_stage == stage:
		key_visual.scale = target_scale
		_material.emission = color
	else:
		_animation = create_tween().set_parallel(true)
		_animation.tween_property(key_visual, "scale", target_scale, 0.35).set_trans(Tween.TRANS_SINE)
		_animation.tween_property(key_visual, "rotation:y", key_visual.rotation.y + PI, 0.35)
		_material.emission = Color.WHITE
		_animation.tween_property(_material, "emission", color, 0.5)
	_previous_stage = stage
