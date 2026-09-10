class_name BaseAutoDoorManager
extends Node

const OPEN_DISTANCE := 2.8
const UPDATE_INTERVAL := 0.08

var _controller: BaseGameplayController
var _doors: Array[Dictionary] = []
var _legacy_blockers: Array[CollisionShape3D] = []
var _update_left := 0.0


func _ready() -> void:
	call_deferred("_setup_doors")


func _process(delta: float) -> void:
	_update_left -= delta
	if _update_left > 0.0:
		return
	_update_left = UPDATE_INTERVAL
	for legacy_blocker in _legacy_blockers:
		if is_instance_valid(legacy_blocker) and not legacy_blocker.disabled:
			legacy_blocker.set_deferred("disabled", true)
	var powered := _controller != null and _controller.main_breaker_on
	for door in _doors:
		var should_open: bool = bool(door.generator_route) or (
			powered and _has_player_near(door.marker)
		)
		_apply_door_state(door, should_open)


func _setup_doors() -> void:
	_controller = get_tree().get_first_node_in_group(
		"base_gameplay_controller"
	) as BaseGameplayController
	var level := get_parent()
	var old_blockers := level.get_node_or_null("Day1_Door_Collisions")
	if old_blockers != null:
		# Every authored door socket is now controlled by the actual door.
		old_blockers.process_mode = Node.PROCESS_MODE_DISABLED
		for shape in old_blockers.find_children("*", "CollisionShape3D", true, false):
			var legacy_blocker := shape as CollisionShape3D
			_legacy_blockers.append(legacy_blocker)
			legacy_blocker.set_deferred("disabled", true)

	for marker in level.find_children("*", "Marker3D", true, false):
		if marker.name not in [&"Door_Socket", &"Vehicle_Door_Socket"]:
			continue
		var visual := _find_authored_visual(marker)
		if visual == null:
			push_warning("Door socket has no authored door: %s" % marker.get_path())
			continue
		visual.visible = true
		var open_nodes: Array[Node] = []
		var closed_nodes: Array[Node] = []
		_collect_state_nodes(visual, open_nodes, closed_nodes)
		if open_nodes.is_empty() or closed_nodes.is_empty():
			push_warning("Authored door has no open/closed states: %s" % visual.get_path())
			continue
		var blocker := _create_passage_blocker(marker, marker.name == &"Vehicle_Door_Socket")
		var indicators := _collect_indicators(visual)
		var generator_route := "South_Technical/Transitions" in str(marker.get_path())
		var door := {
			"marker": marker,
			"visual": visual,
			"open_nodes": open_nodes,
			"closed_nodes": closed_nodes,
			"blocker": blocker,
			"indicators": indicators,
			"generator_route": generator_route,
			"open": not generator_route,
		}
		_doors.append(door)
		_apply_door_state(door, generator_route)


func get_door_count() -> int:
	return _doors.size()


func get_open_door_count() -> int:
	var count := 0
	for door in _doors:
		if bool(door.open):
			count += 1
	return count


func is_door_open_at(marker: Marker3D) -> bool:
	for door in _doors:
		if door.marker == marker:
			return bool(door.open)
	return false


func get_door_indicator_color_at(marker: Marker3D) -> Color:
	for door in _doors:
		if door.marker != marker or (door.indicators as Array).is_empty():
			continue
		var indicator := door.indicators[0] as MeshInstance3D
		var material := indicator.material_override as StandardMaterial3D
		return material.emission if material != null else Color.TRANSPARENT
	return Color.TRANSPARENT


func _find_authored_visual(marker: Marker3D) -> Node3D:
	for sibling in marker.get_parent().get_children():
		if sibling == marker or not sibling is Node3D:
			continue
		var lowered := str(sibling.name).to_lower()
		var source_path := str(sibling.scene_file_path).to_lower()
		if (
			("door" in lowered or "gate" in lowered)
			and ("visual" in lowered or "/art/doors/" in source_path)
		):
			return sibling as Node3D
	return null


func _collect_state_nodes(
	visual: Node,
	open_nodes: Array[Node],
	closed_nodes: Array[Node]
) -> void:
	for node in visual.find_children("*", "Node3D", true, false):
		if node.name in [&"OpenPreview", &"OpenState"]:
			open_nodes.append(node)
		elif node.name in [&"ClosedPreview", &"ClosedState"]:
			closed_nodes.append(node)


func _collect_indicators(visual: Node3D) -> Array[MeshInstance3D]:
	var indicators: Array[MeshInstance3D] = []
	for candidate in visual.find_children("*", "MeshInstance3D", true, false):
		var mesh := candidate as MeshInstance3D
		var lowered_name := str(mesh.name).to_lower()
		var lowered_path := str(visual.get_path_to(mesh)).to_lower()
		if (
			"indicator" not in lowered_name
			and "lamp" not in lowered_name
			and "status" not in lowered_name
			and "indicator" not in lowered_path
		):
			continue
		var source := mesh.material_override as StandardMaterial3D
		var material := (
			source.duplicate() as StandardMaterial3D
			if source != null
			else StandardMaterial3D.new()
		)
		material.resource_local_to_scene = true
		mesh.material_override = material
		indicators.append(mesh)
	return indicators


func _create_passage_blocker(marker: Marker3D, vehicle_gate: bool) -> CollisionShape3D:
	var body := StaticBody3D.new()
	body.name = "AutomaticDoorBlocker"
	marker.add_child(body)
	var shape := CollisionShape3D.new()
	shape.name = "CollisionShape3D"
	var box := BoxShape3D.new()
	box.size = Vector3(5.5, 3.6, 0.24) if vehicle_gate else Vector3(2.35, 2.75, 0.24)
	shape.shape = box
	shape.position.y = 1.8 if vehicle_gate else 1.38
	body.add_child(shape)
	return shape


func _has_player_near(marker: Marker3D) -> bool:
	for player in get_tree().get_nodes_in_group("network_players"):
		if not player is Node3D or not is_instance_valid(player):
			continue
		if player.get("survival") != null and bool(player.survival.dead):
			continue
		var offset: Vector3 = (player as Node3D).global_position - marker.global_position
		offset.y = 0.0
		if offset.length() <= OPEN_DISTANCE:
			return true
	return false


func _apply_door_state(door: Dictionary, is_open: bool) -> void:
	if bool(door.open) == is_open:
		return
	door.open = is_open
	for node in door.open_nodes:
		(node as Node3D).visible = is_open
	for node in door.closed_nodes:
		(node as Node3D).visible = not is_open
	var indicator_color := Color(0.06, 1.0, 0.18) if is_open else Color(1.0, 0.035, 0.015)
	for mesh in door.indicators:
		var material := (mesh as MeshInstance3D).material_override as StandardMaterial3D
		material.albedo_color = indicator_color.darkened(0.45)
		material.emission_enabled = true
		material.emission = indicator_color
		material.emission_energy_multiplier = 4.5
	(door.blocker as CollisionShape3D).set_deferred("disabled", is_open)
