extends Node3D

const PLAYER_SCENE := preload(
	"res://scenes/characters/player.tscn"
)
const BATTERY_PICKUP_SCRIPT := preload("res://scripts/gameplay/items/battery_pickup.gd")
const ITEM_SCENES := {
	&"flame_large_cylinder": preload("res://scenes/objects/crafting/large_cylinder_pickup.tscn"),
	&"flame_small_cylinder": preload("res://scenes/objects/crafting/small_cylinder_pickup.tscn"),
	&"flame_cola_can": preload("res://scenes/objects/crafting/cola_can_pickup.tscn"),
	&"flame_pipe_bundle": preload("res://scenes/objects/crafting/pipe_bundle_pickup.tscn"),
	&"flame_hardware_box": preload("res://scenes/objects/crafting/hardware_box_pickup.tscn"),
	&"flame_pressure_gauge": preload("res://scenes/objects/crafting/pressure_gauge_pickup.tscn"),
	&"flame_valve": preload("res://scenes/objects/crafting/valve_pickup.tscn"),
	&"flamethrower": preload("res://scenes/objects/crafting/flamethrower_pickup.tscn"),
	&"seed_packet": preload("res://scenes/objects/items/seed_packet_pickup.tscn"),
	&"tape": preload("res://scenes/objects/items/tool_pickup.tscn"),
	&"crowbar": preload("res://scenes/objects/items/tool_pickup.tscn"),
	&"pistol_ammo": preload("res://scenes/objects/items/weapon_pickup.tscn"),
	&"rifle_magazine": preload("res://scenes/objects/items/weapon_pickup.tscn"),
	&"pistol": preload("res://scenes/objects/items/pistol_pickup.tscn"),
	&"m4a1": preload("res://scenes/objects/items/m4a1_pickup.tscn"),
	&"kitchen_knife": preload("res://scenes/objects/items/weapon_pickup.tscn"),
	&"flashlight": preload(
		"res://scenes/objects/equipment/flashlight_pickup.tscn"
	),
	&"fuse": preload("res://scenes/objects/items/fuse_pickup.tscn"),
	&"battery": preload("res://scenes/objects/items/battery_pickup.tscn"),
	&"fuel_can": preload("res://scenes/objects/items/fuel_can_pickup.tscn"),
}
const V3_LEVEL_PATH := "res://scenes/levels/base_blockout_v03.tscn"
const DEFAULT_GAMEPLAY_SPAWN_POSITIONS := [
	Vector3(-2.5, 0.05, 4.0),
	Vector3(2.5, 0.05, 4.0),
]
@export_group("Staging Lobby")
@export var uses_staging_lobby: bool = false
@export var staging_spawn_positions := PackedVector3Array([
	Vector3(-0.4, 0.05, 0.85),
	Vector3(0.4, 0.05, 0.85),
])
@export var gameplay_origin_path: NodePath
@export var staging_spawns_path: NodePath

@export_group("Gameplay Nodes")
@export var world_items_path := NodePath("Gameplay/WorldItems")
@export var item_spawner_path := NodePath("Gameplay/ItemSpawner")

@onready var players: Node3D = %Players
@onready var overview_camera: Camera3D = %OverviewCamera
@onready var lobby_hud: HelicopterLobbyHud = $LobbyHud
@onready var world_items: Node3D = get_node_or_null(
	world_items_path
) as Node3D
@onready var item_spawner: MultiplayerSpawner = get_node_or_null(
	item_spawner_path
) as MultiplayerSpawner
@onready var gameplay_origin: Node3D = get_node_or_null(
	gameplay_origin_path
) as Node3D

var _initial_items_spawned: bool = false
var _next_item_id: int = 1
var _player_roster: Dictionary = {}
var _entered_v3_level: bool = false
var _v3_transition_in_progress: bool = false
var _v3_items_spawned: bool = false
var _v3_flashlight_transform: Transform3D = Transform3D.IDENTITY
var _v3_fuel_can_transform: Transform3D = Transform3D.IDENTITY
var _v3_fuel_can_transforms: Array[Transform3D] = []
var _v3_spawn_positions := PackedVector3Array()
var _v3_spawn_yaws := PackedFloat32Array()
var _base_gameplay_controller: BaseGameplayController
var _v3_elevator_controller: FunctionalElevatorController
var _standalone_mode: bool = false
var resume_base_on_start: bool = false
var _v3_ready_peers: Array[int] = []
var _peer_inventory_ids: Dictionary = {}
var _transition_player_physics: Dictionary = {}

func _pause_transition_player(player: GamePlayer) -> void:
	if _transition_player_physics.has(player): return
	_transition_player_physics[player] = [player.is_physics_processing(),player.survival.is_physics_processing()]
	player.set_physics_process(false)
	player.survival.set_physics_process(false)

func _resume_transition_players() -> void:
	for player in _transition_player_physics:
		if not is_instance_valid(player): continue
		var previous: Array = _transition_player_physics[player]
		player.set_physics_process(previous[0])
		player.survival.set_physics_process(previous[1])
	_transition_player_physics.clear()


func get_ready_v3_peers() -> Array[int]:
	return _v3_ready_peers.duplicate()


func _inventory_id(peer_id: int) -> String:
	if _standalone_mode and peer_id == multiplayer.get_unique_id(): return "solo"
	# Steam may no longer resolve a disconnected peer while its equipment is dropped.
	if not _peer_inventory_ids.has(peer_id):
		_peer_inventory_ids[peer_id] = SteamNetwork.get_peer_inventory_id(peer_id)
	return str(_peer_inventory_ids[peer_id])


