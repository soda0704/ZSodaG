extends Node3D

const NETWORK_PLAYER_SCENE := preload(
	"res://scenes/network/host_authoritative_player.tscn"
)
const NETWORK_FLASHLIGHT_PICKUP_SCENE := preload(
	"res://scenes/network/network_flashlight_pickup.tscn"
)
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
@export var flashlight_pickups_path := NodePath("Gameplay/FlashlightPickups")
@export var flashlight_spawner_path := NodePath("Gameplay/FlashlightSpawner")
@export var power_switch_path := NodePath(
	"Gameplay/PoweredDoorSystem/DoorPowerSwitch"
)
@export var interactive_door_path := NodePath(
	"Gameplay/PoweredDoorSystem/InteractiveDoor"
)

@onready var players: Node3D = %Players
@onready var player_spawner: MultiplayerSpawner = %PlayerSpawner
@onready var overview_camera: Camera3D = %OverviewCamera
@onready var flashlight_pickups: Node3D = get_node_or_null(
	flashlight_pickups_path
) as Node3D
@onready var flashlight_spawner: MultiplayerSpawner = get_node_or_null(
	flashlight_spawner_path
) as MultiplayerSpawner
@onready var power_switch: DoorPowerSwitch = get_node_or_null(
	power_switch_path
) as DoorPowerSwitch
@onready var interactive_door: InteractiveDoor = get_node_or_null(
	interactive_door_path
) as InteractiveDoor
@onready var gameplay_origin: Node3D = get_node_or_null(
	gameplay_origin_path
) as Node3D

var _initial_flashlights_spawned: bool = false
var _next_pickup_id: int = 1


func _ready() -> void:
	add_to_group("network_gameplay_controller")
	player_spawner.spawn_function = spawn_network_player
	if flashlight_spawner != null:
		flashlight_spawner.spawn_function = spawn_network_flashlight
	SteamNetwork.session_ready.connect(_on_session_ready)
	SteamNetwork.session_closed.connect(_on_session_closed)
	SteamNetwork.peer_joined.connect(_on_peer_joined)
	SteamNetwork.peer_left.connect(_on_peer_left)
	CoopLobby.gameplay_started.connect(_on_gameplay_started)


func _on_session_ready(as_host: bool) -> void:
	if as_host:
		spawn_player_for_peer(1)
		if not uses_staging_lobby or CoopLobby.game_has_started:
			spawn_initial_flashlights()
	else:
		_request_player_spawn.rpc_id(1)
		_request_gameplay_state.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func _request_player_spawn() -> void:
	if not multiplayer.is_server():
		return

	var sender_id := multiplayer.get_remote_sender_id()
	spawn_player_for_peer(sender_id)


@rpc("any_peer", "call_remote", "reliable")
func _request_gameplay_state() -> void:
	if not multiplayer.is_server():
		return

	var sender_id := multiplayer.get_remote_sender_id()
	if power_switch != null:
		power_switch.sync_network_state_to_peer(sender_id)
	if interactive_door != null:
		interactive_door.sync_network_state_to_peer(sender_id)


func spawn_player_for_peer(peer_id: int) -> void:
	if not multiplayer.is_server() or players.has_node(str(peer_id)):
		return

	var display_name := SteamNetwork.get_peer_persona_name(peer_id)
	var spawn_index := players.get_child_count()
	var hue := fmod(float(peer_id) * 0.173, 1.0)
	player_spawner.spawn({
		"peer_id": peer_id,
		"display_name": display_name,
		"position": get_spawn_position(spawn_index),
		"color": Color.from_hsv(hue, 0.72, 0.95),
	})


func spawn_network_player(data: Variant) -> Node:
	var spawn_data := data as Dictionary
	var player := (
		NETWORK_PLAYER_SCENE.instantiate()
		as HostAuthoritativeNetworkPlayer
	)
	var peer_id := int(spawn_data.get("peer_id", 1))
	player.name = str(peer_id)
	player.setup(
		peer_id,
		str(spawn_data.get("display_name", "Player")),
		spawn_data.get("position", Vector3.ZERO) as Vector3,
		spawn_data.get("color", Color.WHITE) as Color
	)
	return player


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

	spawn_initial_flashlights()
	var player_index := 0
	for player in players.get_children():
		if player.has_method("teleport_authoritative"):
			player.call(
				"teleport_authoritative",
				get_spawn_position(player_index),
				0.0
			)
		player_index += 1


func spawn_initial_flashlights() -> void:
	if (
		not multiplayer.is_server()
		or flashlight_spawner == null
		or _initial_flashlights_spawned
	):
		return

	_initial_flashlights_spawned = true
	spawn_flashlight_pickup(
		Transform3D(Basis.IDENTITY, Vector3(-1.25, 0.12, 3.35)),
		0.25
	)
	spawn_flashlight_pickup(
		Transform3D(
			Basis(Vector3.UP, deg_to_rad(24.0)),
			Vector3(1.45, 0.12, 3.1)
		),
		1.0
	)


func spawn_flashlight_pickup(
	spawn_transform: Transform3D,
	battery_charge: float,
	linear_velocity: Vector3 = Vector3.ZERO,
	angular_velocity: Vector3 = Vector3.ZERO
) -> void:
	if not multiplayer.is_server() or flashlight_spawner == null:
		return

	var pickup_name := "FlashlightPickup_%s" % _next_pickup_id
	_next_pickup_id += 1
	flashlight_spawner.spawn({
		"pickup_name": pickup_name,
		"battery_charge": clampf(battery_charge, 0.0, 1.0),
		"transform": spawn_transform,
		"linear_velocity": linear_velocity,
		"angular_velocity": angular_velocity,
	})


func spawn_network_flashlight(data: Variant) -> Node:
	var pickup := (
		NETWORK_FLASHLIGHT_PICKUP_SCENE.instantiate()
		as NetworkFlashlightPickup
	)
	pickup.setup_spawn(data as Dictionary)
	return pickup


func collect_flashlight_pickup(
	pickup: NetworkFlashlightPickup,
	previous_charge: float,
	interactor: Node
) -> void:
	if not multiplayer.is_server() or not is_instance_valid(pickup):
		return

	if previous_charge >= 0.0:
		var drop_transform := interactor.call(
			"get_flashlight_drop_transform"
		) as Transform3D
		if flashlight_pickups != null:
			drop_transform = (
				flashlight_pickups.global_transform.affine_inverse()
				* drop_transform
			)
		spawn_flashlight_pickup(
			drop_transform,
			previous_charge,
			interactor.call("get_flashlight_drop_linear_velocity") as Vector3,
			Vector3(1.4, 0.8, -1.1)
		)
	pickup.queue_free()


func _on_peer_left(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	var player := players.get_node_or_null(str(peer_id))
	if player != null:
		player.queue_free()


func _on_peer_joined(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	if power_switch != null:
		power_switch.call_deferred("sync_network_state_to_peer", peer_id)
	if interactive_door != null:
		interactive_door.call_deferred("sync_network_state_to_peer", peer_id)


func _on_session_closed(_reason: String) -> void:
	for player in players.get_children():
		player.queue_free()
	if flashlight_pickups != null:
		for pickup in flashlight_pickups.get_children():
			pickup.queue_free()
	_initial_flashlights_spawned = false
	_next_pickup_id = 1
	if power_switch != null:
		power_switch.apply_power_state(false, true)
	if interactive_door != null:
		interactive_door.set_open(false, true)
	overview_camera.current = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
