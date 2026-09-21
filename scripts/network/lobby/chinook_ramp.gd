extends AnimatableBody3D
## Rear cargo ramp. Motion is authored in AnimationPlayer; the server owns its state.
@export var starts_open := false
@export var locked_in_flight := false
@onready var animation: AnimationPlayer = $AnimationPlayer
@onready var clearance: Area3D = $"../RampClearance"
var opened := false

func _ready() -> void:
	add_to_group("helicopter_ramps")
	_apply_state(starts_open, true)

func get_interaction_prompt() -> String:
	if locked_in_flight:
		return "Рампа заблокирована до посадки"
	if animation.is_playing():
		return "Рампа движется"
	if opened and _passage_occupied():
		return "Освободите проход у рампы"
	return "Закрыть рампу" if opened else "Открыть рампу"

func network_interact(peer_id: int, interactor: Node) -> void:
	if not multiplayer.is_server() or interactor == null or int(interactor.get("owner_peer_id")) != peer_id:
		return
	if locked_in_flight or animation.is_playing() or (opened and _passage_occupied()):
		return
	debug_set_open(not opened)

func _passage_occupied() -> bool:
	# Query the authored clearance volume now, including a player teleported
	# this frame; Area3D's cached overlap list may still describe the last tick.
	var volume: CollisionShape3D = clearance.get_node("Shape")
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = volume.shape
	query.transform = volume.global_transform
	query.collision_mask = clearance.collision_mask
	return not get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()

func debug_set_open(value: bool) -> void:
	if not multiplayer.is_server():
		return
	_apply_state(value)
	var session := get_tree().get_first_node_in_group("network_gameplay_controller")
	var peers = multiplayer.get_peers()
	if session != null and not locked_in_flight:
		peers = session.get_ready_v3_peers()
	for peer_id in peers:
		_receive_state.rpc_id(peer_id, value, false)

func sync_network_state_to_peer(peer_id: int) -> void:
	if multiplayer.is_server() and multiplayer.get_peers().has(peer_id):
		_receive_state.rpc_id(peer_id, opened, true)

@rpc("authority", "call_remote", "reliable")
func _receive_state(value: bool, instant: bool) -> void:
	_apply_state(value, instant)

func _apply_state(value: bool, instant := false) -> void:
	var progress := animation.current_animation_position if animation.is_playing() else (animation.get_animation("deploy").length if opened else 0.0)
	opened = value
	animation.play("deploy", -1, 1.0 if value else -1.0, not value)
	animation.seek((animation.current_animation_length if value else 0.0) if instant else progress, true)
	if instant:
		animation.pause()