func capture_inventory_checkpoint() -> Dictionary:
	if not _v3_items_spawned or not is_instance_valid(world_items):
		return {}
	var equipment: Dictionary = _base_gameplay_controller.inventory_checkpoint.get("players", {}).duplicate(true)
	var participants: Dictionary = _base_gameplay_controller.inventory_checkpoint.get("participants", {}).duplicate(true)
	for player in players.get_children():
		if player is GamePlayer and not player.is_queued_for_deletion():
			equipment[_inventory_id(int(player.owner_peer_id))] = player.get_inventory_snapshot()
			var pose: Transform3D = player.global_transform
			var cabin_data := _capture_cabin_pose(pose) if not player.is_sleeping_in_bunk() and not player.is_driving() else {"transform": pose, "in_cabin": false, "cabin_id": ""}
			if player.is_sleeping_in_bunk():
				cabin_data.transform = get_node("V3Level").get_day_start_transform(get_peer_spawn_index(player.owner_peer_id))
			elif player.is_driving():
				cabin_data.transform = player.vehicle.get_checkpoint_exit_transform(player)
			cabin_data["survival"] = player.survival.capture_checkpoint()
			participants[_inventory_id(int(player.owner_peer_id))] = cabin_data
	var pickups: Array[Dictionary] = []
	for pickup in world_items.get_children():
		if pickup.is_queued_for_deletion() or bool(pickup.get("_collected")):
			continue
		var cargo_data := _capture_cabin_pose(pickup.global_transform)
		cargo_data["item_type"] = pickup.item_type
		cargo_data["item_state"] = pickup.item_state.duplicate(true)
		pickups.append(cargo_data)
	var heavy_props := capture_heavy_prop_checkpoint()
	return {"players": equipment, "participants": participants, "pickups": pickups, "heavy_props": heavy_props, "weapon_layout_version": 1, "fuel_layout_version": 1, "tools_layout_version": 1, "discoverable_layout_version": 2, "tape_layout_version": 1, "prop_layout_version": 1, "elevator_backup_layout_version": 1, "flamethrower_parts_layout_version": 1}


func capture_heavy_prop_checkpoint() -> Dictionary:
	var result := {}
	for prop in get_tree().get_nodes_in_group("heavy_carry_props"):
		if prop.is_queued_for_deletion() or prop.checkpoint_key == &"": continue
		var pose: Dictionary = {"transform": prop.global_transform, "in_cabin": false, "cabin_id": "", "frozen": prop.freeze}
		if is_instance_valid(prop._cargo_cabin):
			pose = {"transform": prop._cargo_pose, "in_cabin": true, "cabin_id": prop._cargo_cabin.get_parent().checkpoint_key}
		pose["item_state"] = prop.item_state.duplicate(true)
		result[String(prop.checkpoint_key)] = pose
	return result


func restore_heavy_prop_checkpoint(saved: Dictionary) -> void:
	if not multiplayer.is_server(): return
	for prop in get_tree().get_nodes_in_group("heavy_carry_props"):
		var data: Dictionary = saved.get(String(prop.checkpoint_key), {})
		if not data.get("transform") is Transform3D: continue
		prop.global_transform = _restore_cabin_pose(data, data.transform)
		prop.freeze = bool(data.get("frozen", false))
		if data.get("item_state") is Dictionary: prop.item_state = data.item_state.duplicate(true)
		prop.linear_velocity = Vector3.ZERO
		prop.angular_velocity = Vector3.ZERO
		prop.sync_physics_state()


func _capture_cabin_pose(pose: Transform3D) -> Dictionary:
	for transport in get_tree().get_nodes_in_group("elevator_controllers"):
		if transport.contains_cabin_point(pose.origin):
			return {"transform": transport.cabin.global_transform.affine_inverse() * pose, "in_cabin": true, "cabin_id": transport.checkpoint_key}
	return {"transform": pose, "in_cabin": false, "cabin_id": ""}


func _restore_cabin_pose(data: Dictionary, pose: Transform3D) -> Transform3D:
	if bool(data.get("in_cabin", false)):
		# Older expedition saves contain only the main elevator flag.
		var key := str(data.get("cabin_id", "elevator_floor"))
		for transport in get_tree().get_nodes_in_group("elevator_controllers"):
			if transport.checkpoint_key == key:
				return transport.cabin.global_transform * pose
	return pose


func _equipment_for_resume(key: String, revision: int = 0) -> Dictionary:
	var data: Dictionary = _base_gameplay_controller.inventory_checkpoint.get("players", {}).get(key, {}).duplicate(true)
	if data.is_empty():
		return data
	data["revision"] = maxi(int(data.get("revision", 0)), revision) + 1
	# Resume with the flashlight safely pocketed and switched off.
	if StringName(data.get("held_item", &"")) == &"flashlight":
		data["held_item"] = &""
	data["handheld_flashlight_drawn"] = false
	data["flashlight_enabled"] = false
	data["malfunctioning"] = false
	data["weapon_reload"] = 0.0
	return data


