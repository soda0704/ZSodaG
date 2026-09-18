extends Node

@onready var player: GamePlayer = get_parent()
var ragdoll: SkeletalRagdoll
var original_pose: Transform3D
var sync_time := 0.0
var elapsed := 0.0

func _physics_process(delta: float) -> void:
	if player.survival == null:
		return
	if player.survival.dead:
		if ragdoll == null:
			start()
		elapsed += delta
		if multiplayer.is_server():
			if elapsed > 5.0 and ragdoll.settled():
				ragdoll.freeze_all()
			sync_time += delta
			if sync_time >= 0.1:
				sync_time = 0
				_receive_pose.rpc(ragdoll.capture())
	elif ragdoll != null:
		stop()

func start() -> void:
	original_pose = player.body_animator.transform
	ragdoll = preload("res://scenes/characters/ragdolls/player.tscn").instantiate()
	ragdoll.name = "DeathPhysics"
	player.add_child(ragdoll)
	player.body_animator.reparent(ragdoll, true)
	var rig: Skeleton3D = player.body_animator.find_children("*", "Skeleton3D", true, false)[0]
	for mesh in player.body_animator.find_children("*", "MeshInstance3D", true, false):
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	ragdoll.initialize(rig, multiplayer.is_server(), player.velocity)
	player.collision_shape.set_deferred("disabled", true)
	player.name_label.hide()
	elapsed = 0

func stop() -> void:
	ragdoll.clear_pose()
	player.body_animator.reparent(player, false)
	player.body_animator.transform = original_pose
	for mesh in player.body_animator.find_children("*", "MeshInstance3D", true, false):
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY if player.is_local_player() else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	ragdoll.queue_free()
	ragdoll = null
	player.collision_shape.set_deferred("disabled", not multiplayer.is_server() and not player.is_local_player())
	player.name_label.visible = not player.is_local_player()

@rpc("authority", "call_remote", "unreliable_ordered", 3)
func _receive_pose(poses: Array) -> void:
	if not player.survival.dead:
		return
	if ragdoll == null:
		start()
	ragdoll.apply_poses(poses)
