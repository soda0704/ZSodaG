class_name PlantWateringButton
extends StaticBody3D
## The base owns daily use and persistence; this node owns interaction and VFX.

@export_range(0.1, 5.0) var interaction_distance := 2.5
@export var animation_path := NodePath("../WateringAnimation")
@export var status_animation_path := NodePath("../StatusAnimation")
@export var watering_animation: StringName = &"water"
@onready var animation: AnimationPlayer = get_node(animation_path)
@onready var status_animation: AnimationPlayer = get_node(status_animation_path)
@onready var interaction_point: Marker3D = $InteractionPoint
var _controller: BaseGameplayController
var _last_watered_day := 0
var _initialized := false
var _status: StringName = &""

func _ready() -> void:
	add_to_group("plant_watering_button")
	animation.animation_finished.connect(_on_animation_finished)
	_bind_controller.call_deferred()

func get_controller() -> BaseGameplayController:
	if not is_instance_valid(_controller):
		_controller = get_tree().get_first_node_in_group("base_gameplay_controller") as BaseGameplayController
	return _controller

func can_use(peer_id: int, interactor: Node) -> bool:
	var player := interactor as GamePlayer
	var controller := get_controller()
	if player == null or controller == null or not player.is_inside_tree():
		return false
	if player.owner_peer_id != peer_id or controller.get_player_node(peer_id) != player:
		return false
	if player.survival.dead or player.is_sleeping_in_bunk() or player.is_driving() or player.is_carrying_corpse():
		return false
	if player.camera.global_position.distance_to(interaction_point.global_position) > interaction_distance:
		return false
	if global_basis.z.dot(player.camera.global_position - interaction_point.global_position) <= 0.0:
		return false
	var query := PhysicsRayQueryParameters3D.create(player.camera.global_position, interaction_point.global_position, 5, [player.get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return hit.is_empty() or hit.collider == self

func get_interaction_hint_for(interactor: Node) -> String:
	var player := interactor as GamePlayer
	var controller := get_controller()
	if player == null or controller == null or not can_use(player.owner_peer_id, player):
		return ""
	if not controller.main_breaker_on:
		return "Нет питания"
	if controller.plant_last_watered_day >= controller.day_index:
		return "Сегодня уже полито"
	return "%s Полить" % get_node("/root/SteamInput").get_action_hint(&"interact")

func network_interact(peer_id: int, _interactor: Node) -> void:
	if not multiplayer.is_server() or not can_use(peer_id, _interactor):
		return
	var controller := get_controller()
	if controller != null:
		controller.water_plant_authoritative(peer_id)

func _bind_controller() -> void:
	var controller := get_controller()
	if controller == null:
		push_warning("Plant watering button could not find base gameplay state")
		return
	controller.snapshot_changed.connect(_on_snapshot_changed)
	_on_snapshot_changed(controller.get_snapshot())

func _on_snapshot_changed(_snapshot: Dictionary) -> void:
	var controller := get_controller()
	if controller == null:
		return
	var watered := controller.plant_last_watered_day
	var newly_watered := _initialized and not controller.applying_initial_snapshot and watered != _last_watered_day and watered == controller.day_index
	_last_watered_day = watered
	_initialized = true
	if newly_watered and controller.main_breaker_on:
		animation.play(watering_animation)
	elif not controller.main_breaker_on or watered != controller.day_index:
		animation.play(&"RESET")
		animation.advance(0.0)
	_refresh_status()

func _refresh_status() -> void:
	var controller := get_controller()
	if controller == null:
		return
	var next: StringName = &"off" if not controller.main_breaker_on else &"watered" if controller.plant_last_watered_day >= controller.day_index else &"ready"
	if next != _status:
		_status = next
		status_animation.play(next)
		status_animation.advance(0.0)

func _on_animation_finished(_name: StringName) -> void:
	_refresh_status()