func _restore_player_equipment(player: Node) -> void:
	if not multiplayer.is_server() or not is_instance_valid(_base_gameplay_controller):
		return
	var key := _inventory_id(int(player.owner_peer_id))
	var data := _equipment_for_resume(key, int(player.get("_inventory_revision")))
	if not data.is_empty():
		player.apply_inventory_snapshot(data)
	player.restore_journal_ownership()
	var participant: Dictionary = _base_gameplay_controller.inventory_checkpoint.get("participants", {}).get(key, {})
	if not participant.is_empty():
		var pose: Transform3D = participant.get("transform", player.global_transform)
		pose = _restore_cabin_pose(participant, pose)
		if pose.origin.is_finite():
			player.teleport_authoritative(pose.origin, pose.basis.get_euler().y)
		player.survival.restore_checkpoint_authoritative(participant.get("survival", {}))


func _ready() -> void:
	add_to_group("network_gameplay_controller")
	if item_spawner != null:
		item_spawner.spawn_function = spawn_world_item_from_data
	SteamNetwork.session_ready.connect(_on_session_ready)
	SteamNetwork.session_closed.connect(_on_session_closed)
	SteamNetwork.peer_joined.connect(_on_peer_joined)
	SteamNetwork.peer_left.connect(_on_peer_left)
	CoopLobby.gameplay_started.connect(_on_gameplay_started)


func start_standalone_game() -> void:
	if not multiplayer.is_server() or not _player_roster.is_empty():
		return
	_standalone_mode = true
	overview_camera.current = false
	GameMenu.force_close_menu()
	spawn_player_for_peer(multiplayer.get_unique_id())
	lobby_hud.refresh()
	# New solo sessions stay playable in the cabin until the ESC ready action.


func is_waiting_for_arrival() -> bool:
	return uses_staging_lobby and not _entered_v3_level and not _v3_transition_in_progress


func is_solo_arrival() -> bool:
	return _standalone_mode and is_waiting_for_arrival()


func begin_solo_arrival() -> void:
	if multiplayer.is_server() and is_solo_arrival():
		GameMenu.force_close_menu()
		_enter_v3_level()


func _on_session_ready(as_host: bool) -> void:
	if as_host:
		spawn_player_for_peer(1)
		if resume_base_on_start:
			_enter_v3_level.rpc()
		elif uses_staging_lobby:
			GameMenu.call_deferred("open_menu", GlobalGameMenu.MenuView.SESSION)
		if not uses_staging_lobby or CoopLobby.game_has_started:
			spawn_initial_items()
	else:
		_request_player_spawn.rpc_id(1, GameMenu.get_character_variant_id())
		_request_gameplay_state.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func _request_player_spawn(character_variant: int = 0) -> void:
	if not multiplayer.is_server():
		return
	if character_variant not in [0, 1]:
		return

	var sender_id := multiplayer.get_remote_sender_id()
	# A late join may arrive while the host is still loading spawn markers.
	while _v3_transition_in_progress:
		await get_tree().process_frame
	if not multiplayer.get_peers().has(sender_id):
		return
	spawn_player_for_peer(sender_id, character_variant)
	send_player_roster(sender_id)


@rpc("any_peer", "call_remote", "reliable")
func _request_gameplay_state() -> void:
	if not multiplayer.is_server():
		return

	var sender_id := multiplayer.get_remote_sender_id()
	if _entered_v3_level:
		_enter_v3_level.rpc_id(sender_id)
		return
	for ramp in get_tree().get_nodes_in_group("helicopter_ramps"):
		ramp.sync_network_state_to_peer(sender_id)


@rpc("any_peer", "call_remote", "reliable")
func _request_v3_runtime_state() -> void:
	if not multiplayer.is_server() or not _entered_v3_level:
		return
	var sender_id := multiplayer.get_remote_sender_id()
	# The client can finish loading before the host. Send the snapshot only
	# once the level, parked ramp and initial items actually exist here.
	while _v3_transition_in_progress:
		await get_tree().process_frame
	if not multiplayer.get_peers().has(sender_id):
		return
	if not _v3_ready_peers.has(sender_id):
		_v3_ready_peers.append(sender_id)
	for pickup in get_tree().get_nodes_in_group("world_items"):
		if get_node("V3Level").is_ancestor_of(pickup):
			pickup.sync_physics_state_to_peer(sender_id)
	for ramp in get_tree().get_nodes_in_group("helicopter_ramps"):
		if not ramp.locked_in_flight:
			ramp.sync_network_state_to_peer(sender_id)
	if is_instance_valid(_base_gameplay_controller):
		_base_gameplay_controller.sync_network_state_to_peer(sender_id)
	for transport in get_tree().get_nodes_in_group("elevator_controllers"):
		transport.sync_network_state_to_peer(sender_id)
	for corpse in get_tree().get_nodes_in_group("medical_corpses"):
		corpse.sync_network_state_to_peer(sender_id)


