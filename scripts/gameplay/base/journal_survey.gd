extends Node
## Host records actual floor visits; availability alone reveals no map.
@export var atlas: JournalAtlas
@export_node_path("Node") var state_path := NodePath("../BaseGameplayController")
@onready var state: BaseGameplayController = get_node(state_path)
var _elapsed := 0.0
func _physics_process(delta: float) -> void:
	if not multiplayer.is_server(): return
	_elapsed += delta
	if _elapsed < .3: return
	_elapsed = 0.0
	var visited: Array = state.maintenance.get("journal_visited", []).duplicate()
	var changed := false
	for actor in get_tree().get_nodes_in_group("network_players"):
		if not actor is GamePlayer or actor.survival.dead or actor.is_sleeping_in_bunk(): continue
		var query := PhysicsRayQueryParameters3D.create(actor.global_position + Vector3.UP * .12, actor.global_position + Vector3.DOWN * .35, 1, [actor.get_rid()])
		var hit: Dictionary = actor.get_world_3d().direct_space_state.intersect_ray(query)
		if hit.is_empty() or hit.normal.y < .55: continue
		for i in atlas.floors.size():
			if visited.has(i): continue
			var floor_root := get_parent().get_node_or_null(atlas.floors[i].scene_root)
			if floor_root == null or not floor_root.is_ancestor_of(hit.collider): continue
			visited.append(i)
			changed = true
	if not changed: return
	var snapshot := state.get_snapshot()
	snapshot.maintenance["journal_visited"] = visited
	state._broadcast_snapshot(snapshot)
