class_name BaseBlockoutRuntime
extends Node3D

const PLAYER_SCENE := preload("res://scenes/characters/player.tscn")
const FLASHLIGHT_PICKUP_SCENE := preload(
	"res://scenes/objects/equipment/flashlight_pickup.tscn"
)

@export var player_spawn_positions := PackedVector3Array([
	Vector3(0.35, 0.05, -5.2),
	Vector3(1.45, 0.05, -5.2),
	Vector3(0.35, 0.05, -6.4),
	Vector3(1.45, 0.05, -6.4),
])
@export var player_spawn_marker_paths: Array[NodePath] = [
	NodePath(
		"Floor_0_Base_Blockout/West_Entrance/Gameplay_Sockets/"
		+ "Arrival_And_Exterior/Day1_Player_01_Arrival_Spawn"
	),
	NodePath(
		"Floor_0_Base_Blockout/West_Entrance/Gameplay_Sockets/"
		+ "Arrival_And_Exterior/Day1_Player_02_Arrival_Spawn"
	),
	NodePath(
		"Floor_0_Base_Blockout/West_Entrance/Gameplay_Sockets/"
		+ "Arrival_And_Exterior/Day1_Player_03_Arrival_Spawn"
	),
	NodePath(
		"Floor_0_Base_Blockout/West_Entrance/Gameplay_Sockets/"
		+ "Arrival_And_Exterior/Day1_Player_04_Arrival_Spawn"
	),
]
@export var standalone_flashlight_transform := Transform3D(
	Basis.IDENTITY,
	Vector3(4.6, 0.1, -4.8)
)

var network_runtime_managed: bool = false


func _ready() -> void:
	if network_runtime_managed:
		return
	spawn_standalone_gameplay()


func get_player_spawn_position(index: int) -> Vector3:
	var marker := get_player_spawn_marker(index)
	if marker != null:
		return marker.global_position
	if player_spawn_positions.is_empty():
		return Vector3.ZERO
	return player_spawn_positions[index % player_spawn_positions.size()]


func get_player_spawn_yaw(index: int) -> float:
	var marker := get_player_spawn_marker(index)
	if marker != null:
		return marker.global_rotation.y
	return 0.0


func get_player_spawn_count() -> int:
	var valid_marker_count := 0
	for marker_path in player_spawn_marker_paths:
		if get_node_or_null(marker_path) is Marker3D:
			valid_marker_count += 1
	if valid_marker_count > 0:
		return valid_marker_count
	return player_spawn_positions.size()


func get_player_spawn_marker(index: int) -> Marker3D:
	if player_spawn_marker_paths.is_empty():
		return null
	var marker_path := player_spawn_marker_paths[
		index % player_spawn_marker_paths.size()
	]
	return get_node_or_null(marker_path) as Marker3D


func spawn_standalone_gameplay() -> void:
	if get_node_or_null("RuntimePlayers") == null:
		var runtime_players := Node3D.new()
		runtime_players.name = "RuntimePlayers"
		add_child(runtime_players)

		var player := PLAYER_SCENE.instantiate() as GamePlayer
		player.name = "1"
		player.setup(
			1,
			SteamNetwork.local_user_name,
			get_player_spawn_position(0),
			Color(0.25, 0.75, 1.0),
			get_player_spawn_yaw(0)
		)
		runtime_players.add_child(player)

	if get_node_or_null("StandaloneFlashlight") == null:
		var flashlight := FLASHLIGHT_PICKUP_SCENE.instantiate() as WorldItemPickup
		flashlight.setup_spawn({
			"pickup_name": "StandaloneFlashlight",
			"item_type": GamePlayer.FLASHLIGHT_ITEM,
			"item_state": {"battery_charge": 1.0},
			"transform": standalone_flashlight_transform,
		})
		add_child(flashlight)
