extends Node3D

const PLAYER_SCENE := preload(
	"res://scenes/characters/player.tscn"
)
const ITEM_SCENES := {
	&"flashlight": preload(
		"res://scenes/objects/equipment/flashlight_pickup.tscn"
	),
	&"fuse": preload("res://scenes/objects/items/fuse_pickup.tscn"),
	&"battery": preload("res://scenes/objects/items/battery_pickup.tscn"),
}
const DEFAULT_GAMEPLAY_SPAWN_POSITIONS := [
	Vector3(-2.5, 0.05, 4.0),
	Vector3(2.5, 0.05, 4.0),
	Vector3(-2.5, 0.05, -4.0),
	Vector3(2.5, 0.05, -4.0),
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


func _ready() -> void:
	add_to_group("network_gameplay_controller")
	if item_spawner != null:
		item_spawner.spawn_function = spawn_world_item_from_data
	SteamNetwork.session_ready.connect(_on_session_ready)
	SteamNetwork.session_closed.connect(_on_session_closed)
	SteamNetwork.peer_joined.connect(_on_peer_joined)
	SteamNetwork.peer_left.connect(_on_peer_left)
	CoopLobby.gameplay_started.connect(_on_gameplay_started)


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
	if power_switch != null:
		power_switch.sync_network_state_to_peer(sender_id)
	if interactive_door != null:
		interactive_door.sync_network_state_to_peer(sender_id)
	if generator_panel != null:
		generator_panel.sync_network_state_to_peer(sender_id)


func spawn_player_for_peer(peer_id: int) -> void:
	if not multiplayer.is_server() or _player_roster.has(peer_id):
		return

	var display_name := SteamNetwork.get_peer_persona_name(peer_id)
	var spawn_index := _player_roster.size()
	var hue := fmod(float(peer_id) * 0.173, 1.0)
	var spawn_data := {
		"peer_id": peer_id,
		"display_name": display_name,
		"position": get_spawn_position(spawn_index),
		"color": Color.from_hsv(hue, 0.72, 0.95),
	}
	_player_roster[peer_id] = spawn_data
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
		spawn_data.get("color", Color.WHITE) as Color
	)
	players.add_child(player)


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
	if uses_staging_lobby and not CoopLobby.game_has_started:
		return staging_spawn_positions[
			spawn_index % staging_spawn_positions.size()
		]

	var local_position: Vector3 = DEFAULT_GAMEPLAY_SPAWN_POSITIONS[
		spawn_index % DEFAULT_GAMEPLAY_SPAWN_POSITIONS.size()
	]
	if gameplay_origin != null:
		return gameplay_origin.to_global(local_position)
	return local_position


func _on_gameplay_started() -> void:
	if not uses_staging_lobby or not multiplayer.is_server():
		return

	spawn_initial_items()
	var player_index := 0
	for player in players.get_children():
		if player.has_method("teleport_authoritative"):
			player.call(
				"teleport_authoritative",
				get_spawn_position(player_index),
				0.0
			)
		player_index += 1


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
			Basis(Vector3.UP, deg_to_rad(-18.0)),
			Vector3(2.75, 0.14, -2.65)
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
	item_spawner.spawn({
		"pickup_name": pickup_name,
		"item_type": item_type,
		"item_state": item_state.duplicate(true),
		"transform": spawn_transform,
		"linear_velocity": linear_velocity,
		"angular_velocity": angular_velocity,
	})


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
	_player_roster.erase(peer_id)
	_despawn_player.rpc(peer_id)


func _on_peer_joined(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	if power_switch != null:
		power_switch.call_deferred("sync_network_state_to_peer", peer_id)
	if interactive_door != null:
		interactive_door.call_deferred("sync_network_state_to_peer", peer_id)
	if generator_panel != null:
		generator_panel.call_deferred("sync_network_state_to_peer", peer_id)
	call_deferred("send_player_roster", peer_id)


func _on_session_closed(_reason: String) -> void:
	for player in players.get_children():
		player.queue_free()
	if world_items != null:
		for pickup in world_items.get_children():
			pickup.queue_free()
	_initial_items_spawned = false
	_next_item_id = 1
	_player_roster.clear()
	if power_switch != null:
		power_switch.apply_power_state(false, true)
	if interactive_door != null:
		interactive_door.set_open(false, true)
	if generator_panel != null:
		generator_panel.apply_state(false, false, true)
	overview_camera.current = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
