class_name PlantSeedSocket
extends StaticBody3D
## Optional planting uses ordinary held inventory and the host's shared snapshot.
@export_range(0.1, 5.0) var interaction_distance := 2.5
@export var animation_path := NodePath("../PlantingAnimation")
@export var seed_path := NodePath("../PlantedSeed")
@onready var animation: AnimationPlayer = get_node(animation_path)
@onready var seed: Node3D = get_node(seed_path)
@onready var interaction_point: Marker3D = $InteractionPoint
var _controller: BaseGameplayController
var _initialized := false
var _planted := false

func _ready() -> void:
	add_to_group("plant_seed_socket")
	animation.animation_finished.connect(_finished)
	_bind.call_deferred()

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
	if not player.has_held_item(GamePlayer.SEED_ITEM):
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
	if player == null or controller == null or controller.plant_seed_planted or not player.has_held_item(GamePlayer.SEED_ITEM) or not can_use(player.owner_peer_id, player):
		return ""
	return "%s Посадить семечко" % get_node("/root/SteamInput").get_action_hint(&"interact")

func network_interact(peer_id: int, interactor: Node) -> void:
	if multiplayer.is_server() and can_use(peer_id, interactor):
		get_controller().plant_seed_authoritative(peer_id)

func _bind() -> void:
	var controller := get_controller()
	if controller == null: return
	controller.snapshot_changed.connect(_changed)
	_changed(controller.get_snapshot())

func _changed(_snapshot: Dictionary) -> void:
	var controller := get_controller()
	var planted := controller.plant_seed_planted
	var newly_planted := _initialized and not controller.applying_initial_snapshot and planted and not _planted
	_planted = planted
	_initialized = true
	if newly_planted:
		animation.play(&"plant")
	elif not animation.is_playing() or controller.applying_initial_snapshot or not planted:
		animation.play(&"RESET")
		animation.advance(0.0)
		seed.visible = planted

func _finished(_name: StringName) -> void:
	seed.visible = _planted
