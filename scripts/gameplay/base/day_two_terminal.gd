class_name DayTwoTerminal
extends StaticBody3D

@export var is_key_terminal := false
@export_range(0.1, 10.0) var interaction_distance := 4.0
@export_group("Authored presentation")
@export var powered_housing_material: Material
@export var unpowered_housing_material: Material
@export var display_material: ShaderMaterial
@export_node_path("MeshInstance3D") var display_mesh_path: NodePath
@export var ready_glow_color: Color
@export var missing_glow_color: Color
@export var material_mesh_paths: Array[NodePath] = []
@export var extract_animation: StringName = &"extract"
@export var deliver_animation: StringName = &"deliver"
@onready var screen: Node3D = $Screen
@onready var key_visual: Node3D = $KeyRoot
@onready var screen_viewport: SubViewport = $ScreenViewport
@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var ui: TerminalScreenUI = $ScreenViewport/TerminalScreen
var _controller: BaseGameplayController
var _screen_material: ShaderMaterial
var _display_mesh: MeshInstance3D
var _housing_meshes: Array[MeshInstance3D] = []
var _previous_stage := -1

func _ready() -> void:
	add_to_group("quest_terminals")
	_screen_material = display_material
	_display_mesh = get_node_or_null(display_mesh_path) as MeshInstance3D
	if _display_mesh != null: _display_mesh.material_override = _screen_material
	for path in material_mesh_paths:
		var mesh := get_node_or_null(path) as MeshInstance3D
		if mesh != null: _housing_meshes.append(mesh)
		else: push_warning("Missing terminal presentation mesh: %s" % path)
	_set_powered(false)
	_controller = get_tree().get_first_node_in_group("base_gameplay_controller") as BaseGameplayController
	if _controller != null:
		_controller.snapshot_changed.connect(_on_snapshot_changed)
		_on_snapshot_changed(_controller.get_snapshot())

func get_interaction_prompt() -> String:
	if _controller == null or not _controller.main_breaker_on:
		return "Терминал отключён · нет основного питания"
	if _controller.day_index < 2:
		return "Задание будет доступно на второй день"
	if _controller.day_index > 2:
		return _objective_text()
	match _controller.quest_stage:
		BaseGameplayController.QuestStage.OFFERED:
			return "Сначала получите задание в центральном хабе" if is_key_terminal else "Получить задание: ключ шифрования"
		BaseGameplayController.QuestStage.ACCEPTED:
			return "Извлечь pass key" if is_key_terminal else "Найдите ключ в хранилище данных на уровне 1"
		BaseGameplayController.QuestStage.COLLECTED:
			return "Ключ у команды — вернитесь в хаб" if is_key_terminal else "Передать ключ и завершить задание"
		BaseGameplayController.QuestStage.DELIVERED:
			return "Ключ доставлен. Можно завершить день"
	return "Терминал недоступен"

