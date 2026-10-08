class_name WorldItemPickup
extends RigidBody3D

const PHYSICS_SYNC_RATE := 10.0

@export_group("Item")
@export var item_type: StringName = &""
@export var display_name: String = "предмет"
@export var item_state: Dictionary = {}
@export_group("Interaction")
@export var pickup_enabled := true
@export var draggable := true
@export_range(0.1, 10.0) var drag_distance := 3.5
@export_range(0.1, 10.0) var interaction_distance := 4.0
## -1 keeps the existing item-type resistance; nonnegative values override it.
@export_range(-1.0, 50.0) var push_resistance := -1.0

var _collected: bool = false
var drag_owner_peer := 0

func get_push_resistance() -> float:
	if push_resistance >= 0.0: return push_resistance
	return 4.0 if item_type == &"fuel_can" else 1.6 if item_type in [&"pistol", &"m4a1", &"kitchen_knife"] else 0.8
var _sync_accumulator: float = 0.0
var _initial_linear_velocity: Vector3 = Vector3.ZERO
var _initial_angular_velocity: Vector3 = Vector3.ZERO
var _cargo_cabin: Node3D
var _cargo_candidate: Node3D
var _cargo_pose := Transform3D.IDENTITY
var _cargo_cooldown := 0.0


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
	add_to_group("world_items")
	continuous_cd = true
	# Follow the cabin after its controller has advanced the physics pose.
	process_physics_priority = 20
	if multiplayer.is_server():
		sleeping_state_changed.connect(_on_sleeping_state_changed)
		linear_velocity = _initial_linear_velocity
		angular_velocity = _initial_angular_velocity
	else:
		freeze = true


func _physics_process(delta: float) -> void:
	if _collected:
		return
	if is_instance_valid(_cargo_cabin):
		global_transform = _cargo_cabin.global_transform * _cargo_pose
	elif multiplayer.is_server() and drag_owner_peer == 0:
		_cargo_cooldown = maxf(0.0, _cargo_cooldown - delta)
		if _cargo_cooldown <= 0.0:
			_capture_elevator_cargo()
	if not multiplayer.is_server():
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
		angular_velocity,
		_cargo_cabin.get_path() if is_instance_valid(_cargo_cabin) else NodePath(),
		_cargo_pose
	)


func _on_sleeping_state_changed() -> void:
	if not multiplayer.is_server():
		return
	if sleeping:
		sync_physics_state()
	else:
		_sync_accumulator = 0.0
		set_physics_process(true)


func _capture_elevator_cargo() -> void:
	if not is_instance_valid(_cargo_candidate):
		for cabin in get_tree().get_nodes_in_group("elevator_cabins"):
			var point: Vector3 = cabin.to_local(global_position)
			if absf(point.x) < 2.7 and absf(point.z) < 2.7 and point.y > -0.8 and point.y < 3.9:
				_cargo_candidate = cabin
				break
	if not is_instance_valid(_cargo_candidate):
		return
	var local := _cargo_candidate.to_local(global_position)
	if absf(local.x) >= 2.7 or absf(local.z) >= 2.7 or local.y > 4.0:
		_cargo_candidate = null
		return
	if local.y > 1.0:
		return
	var support := 0.03
	for node in find_children("*", "CollisionShape3D", true, false):
		var shape := node as CollisionShape3D
		if shape.disabled or shape.shape == null:
			continue
		var pose := _cargo_candidate.global_transform.affine_inverse() * shape.global_transform
		var bounds: AABB = pose * shape.shape.get_debug_mesh().get_aabb()
		support = maxf(support, local.y - bounds.position.y)
	# Cabin floor is at +0.05. Catch only items reaching its surface; items
	# above it still fall normally. A remembered candidate recovers tunnelling.
	if local.y > support + 0.12:
		return
	_cargo_cabin = _cargo_candidate
	_cargo_pose = _cargo_cabin.global_transform.affine_inverse() * global_transform
	_cargo_pose.origin.y = support + 0.06
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	freeze = true
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	global_transform = _cargo_cabin.global_transform * _cargo_pose
	sync_physics_state()


func release_elevator_cargo() -> void:
	if not multiplayer.is_server() or not is_instance_valid(_cargo_cabin):
		return
	_cargo_candidate = _cargo_cabin
	_cargo_cabin = null
	_cargo_cooldown = 0.4
	freeze = false
	sleeping = false
	sync_physics_state()


func get_interaction_prompt() -> String:
	if not pickup_enabled: return ""
	match item_type:
		&"flashlight":
			return "Фонарик · %d%%" % roundi(
				float(item_state.get("battery_charge", 1.0)) * 100.0
			)
		&"battery":
			return "Батарейка ( %d%%)" % roundi(
				float(item_state.get("charge_amount", 0.5)) * 100.0
			)
		&"fuse":
			return "Предохранитель"
		&"fuel_can":
			return "Канистра · %.1f / 20 л" % float(item_state.get("fuel_liters", 20.0))
	return "%s" % display_name


func interact(interactor: Node) -> void:
	network_interact(multiplayer.get_unique_id(), interactor)


func network_interact(peer_id: int, interactor: Node) -> void:
	if (
		not multiplayer.is_server()
		or _collected
		or not pickup_enabled
		or drag_owner_peer != 0
		or not interactor.has_method("pickup_world_item_authoritative")
		or int(interactor.get("owner_peer_id")) != peer_id
		or not interactor is Node3D
		or global_position.distance_to((interactor as Node3D).global_position) > interaction_distance
	):
		return

	var offered := item_state.duplicate(true)
	var remaining := 0
	if item_type == &"pistol_ammo":
		var available := maxi(0, 240 - int(interactor.weapon.pistol_ammo))
		var amount := int(item_state.get("amount", 12))
		offered["amount"] = mini(amount, available)
		remaining = amount - int(offered.amount)
	var accepted := bool(interactor.call(
		"pickup_world_item_authoritative",
		item_type,
		offered
	))
	if not accepted:
		return
	interactor.player_audio.play_cue.rpc(&"pickup")
	if remaining > 0:
		_receive_item_state.rpc({"amount": remaining})
		return
	_collected = true
	freeze = true
	collision_layer = 0
	collision_mask = 0
	queue_free()


@rpc("authority", "call_local", "reliable")
func _receive_item_state(next_state: Dictionary) -> void:
	item_state = next_state.duplicate(true)


@rpc("authority", "call_remote", "unreliable_ordered", 2)
func _receive_physics_state(
	next_transform: Transform3D,
	next_linear_velocity: Vector3,
	next_angular_velocity: Vector3,
	cargo_path: NodePath = NodePath(),
	cargo_pose: Transform3D = Transform3D.IDENTITY
) -> void:
	if multiplayer.is_server():
		return
	_cargo_cabin = get_node_or_null(cargo_path) as Node3D if not cargo_path.is_empty() else null
	_cargo_pose = cargo_pose
	global_transform = _cargo_cabin.global_transform * _cargo_pose if is_instance_valid(_cargo_cabin) else next_transform
	linear_velocity = next_linear_velocity
	angular_velocity = next_angular_velocity
