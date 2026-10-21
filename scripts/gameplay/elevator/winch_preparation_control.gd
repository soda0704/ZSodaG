class_name WinchPreparationControl
extends StaticBody3D

enum Action { CONSOLE, PIN, BRAKE }
@export var action: Action = Action.CONSOLE
@export var preparation_path: NodePath
@export_range(0.5, 4.0) var interaction_distance := 2.5
@onready var preparation: WinchPreparationController = get_node(preparation_path)
@onready var interaction_point: Marker3D = $InteractionPoint


func can_use(peer_id: int, interactor: Node) -> bool:
	var player := interactor as GamePlayer
	if player == null or preparation.gameplay_state == null or not player.is_inside_tree(): return false
	if player.owner_peer_id != peer_id or preparation.gameplay_state.get_player_node(peer_id) != player: return false
	if player.survival.dead or player.is_sleeping_in_bunk() or player.is_driving() or player.is_carrying_corpse(): return false
	var point := interaction_point.global_position
	if player.camera.global_position.distance_to(point) > interaction_distance: return false
	if global_basis.z.dot(player.camera.global_position - point) <= 0.0: return false
	var ray := PhysicsRayQueryParameters3D.create(player.camera.global_position, point, 5, [player.get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(ray)
	return hit.is_empty() or hit.collider == self


func get_interaction_hint_for(interactor: Node) -> String:
	var player := interactor as GamePlayer
	if player == null or not can_use(player.owner_peer_id, player): return ""
	var prompt := preparation.get_prompt(action)
	return "" if prompt.is_empty() else "%s %s" % [get_node("/root/SteamInput").get_action_hint(&"interact"), prompt]


func network_interact(peer_id: int, interactor: Node) -> void:
	if multiplayer.is_server() and can_use(peer_id, interactor):
		preparation.use_control(self, peer_id, interactor)
