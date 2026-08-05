class_name NetworkFlashlightPickup
extends RigidBody3D

const PHYSICS_SYNC_RATE := 10.0

@export_range(0.0, 1.0, 0.01) var battery_charge: float = 1.0

var _collected: bool = false
var _sync_accumulator: float = 0.0
var _initial_linear_velocity: Vector3 = Vector3.ZERO
var _initial_angular_velocity: Vector3 = Vector3.ZERO


func setup_spawn(data: Dictionary) -> void:
	name = str(data.get("pickup_name", "FlashlightPickup"))
	battery_charge = clampf(float(data.get("battery_charge", 1.0)), 0.0, 1.0)
	transform = data.get("transform", Transform3D.IDENTITY) as Transform3D
	_initial_linear_velocity = data.get(
		"linear_velocity",
		Vector3.ZERO
	) as Vector3
	_initial_angular_velocity = data.get(
		"angular_velocity",
		Vector3.ZERO
	) as Vector3


func _ready() -> void:
	if multiplayer.is_server():
		sleeping_state_changed.connect(_on_sleeping_state_changed)
		linear_velocity = _initial_linear_velocity
		angular_velocity = _initial_angular_velocity
	else:
		freeze = true
		set_physics_process(false)


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server() or _collected:
		return

	_sync_accumulator += delta
	var interval := 1.0 / PHYSICS_SYNC_RATE
	if _sync_accumulator < interval:
		return
	_sync_accumulator = fmod(_sync_accumulator, interval)
	sync_physics_state()


func sync_physics_state() -> void:
	_receive_physics_state.rpc(
		global_transform,
		linear_velocity,
		angular_velocity
	)


func _on_sleeping_state_changed() -> void:
	if not multiplayer.is_server():
		return
	if sleeping:
		sync_physics_state()
		set_physics_process(false)
	else:
		_sync_accumulator = 0.0
		set_physics_process(true)


func get_interaction_prompt() -> String:
	return "Поднять фонарик — заряд %d%%" % roundi(
		battery_charge * 100.0
	)


func network_interact(peer_id: int, interactor: Node) -> void:
	if (
		not multiplayer.is_server()
		or _collected
		or not interactor.has_method("swap_flashlight_authoritative")
		or int(interactor.get("owner_peer_id")) != peer_id
	):
		return

	var previous_charge := float(
		interactor.call("swap_flashlight_authoritative", battery_charge)
	)
	_collected = true
	var controller := get_tree().get_first_node_in_group(
		"network_gameplay_controller"
	)
	if controller != null and controller.has_method("collect_flashlight_pickup"):
		controller.call(
			"collect_flashlight_pickup",
			self,
			previous_charge,
			interactor
		)


@rpc("authority", "call_remote", "unreliable_ordered", 2)
func _receive_physics_state(
	next_transform: Transform3D,
	next_linear_velocity: Vector3,
	next_angular_velocity: Vector3
) -> void:
	if multiplayer.is_server():
		return
	global_transform = next_transform
	linear_velocity = next_linear_velocity
	angular_velocity = next_angular_velocity
