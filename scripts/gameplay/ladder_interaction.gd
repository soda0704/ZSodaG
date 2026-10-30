extends StaticBody3D
@export var route_path: NodePath
func get_interaction_prompt() -> String:
	var route := get_node_or_null(route_path) as LadderRoute
	return "Лестница занята" if route!=null and route.occupant()!=null else "Подняться / спуститься по лестнице"
func network_interact(peer: int, actor: Node) -> void:
	var p := actor as GamePlayer
	var route := get_node_or_null(route_path) as LadderRoute
	if not multiplayer.is_server() or p == null or p.owner_peer_id != peer or route == null: return
	var state := get_tree().get_first_node_in_group("base_gameplay_controller") as BaseGameplayController
	if state == null or state.get_player_node(peer)!=p or not state.maintenance.get("radio_unlocked",false): return
	if p.global_position.distance_to(global_position)>2.6: return
	p.get_node("LadderClimb").enter(route)
