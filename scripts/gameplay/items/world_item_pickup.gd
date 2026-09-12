class_name WorldItemPickup
extends RigidBody3D

const PHYSICS_SYNC_RATE := 10.0

@export var item_type: StringName = &""
@export var display_name: String = "предмет"
@export var item_state: Dictionary = {}

var _collected: bool = false
var _sync_accumulator: float = 0.0
var _initial_linear_velocity: Vector3 = Vector3.ZERO
var _initial_angular_velocity: Vector3 = Vector3.ZERO


func setup_spawn(data: Dictionary) -> void:
	name = str(data.get("pickup_name", "WorldItemPickup"))
	item_type = StringName(data.get("item_type", item_type))
	item_state = (
		data.get("item_state", item_state) as Dictionary
	).duplicate(true)
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
	continuous_cd = true
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
	match item_type:
		&"flashlight":
			return "Поднять фонарик — заряд %d%%" % roundi(
				float(item_state.get("battery_charge", 1.0)) * 100.0
			)
		&"battery":
			return "Забрать батарейку в запас (заряд %d%%)" % roundi(
				float(item_state.get("charge_amount", 0.5)) * 100.0
			)
		&"fuse":
			return "Поднять предохранитель"
		&"fuel_can":
			return "Поднять канистру · %.1f / 20 л" % float(item_state.get("fuel_liters", 20.0))
	return "Поднять %s" % display_name


func interact(interactor: Node) -> void:
	network_interact(multiplayer.get_unique_id(), interactor)


func network_interact(peer_id: int, interactor: Node) -> void:
	if (
		not multiplayer.is_server()
		or _collected
		or not interactor.has_method("pickup_world_item_authoritative")
		or int(interactor.get("owner_peer_id")) != peer_id
		or not interactor is Node3D
		or global_position.distance_to((interactor as Node3D).global_position) > 4.0
	):
		return

	var accepted := bool(interactor.call(
		"pickup_world_item_authoritative",
		item_type,
		item_state.duplicate(true)
	))
	if not accepted:
		return
	_collected = true
	freeze = true
	collision_layer = 0
	collision_mask = 0
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