func spawn_player_for_peer(peer_id: int, selected_variant: int = -1) -> void:
	if (
		not multiplayer.is_server()
		or _player_roster.has(peer_id)
		or _player_roster.size() >= CoopLobby.MAX_PLAYERS
	):
		return

	var display_name := (
		SteamNetwork.local_user_name
		if _standalone_mode
		else SteamNetwork.get_peer_persona_name(peer_id)
	)
	var spawn_index := get_available_spawn_index()
	var character_variant := GameMenu.get_character_variant_id() if peer_id == multiplayer.get_unique_id() else selected_variant
	if character_variant not in [0, 1]:
		character_variant = 0
	var hue := fmod(float(peer_id) * 0.173, 1.0)
	var spawn_data := {
		"peer_id": peer_id,
		"display_name": display_name,
		"position": get_spawn_position(spawn_index),
		"yaw": get_spawn_yaw(spawn_index),
		"spawn_index": spawn_index,
		"character_variant": character_variant,
		"color": Color.from_hsv(hue, 0.72, 0.95),
	}
	# Include restored state in the spawn RPC itself. Child RPCs issued during
	# local spawning could otherwise arrive before that player exists remotely.
	if _v3_items_spawned and is_instance_valid(_base_gameplay_controller):
		var key := _inventory_id(peer_id)
		var saved := _equipment_for_resume(key)
		if not saved.is_empty():
			spawn_data["inventory"] = saved
		var participant: Dictionary = _base_gameplay_controller.inventory_checkpoint.get("participants", {}).get(key, {})
		if not participant.is_empty():
			var pose: Transform3D = participant.get("transform", Transform3D.IDENTITY)
			pose = _restore_cabin_pose(participant, pose)
			if pose.origin.is_finite():
				spawn_data["position"] = players.to_local(pose.origin)
				spawn_data["yaw"] = pose.basis.get_euler().y
			spawn_data["survival"] = participant.get("survival", {})
	_player_roster[peer_id] = spawn_data
	if _standalone_mode:
		_spawn_player(spawn_data)
	else:
		_spawn_player.rpc(spawn_data)


@rpc("authority", "call_local", "reliable")
func _spawn_player(spawn_data: Dictionary) -> void:
	var peer_id := int(spawn_data.get("peer_id", 1))
	if players.has_node(str(peer_id)):
		_apply_roster_player_state(players.get_node(str(peer_id)), spawn_data)
		if _v3_transition_in_progress: _pause_transition_player(players.get_node(str(peer_id)))
		return

	var player := (
		PLAYER_SCENE.instantiate()
		as GamePlayer
	)
	player.name = str(peer_id)
	player.setup(
		peer_id,
		str(spawn_data.get("display_name", "Player")),
		spawn_data.get("position", Vector3.ZERO) as Vector3,
		spawn_data.get("color", Color.WHITE) as Color,
		float(spawn_data.get("yaw", 0.0)),
		int(spawn_data.get("character_variant", 0))
	)
	players.add_child(player)
	_apply_roster_player_state(player, spawn_data)
	if _v3_transition_in_progress: _pause_transition_player(player)


func _apply_roster_player_state(player: GamePlayer, spawn_data: Dictionary) -> void:
	if spawn_data.has("inventory"):
		player.apply_inventory_snapshot(spawn_data["inventory"])
	if spawn_data.has("sleeping"):
		player._receive_bunk_sleep_state(
			bool(spawn_data.sleeping), spawn_data.sleep_transform
		)
	if spawn_data.has("survival"):
		player.survival.apply_checkpoint(spawn_data.survival)


func send_player_roster(peer_id: int) -> void:
	if not multiplayer.is_server() or peer_id <= 0:
		return

	var roster: Array[Dictionary] = []
	for roster_peer_id_variant in _player_roster:
		var roster_peer_id := int(roster_peer_id_variant)
		var spawn_data := (
			_player_roster[roster_peer_id] as Dictionary
		).duplicate(true)
		var player := players.get_node_or_null(str(roster_peer_id)) as GamePlayer
		if player != null:
			spawn_data["position"] = player.position
			spawn_data["yaw"] = player.rotation.y
			spawn_data["inventory"] = player.get_inventory_snapshot()
			spawn_data["sleeping"] = player.is_sleeping_in_bunk()
			spawn_data["sleep_transform"] = player.global_transform
			spawn_data["survival"] = player.survival.capture_checkpoint()
		roster.append(spawn_data)
	_receive_player_roster.rpc_id(peer_id, roster)


@rpc("authority", "call_remote", "reliable")
func _receive_player_roster(roster: Array) -> void:
	for spawn_data_variant in roster:
		_spawn_player(spawn_data_variant as Dictionary)


@rpc("authority", "call_local", "reliable")
func _despawn_player(peer_id: int) -> void:
	var player := players.get_node_or_null(str(peer_id))
	if player != null:
		player.queue_free()


func get_spawn_position(spawn_index: int) -> Vector3:
	if _entered_v3_level:
		return get_v3_spawn_position(spawn_index)
	var marker := _get_staging_marker(spawn_index)
	if marker != null:
		return marker.global_position
	if (
		uses_staging_lobby
		and not CoopLobby.game_has_started
		and not _standalone_mode
	):
		return staging_spawn_positions[
			spawn_index % staging_spawn_positions.size()
		]

	var local_position: Vector3 = DEFAULT_GAMEPLAY_SPAWN_POSITIONS[
		spawn_index % DEFAULT_GAMEPLAY_SPAWN_POSITIONS.size()
	]
	if gameplay_origin != null:
		return gameplay_origin.to_global(local_position)
	return local_position


func get_spawn_yaw(spawn_index: int) -> float:
	if _entered_v3_level:
		return get_v3_spawn_yaw(spawn_index)
	var marker := _get_staging_marker(spawn_index)
	if marker != null:
		return marker.global_rotation.y
	return 0.0


func _get_staging_marker(index: int) -> Marker3D:
	if staging_spawns_path.is_empty():
		return null
	var markers := get_node_or_null(staging_spawns_path)
	if markers == null or markers.get_child_count() == 0:
		return null
	return markers.get_child(index % markers.get_child_count()) as Marker3D