func network_interact(peer_id: int, interactor: Node) -> void:
	if not multiplayer.is_server() or _controller == null or not _controller.main_breaker_on:
		return
	var player := interactor as GamePlayer
	if player == null or player.owner_peer_id != peer_id or _controller.get_player_node(peer_id) != player:
		return
	if player.survival.dead or player.is_sleeping_in_bunk() or player.is_driving() or player.is_carrying_corpse():
		return
	if player.global_position.distance_to(global_position) > interaction_distance:
		return
	var origin := player.camera.global_position
	if screen.global_basis.z.dot(origin - screen.global_position) <= 0.0:
		return
	var query := PhysicsRayQueryParameters3D.create(origin, screen.global_position, 3, [player.get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty() and hit.collider != self:
		return
	var stage := _controller.quest_stage
	if is_key_terminal:
		if stage == BaseGameplayController.QuestStage.ACCEPTED:
			_controller.advance_quest_authoritative(peer_id, stage)
	elif stage in [BaseGameplayController.QuestStage.OFFERED, BaseGameplayController.QuestStage.COLLECTED]:
		_controller.advance_quest_authoritative(peer_id, stage)

func _on_snapshot_changed(_snapshot: Dictionary) -> void:
	var powered := _controller.main_breaker_on
	_set_powered(powered)
	_refresh_screen()
	var stage := int(_controller.quest_stage)
	if stage != _previous_stage:
		var extracting := is_key_terminal and _previous_stage == 2 and stage == 3
		var delivering := not is_key_terminal and _previous_stage == 3 and stage == 4
		if extracting:
			animation_player.play(extract_animation)
		elif delivering:
			animation_player.play(deliver_animation)
		else:
			animation_player.play(&"RESET")
			animation_player.advance(0.0)
			animation_player.stop()
			key_visual.visible = (is_key_terminal and stage in [1, 2]) or (not is_key_terminal and stage == 4)
	_previous_stage = stage
	if powered: screen_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE

func _set_powered(powered: bool) -> void:
	if _screen_material != null: _screen_material.set_shader_parameter("powered", powered)
	for mesh in _housing_meshes:
		if mesh == _display_mesh: continue
		mesh.material_override = powered_housing_material if powered else unpowered_housing_material
	if not powered: screen_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED

func _refresh_screen() -> void:
	var stage := int(_controller.quest_stage)
	var has_key := (is_key_terminal and stage in [1, 2]) or (not is_key_terminal and stage == 4)
	ui.set_key_present(has_key)
	_screen_material.set_shader_parameter("key_missing", not has_key)
	ui.get_node("%Title").text = "X-LAB / ХРАНИЛИЩЕ ДАННЫХ · 1" if is_key_terminal else "NORTHERN LAB / ЭКСПЕДИЦИЯ"
	ui.get_node("%Day").text = "ДЕНЬ %d" % _controller.day_index
	ui.get_node("%System").text = "ПИТАНИЕ / СЕТЬ БАЗЫ · ТОПЛИВО %.1f Л · РЕЗЕРВ ЛИФТА %s" % [_controller.fuel_liters, "ГОТОВ" if _controller.elevator_backup_installed else "ОТКЛЮЧЁН"]
	var heading := "ПОДГОТОВКА ЭКСПЕДИЦИИ"
	match _controller.day_index:
		2: heading = "КЛЮЧ ШИФРОВАНИЯ / PASS KEY"
		3: heading = "ОБСЛЕДОВАНИЕ УРОВНЯ 2"
		4: heading = "БИОКОНТЕЙНМЕНТ / УРОВЕНЬ 3"
		5: heading = "АРХИВ ЗАДАНИЙ"
	ui.get_node("%Heading").text = heading
	ui.get_node("%Objective").text = _objective_text()
	var stages := ["НЕДОСТУПЕН", "ЗАДАНИЕ НЕ ПРИНЯТО", "В ХРАНИЛИЩЕ", "У КОМАНДЫ · 1 ШТ.", "ПЕРЕДАН НА БАЗУ"]
	ui.get_node("%Progress").text = "PASS KEY / " + stages[int(_controller.quest_stage)]
	ui.get_node("%Action").text = get_interaction_prompt()

func _objective_text() -> String:
	match _controller.day_index:
		1:
			return "Восстановите основное питание базы. Подключите резерв лифта: предохранитель находится в медицинской комнате. После подготовки отдохните."
		2:
			match _controller.quest_stage:
				BaseGameplayController.QuestStage.OFFERED:
					return "Получите задание в центральном хабе. Ключ шифрования находится в защищённом хранилище данных на уровне 1."
				BaseGameplayController.QuestStage.ACCEPTED:
					return "Извлеките pass key из терминала хранилища на уровне 1 и передайте в центральный хаб. Ключ общий для команды и не занимает руки."
				BaseGameplayController.QuestStage.COLLECTED:
					return "Ключ получен командой. Вернитесь на уровень 0 и передайте его терминалу центрального хаба."
				BaseGameplayController.QuestStage.DELIVERED:
					return "Ключ принят. Задание второго дня выполнено. Подтвердите готовность на койках и отдохните всей командой."
		3:
			return "Уровень 2 обследован. Вернитесь на базу и отдохните." if _controller.containment.get("level2", false) else "Спуститесь на уровень 2 и обследуйте внутреннюю зону. Уровень 3 будет доступен на следующий день."
		4:
			if _controller.containment.get("resolved", false) and _controller.containment.get("level3", false):
				return "Уровень 3 обследован, угроза устранена и питание восстановлено. Вернитесь на базу и отдохните."
			if _controller.containment.get("fault", false):
				return "Сбой питания после зачистки. Выключите и снова включите главный щит. Обследуйте внутреннюю зону уровня 3."
			return "Обследуйте уровень 3, устраните угрозу и восстановите питание после зачистки."
		5:
			return "Предыдущие задания завершены. Уровень 4 доступен. Следующее сюжетное задание пока не добавлено."
	return "Данные задания недоступны."
