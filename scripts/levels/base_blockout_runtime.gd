class_name BaseBlockoutRuntime
extends Node3D

const PLAYER_SCENE := preload("res://scenes/characters/player.tscn")
const QUEST_TERMINAL_SCENE := preload("res://scenes/objects/base/day_two_terminal.tscn")
const FLASHLIGHT_PICKUP_SCENE := preload(
	"res://scenes/objects/equipment/flashlight_pickup.tscn"
)
const FUEL_PICKUP_SCENE := preload(
	"res://scenes/objects/items/fuel_can_pickup.tscn"
)

@export var player_spawn_positions := PackedVector3Array([
	Vector3(0.35, 0.05, -5.2),
	Vector3(1.45, 0.05, -5.2),
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
]
@export var standalone_flashlight_transform := Transform3D(
	Basis.IDENTITY,
	Vector3(4.6, 0.1, -4.8)
)
@export var fuel_can_spawn_marker_path := NodePath(
	"Floor_0_Base_Blockout/South_Technical/Gameplay_Sockets/"
	+ "Power_And_Maintenance/Day1_Fuel_Can_Spawn"
)
@export var bunk_item_drop_marker_paths: Array[NodePath] = [
	NodePath(
		"Floor_0_Base_Blockout/East_Living/Gameplay_Sockets/"
		+ "Sleep_And_Checkpoint/End_Day_Bunk_Player_01_Item_Drop"
	),
	NodePath(
		"Floor_0_Base_Blockout/East_Living/Gameplay_Sockets/"
		+ "Sleep_And_Checkpoint/End_Day_Bunk_Player_02_Item_Drop"
	),
]
@export var day_start_marker_paths: Array[NodePath] = [
	NodePath(
		"Floor_0_Base_Blockout/East_Living/Gameplay_Sockets/"
		+ "Sleep_And_Checkpoint/Day_Start_Player_01_Spawn"
	),
	NodePath(
		"Floor_0_Base_Blockout/East_Living/Gameplay_Sockets/"
		+ "Sleep_And_Checkpoint/Day_Start_Player_02_Spawn"
	),
]

var network_runtime_managed: bool = false


func _ready() -> void:
	add_to_group("expedition_level")
	var reservoir := get_node("Floor_Minus2_Life_Support_Blockout/Water/Central_Reservoir_Water") as Node3D
	var radiation := preload("res://scripts/gameplay/radiation_zone.gd").new()
	radiation.name = "ReservoirRadiation"
	reservoir.add_child(radiation)
	_install_quest_terminals()
	_install_weapon_range()
	if network_runtime_managed:
		return
	spawn_standalone_gameplay()


func _install_weapon_range() -> void:
	var range_root := Node3D.new()
	range_root.name = "WeaponRange"
	add_child(range_root)
	for index in 3:
		var dispenser := preload("res://scripts/gameplay/weapon_dispenser.gd").new()
		dispenser.name = "Rack%d" % index
		dispenser.item_type = WeaponController.TYPES[index]
		dispenser.position = Vector3(-36.0, 1.05, 3.0 + index * 1.35)
		range_root.add_child(dispenser)
		var target := preload("res://scripts/gameplay/weapon_target.gd").new()
		target.name = "Target%d" % index
		target.position = Vector3(-28.0, 1.3, 3.0 + index * 1.35)
		range_root.add_child(target)
	var light := OmniLight3D.new()
	light.position = Vector3(-33, 3.0, 4.3)
	light.omni_range = 10.0
	light.light_energy = 2.5
	range_root.add_child(light)


func _install_quest_terminals() -> void:
	var task_socket := get_node("Floor_0_Base_Blockout/Center_Hub/Gameplay_Sockets/Daily_Loop/Daily_Task_Terminal_Socket") as Node3D
	var task_terminal := QUEST_TERMINAL_SCENE.instantiate() as DayTwoTerminal
	task_terminal.name = "DayTwoTaskTerminal"
	add_child(task_terminal)
	task_terminal.global_transform = task_socket.global_transform
	var key_socket := get_node("Floor_Minus1_Control_Security_Blockout/Secure_Data_Vault/Encryption_Key_Terminal") as Node3D
	var key_terminal := QUEST_TERMINAL_SCENE.instantiate() as DayTwoTerminal
	key_terminal.name = "DayTwoKeyTerminal"
	key_terminal.is_key_terminal = true
	add_child(key_terminal)
	# Mount the interaction panel on the existing cabinet's east-facing surface.
	key_terminal.global_position = key_socket.global_position + Vector3(0.67, 0.35, 0)
	key_terminal.rotation.y = PI * 0.5


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


func get_fuel_can_spawn_transform() -> Transform3D:
	var marker := get_node_or_null(fuel_can_spawn_marker_path) as Marker3D
	if marker != null:
		return marker.global_transform
	return Transform3D(Basis.IDENTITY, Vector3(-3.2, 0.36, 19.2))


func get_bunk_item_drop_transform(player_slot: int) -> Transform3D:
	if not bunk_item_drop_marker_paths.is_empty():
		var marker_path := bunk_item_drop_marker_paths[
			clampi(player_slot, 0, bunk_item_drop_marker_paths.size() - 1)
		]
		var marker := get_node_or_null(marker_path) as Marker3D
		if marker != null:
			return marker.global_transform
	var fallback_x := 23.25 if player_slot <= 0 else 28.0
	return Transform3D(Basis.IDENTITY, Vector3(fallback_x, 0.4, -5.55))


func get_day_start_transform(player_slot: int) -> Transform3D:
	if not day_start_marker_paths.is_empty():
		var marker_path := day_start_marker_paths[
			clampi(player_slot, 0, day_start_marker_paths.size() - 1)
		]
		var marker := get_node_or_null(marker_path) as Marker3D
		if marker != null:
			return marker.global_transform
	var fallback_x := 23.0 if player_slot <= 0 else 27.0
	return Transform3D(Basis.IDENTITY, Vector3(fallback_x, 0.05, -5.4))


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

	if get_node_or_null("StandaloneFuelCan") == null:
		var fuel_can := FUEL_PICKUP_SCENE.instantiate() as WorldItemPickup
		fuel_can.setup_spawn({
			"pickup_name": "StandaloneFuelCan",
			"item_type": GamePlayer.FUEL_ITEM,
			"item_state": {},
		})
		add_child(fuel_can)
		fuel_can.global_transform = get_fuel_can_spawn_transform()
