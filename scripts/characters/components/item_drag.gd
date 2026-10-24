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
var heavy_body: HeavyCarryProp
var _gesture := 0
var _server_gesture := -1
var _server_released := false

func is_heavy_carrying() -> bool:
	return is_instance_valid(heavy_body)

func begin_interaction() -> bool:
	if player.is_driving() or player.is_carrying_corpse():
		return false
	var target := player.get_interaction_target()
	while target != null and not target is WorldItemPickup:
		target = target.get_parent()
	if target == null or (not target.draggable and not target is HeavyCarryProp):
		return false
	pending = target.get_path()
	_gesture += 1
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
					_request_pickup.rpc_id(1, pending, _gesture)
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
					_request_hold.rpc_id(1, pending, _gesture, Vector2(player.rotation.y, player.head.rotation.x))
	if multiplayer.is_server() and is_instance_valid(body):
		if body is HeavyCarryProp: return
		if Time.get_ticks_msec() - last_hold > 400 or player.survival.dead or player.is_driving() or player.is_carrying_corpse() or player.is_sleeping_in_bunk() or body._collected or body.global_position.distance_to(player.head.global_position) > 4.5:
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
		_request_release.rpc_id(1, _gesture)

func _valid_item(path: NodePath) -> WorldItemPickup:
	if path.is_empty() or player.survival.dead or player.is_driving() or player.is_carrying_corpse() or player.is_sleeping_in_bunk():
		return null
	var item := get_node_or_null(path) as WorldItemPickup
	if is_heavy_carrying() and not item is HeavyCarryProp: return null
	if item == null or item._collected or (not item is HeavyCarryProp and item.drag_owner_peer not in [0, player.owner_peer_id]) or item.global_position.distance_to(player.head.global_position) > item.drag_distance:
		return null
	# Bottom pivots may sit microscopically inside a supporting floor/table.
	# Test the authored interior anchor, keeping real world occlusion intact.
	var ray := PhysicsRayQueryParameters3D.create(player.head.global_position, item.get_interaction_position(), 1, [player.get_rid(), item.get_rid()])
	if not player.debug_across and not player.get_world_3d().direct_space_state.intersect_ray(ray).is_empty():
		return null
	return item

func _hold(path: NodePath) -> void:
	var item := _valid_item(path)
	if item is HeavyCarryProp:
		if body != item: _release()
		if item.acquire_grip(player): body = item
		else: _release()
		return
	if item == null or not item.draggable:
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
		if body is HeavyCarryProp: body.release_grip(player.owner_peer_id)
		else:
			body.drag_owner_peer = 0
			body.linear_velocity = body.linear_velocity.limit_length(3.0)
			body.sync_physics_state()
	body = null

func _exit_tree() -> void:
	if is_instance_valid(body):
		if body is HeavyCarryProp: body.release_grip(player.owner_peer_id)
		else: body.drag_owner_peer = 0

@rpc("any_peer", "call_remote", "reliable", 2)
func _request_hold(path: NodePath, gesture := 0, aim := Vector2(INF, INF)) -> void:
	if multiplayer.is_server() and multiplayer.get_remote_sender_id() == player.owner_peer_id:
		if aim.is_finite() and absf(aim.y) > deg_to_rad(85.1): return
		if not _accept_gesture(gesture): return
		if aim.is_finite():
			player._server_yaw = wrapf(aim.x, -PI, PI)
			player._server_pitch = aim.y
			player.rotation.y = player._server_yaw
			player.head.rotation.x = player._server_pitch
		_hold(path)

@rpc("any_peer", "call_remote", "reliable", 2)
func _request_pickup(path: NodePath, gesture := 0) -> void:
	if multiplayer.is_server() and multiplayer.get_remote_sender_id() == player.owner_peer_id:
		if _accept_gesture(gesture): _pickup(path)

@rpc("any_peer", "call_remote", "reliable", 2)
func _request_release(gesture := 0) -> void:
	if multiplayer.is_server() and multiplayer.get_remote_sender_id() == player.owner_peer_id:
		if gesture < _server_gesture: return
		_server_gesture = gesture
		_server_released = true
		_release()

func _accept_gesture(gesture: int) -> bool:
	if gesture < _server_gesture or (gesture == _server_gesture and _server_released): return false
	if gesture > _server_gesture:
		_release()
		_server_gesture = gesture
		_server_released = false
	return true
