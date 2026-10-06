extends Node

@export var hold_seconds := 0.25
@export var carry_distance := 1.8
@export var pull_speed := 10.0
@onready var player: GamePlayer = get_parent()
var pending := NodePath()
var held_time := 0.0
var heartbeat := 0.0
var dragging := false
var body: WorldItemPickup
var last_hold := 0

func begin_interaction() -> bool:
	if player.is_driving():
		return false
	var target := player.get_interaction_target()
	while target != null and not target is WorldItemPickup:
		target = target.get_parent()
	if target == null:
		return false
	pending = target.get_path()
	held_time = 0
	heartbeat = 0
	dragging = false
	return true

func _physics_process(delta: float) -> void:
	if player.is_local_player() and not pending.is_empty():
		var allowed := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not player.survival.dead and not player.is_driving() and not player.is_sleeping_in_bunk() and not player._is_journal_open()
		if not allowed or not Input.is_action_pressed("interact"):
			if allowed and not dragging:
				if multiplayer.is_server():
					_pickup(pending)
				else:
					_request_pickup.rpc_id(1, pending)
			cancel()
		else:
			held_time += delta
			heartbeat -= delta
			if held_time >= hold_seconds and heartbeat <= 0:
				dragging = true
				heartbeat = 0.1
				if multiplayer.is_server():
					_hold(pending)
				else:
					_request_hold.rpc_id(1, pending)
	if multiplayer.is_server() and is_instance_valid(body):
		if Time.get_ticks_msec() - last_hold > 400 or player.survival.dead or player.is_driving() or player.is_sleeping_in_bunk() or body._collected or body.global_position.distance_to(player.head.global_position) > 4.5:
			_release()
			return
		var origin := player.head.global_position
		var destination := origin - player.head.global_basis.z * carry_distance
		var ray := PhysicsRayQueryParameters3D.create(origin, destination, 1, [player.get_rid(), body.get_rid()])
		var hit := player.get_world_3d().direct_space_state.intersect_ray(ray)
		if not player.debug_across and not hit.is_empty():
			destination = hit.position + hit.normal * 0.25
		body.sleeping = false
		body.linear_velocity = ((destination - body.global_position) * pull_speed).limit_length(8.0)
		body.angular_velocity *= exp(-8.0 * delta)

func cancel() -> void:
	pending = NodePath()
	dragging = false
	if multiplayer.is_server():
		_release()
	else:
		_request_release.rpc_id(1)

func _valid_item(path: NodePath) -> WorldItemPickup:
	if path.is_empty() or player.survival.dead or player.is_driving() or player.is_sleeping_in_bunk():
		return null
	var item := get_node_or_null(path) as WorldItemPickup
	if item == null or item._collected or item.drag_owner_peer not in [0, player.owner_peer_id] or item.global_position.distance_to(player.head.global_position) > 3.5:
		return null
	var ray := PhysicsRayQueryParameters3D.create(player.head.global_position, item.global_position, 1, [player.get_rid(), item.get_rid()])
	if not player.debug_across and not player.get_world_3d().direct_space_state.intersect_ray(ray).is_empty():
		return null
	return item

func _hold(path: NodePath) -> void:
	var item := _valid_item(path)
	if item == null:
		_release()
		return
	if body != item:
		_release()
		body = item
		body.release_elevator_cargo()
		body.drag_owner_peer = player.owner_peer_id
		body.freeze = false
	last_hold = Time.get_ticks_msec()

func _pickup(path: NodePath) -> void:
	var item := _valid_item(path)
	if item != null:
		item.network_interact(player.owner_peer_id, player)

func _release() -> void:
	if is_instance_valid(body):
		body.drag_owner_peer = 0
		body.linear_velocity = body.linear_velocity.limit_length(3.0)
		body.sync_physics_state()
	body = null

func _exit_tree() -> void:
	if is_instance_valid(body):
		body.drag_owner_peer = 0

@rpc("any_peer", "call_remote", "unreliable_ordered", 0)
func _request_hold(path: NodePath) -> void:
	if multiplayer.is_server() and multiplayer.get_remote_sender_id() == player.owner_peer_id:
		_hold(path)

@rpc("any_peer", "call_remote", "reliable")
func _request_pickup(path: NodePath) -> void:
	if multiplayer.is_server() and multiplayer.get_remote_sender_id() == player.owner_peer_id:
		_pickup(path)

@rpc("any_peer", "call_remote", "reliable")
func _request_release() -> void:
	if multiplayer.is_server() and multiplayer.get_remote_sender_id() == player.owner_peer_id:
		_release()
