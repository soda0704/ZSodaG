class_name DayTwoTerminal
extends StaticBody3D

signal clicker_result(id: StringName, success: bool, amount: float)

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
var active := false
var _previous_camera: Camera3D
var _local_player: GamePlayer
var _sequence := 0
var _sessions: Dictionary = {}
var operator_peer := 0
var app_scroll := 0
var _operator_check_elapsed := 0.0
var _opening_day := 0
var _quest_authorized_peer := 0
var _screen_triangles: Array = []
@onready var app_camera: Camera3D = $Screen/AppCamera

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
		ui.bind(_controller, self)
		ui.quest_requested.connect(func(): request_clicker_action(&"quest"))
		ui.close_requested.connect(close_terminal)
		_controller.clicker_changed.connect(_refresh_idle_clicker)
		_controller.snapshot_changed.connect(_on_snapshot_changed)
		_on_snapshot_changed(_controller.get_snapshot())
	_cache_screen_triangles()

func get_interaction_prompt() -> String:
	if _controller == null or not _controller.main_breaker_on: return ""
	return "Открыть терминал"

func network_interact(peer_id: int, interactor: Node) -> void:
	if not can_use(peer_id, interactor): return
	var stage := _controller.quest_stage
	if is_key_terminal:
		if _quest_authorized_peer != peer_id: return
		if stage in [BaseGameplayController.QuestStage.OFFERED, BaseGameplayController.QuestStage.ACCEPTED]:
			_controller.advance_quest_authoritative(peer_id, stage)
	elif stage == BaseGameplayController.QuestStage.COLLECTED:
		_controller.advance_quest_authoritative(peer_id, stage)

