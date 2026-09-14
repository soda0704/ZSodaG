class_name BaseBlockoutRuntime
extends Node3D

const WEAPON_LOOT := [
	{"type": &"pistol", "position": Vector3(-29.7, 1.12, 7.05), "state": {"rounds": 12}},
	{"type": &"m4a1", "position": Vector3(-7.35, 1.25, 22.5), "state": {"rounds": 30}},
	{"type": &"kitchen_knife", "position": Vector3(11.6, 1.08, -7.35), "state": {}},
	{"type": &"pistol_ammo", "position": Vector3(-29.25, 1.12, 7.05), "state": {"amount": 12}},
	{"type": &"pistol_ammo", "position": Vector3(2.5, 1.1, 17.25), "state": {"amount": 12}},
	{"type": &"rifle_magazine", "position": Vector3(-7.35, 1.2, 23.2), "state": {"rounds": 30}},
	{"type": &"rifle_magazine", "position": Vector3(-29, 1.2, 7.25), "state": {"rounds": 30}},
]

const TOOL_LOOT := [
	{"type": &"tape", "position": Vector3(-29.0, 1.2, 7.8), "state": {}},
	{"type": &"tape", "position": Vector3(-7.0, 1.2, 22.8), "state": {}},
	{"type": &"crowbar", "position": Vector3(-24.8, 0.25, 3.5), "state": {"uses": 3}},
]

const DISCOVERABLE_LOOT := [
	{"type": &"kitchen_knife", "position": Vector3(11.6, 1.08, -7.35), "state": {}},
	{"type": &"pistol", "position": Vector3(-29.7, 1.12, 7.05), "state": {"rounds": 12}},
	{"type": &"pistol_ammo", "position": Vector3(-29.25, 1.12, 7.05), "state": {"amount": 12}},
	{"type": &"crowbar", "position": Vector3(-24.8, 0.25, 3.5), "state": {"uses": 3}},
]

const PLAYER_SCENE := preload("res://scenes/characters/player.tscn")
const QUEST_TERMINAL_SCENE := preload("res://scenes/objects/base/day_two_terminal.tscn")
const FLASHLIGHT_PICKUP_SCENE := preload(
	"res://scenes/objects/equipment/flashlight_pickup.tscn"
)
const FUEL_PICKUP_SCENE := preload(
	"res://scenes/objects/items/fuel_can_pickup.tscn"
)

@export var player_spawn_positions := PackedVector3Array([
	Vector3(-39.5, 0.05, 2.5),
	Vector3(-39.5, 0.05, 3.5),
])
@export var player_spawn_yaws := PackedFloat32Array([PI * 0.5, PI * 0.5])
@export var standalone_flashlight_transform := Transform3D(
	Basis.IDENTITY,
	Vector3(4.6, 0.1, -4.8)
)
@export var task_terminal_transform := Transform3D(
	Basis.IDENTITY,
	Vector3(3.8, 1.25, -6.95)
)
@export var fuel_can_spawn_transform := Transform3D(
	Basis.IDENTITY,
	Vector3(-3.2, 0.36, 19.2)
)
@export var bunk_item_drop_transforms: Array[Transform3D] = [
	Transform3D(Basis.IDENTITY, Vector3(23.25, 0.4, -5.55)),
	Transform3D(Basis.IDENTITY, Vector3(28.0, 0.4, -5.55)),
]
@export var day_start_transforms: Array[Transform3D] = [
	Transform3D(Basis.IDENTITY, Vector3(23.0, 0.05, -5.4)),
	Transform3D(Basis.IDENTITY, Vector3(27.0, 0.05, -5.4)),
]

var network_runtime_managed: bool = false


func _ready() -> void:
	add_to_group("expedition_level")
	var developer_room := preload("res://scripts/levels/developer_test_room.gd").new()
	add_child(developer_room)
	var reservoir := get_node("Floor_Minus2_Life_Support_Blockout/Water/Central_Reservoir_Water") as Node3D
	var radiation := preload("res://scripts/gameplay/radiation_zone.gd").new()
	radiation.name = "ReservoirRadiation"
	reservoir.add_child(radiation)
	_install_quest_terminals()
	var encounter := preload("res://scripts/gameplay/containment_encounter.gd").new()
	encounter.name = "ContainmentEncounter"
	add_child(encounter)
	if network_runtime_managed:
		return
	spawn_standalone_gameplay()


