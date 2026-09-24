class_name BaseAutoDoorManager
extends Node

const OPEN_DISTANCE := 3.2
const CLOSE_DISTANCE := 4.4
const UPDATE_INTERVAL := 0.08
const DOOR_MOVE_TIME := 0.7

var _controller: BaseGameplayController
var _doors: Array[Dictionary] = []
var _legacy_blockers: Array[CollisionShape3D] = []
var _update_left := 0.0
var _nearby_players: Array[Node] = []


func _ready() -> void:
	add_to_group("base_auto_door_managers")
	call_deferred("_setup_doors")


func _process(delta: float) -> void:
	_update_left -= delta
	if _update_left > 0.0:
		return
	_update_left = UPDATE_INTERVAL
	_nearby_players = get_tree().get_nodes_in_group("network_players")
	for legacy_blocker in _legacy_blockers:
		if is_instance_valid(legacy_blocker) and not legacy_blocker.disabled:
			legacy_blocker.set_deferred("disabled", true)
	var powered := _controller != null and _controller.main_breaker_on
	var expired: Array[String] = []
	for door in _doors:
		var should_open: bool = false
		if not bool(door.locked):
			should_open = (
				(not powered and bool(door.startup_route))
				or (
					powered
					and _has_player_near(
						door.anchor,
						CLOSE_DISTANCE if bool(door.open) else OPEN_DISTANCE
					)
				)
			)
			# Emergency egress from the bunks must survive the morning outage.
			if not powered and _controller != null and _controller.day_index >= 2 and bool(door.emergency_egress):
				should_open = true
			if is_door_pried(door):
				should_open = bool(_controller.maintenance.get("manual_doors", {}).get(str(get_parent().get_path_to(door.anchor)), true))
		var overrides: Dictionary = _controller.maintenance.get("debug_doors", {}) if _controller != null else {}
		var id := str(get_parent().get_path_to(door.anchor))
		if overrides.has(id):
			var command = overrides[id]
			# Old saves contained permanent bool overrides. Retire those too.
			if command is Dictionary and bool(command.get("powered", not powered)) == powered and bool(command.get("near", false)) == _has_player_near(door.anchor, CLOSE_DISTANCE):
				should_open = bool(command.get("open", false))
			else:
				expired.append(id)
		_apply_door_state(door, should_open)
	if not expired.is_empty() and multiplayer.is_server():
		var snapshot := _controller.get_snapshot()
		var overrides: Dictionary = snapshot.maintenance.get("debug_doors", {})
		for id in expired:
			overrides.erase(id)
		snapshot.maintenance["debug_doors"] = overrides
		_controller._broadcast_snapshot(snapshot)


func debug_set_door_open(anchor: Node, opened: bool) -> bool:
	if not multiplayer.is_server() or _controller == null:
		return false
	for door in _doors:
		if door.anchor == anchor:
			var snapshot := _controller.get_snapshot()
			var overrides: Dictionary = snapshot.maintenance.get("debug_doors", {})
			_nearby_players = get_tree().get_nodes_in_group("network_players")
			overrides[str(get_parent().get_path_to(anchor))] = {"open": opened, "powered": _controller.main_breaker_on, "near": _has_player_near(door.anchor, CLOSE_DISTANCE)}
			snapshot.maintenance["debug_doors"] = overrides
			_controller._broadcast_snapshot(snapshot)
			return true
	return false


func is_door_pried(door: Dictionary) -> bool:
	return _controller != null and str(get_parent().get_path_to(door.anchor)) in _controller.maintenance.get("pried_doors", [])


func set_pried_door_open(door: Dictionary, opened: bool) -> void:
	if not multiplayer.is_server() or not is_door_pried(door) or bool(door.locked):
		return
	var snapshot := _controller.get_snapshot()
	var id := str(get_parent().get_path_to(door.anchor))
	var states: Dictionary = snapshot.maintenance.get("manual_doors", {})
	states[id] = opened
	snapshot.maintenance["manual_doors"] = states
	var overrides: Dictionary = snapshot.maintenance.get("debug_doors", {})
	overrides.erase(id)
	snapshot.maintenance["debug_doors"] = overrides
	_controller._broadcast_snapshot(snapshot)


