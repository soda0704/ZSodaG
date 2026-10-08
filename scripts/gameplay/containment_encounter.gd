extends Node3D

const CREATURE_SCENES := [preload("res://scenes/characters/monsters/the_monster.tscn"), preload("res://scenes/characters/monsters/slasher.tscn"), preload("res://scenes/characters/monsters/smily.tscn")]
@export var state_path := NodePath("../BaseGameplayController")
@export var navigation_level_path := NodePath("../Floor_Minus3_Biocontainment_Blockout")
@export var level_two_zone_path := NodePath("../Floor_Minus2_Life_Support_Blockout/InvestigationZone")
@export var level_three_zone_path := NodePath("../Floor_Minus3_Biocontainment_Blockout/InvestigationZone")
@export var monster_spawn_paths: Array[NodePath] = []
var state: BaseGameplayController
var _zones: Array[Area3D] = []
var navigation_ready: bool = false
var region: NavigationRegion3D
var _spawn_serial := 0

func _ready() -> void:
	add_to_group("containment_encounter")
	state = get_node_or_null(state_path) as BaseGameplayController
	if state == null:
		push_error("ContainmentEncounter: assign the base state in Inspector")
		return
	state.snapshot_changed.connect(_on_state)
	var level := get_node_or_null(navigation_level_path) as Node3D
	for index in 3:
		if index >= monster_spawn_paths.size():
			push_error("ContainmentEncounter: assign three spawn markers in Inspector")
			return
		var marker := get_node_or_null(monster_spawn_paths[index]) as Marker3D
		if marker == null:
			push_error("ContainmentEncounter: missing spawn marker")
			return
		var monster := get_node("Monster%d" % index)
		monster.encounter = self
		monster.global_transform = marker.global_transform
		monster._home = monster.global_position
		monster._target_position = monster.position
	_zones = [get_node_or_null(level_two_zone_path) as Area3D, get_node_or_null(level_three_zone_path) as Area3D]
	for index in _zones.size():
		if _zones[index] == null:
			push_error("ContainmentEncounter: assign investigation zones in Inspector")
			continue
		_zones[index].body_entered.connect(_on_zone_entered.bind(index))
	if multiplayer.is_server() and level != null:
		_bake.call_deferred(level)
	_on_state({})
	_check_current_zones.call_deferred()

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

func _on_zone_entered(body: Node3D, index: int) -> void:
	if not multiplayer.is_server() or state == null or not body is GamePlayer:
		return
	var required_day := state.LEVEL_TWO_DAY_INDEX if index == 0 else state.CONTAINMENT_DAY_INDEX
	var key := "level2" if index == 0 else "level3"
	if state.day_index != required_day or body.survival.dead or body.is_sleeping_in_bunk() or not state._can_mutate_for_peer(body.owner_peer_id) or state.containment.get(key, false):
		return
	var data := state.containment.duplicate(true)
	data[key] = true
	_commit(data)

func _check_current_zones() -> void:
	if not multiplayer.is_server(): return
	for index in _zones.size():
		if _zones[index] != null:
			for body in _zones[index].get_overlapping_bodies():
				_on_zone_entered(body, index)

func get_ready_peers() -> Array[int]:
	var world := get_tree().get_first_node_in_group("network_gameplay_controller")
	var peers: Array[int] = []
	if world != null and world.has_method("get_ready_v3_peers"):
		peers.assign(world.get_ready_v3_peers())
	return peers

func closest_player(point: Vector3, accepts: Callable = Callable(), search_distance:float = 40.0, vertical_distance:float = 3.5) -> Node3D:
	var best: Node3D
	var distance := search_distance
	for peer in state.get_connected_player_peer_ids():
		var player_node = state.get_player_node(peer)
		if not player_node is Node3D:
			continue
		var player := player_node as Node3D
		if player == null or player.survival.dead or player.is_sleeping_in_bunk() or absf(player.global_position.y - point.y) > vertical_distance:
			continue
		var candidate := point.distance_to(player.global_position)
		if candidate < distance and (not accepts.is_valid() or accepts.call(player)):
			distance = candidate
			best = player
	return best

func get_start_health() -> Array:
	var values: Array = []
	for index in 3:
		values.append(get_node("Monster%d" % index).ai_profile.max_health)
	return values

func get_monster_health(index: int) -> float:
	return float(state.containment.get("health", get_start_health())[index])

func damage_monster(index: int, amount: float) -> void:
	if not multiplayer.is_server() or amount <= 0.0:
		return
	var data: Dictionary = state.containment.duplicate(true)
	var health: Array = data.get("health", get_start_health()).duplicate()
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
	data.health = get_start_health()
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
		var monster = CREATURE_SCENES[model_index].instantiate()
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
	# Story creatures belong to the separate containment day; debug spawns are independent.
	var active := state.day_index >= state.CONTAINMENT_DAY_INDEX
	for index in 3:
		var monster := get_node_or_null("Monster%d" % index) as CharacterBody3D
		if monster != null:
			monster.visible = active
			monster.set_physics_process(active)
			monster.collision_layer = 2 if active and get_monster_health(index) > 0.0 else 0
	_check_current_zones.call_deferred()
