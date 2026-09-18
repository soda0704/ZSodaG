extends Node3D

const START_HEALTH := [120.0, 90.0, 75.0]
var state: Node
var navigation_ready: bool = false
var region: NavigationRegion3D
var _tick: float = 0.0
var _spawn_serial := 0

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

func get_ready_peers() -> Array[int]:
	var world := get_tree().get_first_node_in_group("network_gameplay_controller")
	var peers: Array[int] = []
	if world != null and world.has_method("get_ready_v3_peers"):
		peers.assign(world.get_ready_v3_peers())
	return peers

func closest_player(point: Vector3, accepts: Callable = Callable()) -> Node3D:
	var best: Node3D
	var distance := 40.0
	for peer in state.get_connected_player_peer_ids():
		var player_node = state.get_player_node(peer)
		if not player_node is Node3D:
			continue
		var player := player_node as Node3D
		if player == null or player.survival.dead or player.is_sleeping_in_bunk() or absf(player.global_position.y - point.y) > 3.5:
			continue
		var candidate := point.distance_to(player.global_position)
		if candidate < distance and (not accepts.is_valid() or accepts.call(player)):
			distance = candidate
			best = player
	return best

func get_monster_health(index: int) -> float:
	return float(state.containment.get("health", START_HEALTH)[index])

func damage_monster(index: int, amount: float) -> void:
	if not multiplayer.is_server() or amount <= 0.0:
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

func save_body(index: int, pose: Transform3D, settled: bool, ragdoll: Array = []) -> void:
	var data: Dictionary = state.containment.duplicate(true)
	var bodies: Dictionary = data.get("bodies", {}).duplicate(true)
	bodies[str(index)] = {"transform": pose, "settled": settled, "ragdoll": ragdoll}
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
		bodies[str(index)] = {"transform": monster.corpse.global_transform if monster.corpse != null else monster.global_transform, "settled": monster._corpse_saved, "ragdoll": monster.ragdoll.capture() if monster.ragdoll != null else []}
	return bodies

func debug_reset() -> void:
	if not multiplayer.is_server():
		return
	var data: Dictionary = state.containment.duplicate(true)
	data.health = START_HEALTH.duplicate()
	data.bodies = {}
	# Resetting the encounter must not repair an already triggered power fault.
	_commit(data)
	_reset_actors.rpc()
	state.save_progress_authoritative()

func debug_spawn(model_index: int, count: int, center: Vector3, forward: Vector3, at_point: bool = false) -> int:
	if not multiplayer.is_server() or model_index not in range(3) or count <= 0:
		return 0
	var first_serial := _spawn_serial
	_spawn_serial += count
	_spawn_debug_batch.rpc(model_index, count, first_serial, center, forward, at_point)
	return count

@rpc("authority", "call_local", "reliable")
func _spawn_debug_batch(model_index: int, count: int, first_serial: int, center: Vector3, forward: Vector3, at_point: bool = false) -> void:
	_spawn_debug_batch_async(model_index, count, first_serial, center, forward, at_point)

func _spawn_debug_batch_async(model_index: int, count: int, first_serial: int, center: Vector3, forward: Vector3, at_point: bool = false) -> void:
	var side := forward.cross(Vector3.UP).normalized()
	for offset_index in count:
		var serial := first_serial + offset_index
		var row := floori(float(offset_index) / 20.0)
		var column := offset_index % 20
		var lateral := (float(column) - 9.5) * 1.25
		var distance := 4.0 + float(row) * 1.25
		var spawn_point := center + forward * distance + side * lateral
		if at_point:
			spawn_point = center + forward * float(row) * 1.25 + side * float(column) * 1.25
		var monster := preload("res://scripts/gameplay/hostile_monster.gd").new()
		monster.name = "DebugMonster%d" % serial
		monster.monster_id = model_index
		monster.model_id = ["the_monster", "slasher", "smily"][model_index]
		monster.encounter = self
		monster.debug_spawned = true
		add_child(monster)
		monster.global_position = spawn_point
		monster.look_at(spawn_point - forward if at_point else center, Vector3.UP)
		monster._home = spawn_point
		monster._target_position = monster.position
		if offset_index % 25 == 24:
			await get_tree().process_frame

func debug_clear_spawned() -> int:
	if not multiplayer.is_server():
		return 0
	var count := get_tree().get_nodes_in_group("debug_spawned_monsters").size()
	_clear_debug_spawned.rpc()
	return count

@rpc("authority", "call_local", "reliable")
func _clear_debug_spawned() -> void:
	for monster in get_tree().get_nodes_in_group("debug_spawned_monsters"):
		if is_instance_valid(monster) and monster.encounter == self:
			if monster.corpse != null:
				monster.corpse.queue_free()
			monster.queue_free()

@rpc("authority", "call_local", "reliable")
func _reset_actors() -> void:
	for index in 3:
		get_node("Monster%d" % index).reset_enemy()

func _on_state(_snapshot: Dictionary) -> void:
	if multiplayer.is_server() and state.day_index == 3 and state.containment.get("level2", false):
		get_parent().get_node("Elevator_Functional_Blockout").set_day(4)
