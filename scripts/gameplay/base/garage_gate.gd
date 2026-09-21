extends Node3D

## Required cooperative hold time; the lift duration is authored in AnimationPlayer.
@export_range(0.1, 30.0, 0.1) var opening_seconds := 4.0
var progress := 0.0
var _holds: Dictionary = {}
var _tick := 0.0
var _state: BaseGameplayController
var _target_open := false
var _received_progress := false
@onready var handles: Array[Node3D] = [%Handle0, %Handle1]
@onready var animation: AnimationPlayer = $AnimationPlayer

func _ready() -> void:
	animation.animation_finished.connect(func(_name): _refresh_status())
	_bind.call_deferred()

func _bind() -> void:
	_state = get_tree().get_first_node_in_group("base_gameplay_controller")
	if _state != null:
		_state.snapshot_changed.connect(_on_snapshot)
		_on_snapshot({})
	_apply_pose(true)

func _on_snapshot(_snapshot: Dictionary) -> void:
	if _state.maintenance.has("garage_debug_open"):
		progress = 1.0 if _state.maintenance.garage_debug_open else 0.0
		_apply_pose()
	elif _state.maintenance.get("garage_open", false):
		progress = 1.0
		_apply_pose()

func debug_set_open(opened: bool) -> void:
	if not multiplayer.is_server() or _state == null:
		return
	_holds.clear()
	var snapshot := _state.get_snapshot()
	snapshot.maintenance["garage_open"] = opened
	snapshot.maintenance["garage_debug_open"] = opened
	_state._broadcast_snapshot(snapshot)

func _physics_process(delta: float) -> void:
	_tick += delta
	if _tick < 0.1:
		return
	var elapsed := _tick
	_tick = 0
	var local := get_tree().get_first_node_in_group("local_player")
	if local != null and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and Input.is_action_pressed("interact"):
		local.interaction_ray.force_raycast_update()
		var target: Object = local.interaction_ray.get_collider()
		for index in 2:
			if target == handles[index]:
				if multiplayer.is_server():
					_hold(local.owner_peer_id, index)
				else:
					_request_hold.rpc_id(1, index)
	if multiplayer.is_server():
		var now := Time.get_ticks_msec()
		var operators: Array[int] = []
		for index in 2:
			var entry: Dictionary = _holds.get(index, {})
			if entry.is_empty() or now - int(entry.time) > 350 or not _valid_operator(int(entry.peer), index):
				continue
			if not operators.has(int(entry.peer)):
				operators.append(int(entry.peer))
		if operators.size() == 2 and progress < 1:
			progress = minf(1, progress + elapsed / opening_seconds)
			if progress >= 1 and _state != null:
				var snapshot := _state.get_snapshot()
				snapshot.maintenance.erase("garage_debug_open")
				snapshot.maintenance["garage_open"] = true
				_state._broadcast_snapshot(snapshot)
		_apply_pose()
		var world := get_tree().get_first_node_in_group("network_gameplay_controller")
		if world != null and world.has_method("get_ready_v3_peers"):
			for peer in world.get_ready_v3_peers():
				_receive_progress.rpc_id(peer, progress)

func _valid_operator(peer: int, index: int) -> bool:
	if _state == null or index not in [0, 1]:
		return false
	var player := _state.get_player_node(peer) as Node3D
	if player == null or player.survival.dead or player.is_sleeping_in_bunk() or player.is_driving():
		return false
	var handle := handles[index]
	if player.global_position.distance_to(handle.global_position) > 2.5:
		return false
	var ray := PhysicsRayQueryParameters3D.create(player.head.global_position, handle.global_position, 1, [player.get_rid()])
	return get_world_3d().direct_space_state.intersect_ray(ray).is_empty()

func _hold(peer: int, index: int) -> void:
	if multiplayer.is_server() and _valid_operator(peer, index):
		_holds[index] = {"peer": peer, "time": Time.get_ticks_msec()}

@rpc("any_peer", "call_remote", "unreliable_ordered")
func _request_hold(index: int) -> void:
	_hold(multiplayer.get_remote_sender_id(), index)

@rpc("authority", "call_remote", "unreliable_ordered", 3)
func _receive_progress(value: float) -> void:
	progress = clampf(value, 0, 1)
	_apply_pose(not _received_progress)
	_received_progress = true

func _apply_pose(instant: bool = false) -> void:
	var opened := progress >= 1.0
	if instant or opened != _target_open:
		var time := animation.current_animation_position if animation.is_playing() else (animation.get_animation("open").length if _target_open else 0.0)
		_target_open = opened
		animation.play("open", -1, 1.0 if opened else -1.0, not opened)
		animation.seek((animation.current_animation_length if opened else 0.0) if instant else time, true)
		if instant:
			animation.pause()
	_refresh_status()

func _refresh_status() -> void:
	if animation.is_playing():
		$Status.text = "ВОРОТА ОТКРЫВАЮТСЯ" if _target_open else "ВОРОТА ЗАКРЫВАЮТСЯ"
	else:
		$Status.text = "ГАРАЖ ОТКРЫТ" if _target_open else "ДВОЕ · УДЕРЖИВАЙТЕ E · %d%%" % roundi(progress * 100)
