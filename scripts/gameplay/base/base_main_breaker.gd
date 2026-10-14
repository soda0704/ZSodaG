class_name BaseMainBreaker
extends StaticBody3D

@export_range(0.1, 10.0) var interaction_distance := 4.0
@export var powered_model_material: Material
@export var unpowered_model_material: Material
@export var powered_indicator_material: Material
@export var unpowered_indicator_material: Material
@onready var indicator: MeshInstance3D = %Indicator
@onready var status_label: Label3D = %StatusLabel
@onready var cover: Node3D = %ServiceCover
@onready var cover_animation: AnimationPlayer = %CoverAnimation
@onready var lever_animation: AnimationPlayer = %LeverAnimation
@onready var wiring: BreakerWiringInteraction = $Wiring
@onready var interaction_point: Marker3D = $InteractionPoint
var _controller: BaseGameplayController
var _initialized := false
var _last_power := false
var _last_cover_open := false
var _cover_open := false
var _viewers: Dictionary = {}

func _ready() -> void:
	add_to_group("main_breaker")
	multiplayer.peer_disconnected.connect(_on_viewer_left)
	call_deferred("_bind_controller")

# Opening the service door is a transient interaction, not a saved day state.
func set_local_service_view(opened: bool) -> void:
	if not is_inside_tree(): return
	if multiplayer.is_server(): _request_service_view(opened)
	else: _request_service_view.rpc_id(1, opened)

@rpc("any_peer", "call_remote", "reliable")
func _request_service_view(opened: bool) -> void:
	if not multiplayer.is_server(): return
	var peer_id := multiplayer.get_remote_sender_id()
	if peer_id == 0: peer_id = multiplayer.get_unique_id()
	var controller := get_controller()
	if opened:
		if controller == null or not controller.maintenance.get("wires_required", false) or not can_use(peer_id, controller.get_player_node(peer_id)): return
		_viewers[peer_id] = true
	else: _viewers.erase(peer_id)
	_sync_cover()

@rpc("any_peer", "call_remote", "reliable")
func _request_service_state() -> void:
	if multiplayer.is_server(): _set_service_open.rpc_id(multiplayer.get_remote_sender_id(), _cover_open)

@rpc("authority", "call_local", "reliable")
func _set_service_open(opened: bool) -> void:
	_cover_open = opened
	_apply_cover()

func _sync_cover() -> void:
	var opened := not _viewers.is_empty()
	if opened != _cover_open: _set_service_open.rpc(opened)

func _on_viewer_left(peer_id: int) -> void:
	if multiplayer.is_server():
		_viewers.erase(peer_id)
		_sync_cover()

func _process(_delta: float) -> void:
	if not multiplayer.is_server() or _viewers.is_empty(): return
	var controller := get_controller()
	for peer_id in _viewers.keys():
		if controller == null or controller.main_breaker_on or not can_use(peer_id, controller.get_player_node(peer_id)):
			_viewers.erase(peer_id)
	_sync_cover()

func get_controller() -> BaseGameplayController:
	if not is_instance_valid(_controller):
		_controller = get_tree().get_first_node_in_group("base_gameplay_controller") as BaseGameplayController
	return _controller

func get_interaction_prompt() -> String:
	var controller := get_controller()
	if controller == null: return "Главный щит недоступен"
	if controller.maintenance.get("wires_required", false): return "Открыть щит · восстановить проводку"
	if controller.containment.get("fault", false):
		return "Выключить щит для сброса сбоя" if controller.main_breaker_on else "Включить щит — восстановить освещение"
	if controller.main_breaker_on: return "Выключить главный щит"
	if not controller.fuel_delivered: return "Нет топлива для запуска"
	return "Включить главный щит"

func interact(interactor: Node) -> void:
	network_interact(multiplayer.get_unique_id(), interactor)

func can_use(peer_id: int, interactor: Node) -> bool:
	var player := interactor as GamePlayer
	if not is_inside_tree() or player == null or not player.is_inside_tree(): return false
	var controller := get_controller()
	if player == null or controller == null or player.owner_peer_id != peer_id or controller.get_player_node(peer_id) != player: return false
	if player.survival.dead or player.is_sleeping_in_bunk() or player.is_driving() or player.is_carrying_corpse(): return false
	if player.global_position.distance_to(global_position) > interaction_distance: return false
	var origin := player.camera.global_position
	if (-global_basis.z).dot(origin - interaction_point.global_position) <= 0.0: return false
	var query := PhysicsRayQueryParameters3D.create(origin, interaction_point.global_position, 3, [player.get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return hit.is_empty() or hit.collider == self

func network_interact(peer_id: int, interactor: Node) -> void:
	if not multiplayer.is_server() or not can_use(peer_id, interactor): return
	var controller := get_controller()
	if controller.maintenance.get("wires_required", false):
		controller.open_wiring_ui.rpc_id(peer_id)
	elif controller.containment.get("fault", false):
		var encounter := get_tree().get_first_node_in_group("containment_encounter")
		if encounter != null: encounter.cycle_breaker(peer_id)
	elif controller.main_breaker_on:
		controller.deactivate_main_breaker_authoritative(peer_id)
	else:
		controller.activate_main_breaker_authoritative(peer_id)

func _bind_controller() -> void:
	var controller := get_controller()
	if controller == null:
		push_warning("BaseMainBreaker could not find BaseGameplayController")
		return
	controller.snapshot_changed.connect(_apply_snapshot)
	wiring.bind_controller(controller)
	_apply_snapshot(controller.get_snapshot())
	if not multiplayer.is_server(): _request_service_state.rpc_id(1)

func _apply_snapshot(_snapshot: Dictionary) -> void:
	var controller := get_controller()
	if controller == null: return
	var powered := controller.main_breaker_on
	if not _initialized or powered != _last_power:
		indicator.material_override = powered_indicator_material if powered else unpowered_indicator_material
		for mesh in [%Housing, %Handle]:
			mesh.material_override = powered_model_material if powered else unpowered_model_material
		_set_clip(lever_animation, &"switch", powered, not _initialized)
		if _initialized and powered: $PowerAudio.play()
		status_label.text = "ОСНОВНОЕ ПИТАНИЕ / ВКЛ" if powered else "ОСНОВНОЕ ПИТАНИЕ / ВЫКЛ"
	if multiplayer.is_server() and powered:
		_viewers.clear()
		_sync_cover()
	_apply_cover()
	_last_power = powered
	_initialized = true

func _apply_cover() -> void:
	if not _initialized or _cover_open != _last_cover_open:
		_set_clip(cover_animation, &"open", _cover_open, not _initialized)
		if _initialized: $CoverAudio.play()
	$Wiring/Board.visible = _cover_open
	_last_cover_open = _cover_open

func _set_clip(animator: AnimationPlayer, clip: StringName, forward: bool, instant: bool) -> void:
	if instant:
		animator.play(clip)
		animator.seek(animator.get_animation(clip).length if forward else 0.0, true)
		animator.stop(true)
	elif forward: animator.play(clip)
	else: animator.play_backwards(clip)