func get_available_spawn_index() -> int:
	var used_spawn_indices: Array[int] = []
	for spawn_data_variant in _player_roster.values():
		var spawn_data := spawn_data_variant as Dictionary
		var spawn_index := int(spawn_data.get("spawn_index", -1))
		if spawn_index >= 0 and not used_spawn_indices.has(spawn_index):
			used_spawn_indices.append(spawn_index)
	for spawn_index in DEFAULT_GAMEPLAY_SPAWN_POSITIONS.size():
		if not used_spawn_indices.has(spawn_index):
			return spawn_index
	return _player_roster.size() % DEFAULT_GAMEPLAY_SPAWN_POSITIONS.size()


func get_peer_spawn_index(peer_id: int) -> int:
	var spawn_data := _player_roster.get(peer_id, {}) as Dictionary
	if spawn_data.has("spawn_index"):
		return maxi(int(spawn_data["spawn_index"]), 0)
	var peer_ids := _player_roster.keys()
	peer_ids.sort()
	return peer_ids.find(peer_id)


func _on_gameplay_started() -> void:
	if not uses_staging_lobby or not multiplayer.is_server():
		return
	_enter_v3_level.rpc()


@rpc("authority", "call_local", "reliable")
func _enter_v3_level() -> void:
	if _entered_v3_level or _v3_transition_in_progress:
		return
	_v3_transition_in_progress = true
	# Restored doses, death countdowns and cabin poses must not advance while
	# the player is still behind the loading cover. Rendering stays active.
	for player in players.get_children():
		if player is GamePlayer: _pause_transition_player(player)
	_entered_v3_level = true
	if has_node("CabinSound"):
		if resume_base_on_start:
			$CabinSound/CabinLoop.stop()
		else:
			$CabinSound/FadePlayer.play("arrival")
	GameMenu.force_close_menu()
	var transition_id := lobby_hud.show_transition_cover(
		"ПОСАДКА У БАЗЫ..."
	)
	await get_tree().create_timer(0.8).timeout

	var packed_level: PackedScene
	if DisplayServer.get_name() == "headless":
		# The dummy renderer's resource RID owners are not thread-safe. Keep
		# loading serial too: dependencies can create materials and textures.
		packed_level = load(V3_LEVEL_PATH) as PackedScene
	else:
		# Threaded IO keeps the visible transition UI and journal hint animating.
		ResourceLoader.load_threaded_request(V3_LEVEL_PATH)
		while ResourceLoader.load_threaded_get_status(V3_LEVEL_PATH) == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			await get_tree().process_frame
		packed_level = ResourceLoader.load_threaded_get(V3_LEVEL_PATH) as PackedScene
	if packed_level == null:
		push_error("Could not load V3 level: %s" % V3_LEVEL_PATH)
		_entered_v3_level = false
		_v3_transition_in_progress = false
		_resume_transition_players()
		lobby_hud.reveal_transition_cover(transition_id)
		return

	var construction := preload("res://scripts/network/level_load_job.gd").new()
	var v3_level := await construction.instantiate(packed_level, get_tree()) as BaseBlockoutRuntime
	if v3_level == null:
		push_error("V3 root must use BaseBlockoutRuntime")
		_entered_v3_level = false
		_v3_transition_in_progress = false
		_resume_transition_players()
		lobby_hud.reveal_transition_cover(transition_id)
		return
	v3_level.name = "V3Level"
	v3_level.network_runtime_managed = true
	var indirect := v3_level.get_node("WorldIndirectLighting")
	indirect.prepare_loading()
	_v3_flashlight_transform = v3_level.standalone_flashlight_transform
	# The staging sky belongs to the cabin, not the loaded expedition.
	for path in ["ArrivalEnvironment", "ArrivalSun"]:
		var node := get_node_or_null(path)
		if node != null:
			node.free()
	add_child(v3_level)
	if multiplayer.is_server():
		_v3_fuel_can_transforms = v3_level.get_fuel_can_spawn_transforms()
		_v3_fuel_can_transform = _v3_fuel_can_transforms[0]
	_v3_spawn_positions = PackedVector3Array()
	_v3_spawn_yaws = PackedFloat32Array()
	for spawn_index in v3_level.get_player_spawn_count():
		_v3_spawn_positions.append(
			v3_level.get_player_spawn_position(spawn_index)
		)
		_v3_spawn_yaws.append(v3_level.get_player_spawn_yaw(spawn_index))
	_base_gameplay_controller = v3_level.get_node_or_null(
		"BaseGameplayController"
	) as BaseGameplayController
	if multiplayer.is_server() and _base_gameplay_controller.day_index >= 2:
		for spawn_index in _v3_spawn_positions.size():
			var morning := v3_level.get_day_start_transform(spawn_index)
			_v3_spawn_positions[spawn_index] = morning.origin
			_v3_spawn_yaws[spawn_index] = morning.basis.get_euler().y
	_v3_elevator_controller = v3_level.get_node_or_null(
		"Elevator_Functional_Blockout"
	) as FunctionalElevatorController
	if multiplayer.is_server():
		for transport in get_tree().get_nodes_in_group("elevator_controllers"):
			transport.set_day(_base_gameplay_controller.day_index)
			transport.restore_checkpoint_floor(int(_base_gameplay_controller.maintenance.get(transport.checkpoint_key, 0)))

	overview_camera.current = false
	# Let the authored terrain and CSG collision enter the physics world before
	# moving players away from the staging cabin.
	await get_tree().physics_frame
	await get_tree().physics_frame
	if multiplayer.is_server():
		for player in players.get_children():
			if player.has_method("teleport_authoritative"):
				var spawn_index := get_peer_spawn_index(
					int(player.get("owner_peer_id"))
				)
				player.call(
					"teleport_authoritative",
					get_v3_spawn_position(spawn_index),
					get_v3_spawn_yaw(spawn_index)
				)

	cleanup_test_room_for_v3()
	var arrival_cabin := get_node_or_null("ArrivalCabin")
	if arrival_cabin != null:
		arrival_cabin.queue_free()
		await get_tree().process_frame
	if multiplayer.is_server():
		spawn_v3_world_items()
	else:
		_request_v3_runtime_state.rpc_id(1)
		# A faster guest must not uncover a default day or an empty expedition
		# while a slower host is still restoring its checkpoint.
		while is_instance_valid(_base_gameplay_controller) and not _base_gameplay_controller.has_authoritative_snapshot:
			await get_tree().process_frame
		if not is_instance_valid(_base_gameplay_controller): return
	# The final camera, physics bodies and restored loot must exist before warming
	# lighting. Keep the cover up until actual frames have settled on this machine.
	await get_tree().process_frame
	var arrival_camera := get_viewport().get_camera_3d()
	if arrival_camera != null:
		await indirect.finish_loading(arrival_camera.global_position.y)
	else:
		await indirect.finish_loading(get_v3_spawn_position(0).y)
	await lobby_hud.wait_for_transition_ready(transition_id)
	await lobby_hud.reveal_transition_cover(transition_id)
	_v3_transition_in_progress = false
	_resume_transition_players()
	lobby_hud.refresh()


