extends Node3D

const PLAYER_SCENE := preload(
	"res://scenes/characters/player.tscn"
)
const ITEM_SCENES := {
	&"pistol_ammo": preload("res://scenes/objects/items/weapon_pickup.tscn"),
	&"rifle_magazine": preload("res://scenes/objects/items/weapon_pickup.tscn"),
	&"pistol": preload("res://scenes/objects/items/weapon_pickup.tscn"),
	&"m4a1": preload("res://scenes/objects/items/weapon_pickup.tscn"),
	&"kitchen_knife": preload("res://scenes/objects/items/weapon_pickup.tscn"),
	&"flashlight": preload(
		"res://scenes/objects/equipment/flashlight_pickup.tscn"
	),
	&"fuse": preload("res://scenes/objects/items/fuse_pickup.tscn"),
	&"battery": preload("res://scenes/objects/items/battery_pickup.tscn"),
	&"fuel_can": preload("res://scenes/objects/items/fuel_can_pickup.tscn"),
}
const V3_LEVEL_PATH := "res://scenes/levels/Base_Blockout_v03.tscn"
const DEFAULT_GAMEPLAY_SPAWN_POSITIONS := [
	Vector3(-2.5, 0.05, 4.0),
	Vector3(2.5, 0.05, 4.0),
]
const V3_TEST_BRANCHES := [
	NodePath("Helicopter"),
	NodePath("Gameplay/Geometry"),
	NodePath("Gameplay/PoweredDoorSystem"),
	NodePath("Gameplay/GeneratorPanel"),
	NodePath("Gameplay/Lighting"),
	NodePath("Gameplay/PowerGrid"),
	NodePath("Gameplay/V3ExitTerminal"),
]

@export_group("Staging Lobby")
@export var uses_staging_lobby: bool = false
@export var staging_spawn_positions := PackedVector3Array([
	Vector3(-0.4, 0.05, 0.85),
	Vector3(0.4, 0.05, 0.85),
])
@export var gameplay_origin_path: NodePath

@export_group("Gameplay Nodes")
@export var world_items_path := NodePath("Gameplay/WorldItems")
@export var item_spawner_path := NodePath("Gameplay/ItemSpawner")
@export var power_switch_path := NodePath(
	"Gameplay/PoweredDoorSystem/DoorPowerSwitch"
)
@export var interactive_door_path := NodePath(
	"Gameplay/PoweredDoorSystem/InteractiveDoor"
)
@export var generator_panel_path := NodePath("Gameplay/GeneratorPanel")

@onready var players: Node3D = %Players
@onready var overview_camera: Camera3D = %OverviewCamera
@onready var lobby_hud: HelicopterLobbyHud = $LobbyHud
@onready var world_items: Node3D = get_node_or_null(
	world_items_path
) as Node3D
@onready var item_spawner: MultiplayerSpawner = get_node_or_null(
	item_spawner_path
) as MultiplayerSpawner
@onready var power_switch: DoorPowerSwitch = get_node_or_null(
	power_switch_path
) as DoorPowerSwitch
@onready var interactive_door: InteractiveDoor = get_node_or_null(
	interactive_door_path
) as InteractiveDoor
@onready var generator_panel: GeneratorPanel = get_node_or_null(
	generator_panel_path
) as GeneratorPanel
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
var _v3_spawn_positions := PackedVector3Array()
var _v3_spawn_yaws := PackedFloat32Array()
var _base_gameplay_controller: BaseGameplayController
var _v3_elevator_controller: FunctionalElevatorController
var _standalone_mode: bool = false
var resume_base_on_start: bool = false
var _inventory_save_elapsed: float = 0.0


func _process(delta: float) -> void:
	if multiplayer.is_server() and _v3_items_spawned:
		_inventory_save_elapsed += delta
		if _inventory_save_elapsed >= 5.0:
			_inventory_save_elapsed = 0.0
			save_inventory_checkpoint()


func save_inventory_checkpoint() -> void:
	if multiplayer.is_server() and _v3_items_spawned and is_instance_valid(_base_gameplay_controller):
		_base_gameplay_controller.save_progress_authoritative()


func _inventory_id(peer_id: int) -> String:
	return "solo" if _standalone_mode and peer_id == multiplayer.get_unique_id() else SteamNetwork.get_peer_inventory_id(peer_id)