func can_use(peer_id: int, interactor: Node) -> bool:
	if not multiplayer.is_server() or _controller == null or not _controller.main_breaker_on:
		return false
	var player := interactor as GamePlayer
	if player == null or player.owner_peer_id != peer_id or _controller.get_player_node(peer_id) != player:
		return false
	if player.survival.dead or player.is_sleeping_in_bunk() or player.is_driving() or player.is_carrying_corpse():
		return false
	if player.global_position.distance_to(global_position) > interaction_distance:
		return false
	var origin := player.camera.global_position
	if screen.global_basis.z.dot(origin - screen.global_position) <= 0.0:
		return false
	var query := PhysicsRayQueryParameters3D.create(origin, screen.global_position, 3, [player.get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty() and hit.collider != self:
		return false
	return true

func _on_snapshot_changed(_snapshot: Dictionary) -> void:
	var powered := _controller.main_breaker_on
	_set_powered(powered)
	_refresh_screen()
	var stage := int(_controller.quest_stage)
	if stage != _previous_stage:
		var extracting := is_key_terminal and _previous_stage in [1, 2] and stage == 3
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
	if powered: screen_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if active or operator_peer > 0 else SubViewport.UPDATE_ONCE
	if not powered and multiplayer.is_server() and operator_peer != 0: _release_operator()
	if active and not powered: close_terminal()

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
	_screen_material.set_shader_parameter("key_missing", not has_key and not ui.app_open)
	ui.get_node("%Title").text = "X-LAB / ХРАНИЛИЩЕ ДАННЫХ · 1" if is_key_terminal else "NORTHERN LAB / ЭКСПЕДИЦИЯ"
	ui.get_node("%Day").text = "ДЕНЬ %d" % _controller.day_index
	ui.get_node("%System").text = "ПИТАНИЕ / СЕТЬ БАЗЫ · ТОПЛИВО %.1f Л · РЕЗЕРВ ЛИФТА %s" % [_controller.fuel_liters, "ГОТОВ" if _controller.elevator_backup_installed else "ОТКЛЮЧЁН"]
	var heading := "ПОДГОТОВКА ЭКСПЕДИЦИИ"
	match _controller.day_index:
		2: heading = "КЛЮЧ ШИФРОВАНИЯ / PASS KEY"
		3: heading = "ОБСЛЕДОВАНИЕ УРОВНЯ 2"
		4: heading = "ИСПЫТАНИЯ И НАБЛЮДЕНИЕ / УРОВЕНЬ 3"
		5: heading = "БИОКОНТЕЙНМЕНТ / УРОВЕНЬ 4"
		6: heading = "ЭКСПЕДИЦИОННАЯ ШАХТА / УРОВЕНЬ 5"
		7: heading = "ПЕЩЕРА / ГЛУБИННАЯ ЭКСПЕДИЦИЯ"
	ui.get_node("%Heading").text = heading
	ui.get_node("%Objective").text = _objective_text()
	var stages := ["НЕДОСТУПЕН", "В ХРАНИЛИЩЕ", "В ХРАНИЛИЩЕ", "У КОМАНДЫ · 1 ШТ.", "ПЕРЕДАН НА БАЗУ"]
	ui.get_node("%Progress").text = "PASS KEY / " + stages[int(_controller.quest_stage)]
	ui.get_node("%Action").text = get_interaction_prompt()
	ui.set_quest_available(_controller.day_index == 2 and ((is_key_terminal and stage in [1, 2]) or (not is_key_terminal and stage == 3)))

func _objective_text() -> String:
	match _controller.day_index:
		1:
			return "Восстановите основное питание базы. Подключите резерв лифта: предохранитель находится в медицинской комнате. После подготовки отдохните."
		2:
			match _controller.quest_stage:
				BaseGameplayController.QuestStage.OFFERED:
					return "Извлеките pass key из хранилища данных на уровне 1 и принесите в центральный хаб. Предварительно получать задание в хабе не нужно."
				BaseGameplayController.QuestStage.ACCEPTED:
					return "Извлеките pass key из терминала хранилища на уровне 1 и передайте в центральный хаб. Ключ общий для команды и не занимает руки."
				BaseGameplayController.QuestStage.COLLECTED:
					return "Ключ получен командой. Вернитесь на уровень 0 и передайте его терминалу центрального хаба."
				BaseGameplayController.QuestStage.DELIVERED:
					return "Ключ принят. Задание второго дня выполнено. Ложитесь спать на койках всей командой."
		3:
			return "Уровень 2 обследован. Вернитесь на базу и отдохните." if _controller.containment.get("level2", false) else "Спуститесь на уровень 2 и обследуйте внутреннюю зону. На следующий день будет доступен уровень 3."
		4:
			return "Испытательная камера обследована. Вернитесь на базу и отдохните." if _controller.containment.get("trials", false) else "Обследуйте испытательную камеру на уровне 3. Вход доступен через служебный обход."
		_:
			var objective := _controller.get_expedition_objective()
			var lines: PackedStringArray = []
			if not str(objective.get("description", "")).is_empty(): lines.append(str(objective.description))
			for task in objective.tasks:
				lines.append(("✓ " if task.done else "") + str(task.text))
			if not objective.note.is_empty(): lines.append(objective.note)
			return "\n".join(lines)

	return "Данные задания недоступны."


func begin_terminal_interaction() -> void:
	if active or _controller == null or not _controller.main_breaker_on: return
	if get_tree().get_first_node_in_group("terminal_ui") != null or get_tree().get_first_node_in_group("wiring_ui") != null: return
	var menu := get_node_or_null("/root/GameMenu")
	if menu != null and menu.is_menu_open(): return
	_local_player = get_tree().get_first_node_in_group("local_player") as GamePlayer
	if _local_player == null or _local_player.survival.dead or _local_player.is_sleeping_in_bunk() or _local_player.is_driving() or _local_player.is_carrying_corpse(): return
	get_node("/root/QuestJournal").force_close()
	_previous_camera = get_viewport().get_camera_3d()
	active = true
	_sequence = 0
	add_to_group("terminal_ui")
	_local_player.refresh_crosshair_visibility()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	app_camera.make_current()
	_opening_day = _controller.day_index
	screen_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	if multiplayer.is_server(): _open_session(multiplayer.get_unique_id())
	else: _request_open.rpc_id(1)

func _process(delta: float) -> void:
	if multiplayer.is_server() and operator_peer > 0:
		_operator_check_elapsed += delta
		if _operator_check_elapsed > 0.5:
			_operator_check_elapsed = 0.0
			if not can_use(operator_peer, _controller.get_player_node(operator_peer)): _release_operator()
	if not active: return
	var menu := get_node_or_null("/root/GameMenu")
	var console := get_node_or_null("/root/DeveloperConsole")
	if not is_instance_valid(_local_player) or not _controller.main_breaker_on or (menu != null and menu.is_menu_open() and not menu.is_capturing_feedback_screenshot()) or (console != null and console.opened):
		close_terminal()
	elif _controller.day_index != _opening_day or _local_player.survival.dead or _local_player.is_sleeping_in_bunk() or _local_player.is_debug_free_camera_active() or _local_player.is_driving() or _local_player.is_carrying_corpse() or _local_player.global_position.distance_to(global_position) > interaction_distance:
		close_terminal()

func refresh_app_display() -> void:
	if _controller != null:
		_refresh_screen()
		if _controller.main_breaker_on: screen_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if active or operator_peer > 0 else SubViewport.UPDATE_ONCE

func close_terminal() -> void:
	if not active: return
	ui._cancel_quest_hold()
	active = false
	remove_from_group("terminal_ui")
	if multiplayer.is_server():
		if operator_peer == multiplayer.get_unique_id(): _release_operator()
	elif multiplayer.multiplayer_peer != null and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		_request_close.rpc_id(1)
	if get_viewport().get_camera_3d() == app_camera and is_instance_valid(_previous_camera) and _previous_camera.is_inside_tree(): _previous_camera.make_current()
	var menu := get_node_or_null("/root/GameMenu")
	var console := get_node_or_null("/root/DeveloperConsole")
	if is_instance_valid(_local_player) and _local_player.is_inside_tree():
		if not _local_player.survival.dead and (menu == null or not menu.is_menu_open()) and (console == null or not console.opened): Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		_local_player.refresh_crosshair_visibility()
	ui.refresh_access()
	refresh_app_display()
	_local_player = null

func _exit_tree() -> void:
	if active: close_terminal()

@rpc("any_peer", "call_remote", "reliable")
func _request_open() -> void:
	if multiplayer.is_server(): _open_session(multiplayer.get_remote_sender_id())

func _open_session(peer: int) -> void:
	var allowed := can_use(peer, _controller.get_player_node(peer))
	if allowed and operator_peer == 0:
		_sessions.clear()
		_sessions[peer] = {"sequence": 0, "tokens": 45.0, "time": Time.get_ticks_msec()}
		_publish_operator(peer, ui.app_open)
	elif allowed and peer != multiplayer.get_unique_id():
		_receive_operator.rpc_id(peer, operator_peer, ui.app_open)
	if peer == multiplayer.get_unique_id():
		if not allowed: close_terminal()
	else: _session_reply.rpc_id(peer, allowed)

func can_operate() -> bool:
	return active and operator_peer == multiplayer.get_unique_id()

func _release_operator() -> void:
	_sessions.clear()
	_publish_operator(0, ui.app_open)

@rpc("authority", "call_local", "reliable")
func _receive_operator(peer: int, app: bool) -> void:
	operator_peer = peer
	ui.select_app(app)
	ui.refresh_access()
	refresh_app_display()

func request_app(app: bool) -> void:
	if not can_operate(): return
	if multiplayer.is_server(): _publish_operator(operator_peer, app)
	else: _request_app.rpc_id(1, app)

@rpc("any_peer", "call_remote", "reliable")
func _request_app(app: bool) -> void:
	if multiplayer.is_server() and multiplayer.get_remote_sender_id() == operator_peer and can_use(operator_peer, _controller.get_player_node(operator_peer)):
		_publish_operator(operator_peer, app)

@rpc("authority", "call_remote", "reliable")
func _session_reply(allowed: bool) -> void:
	if not allowed: close_terminal()

@rpc("any_peer", "call_remote", "reliable")
func _request_close() -> void:
	if multiplayer.is_server() and multiplayer.get_remote_sender_id() == operator_peer: _release_operator()

func request_clicker_action(id: StringName, event_id: int = 0) -> bool:
	if not can_operate(): return false
	_sequence += 1
	if multiplayer.is_server(): _command(multiplayer.get_unique_id(), _sequence, id, event_id)
	else: _request_command.rpc_id(1, _sequence, id, event_id)
	return true

@rpc("any_peer", "call_remote", "reliable")
func _request_command(sequence: int, id: StringName, event_id: int = 0) -> void:
	if multiplayer.is_server(): _command(multiplayer.get_remote_sender_id(), sequence, id, event_id)

func _command(peer: int, sequence: int, id: StringName, event_id: int = 0) -> void:
	if peer != operator_peer or not _sessions.has(peer) or sequence <= int(_sessions[peer].sequence): return
	var session: Dictionary = _sessions[peer]
	session.sequence = sequence
	var now := Time.get_ticks_msec()
	session.tokens = minf(45.0, float(session.tokens) + (now - int(session.time)) * 0.03)
	session.time = now
	var accepted := can_use(peer, _controller.get_player_node(peer)) and float(session.tokens) >= 1.0
	var amount := 0.0
	if accepted:
		session.tokens = float(session.tokens) - 1.0
		match id:
			&"click": amount = _controller.clicker.click()
			&"quest_begin": session.quest_started = now
			&"quest_cancel": session.erase("quest_started")
			&"quest":
				accepted = not is_key_terminal or (session.has("quest_started") and now - int(session.quest_started) >= 1250)
				session.erase("quest_started")
				if accepted:
					_quest_authorized_peer = peer
					network_interact(peer, _controller.get_player_node(peer))
					_quest_authorized_peer = 0
			&"bacteria":
				accepted = event_id == _controller.clicker.bacteria_id and event_id > 0 and _controller.clicker.bacteria_remaining > 0.0
				if accepted: amount = _controller.clicker.collect_bacterium(event_id)
			_: accepted = _controller.clicker.buy(id)
	var data := _controller.clicker.capture_runtime()
	_command_reply(id, accepted, amount, data)
	for ready_peer in _controller.clicker_ready_peers(): _command_reply.rpc_id(ready_peer, id, accepted, amount, data)
	# Terminal progress is captured only by manual saves and morning checkpoints.

@rpc("authority", "call_local", "reliable")
func _command_reply(id: StringName, accepted: bool, amount: float, data: Dictionary) -> void:
	_controller._receive_clicker_state(data)
	clicker_result.emit(id, accepted, amount)
	if _controller.main_breaker_on and not active and operator_peer == 0: screen_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE

func _cache_screen_triangles() -> void:
	if _display_mesh == null or _display_mesh.mesh == null: return
	var bounds: Vector4 = _screen_material.get_shader_parameter("screen_atlas_rect")
	for surface in _display_mesh.mesh.get_surface_count():
		var arrays := _display_mesh.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		if uvs.size() != vertices.size(): continue
		if indices.is_empty():
			for i in vertices.size(): indices.append(i)
		for index in range(0, indices.size() - 2, 3):
			var triangle: Array = []
			var uv_min := Vector2(INF, INF)
			var uv_max := Vector2(-INF, -INF)
			for j in 3:
				var uv := uvs[indices[index + j]]
				uv_min = uv_min.min(uv)
				uv_max = uv_max.max(uv)
				triangle.append(vertices[indices[index + j]])
				triangle.append(uv)
			if uv_max.x >= bounds.x and uv_min.x <= bounds.z and uv_max.y >= bounds.y and uv_min.y <= bounds.w: _screen_triangles.append(triangle)

func screen_point(point: Vector2) -> Vector2:
	# Intersect the imported screen triangles and interpolate their real UVs.
	# This preserves the model's bevelled shape and avoids a guessed overlay plane.
	var canvas_size := get_viewport().get_visible_rect().size
	var render_size := app_camera.get_viewport().get_visible_rect().size
	var pixel := point * render_size / canvas_size
	var inverse := _display_mesh.global_transform.affine_inverse()
	var origin := inverse * app_camera.project_ray_origin(pixel)
	var direction := inverse.basis * app_camera.project_ray_normal(pixel)
	var bounds: Vector4 = _screen_material.get_shader_parameter("screen_atlas_rect")
	for triangle in _screen_triangles:
		var hit: Variant = Geometry3D.ray_intersects_triangle(origin, direction, triangle[0], triangle[2], triangle[4])
		if hit == null: continue
		var v0: Vector3 = triangle[2] - triangle[0]
		var v1: Vector3 = triangle[4] - triangle[0]
		var v2: Vector3 = hit - triangle[0]
		var denominator: float = v0.dot(v0) * v1.dot(v1) - v0.dot(v1) * v0.dot(v1)
		if absf(denominator) < 0.00000001: continue
		var b: float = (v1.dot(v1) * v2.dot(v0) - v0.dot(v1) * v2.dot(v1)) / denominator
		var c: float = (v0.dot(v0) * v2.dot(v1) - v0.dot(v1) * v2.dot(v0)) / denominator
		var uv: Vector2 = triangle[1] * (1.0 - b - c) + triangle[3] * b + triangle[5] * c
		if uv.x < bounds.x or uv.x > bounds.z or uv.y < bounds.y or uv.y > bounds.w: continue
		return Vector2((uv.y - bounds.y) / (bounds.w - bounds.y), (uv.x - bounds.x) / (bounds.z - bounds.x)) * Vector2(screen_viewport.size)
	return Vector2(-100, -100)

func _input(event: InputEvent) -> void:
	if not active: return
	if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
		close_terminal()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("tester_feedback"): return
	if event is InputEventMouse:
		var forwarded := event.duplicate() as InputEventMouse
		forwarded.position = screen_point(event.position)
		forwarded.global_position = forwarded.position
		if forwarded is InputEventMouseMotion: forwarded.relative = Vector2.ZERO
		screen_viewport.push_input(forwarded, true)
		get_viewport().set_input_as_handled()
	elif event is InputEventKey or event is InputEventJoypadButton or event is InputEventJoypadMotion:
		# Contextual GUI navigation never invokes weapon, journal or world actions.
		screen_viewport.push_input(event, true)
		get_viewport().set_input_as_handled()


func _refresh_idle_clicker() -> void:
	if _controller.main_breaker_on and ui.app_open and not active and operator_peer == 0:
		screen_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


func sync_app_to_peer(peer: int) -> void:
	if multiplayer.is_server():
		_receive_operator.rpc_id(peer, operator_peer, ui.app_open)
		_receive_scroll.rpc_id(peer, app_scroll)


func _publish_operator(peer: int, app: bool) -> void:
	_receive_operator(peer, app)
	for ready_peer in _controller.clicker_ready_peers(): _receive_operator.rpc_id(ready_peer, peer, app)


func request_scroll(value: int) -> void:
	if not can_operate(): return
	if multiplayer.is_server(): _publish_scroll(value)
	else: _request_scroll.rpc_id(1, value)

@rpc("any_peer", "call_remote", "reliable")
func _request_scroll(value: int) -> void:
	if multiplayer.is_server() and multiplayer.get_remote_sender_id() == operator_peer and can_use(operator_peer, _controller.get_player_node(operator_peer)):
		_publish_scroll(value)

func _publish_scroll(value: int) -> void:
	var bar: VScrollBar = ui.get_node("Overlay/LabClicker/Scroll").get_v_scroll_bar()
	var bounded := clampi(value, 0, maxi(0, int(bar.max_value - bar.page)))
	_receive_scroll(bounded)
	for ready_peer in _controller.clicker_ready_peers(): _receive_scroll.rpc_id(ready_peer, bounded)

@rpc("authority", "call_remote", "reliable")
func _receive_scroll(value: int) -> void:
	app_scroll = maxi(0, value)
	if not can_operate(): ui.get_node("Overlay/LabClicker/Scroll").scroll_vertical = app_scroll
