extends Node

@export_range(0.0,0.4) var death_transition_seconds := 0.14
@export_range(5.0,30.0) var pose_send_rate := 12.0
@export_range(1.0,30.0) var remote_pose_smoothing := 16.0
@onready var player: GamePlayer = get_parent()
var ragdoll: SkeletalRagdoll
var original_pose: Transform3D
var sync_time := 0.0
var elapsed := 0.0
var _transitioning := false
var _remote_poses: Array = []

func _physics_process(delta: float) -> void:
	if player.survival == null: return
	if not player.survival.dead:
		if ragdoll != null or _transitioning: stop()
		return
	if ragdoll == null and not _transitioning:
		_transitioning = true
		elapsed = 0
		player.body_animator.begin_death()
	elapsed += delta
	if ragdoll == null:
		player.body_animator.advance_death(delta)
		if elapsed >= death_transition_seconds: start()
		return
	if multiplayer.is_server():
		if elapsed > 5.0 and ragdoll.settled(): ragdoll.freeze_all()
		sync_time += delta
		if sync_time >= 1.0/pose_send_rate:
			sync_time = fmod(sync_time,1.0/pose_send_rate)
			_receive_pose.rpc(ragdoll.capture())
	elif _remote_poses.size()==ragdoll.bodies.size():
		var smooth: Array[Transform3D] = []
		var weight := 1.0-exp(-remote_pose_smoothing*delta)
		for i in _remote_poses.size():
			smooth.append(ragdoll.bodies[i].global_transform.interpolate_with(_remote_poses[i],weight))
			ragdoll.apply_poses(smooth)

func start() -> void:
	if ragdoll != null: return
	original_pose = player.body_animator.transform
	player.body_animator.freeze_for_ragdoll()
	ragdoll = player.body_animator.variant.ragdoll_scene.instantiate()
	ragdoll.name = "DeathPhysics"
	player.add_child(ragdoll)
	player.body_animator.reparent(ragdoll,true)
	ragdoll.initialize(player.body_animator.skeleton,multiplayer.is_server(),player.survival.death_velocity)
	player.collision_shape.set_deferred("disabled",true)
	player.name_label.hide()
	_transitioning = false
	sync_time = 0

func stop() -> void:
	if ragdoll != null:
		ragdoll.clear_pose()
		player.body_animator.reparent(player,false)
		player.body_animator.transform = original_pose
		ragdoll.queue_free()
		ragdoll = null
	player.body_animator.restore_after_respawn()
	player.collision_shape.set_deferred("disabled",not multiplayer.is_server() and not player.is_local_player())
	player.name_label.visible = not player.is_local_player()
	_transitioning = false
	_remote_poses.clear()
	elapsed = 0

@rpc("authority","call_remote","unreliable_ordered",3)
func _receive_pose(poses: Array) -> void:
	if not player.survival.dead: return
	if ragdoll==null:
		if not _transitioning: player.body_animator.begin_death()
		start()
	if poses.size()!=ragdoll.bodies.size(): return
	if _remote_poses.is_empty(): ragdoll.apply_poses(poses)
	_remote_poses = poses.duplicate()