func capture_inventory_checkpoint() -> Dictionary:
	if not _v3_items_spawned or not is_instance_valid(world_items):
		return {}
	var equipment: Dictionary = _base_gameplay_controller.inventory_checkpoint.get("players", {}).duplicate(true)
	for player in players.get_children():
		if not player.is_queued_for_deletion():
			equipment[_inventory_id(int(player.owner_peer_id))] = player.get_inventory_snapshot()
	var pickups: Array[Dictionary] = []
	for pickup in world_items.get_children():
		if pickup.is_queued_for_deletion() or bool(pickup.get("_collected")):
			continue
		if pickup.item_type == GamePlayer.FUEL_ITEM and _base_gameplay_controller.fuel_delivered:
			continue
		var item_transform: Transform3D = pickup.global_transform
		var in_cabin := false
		if is_instance_valid(_v3_elevator_controller):
			var local: Vector3 = _v3_elevator_controller.cabin.to_local(item_transform.origin)
			in_cabin = absf(local.x) < 2.7 and absf(local.z) < 2.7 and local.y > -0.2 and local.y < 4.0
			if in_cabin:
				item_transform = _v3_elevator_controller.cabin.global_transform.affine_inverse() * item_transform
		pickups.append({"item_type": pickup.item_type, "item_state": pickup.item_state.duplicate(true), "transform": item_transform, "in_cabin": in_cabin})
	return {"players": equipment, "pickups": pickups, "weapon_layout_version": 1}


func _restore_player_equipment(player: Node) -> void:
	if not multiplayer.is_server() or not is_instance_valid(_base_gameplay_controller):
		return
	var saved_players: Dictionary = _base_gameplay_controller.inventory_checkpoint.get("players", {})
	var key := _inventory_id(int(player.owner_peer_id))
	if saved_players.has(key):
		var data: Dictionary = saved_players[key].duplicate(true)
		data["revision"] = int(player.get("_inventory_revision")) + 1
		# Resume with the flashlight safely pocketed and switched off.
		if StringName(data.get("held_item", &"")) == &"flashlight":
			data["held_item"] = &""
		data["flashlight_enabled"] = false
		data["malfunctioning"] = false
		data["weapon_reload"] = 0.0
		player.apply_inventory_snapshot(data)


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
	lobby_hud.visible = false
	overview_camera.current = false
	GameMenu.force_close_menu()
	spawn_player_for_peer(multiplayer.get_unique_id())
	spawn_initial_items()


func _on_session_ready(as_host: bool) -> void:
	if as_host:
		spawn_player_for_peer(1)
		if not uses_staging_lobby or CoopLobby.game_has_started:
			spawn_initial_items()
	else:
		_request_player_spawn.rpc_id(1)
		_request_gameplay_state.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func _request_player_spawn() -> void:
	if not multiplayer.is_server():
		return

	var sender_id := multiplayer.get_remote_sender_id()
	spawn_player_for_peer(sender_id)
	send_player_roster(sender_id)


@rpc("any_peer", "call_remote", "reliable")
func _request_gameplay_state() -> void:
	if not multiplayer.is_server():
		return

	var sender_id := multiplayer.get_remote_sender_id()
	if _entered_v3_level:
		_enter_v3_level.rpc_id(sender_id)
		return
	if is_instance_valid(power_switch):
		power_switch.sync_network_state_to_peer(sender_id)
	if is_instance_valid(interactive_door):
		interactive_door.sync_network_state_to_peer(sender_id)
	if is_instance_valid(generator_panel):
		generator_panel.sync_network_state_to_peer(sender_id)


@rpc("any_peer", "call_remote", "reliable")
func _request_v3_runtime_state() -> void:
	if not multiplayer.is_server() or not _entered_v3_level:
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if not multiplayer.get_peers().has(sender_id):
		return
	if is_instance_valid(_base_gameplay_controller):
		_base_gameplay_controller.sync_network_state_to_peer(sender_id)
	if is_instance_valid(_v3_elevator_controller):
		_v3_elevator_controller.sync_network_state_to_peer(sender_id)


func spawn_player_for_peer(peer_id: int) -> void:
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
	var hue := fmod(float(peer_id) * 0.173, 1.0)
	var spawn_data := {
		"peer_id": peer_id,
		"display_name": display_name,
		"position": get_spawn_position(spawn_index),
		"yaw": get_spawn_yaw(spawn_index),
		"spawn_index": spawn_index,
		"color": Color.from_hsv(hue, 0.72, 0.95),
	}
	_player_roster[peer_id] = spawn_data
	if _standalone_mode:
		_spawn_player(spawn_data)
	else:
		_spawn_player.rpc(spawn_data)


@rpc("authority", "call_local", "reliable")
func _spawn_player(spawn_data: Dictionary) -> void:
	var peer_id := int(spawn_data.get("peer_id", 1))
	if players.has_node(str(peer_id)):
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
		float(spawn_data.get("yaw", 0.0))
	)
	players.add_child(player)
	if _v3_items_spawned:
		_restore_player_equipment(player)
	if spawn_data.has("inventory"):
		player.apply_inventory_snapshot(spawn_data["inventory"])


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
			spawn_data["inventory"] = player.get_inventory_snapshot()
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
	return 0.0


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
	if resume_base_on_start:
		_enter_v3_level.rpc()
		return

	spawn_initial_items()
	for player in players.get_children():
		if player.has_method("teleport_authoritative"):
			var spawn_index := get_peer_spawn_index(
				int(player.get("owner_peer_id"))
			)
			player.call(
				"teleport_authoritative",
				get_spawn_position(spawn_index),
				0.0
			)