func get_v3_spawn_position(index: int) -> Vector3:
	if _v3_spawn_positions.is_empty():
		return Vector3.ZERO
	return _v3_spawn_positions[index % _v3_spawn_positions.size()]


func get_v3_spawn_yaw(index: int) -> float:
	if _v3_spawn_yaws.is_empty():
		return 0.0
	return _v3_spawn_yaws[index % _v3_spawn_yaws.size()]


func cleanup_test_room_for_v3() -> void:
	if multiplayer.is_server() and is_instance_valid(world_items):
		for pickup in world_items.get_children():
			pickup.queue_free()
func spawn_v3_world_items() -> void:
	if (
		not multiplayer.is_server()
		or _v3_items_spawned
		or not is_instance_valid(world_items)
	):
		return
	_v3_items_spawned = true
	restore_heavy_prop_checkpoint(_base_gameplay_controller.inventory_checkpoint.get("heavy_props", {}))
	var migrate_craft := int(_base_gameplay_controller.inventory_checkpoint.get("flamethrower_parts_layout_version", 0)) < 1
	if migrate_craft:
		for loot: Dictionary in get_node("V3Level").get_flamethrower_loot():
			spawn_world_item(loot.type, world_items.global_transform.affine_inverse() * loot.transform, loot.state)
	var migrate_backup := int(_base_gameplay_controller.inventory_checkpoint.get("elevator_backup_layout_version", 0)) < 1
	if migrate_backup and not _base_gameplay_controller.elevator_backup_installed and not _checkpoint_has_fuse():
		var level := get_node("V3Level") as BaseBlockoutRuntime
		var fuse_transform := world_items.global_transform.affine_inverse() * level.get_elevator_backup_fuse_spawn_transform()
		spawn_world_item(GamePlayer.FUSE_ITEM, fuse_transform, {})
	if not _base_gameplay_controller.inventory_checkpoint.is_empty() and int(_base_gameplay_controller.inventory_checkpoint.get("tape_layout_version", 0)) < 1:
		for loot: Dictionary in BaseBlockoutRuntime.TOOL_LOOT:
			if loot.type == &"tape":
				spawn_world_item(loot.type, world_items.global_transform.affine_inverse() * BaseBlockoutRuntime.loot_transform(loot), loot.state)
	# One-time migration for saves made before these essentials got deliberate,
	# easy-to-find placements. It intentionally runs only for an existing save;
	# a fresh game receives the same entries from TOOL_LOOT/WEAPON_LOOT below.
	if not _base_gameplay_controller.inventory_checkpoint.is_empty() and int(_base_gameplay_controller.inventory_checkpoint.get("discoverable_layout_version", 0)) < 2:
		for loot: Dictionary in BaseBlockoutRuntime.DISCOVERABLE_LOOT:
			spawn_world_item(loot.type, world_items.global_transform.affine_inverse() * BaseBlockoutRuntime.loot_transform(loot), loot.state)
	if int(_base_gameplay_controller.inventory_checkpoint.get("tools_layout_version", 0)) < 1:
		for loot: Dictionary in BaseBlockoutRuntime.TOOL_LOOT:
			spawn_world_item(loot.type, world_items.global_transform.affine_inverse() * BaseBlockoutRuntime.loot_transform(loot), loot.state)
	if int(_base_gameplay_controller.inventory_checkpoint.get("fuel_layout_version", 0)) < 1:
		for index in range(1, _v3_fuel_can_transforms.size()):
			var fuel_transform := world_items.global_transform.affine_inverse() * _v3_fuel_can_transforms[index]
			spawn_world_item(GamePlayer.FUEL_ITEM, fuel_transform, {"fuel_liters": 20.0})
	if int(_base_gameplay_controller.inventory_checkpoint.get("weapon_layout_version", 0)) < 1:
		for loot: Dictionary in BaseBlockoutRuntime.WEAPON_LOOT:
			spawn_world_item(loot.type, world_items.global_transform.affine_inverse() * BaseBlockoutRuntime.loot_transform(loot), loot.state)
	var migrate_props := int(_base_gameplay_controller.inventory_checkpoint.get("prop_layout_version", 0)) < 1
	if migrate_props:
		for loot: Dictionary in BaseBlockoutRuntime.EXTRA_LOOT:
			spawn_world_item(loot.type, world_items.global_transform.affine_inverse() * BaseBlockoutRuntime.loot_transform(loot), loot.state)
	for player in players.get_children():
		if player is GamePlayer: _restore_player_equipment(player)
	if not _base_gameplay_controller.inventory_checkpoint.is_empty():
		var migrated_fuel_count := 0
		for data: Dictionary in _base_gameplay_controller.inventory_checkpoint.get("pickups", []):
			var restored: Transform3D = data.get("transform", Transform3D.IDENTITY)
			if bool(data.get("in_cabin", false)):
				restored = _restore_cabin_pose(data, restored)
			elif migrate_props:
				if StringName(data.item_type) == GamePlayer.FUEL_ITEM and _is_original_fuel_location(restored.origin):
					restored = _v3_fuel_can_transforms[migrated_fuel_count % _v3_fuel_can_transforms.size()]
					migrated_fuel_count += 1
				else:
					restored = _migrate_prop_transform(StringName(data.item_type), restored)
			spawn_world_item(StringName(data.item_type), world_items.global_transform.affine_inverse() * restored, data.item_state)
		return
	if not _base_gameplay_controller.plant_seed_planted:
		var level := get_node("V3Level") as BaseBlockoutRuntime
		spawn_world_item(GamePlayer.SEED_ITEM, world_items.global_transform.affine_inverse() * level.get_seed_packet_spawn_transform(), {})
	var local_transform := (
		world_items.global_transform.affine_inverse()
		* _v3_flashlight_transform
	)
	spawn_world_item(
		GamePlayer.FLASHLIGHT_ITEM,
		local_transform,
		{"battery_charge": 1.0}
	)
	var local_fuel_transform := (
		world_items.global_transform.affine_inverse()
		* _v3_fuel_can_transform
	)
	if not _standalone_mode:
		var second_light := local_transform
		second_light.origin += Vector3(0.4, 0.0, 0.0)
		spawn_world_item(GamePlayer.FLASHLIGHT_ITEM, second_light, {"battery_charge": 1.0})
	for index in 3:
		var cell_transform := world_items.global_transform.affine_inverse() * Transform3D(Basis.IDENTITY, Vector3(4.35 + index * 0.18, 0.1, -4.4))
		spawn_world_item(GamePlayer.BATTERY_ITEM, cell_transform, {"charge_amount": 1.0})
	if not _base_gameplay_controller.fuel_delivered:
		spawn_world_item(GamePlayer.FUEL_ITEM, local_fuel_transform, {})
	_base_gameplay_controller.save_progress_authoritative(false, "start", "Начало экспедиции")


