class_name BaseBlockoutRuntime
extends Node3D

const PLAYER_SCENE := preload("res://scenes/characters/player.tscn")
const FLASHLIGHT_PICKUP_SCENE := preload(
	"res://scenes/objects/equipment/flashlight_pickup.tscn"
)

@export var player_spawn_positions := PackedVector3Array([
	Vector3(0.35, 0.05, -5.2),
	Vector3(1.45, 0.05, -5.2),
])
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
	if player_spawn_positions.is_empty():
		return Vector3.ZERO
	return player_spawn_positions[index % player_spawn_positions.size()]


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
			Color(0.25, 0.75, 1.0)
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