func toggle_developer_test_room(player: Node3D) -> bool:
	var room := get_node_or_null("DeveloperTestRoom") as DeveloperTestRoom
	if room == null or player == null:
		return false
	if room.contains(player.global_position):
		var back: Transform3D = player.get_meta("developer_test_return", get_day_start_transform(0))
		player.teleport_authoritative(back.origin, back.basis.get_euler().y)
		player.remove_meta("developer_test_return")
	else:
		player.set_meta("developer_test_return", player.global_transform)
		var index := maxi(0, int(player.get("owner_peer_id")) - 1)
		player.teleport_authoritative(room.spawn_position(index), 0.0)
	return true


func _install_quest_terminals() -> void:
	var task_terminal := QUEST_TERMINAL_SCENE.instantiate() as DayTwoTerminal
	task_terminal.name = "DayTwoTaskTerminal"
	add_child(task_terminal)
	task_terminal.global_transform = task_terminal_transform
	var key_socket := get_node("Floor_Minus1_Control_Security_Blockout/Secure_Data_Vault/Encryption_Key_Terminal") as Node3D
	var key_terminal := QUEST_TERMINAL_SCENE.instantiate() as DayTwoTerminal
	key_terminal.name = "DayTwoKeyTerminal"
	key_terminal.is_key_terminal = true
	add_child(key_terminal)
	# Mount the interaction panel on the existing cabinet's east-facing surface.
	key_terminal.global_position = key_socket.global_position + Vector3(0.67, 0.35, 0)
	key_terminal.rotation.y = PI * 0.5


func get_player_spawn_position(index: int) -> Vector3:
	if player_spawn_positions.is_empty():
		return Vector3.ZERO
	return player_spawn_positions[index % player_spawn_positions.size()]


func get_player_spawn_yaw(index: int) -> float:
	if player_spawn_yaws.is_empty():
		return 0.0
	return player_spawn_yaws[index % player_spawn_yaws.size()]


func get_player_spawn_count() -> int:
	return player_spawn_positions.size()


func get_fuel_can_spawn_transform() -> Transform3D:
	return fuel_can_spawn_transform


func get_bunk_item_drop_transform(player_slot: int) -> Transform3D:
	if bunk_item_drop_transforms.is_empty():
		return Transform3D.IDENTITY
	return bunk_item_drop_transforms[
		clampi(player_slot, 0, bunk_item_drop_transforms.size() - 1)
	]


func get_day_start_transform(player_slot: int) -> Transform3D:
	if day_start_transforms.is_empty():
		return Transform3D.IDENTITY
	return day_start_transforms[
		clampi(player_slot, 0, day_start_transforms.size() - 1)
	]


func spawn_standalone_gameplay() -> void:
	for index in WEAPON_LOOT.size():
		var loot: Dictionary = WEAPON_LOOT[index]
		var pickup := preload("res://scenes/objects/items/weapon_pickup.tscn").instantiate()
		pickup.setup_spawn({"pickup_name": "WeaponLoot%d" % index, "item_type": loot.type, "item_state": loot.state, "transform": Transform3D(Basis.IDENTITY, loot.position)})
		add_child(pickup)
	if get_node_or_null("RuntimePlayers") == null:
		var runtime_players := Node3D.new()
		runtime_players.name = "RuntimePlayers"
		add_child(runtime_players)

		var player := PLAYER_SCENE.instantiate() as GamePlayer
		player.name = "1"
		var steam_network := get_node_or_null("/root/SteamNetwork")
		var local_user_name := "Игрок"
		if steam_network != null:
			local_user_name = str(steam_network.get("local_user_name"))
		player.setup(
			1,
			local_user_name,
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
		for index in TOOL_LOOT.size():
			var loot: Dictionary = TOOL_LOOT[index]
			var tool := preload("res://scenes/objects/items/tool_pickup.tscn").instantiate() as WorldItemPickup
			tool.setup_spawn({"pickup_name": "StandaloneTool%d" % index, "item_type": loot.type, "item_state": loot.state, "transform": Transform3D(Basis.IDENTITY, loot.position)})
			add_child(tool)
		var fuel_can := FUEL_PICKUP_SCENE.instantiate() as WorldItemPickup
		fuel_can.setup_spawn({
			"pickup_name": "StandaloneFuelCan",
			"item_type": GamePlayer.FUEL_ITEM,
			"item_state": {},
		})
		add_child(fuel_can)
		fuel_can.global_transform = get_fuel_can_spawn_transform()
		for index in 2:
			var reserve := FUEL_PICKUP_SCENE.instantiate() as WorldItemPickup
			reserve.setup_spawn({"pickup_name": "ReserveFuelCan%d" % index, "item_type": GamePlayer.FUEL_ITEM, "item_state": {"fuel_liters": 20.0}})
			add_child(reserve)
			reserve.global_transform = get_fuel_can_spawn_transform()
			reserve.global_position += Vector3(1.0, 0.0, index * 0.8)
