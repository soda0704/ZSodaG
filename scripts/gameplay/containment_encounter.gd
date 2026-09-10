extends Node3D

const START_HEALTH := [120.0, 90.0, 75.0]
var state: Node
var navigation_ready: bool = false
var region: NavigationRegion3D
var _tick: float = 0.0

func _ready() -> void:
	add_to_group("containment_encounter")
	state = get_parent().get_node("BaseGameplayController")
	state.snapshot_changed.connect(_on_state)
	var level := get_parent().get_node("Floor_Minus3_Biocontainment_Blockout") as Node3D
	for index in 3:
		var monster := preload("res://scripts/gameplay/hostile_monster.gd").new()
		monster.name = "Monster%d" % index
		monster.monster_id = index
		monster.model_id = ["the_monster", "slasher", "smily"][index]
		monster.encounter = self
		add_child(monster)
		monster.global_position = level.to_global([Vector3(-29.5, 0.1, -7.5), Vector3(-33, 0.1, -18), Vector3(-20, 0.1, -24)][index])
		monster._home = monster.global_position
		monster._target_position = monster.position
	if multiplayer.is_server():
		_bake.call_deferred(level)
	_on_state({})

func _bake(level: Node3D) -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	level.add_to_group("containment_navigation_source")
	region = NavigationRegion3D.new()
	add_child(region)
	var mesh := NavigationMesh.new()
	mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	mesh.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_GROUPS_WITH_CHILDREN
	mesh.geometry_source_group_name = &"containment_navigation_source"
	mesh.agent_radius = 0.5
	mesh.agent_height = 2.0
	mesh.agent_max_climb = 0.25
	mesh.cell_size = 0.25
	mesh.cell_height = 0.25
	region.navigation_mesh = mesh
	region.bake_finished.connect(func(): navigation_ready = mesh.get_polygon_count() > 0)
	region.bake_navigation_mesh(true)

func _physics_process(delta: float) -> void:
	if not multiplayer.is_server() or state.day_index != 3:
		return
	_tick += delta
	if _tick < 0.25:
		return
	_tick = 0.0
	var data: Dictionary = state.containment.duplicate(true)
	var changed := false
	for peer in state.get_connected_player_peer_ids():
		var player: Node3D = state.get_player_node(peer)
		if player == null or player.survival.dead:
			continue
		var point: Vector3 = get_parent().to_local(player.global_position)
		if absf(point.y + 36.0) < 2.0 and point.x < -7.0 and not data.get("level2", false):
			data.level2 = true
			changed = true
		if absf(point.y + 54.0) < 3.0 and point.x < -3.0 and data.get("level2", false) and not data.get("level3", false):
			data.level3 = true
			changed = true
	if changed:
		_commit(data)

func closest_player(point: Vector3) -> Node3D:
	if state.day_index < 3:
		return null
	var best: Node3D
	var distance := 28.0
	for peer in state.get_connected_player_peer_ids():
		var player: Node3D = state.get_player_node(peer)
		if player == null or player.survival.dead or player.is_sleeping_in_bunk() or absf(player.global_position.y - point.y) > 3.5:
			continue
		var candidate := point.distance_to(player.global_position)
		if candidate < distance:
			distance = candidate
			best = player
	return best

func get_monster_health(index: int) -> float:
	return float(state.containment.get("health", START_HEALTH)[index])

func damage_monster(index: int, amount: float) -> void:
	if not multiplayer.is_server() or state.day_index < 3 or amount <= 0.0:
		return
	var data: Dictionary = state.containment.duplicate(true)
	var health: Array = data.get("health", START_HEALTH).duplicate()
	if health[index] <= 0.0:
		return
	health[index] = maxf(0.0, float(health[index]) - amount)
	data.health = health
	if health[index] == 0.0:
		var bodies: Dictionary = data.get("bodies", {}).duplicate(true)
		bodies[str(index)] = {"transform": get_node("Monster%d" % index).global_transform, "settled": false}
		data.bodies = bodies
	if health.all(func(hp): return hp <= 0.0) and not data.get("resolved", false):
		data.fault = true
		data.reset_armed = false
	_commit(data)

func cycle_breaker(peer: int) -> bool:
	if not multiplayer.is_server() or not state._can_mutate_for_peer(peer) or not state.containment.get("fault", false):
		return false
	var data: Dictionary = state.containment.duplicate(true)
	var snapshot: Dictionary = state.get_snapshot()
	if state.main_breaker_on:
		data.reset_armed = true
		snapshot.main_breaker_on = false
	else:
		if not data.get("reset_armed", false):
			snapshot.main_breaker_on = true
		else:
			data.fault = false
			data.resolved = true
		snapshot.main_breaker_on = true
	snapshot.containment = data
	state._broadcast_snapshot(snapshot)
	return true

func _commit(data: Dictionary) -> void:
	var snapshot: Dictionary = state.get_snapshot()
	snapshot.containment = data
	state._broadcast_snapshot(snapshot)

func save_body(index: int, pose: Transform3D, settled: bool) -> void:
	var data: Dictionary = state.containment.duplicate(true)
	var bodies: Dictionary = data.get("bodies", {}).duplicate(true)
	bodies[str(index)] = {"transform": pose, "settled": settled}
	data.bodies = bodies
	_commit(data)

func capture_bodies() -> Dictionary:
	var bodies := {}
	for index in 3:
		var monster = get_node_or_null("Monster%d" % index)
		if monster == null:
			continue
		if not monster._restored:
			if state.containment.get("bodies", {}).has(str(index)):
				bodies[str(index)] = state.containment.bodies[str(index)].duplicate(true)
			continue
		bodies[str(index)] = {"transform": monster.corpse.global_transform if monster.corpse != null else monster.global_transform, "settled": monster._corpse_saved}
	return bodies

func debug_reset() -> void:
	if not multiplayer.is_server():
		return
	var data: Dictionary = state.containment.duplicate(true)
	data.health = START_HEALTH.duplicate()
	data.bodies = {}
	data.fault = false
	data.resolved = false
	data.reset_armed = false
	_commit(data)
	_reset_actors.rpc()
	state.save_progress_authoritative()

@rpc("authority", "call_local", "reliable")
func _reset_actors() -> void:
	for index in 3:
		get_node("Monster%d" % index).reset_enemy()

func _on_state(_snapshot: Dictionary) -> void:
	if multiplayer.is_server() and state.day_index == 3 and state.containment.get("level2", false):
		get_parent().get_node("Elevator_Functional_Blockout").set_day(4)