func _setup_doors() -> void:
	_controller = get_tree().get_first_node_in_group(
		"base_gameplay_controller"
	) as BaseGameplayController
	var doors_root := get_parent()
	var old_blockers := doors_root.get_node_or_null("Day1_Door_Collisions")
	if old_blockers != null:
		# Every authored door is now controlled directly by its scene root.
		old_blockers.process_mode = Node.PROCESS_MODE_DISABLED
		for shape in old_blockers.find_children("*", "CollisionShape3D", true, false):
			var legacy_blocker := shape as CollisionShape3D
			_legacy_blockers.append(legacy_blocker)
			legacy_blocker.set_deferred("disabled", true)

	for candidate in doors_root.get_children():
		if not candidate is Node3D:
			continue
		var visual := candidate as Node3D
		if "/art/doors/" not in str(visual.scene_file_path).to_lower():
			continue
		visual.visible = true
		var open_nodes: Array[Node] = []
		var closed_nodes: Array[Node] = []
		_collect_state_nodes(visual, open_nodes, closed_nodes)
		if open_nodes.is_empty() or closed_nodes.is_empty():
			push_warning("Authored door has no open/closed states: %s" % visual.get_path())
			continue
		var lowered_name := str(visual.name).to_lower()
		var vehicle_gate := "vehicle" in lowered_name or "gate" in lowered_name
		var blocker := _create_passage_blocker(visual, vehicle_gate)
		if visual.find_child("Leaf", true, false) != null:
			(blocker.shape as BoxShape3D).size = Vector3(1.12, 2.7, 0.24)
			blocker.position.y = 1.35
		if visual.has_meta("passage_size"):
			var passage: Vector3 = visual.get_meta("passage_size")
			(blocker.shape as BoxShape3D).size = passage
			blocker.position.y = passage.y * 0.5
		var indicators := _collect_indicators(visual)
		var startup_route := (
			lowered_name.begins_with("west_")
			or lowered_name.begins_with("technical_")
		)
		startup_route = bool(visual.get_meta("unpowered_open", startup_route))
		var locked := vehicle_gate
		var emergency_egress := (
			visual.name == &"living_hermetic_door"
			or visual.name == &"Standard_Door_Visual_Prototype"
			or visual.name == &"Standard_Door_Frosted_Visual_Prototype"
		)
		var initial_open := startup_route and not locked
		_attach_center_seals(closed_nodes)
		var leaf_pairs := _collect_leaf_pairs(visual, open_nodes, closed_nodes)
		var vertical_state := _collect_vertical_state(open_nodes, closed_nodes)
		var door := {
			"anchor": visual,
			"visual": visual,
			"open_nodes": open_nodes,
			"closed_nodes": closed_nodes,
			"blocker": blocker,
			"indicators": indicators,
			"startup_route": startup_route,
			"locked": locked,
			"emergency_egress": emergency_egress,
			"leaf_pairs": leaf_pairs,
			"vertical_state": vertical_state,
			"tween": null,
			"open": not initial_open,
		}
		_doors.append(door)
		blocker.get_parent().set("manager", self)
		blocker.get_parent().set("door", door)
		var interaction := Area3D.new()
		interaction.name = "ManualInteraction"
		interaction.collision_layer = 4
		interaction.collision_mask = 0
		interaction.set_script(preload("res://scripts/gameplay/base/pry_door_interaction.gd"))
		blocker.get_parent().add_child(interaction)
		interaction.set("manager", self)
		interaction.set("door", door)
		var interaction_shape := CollisionShape3D.new()
		interaction_shape.shape = blocker.shape
		interaction_shape.transform = blocker.transform
		interaction.add_child(interaction_shape)
		_apply_door_state(door, initial_open, true)


func get_door_count() -> int:
	return _doors.size()


func get_open_door_count() -> int:
	var count := 0
	for door in _doors:
		if bool(door.open):
			count += 1
	return count


func is_door_open_at(anchor: Node3D) -> bool:
	for door in _doors:
		if door.anchor == anchor:
			return bool(door.open)
	return false


func get_door_indicator_color_at(anchor: Node3D) -> Color:
	for door in _doors:
		if door.anchor != anchor or (door.indicators as Array).is_empty():
			continue
		var indicator := door.indicators[0] as MeshInstance3D
		var material := indicator.material_override as StandardMaterial3D
		return material.emission if material != null else Color.TRANSPARENT
	return Color.TRANSPARENT


func get_door_leaf_aperture_at(anchor: Node3D) -> float:
	for door in _doors:
		if door.anchor != anchor or (door.leaf_pairs as Array).size() < 2:
			continue
		var left := door.leaf_pairs[0].leaf as Node3D
		var right := door.leaf_pairs[1].leaf as Node3D
		return absf(right.position.x - left.position.x)
	return 0.0


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


func _collect_leaf_pairs(
	visual: Node3D,
	open_nodes: Array[Node],
	closed_nodes: Array[Node]
) -> Array[Dictionary]:
	var pairs: Array[Dictionary] = []
	for index in mini(open_nodes.size(), closed_nodes.size()):
		var open_state := open_nodes[index]
		var closed_state := closed_nodes[index]
		for leaf_name in [&"LeftLeaf", &"RightLeaf", &"Leaf"]:
			var closed_leaf := closed_state.find_child(str(leaf_name), true, false) as Node3D
			var open_leaf := open_state.find_child(str(leaf_name), true, false) as Node3D
			if closed_leaf == null:
				continue
			var open_position := Vector3.ZERO
			var socket := visual.find_child("%sOpenSocket" % leaf_name, true, false) as Marker3D
			if socket != null:
				open_position = closed_leaf.get_parent().to_local(socket.global_position)
			elif open_leaf != null:
				open_position = open_leaf.position
			else:
				continue
			pairs.append({
				"leaf": closed_leaf,
				"closed_position": closed_leaf.position,
				"open_position": open_position,
			})
	return pairs


