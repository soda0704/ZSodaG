class_name FlashlightPickup
extends RigidBody3D

const PHYSICS_SYNC_RATE := 10.0

@export var interaction_prompt: String = "Поднять фонарик"
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
	return "%s — заряд %d%%" % [
		interaction_prompt,
		roundi(battery_charge * 100.0),
	]


func interact(interactor: Node) -> void:
	network_interact(multiplayer.get_unique_id(), interactor)


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
	freeze = true
	collision_layer = 0
	collision_mask = 0
	if (
		previous_charge >= 0.0
		and interactor.has_method("spawn_dropped_flashlight_authoritative")
	):
		interactor.call(
			"spawn_dropped_flashlight_authoritative",
			previous_charge
		)
	queue_free()


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