func can_enter_v3_level() -> bool:
	return (
		not _entered_v3_level
		and not _v3_transition_in_progress
		and is_instance_valid(generator_panel)
		and generator_panel.is_powered
		and is_instance_valid(power_switch)
		and power_switch.is_powered
		and is_instance_valid(interactive_door)
		and interactive_door.state == InteractiveDoor.DoorState.OPEN
	)


func request_v3_transition(peer_id: int) -> void:
	if (
		not multiplayer.is_server()
		or not players.has_node(str(peer_id))
		or not can_enter_v3_level()
	):
		return
	_enter_v3_level.rpc()


@rpc("authority", "call_local", "reliable")
func _enter_v3_level() -> void:
	if _entered_v3_level or _v3_transition_in_progress:
		return
	_v3_transition_in_progress = true
	_entered_v3_level = true
	var transition_id := lobby_hud.show_transition_cover(
		"ПЕРЕХОД НА БАЗУ V3..."
	)
	await get_tree().create_timer(0.2).timeout

	var packed_level := load(V3_LEVEL_PATH) as PackedScene
	if packed_level == null:
		push_error("Could not load V3 level: %s" % V3_LEVEL_PATH)
		_entered_v3_level = false
		_v3_transition_in_progress = false
		lobby_hud.reveal_transition_cover(transition_id)
		return

	var v3_level := packed_level.instantiate() as BaseBlockoutRuntime
	if v3_level == null:
		push_error("V3 root must use BaseBlockoutRuntime")
		_entered_v3_level = false
		_v3_transition_in_progress = false
		lobby_hud.reveal_transition_cover(transition_id)
		return
	v3_level.name = "V3Level"
	v3_level.network_runtime_managed = true
	_v3_flashlight_transform = v3_level.standalone_flashlight_transform
	add_child(v3_level)
	_v3_fuel_can_transform = v3_level.get_fuel_can_spawn_transform()
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

	cleanup_test_room_for_v3()
	overview_camera.current = false
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

	await get_tree().process_frame
	if multiplayer.is_server():
		spawn_v3_world_items()
	else:
		_request_v3_runtime_state.rpc_id(1)
	lobby_hud.reveal_transition_cover(transition_id)
	_v3_transition_in_progress = false


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
	for branch_path in V3_TEST_BRANCHES:
		var branch := get_node_or_null(branch_path)
		if branch != null:
			branch.free()


func spawn_v3_world_items() -> void:
	if (
		not multiplayer.is_server()
		or _v3_items_spawned
		or not is_instance_valid(world_items)
	):
		return
	_v3_items_spawned = true
	if int(_base_gameplay_controller.inventory_checkpoint.get("weapon_layout_version", 0)) < 1:
		for loot: Dictionary in BaseBlockoutRuntime.WEAPON_LOOT:
			spawn_world_item(loot.type, Transform3D(Basis.IDENTITY, loot.position), loot.state)
	for player in players.get_children():
		_restore_player_equipment(player)
	if not _base_gameplay_controller.inventory_checkpoint.is_empty():
		for data: Dictionary in _base_gameplay_controller.inventory_checkpoint.get("pickups", []):
			var restored: Transform3D = data.get("transform", Transform3D.IDENTITY)
			if bool(data.get("in_cabin", false)):
				restored = _v3_elevator_controller.cabin.global_transform * restored
			spawn_world_item(StringName(data.item_type), world_items.global_transform.affine_inverse() * restored, data.item_state)
		return
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
		var cell_transform := local_transform
		cell_transform.origin += Vector3(-0.25 + index * 0.18, 0.0, 0.4)
		spawn_world_item(GamePlayer.BATTERY_ITEM, cell_transform, {"charge_amount": 1.0})
	if not _base_gameplay_controller.fuel_delivered:
		spawn_world_item(GamePlayer.FUEL_ITEM, local_fuel_transform, {})


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
	var spawn_data := {
		"pickup_name": pickup_name,
		"item_type": item_type,
		"item_state": item_state.duplicate(true),
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
	save_inventory_checkpoint()
	_player_roster.erase(peer_id)
	_despawn_player.rpc(peer_id)


func _on_peer_joined(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	if is_instance_valid(power_switch):
		power_switch.call_deferred("sync_network_state_to_peer", peer_id)
	if is_instance_valid(interactive_door):
		interactive_door.call_deferred("sync_network_state_to_peer", peer_id)
	if is_instance_valid(generator_panel):
		generator_panel.call_deferred("sync_network_state_to_peer", peer_id)
	call_deferred("send_player_roster", peer_id)


func _on_session_closed(_reason: String) -> void:
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
	_base_gameplay_controller = null
	_v3_elevator_controller = null
	_player_roster.clear()
	if is_instance_valid(power_switch):
		power_switch.apply_power_state(false, true)
	if is_instance_valid(interactive_door):
		interactive_door.set_open(false, true)
	if is_instance_valid(generator_panel):
		generator_panel.apply_state(false, false, true)
	overview_camera.current = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