func _attach_center_seals(closed_nodes: Array[Node]) -> void:
	for closed_state in closed_nodes:
		var right_leaf := closed_state.find_child("RightLeaf", true, false) as Node3D
		if right_leaf == null:
			continue
		for seal_name in [&"CenterOverlapSeal", &"BackCenterOverlapSeal"]:
			var seal := closed_state.find_child(str(seal_name), true, false) as Node3D
			if seal != null and seal.get_parent() != right_leaf:
				seal.reparent(right_leaf, true)


func _collect_vertical_state(open_nodes: Array[Node], closed_nodes: Array[Node]) -> Dictionary:
	if open_nodes.is_empty() or closed_nodes.is_empty():
		return {}
	if (closed_nodes[0] as Node).find_child("Panel01", true, false) == null:
		return {}
	var closed_state := closed_nodes[0] as Node3D
	return {
		"node": closed_state,
		"closed_position": closed_state.position,
		"open_position": closed_state.position + Vector3.UP * 3.6,
	}


func _create_passage_blocker(anchor: Node3D, vehicle_gate: bool) -> CollisionShape3D:
	var body := StaticBody3D.new()
	body.set_script(preload("res://scripts/gameplay/base/pry_door_interaction.gd"))
	body.name = "%s_Blocker" % anchor.name
	get_parent().add_child(body)
	body.global_transform = Transform3D(
		Basis.from_euler(Vector3(0.0, anchor.global_rotation.y, 0.0)),
		anchor.global_position
	)
	var shape := CollisionShape3D.new()
	shape.name = "CollisionShape3D"
	var box := BoxShape3D.new()
	box.size = Vector3(5.5, 3.6, 0.24) if vehicle_gate else Vector3(2.35, 2.75, 0.24)
	shape.shape = box
	shape.position.y = 1.8 if vehicle_gate else 1.38
	body.add_child(shape)
	return shape


func _has_player_near(anchor: Node3D, distance: float) -> bool:
	for player in _nearby_players:
		if not player is Node3D or not is_instance_valid(player):
			continue
		if player.get("survival") != null and bool(player.survival.dead):
			continue
		var offset: Vector3 = (player as Node3D).global_position - anchor.global_position
		if absf(offset.y) > 3.5:
			continue
		offset.y = 0.0
		if offset.length_squared() <= distance * distance:
			return true
	return false


func _apply_door_state(door: Dictionary, is_open: bool, instant: bool = false) -> void:
	if bool(door.open) == is_open:
		return
	door.open = is_open
	var old_tween := door.tween as Tween
	if old_tween != null and old_tween.is_valid():
		old_tween.kill()
	for node in door.closed_nodes:
		(node as Node3D).visible = true
	for node in door.open_nodes:
		(node as Node3D).visible = false
	var indicator_color := Color(0.06, 1.0, 0.18) if is_open else Color(1.0, 0.035, 0.015)
	if instant:
		_set_motion_position(door, is_open)
		_finish_door_motion(door, is_open)
		_apply_indicator_color(door, indicator_color)
		return
	var tween := create_tween().set_parallel(true)
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	door.tween = tween
	for pair in door.leaf_pairs:
		tween.tween_property(
			pair.leaf,
			"position",
			pair.open_position if is_open else pair.closed_position,
			DOOR_MOVE_TIME
		)
	if not (door.vertical_state as Dictionary).is_empty():
		var vertical := door.vertical_state as Dictionary
		tween.tween_property(
			vertical.node,
			"position",
			vertical.open_position if is_open else vertical.closed_position,
			DOOR_MOVE_TIME
		)
	for mesh in door.indicators:
		var material := (mesh as MeshInstance3D).material_override as StandardMaterial3D
		material.emission_enabled = true
		material.emission_energy_multiplier = 4.5
		tween.tween_property(material, "albedo_color", indicator_color.darkened(0.45), DOOR_MOVE_TIME * 0.65)
		tween.tween_property(material, "emission", indicator_color, DOOR_MOVE_TIME * 0.65)
	if is_open:
		(door.blocker as CollisionShape3D).set_deferred("disabled", true)
	tween.chain().tween_callback(_finish_door_motion.bind(door, is_open))


func _set_motion_position(door: Dictionary, is_open: bool) -> void:
	for pair in door.leaf_pairs:
		(pair.leaf as Node3D).position = pair.open_position if is_open else pair.closed_position
	if not (door.vertical_state as Dictionary).is_empty():
		var vertical := door.vertical_state as Dictionary
		(vertical.node as Node3D).position = vertical.open_position if is_open else vertical.closed_position


func _finish_door_motion(door: Dictionary, is_open: bool) -> void:
	if bool(door.open) != is_open:
		return
	# Keep one authored set alive throughout the whole motion. Swapping the
	# Open/Closed preview copies caused a visible jump on inherited living doors.
	for node in door.open_nodes:
		(node as Node3D).visible = false
	for node in door.closed_nodes:
		(node as Node3D).visible = true
	(door.blocker as CollisionShape3D).set_deferred("disabled", is_open)


func _apply_indicator_color(door: Dictionary, color: Color) -> void:
	for mesh in door.indicators:
		var material := (mesh as MeshInstance3D).material_override as StandardMaterial3D
		material.albedo_color = color.darkened(0.45)
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = 4.5
