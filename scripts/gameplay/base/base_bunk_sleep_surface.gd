extends StaticBody3D


func get_interaction_prompt() -> String:
	var bunk := _get_bunk()
	if bunk == null:
		return "Койка недоступна"
	return str(bunk.call("get_sleep_interaction_prompt"))


func network_interact(peer_id: int, interactor: Node) -> void:
	var bunk := _get_bunk()
	if bunk != null:
		bunk.call("network_sleep_interact", peer_id, interactor)


func _get_bunk() -> Node:
	var pivot := get_parent()
	return pivot.get_parent() if pivot != null else null