func _checkpoint_has_fuse() -> bool:
	var checkpoint := _base_gameplay_controller.inventory_checkpoint
	for equipment: Dictionary in (checkpoint.get("players", {}) as Dictionary).values():
		if StringName(equipment.get("held_item", &"")) == GamePlayer.FUSE_ITEM:
			return true
	for pickup: Dictionary in checkpoint.get("pickups", []):
		if StringName(pickup.get("item_type", &"")) == GamePlayer.FUSE_ITEM:
			return true
	return false


func _is_original_fuel_location(position: Vector3) -> bool:
	return position.y < 1.0 and position.x > -3.9 and position.x < -1.5 and position.z > 18.6 and position.z < 20.6


func _migrate_prop_transform(item: StringName, original: Transform3D) -> Transform3D:
	# Only relocate uncollected props still at their original authored locations.
	# Inventory, cabin cargo and items carried elsewhere keep their saved state.
	var moves := [
		[&"pistol", Vector3(-29.7, 1.1, 7.05), BaseBlockoutRuntime.WEAPON_LOOT[0]],
		[&"m4a1", Vector3(-7.35, 1.25, 22.5), BaseBlockoutRuntime.WEAPON_LOOT[1]],
		[&"kitchen_knife", Vector3(11.6, 1.08, -7.35), BaseBlockoutRuntime.WEAPON_LOOT[2]],
		[&"rifle_magazine", Vector3(-7.35, 1.2, 23.2), BaseBlockoutRuntime.WEAPON_LOOT[5]],
		[&"tape", Vector3(-7, 1.2, 22.8), BaseBlockoutRuntime.TOOL_LOOT[1]],
	]
	for move: Array in moves:
		if item == move[0] and original.origin.distance_to(move[1]) < 0.65:
			return BaseBlockoutRuntime.loot_transform(move[2])
	if item == GamePlayer.FLASHLIGHT_ITEM and original.origin.distance_to(Vector3(4.8, 0.1, -4.8)) < 0.7:
		var result := _v3_flashlight_transform
		result.origin.x += clampf(original.origin.x - 4.6, 0.0, 0.4)
		return result
	return original


