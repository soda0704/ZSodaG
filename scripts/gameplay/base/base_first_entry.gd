extends Area3D
## Editor-authored coverage; actual base-floor contact reveals the first objective.
@export_node_path("Node") var state_path := NodePath("../BaseGameplayController")
@export_node_path("Node3D") var floor_root_path := NodePath("../Floor_0_Base_Blockout")
@export var foot_probe_radius := .22
@onready var state: BaseGameplayController = get_node(state_path)
@onready var floor_root: Node3D = get_node(floor_root_path)
var _check_left := 0.0

func _physics_process(delta: float) -> void:
	if not multiplayer.is_server(): return
	if state.has_entered_base():
		return
	_check_left -= delta
	if _check_left > 0: return
	_check_left = .08
	for body in get_overlapping_bodies():
		if not body is GamePlayer or body.survival.dead or body.is_sleeping_in_bunk() or not state._can_mutate_for_peer(body.owner_peer_id): continue
		if not _standing_on_base(body): continue
		var snapshot := state.get_snapshot()
		snapshot.maintenance["base_entered"] = true
		state._broadcast_snapshot(snapshot)
		return

func _standing_on_base(body: GamePlayer) -> bool:
	# Probe the feet, including the leading edge of the capsule. A camera/head
	# inside the building or a jump over its threshold does not reveal the task.
	for offset in [Vector3.ZERO, Vector3.LEFT, Vector3.RIGHT, Vector3.FORWARD, Vector3.BACK]:
		var foot: Vector3 = body.global_position + offset * foot_probe_radius
		var query := PhysicsRayQueryParameters3D.create(foot + Vector3.UP * .12, foot + Vector3.DOWN * .12, 1, [body.get_rid()])
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty() and hit.normal.y > .6 and floor_root.is_ancestor_of(hit.collider): return true
	return false
