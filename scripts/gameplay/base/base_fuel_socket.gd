class_name BaseFuelSocket
extends StaticBody3D

const FUEL_ITEM := &"fuel_can"

@export_range(0.1, 10.0) var interaction_distance := 4.0
@export var gauge_animation: StringName = &"fuel_level"
@onready var gauge: AnimationPlayer = %GaugeAnimation
@onready var filler_animation: AnimationPlayer = $FillerAnimation
@onready var interaction_point: Marker3D = $InteractionPoint
var _controller: BaseGameplayController
var _last_fraction := -1.0

func _ready() -> void:
	call_deferred("_bind_controller")

# The player renders only the bound action glyph, without fuel/status text.
func get_interaction_hint_for(interactor: Node) -> String:
	var player := interactor as GamePlayer
	var controller := _get_controller()
	if player == null or controller == null or not player.has_held_item(FUEL_ITEM) or player.fuel_liters <= 0.0 or controller.fuel_liters >= controller.FUEL_CAPACITY:
		return ""
	return get_node("/root/SteamInput").get_action_hint(&"interact")

func get_interaction_prompt() -> String:
	return ""

func interact(interactor: Node) -> void:
	network_interact(multiplayer.get_unique_id(), interactor)

func can_refill(peer_id: int, interactor: Node) -> bool:
	var player := interactor as GamePlayer
	var controller := _get_controller()
	if player == null or controller == null or not player.is_inside_tree() or player.owner_peer_id != peer_id or controller.get_player_node(peer_id) != player: return false
	if player.survival.dead or player.is_sleeping_in_bunk() or player.is_driving() or player.is_carrying_corpse(): return false
	if not player.has_held_item(FUEL_ITEM) or not is_finite(player.fuel_liters) or player.fuel_liters <= 0.0: return false
	if player.global_position.distance_to(interaction_point.global_position) > interaction_distance: return false
	if (-global_basis.z).dot(player.camera.global_position - interaction_point.global_position) <= 0.0: return false
	var query := PhysicsRayQueryParameters3D.create(player.camera.global_position, interaction_point.global_position, 3, [player.get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return hit.is_empty() or hit.collider == self

func network_interact(peer_id: int, interactor: Node) -> void:
	if not multiplayer.is_server() or not can_refill(peer_id, interactor): return
	var player := interactor as GamePlayer
	var controller := _get_controller()
	var remaining := player.fuel_liters
	var transfer := minf(remaining, controller.FUEL_CAPACITY - controller.fuel_liters)
	if transfer <= 0.0: return
	# The synchronous world checkpoint must already include the reduced canister.
	player.fuel_liters = remaining - transfer
	var added := controller.refill_authoritative(peer_id, transfer)
	player.fuel_liters = remaining - added
	if added <= 0.0: return
	player._publish_inventory()
	_play_pour.rpc()

func _process(_delta: float) -> void:
	if is_instance_valid(_controller): _update_gauge()

func _bind_controller() -> void:
	_controller = _get_controller()
	if _controller == null:
		push_warning("BaseFuelSocket could not find BaseGameplayController")
		return
	gauge.play(gauge_animation)
	gauge.pause()
	_controller.snapshot_changed.connect(_on_snapshot_changed)
	_update_gauge()

func _on_snapshot_changed(_snapshot: Dictionary) -> void:
	_update_gauge()

func _get_controller() -> BaseGameplayController:
	if is_instance_valid(_controller): return _controller
	_controller = get_tree().get_first_node_in_group("base_gameplay_controller") as BaseGameplayController
	return _controller

func _update_gauge() -> void:
	var fraction := clampf(_controller.fuel_liters / _controller.FUEL_CAPACITY, 0.0, 1.0)
	if is_equal_approx(fraction, _last_fraction): return
	gauge.seek(fraction * gauge.get_animation(gauge_animation).length, true)
	_last_fraction = fraction

@rpc("authority", "call_local", "reliable")
func _play_pour() -> void:
	$PourAudio.play()
	filler_animation.play(&"refill")