func spawn_initial_items() -> void:
	if (
		not multiplayer.is_server()
		or item_spawner == null
		or _initial_items_spawned
	):
		return

	_initial_items_spawned = true
	spawn_world_item(
		GamePlayer.FLASHLIGHT_ITEM,
		Transform3D(Basis.IDENTITY, Vector3(-1.25, 0.12, 3.35)),
		{"battery_charge": 0.25}
	)
	spawn_world_item(
		GamePlayer.FLASHLIGHT_ITEM,
		Transform3D(
			Basis(Vector3.UP, deg_to_rad(24.0)),
			Vector3(1.45, 0.12, 3.1)
		),
		{"battery_charge": 1.0}
	)
	spawn_world_item(
		GamePlayer.FUSE_ITEM,
		Transform3D(
			Basis(Vector3.UP, deg_to_rad(22.0)),
			Vector3(2.35, 0.14, 2.35)
		),
		{}
	)
	for battery_position in [
		Vector3(-2.75, 0.08, 3.1),
		Vector3(-2.45, 0.08, 3.35),
		Vector3(2.65, 0.08, -4.35),
	]:
		spawn_world_item(
			GamePlayer.BATTERY_ITEM,
			Transform3D(Basis.IDENTITY, battery_position),
			{"charge_amount": 0.5}
		)


func spawn_world_item(
	item_type: StringName,
	spawn_transform: Transform3D,
	item_state: Dictionary,
	linear_velocity: Vector3 = Vector3.ZERO,
	angular_velocity: Vector3 = Vector3.ZERO
) -> void:
	if (
		not multiplayer.is_server()
		or item_spawner == null
		or not ITEM_SCENES.has(item_type)
	):
		return

	var pickup_name := "%sPickup_%s" % [
		str(item_type).capitalize().replace(" ", ""),
		_next_item_id,
	]
	_next_item_id += 1
	var state := BATTERY_PICKUP_SCRIPT.prepare_state(item_state) if item_type==&"battery" else item_state.duplicate(true)
	var spawn_data := {
		"pickup_name": pickup_name,
		"item_type": item_type,
		"item_state": state,
		"transform": spawn_transform,
		"linear_velocity": linear_velocity,
		"angular_velocity": angular_velocity,
	}
	if _standalone_mode:
		var pickup := spawn_world_item_from_data(spawn_data)
		world_items.add_child(pickup)
	else:
		item_spawner.spawn(spawn_data)


func spawn_world_item_from_data(data: Variant) -> Node:
	var spawn_data := data as Dictionary
	var item_type := StringName(spawn_data.get("item_type", &""))
	var item_scene := ITEM_SCENES.get(item_type) as PackedScene
	if item_scene == null:
		push_error("No pickup scene registered for item: %s" % item_type)
		return Node3D.new()
	var pickup := item_scene.instantiate() as WorldItemPickup
	pickup.setup_spawn(spawn_data)
	return pickup


func spawn_dropped_item(item_type: StringName, item_state: Dictionary) -> void:
	if not multiplayer.is_server() or not ITEM_SCENES.has(item_type):
		return

	var drop_transform := item_state.get(
		"transform",
		Transform3D.IDENTITY
	) as Transform3D
	if world_items != null:
		drop_transform = (
			world_items.global_transform.affine_inverse()
			* drop_transform
		)
	spawn_world_item(
		item_type,
		drop_transform,
		item_state.get("item_state", {}) as Dictionary,
		item_state.get("linear_velocity", Vector3.ZERO) as Vector3,
		item_state.get("angular_velocity", Vector3.ZERO) as Vector3
	)


func _on_peer_left(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	_v3_ready_peers.erase(peer_id)
	var departing_player := players.get_node_or_null(str(peer_id))
	if (
		departing_player != null
		and departing_player.has_method("drop_all_items_at_authoritative")
		and _entered_v3_level
	):
		var v3_level := get_node_or_null("V3Level")
		if v3_level != null and v3_level.has_method(
			"get_bunk_item_drop_transform"
		):
			departing_player.call(
				"drop_all_items_at_authoritative",
				v3_level.call(
					"get_bunk_item_drop_transform",
					get_peer_spawn_index(peer_id)
				)
			)
		else:
			departing_player.call("drop_all_items_at_authoritative", departing_player.call("get_held_item_drop_transform"))
	elif (
		departing_player != null
		and departing_player.has_method("drop_current_item_authoritative")
	):
		departing_player.call("drop_all_items_at_authoritative", departing_player.call("get_held_item_drop_transform"))
	# Keep departed equipment in memory for reconnects; only explicit saves write it.
	if is_instance_valid(_base_gameplay_controller):
		_base_gameplay_controller.inventory_checkpoint = capture_inventory_checkpoint()
	_player_roster.erase(peer_id)
	_peer_inventory_ids.erase(peer_id)
	_despawn_player.rpc(peer_id)


func _on_peer_joined(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	call_deferred("send_player_roster", peer_id)


func _on_session_closed(_reason: String) -> void:
	_peer_inventory_ids.clear()
	if is_instance_valid(_base_gameplay_controller):
		_base_gameplay_controller.progress_persistence_enabled = false
	_v3_ready_peers.clear()
	for player in players.get_children():
		player.queue_free()
	if is_instance_valid(world_items):
		for pickup in world_items.get_children():
			pickup.queue_free()
	_initial_items_spawned = false
	_next_item_id = 1
	_v3_items_spawned = false
	_v3_spawn_positions = PackedVector3Array()
	_v3_spawn_yaws = PackedFloat32Array()
	_v3_fuel_can_transform = Transform3D.IDENTITY
	_v3_fuel_can_transforms.clear()
	_base_gameplay_controller = null
	_v3_elevator_controller = null
	_player_roster.clear()
	overview_camera.current = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
