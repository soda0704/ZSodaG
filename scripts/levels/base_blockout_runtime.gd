class_name BaseBlockoutRuntime
extends Node3D

@export var fall_out_depth: float = -160.0

const WEAPON_LOOT := [
	{"type": &"pistol", "position": Vector3(-29.7, 1.06, 7.05), "rotation": Vector3(0, 17, 90), "state": {"rounds": 12}},
	{"type": &"m4a1", "position": Vector3(-7.22, 0.11, 18.85), "rotation": Vector3(0, -23, 90), "state": {"rounds": 30}},
	{"type": &"kitchen_knife", "position": Vector3(14.05, 1.12, -7.25), "rotation": Vector3(0, 19, 90), "state": {}},
	{"type": &"pistol_ammo", "position": Vector3(-29.25, 1.12, 7.05), "state": {"amount": 12}},
	{"type": &"pistol_ammo", "position": Vector3(2.5, 1.1, 17.25), "state": {"amount": 12}},
	{"type": &"rifle_magazine", "position": Vector3(-6.93, 0.10, 18.75), "rotation": Vector3(90, 31, 0), "state": {"rounds": 30}},
	{"type": &"rifle_magazine", "position": Vector3(-29, 1.2, 7.25), "state": {"rounds": 30}},
]

const TOOL_LOOT := [
	{"type": &"tape", "position": Vector3(-29.0, 1.2, 7.8), "state": {}},
	{"type": &"tape", "position": Vector3(-7.49, 0.08, 19.06), "rotation": Vector3(0, -11, 0), "state": {}},
	{"type": &"crowbar", "position": Vector3(-24.8, 0.25, 3.5), "state": {"uses": 3}},
]

const EXTRA_LOOT := [
	{"type": &"kitchen_knife", "position": Vector3(14.52, 1.12, -7.39), "rotation": Vector3(0, -28, 90), "state": {}},
	{"type": &"flashlight", "position": Vector3(2.08, 1.07, 17.12), "rotation": Vector3(0, 52, 0), "state": {"battery_charge": 1.0}},
	{"type": &"battery", "position": Vector3(2.45, 1.06, 17.40), "rotation": Vector3(0, -34, 0), "state": {"charge_amount": 1.0}},
	{"type": &"battery", "position": Vector3(2.62, 1.06, 17.24), "rotation": Vector3(0, 67, 0), "state": {"charge_amount": 1.0}},
	{"type": &"pistol_ammo", "position": Vector3(2.97, 1.07, 17.13), "rotation": Vector3(0, -21, 0), "state": {"amount": 6}},
]

const DISCOVERABLE_LOOT := [
	{"type": &"kitchen_knife", "position": Vector3(14.05, 1.12, -7.25), "rotation": Vector3(0, 19, 90), "state": {}},
	{"type": &"pistol", "position": Vector3(-29.7, 1.06, 7.05), "rotation": Vector3(0, 17, 90), "state": {"rounds": 12}},
	{"type": &"pistol_ammo", "position": Vector3(-29.25, 1.12, 7.05), "state": {"amount": 12}},
	{"type": &"crowbar", "position": Vector3(-24.8, 0.25, 3.5), "state": {"uses": 3}},
]

const PLAYER_SCENE := preload("res://scenes/characters/player.tscn")
const FLASHLIGHT_PICKUP_SCENE := preload(
	"res://scenes/objects/equipment/flashlight_pickup.tscn"
)
const FUEL_PICKUP_SCENE := preload(
	"res://scenes/objects/items/fuel_can_pickup.tscn"
)
const SUPPLY_PICKUP_SCENES := {
	&"fuel_can": FUEL_PICKUP_SCENE,
	&"flashlight": FLASHLIGHT_PICKUP_SCENE,
	&"battery": preload("res://scenes/objects/items/battery_pickup.tscn"),
	&"pistol": preload("res://scenes/objects/items/pistol_pickup.tscn"),
	&"m4a1": preload("res://scenes/objects/items/m4a1_pickup.tscn"),
	&"pistol_ammo": preload("res://scenes/objects/items/weapon_pickup.tscn"),
	&"rifle_magazine": preload("res://scenes/objects/items/weapon_pickup.tscn"),
}

@export var player_spawn_positions := PackedVector3Array([
	Vector3(-39.5, 0.05, 2.5),
	Vector3(-39.5, 0.05, 3.5),
])
@export var player_spawn_yaws := PackedFloat32Array([PI * 0.5, PI * 0.5])
@export var arrival_spawns_path := NodePath("ArrivalSite/Spawns")
@export var seed_packet_spawn_path := NodePath("Floor_0_Base_Blockout/East_Living/Art/CommonRoomArt/Visual/SeedPacketSpawn")
@export var elevator_backup_fuse_spawn_path := NodePath("Floor_0_Base_Blockout/Gameplay/MedicalFuseTray/Spawn")
@export var standalone_flashlight_transform := Transform3D(
	Basis(Vector3.UP, -0.43),
	Vector3(-24.2, 0.08, 3.85)
)
@export var fuel_can_spawn_transform := Transform3D(
	Basis.IDENTITY,
	Vector3(-34.5, 0.36, 6.3)
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
var _fuel_scatter: Array[Transform3D] = []


static func loot_transform(loot: Dictionary) -> Transform3D:
	var angles: Vector3 = loot.get("rotation", Vector3.ZERO)
	return Transform3D(Basis.from_euler(angles * PI / 180.0), loot.position)


func get_fuel_can_spawn_transforms() -> Array[Transform3D]:
	if _fuel_scatter.is_empty():
		# Separate clear floor areas; only the server chooses and replicates poses.
		for center in [fuel_can_spawn_transform.origin, Vector3(-27.2, 0.36, -5.7), Vector3(-36.4, 0.36, -3.5)]:
			var spawn_position: Vector3 = center + Vector3(randf_range(-0.25, 0.25), 0, randf_range(-0.25, 0.25))
			_fuel_scatter.append(Transform3D(Basis(Vector3.UP, randf_range(-PI, PI)), spawn_position))
		_fuel_scatter.shuffle()
	return _fuel_scatter.duplicate()


func _enter_tree() -> void:
	# F6 is a disposable preview; only the session owns normal checkpoints.
	# Existing automated tests explicitly select their own isolated save path.
	$BaseGameplayController.progress_persistence_enabled = (
		network_runtime_managed
		or ProjectSettings.has_setting(BaseGameplayController.TEST_SAVE_PATH_SETTING)
	)


func _ready() -> void:
	add_to_group("expedition_level")
	var developer_room := preload("res://scripts/levels/developer_test_room.gd").new()
	add_child(developer_room)
	var reservoir := get_node("Floor_Minus2_Life_Support_Blockout/Water/Central_Reservoir_Water") as Node3D
	var radiation := preload("res://scripts/gameplay/radiation_zone.gd").new()
	radiation.name = "ReservoirRadiation"
	reservoir.add_child(radiation)
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


func get_player_spawn_position(index: int) -> Vector3:
	var marker := _arrival_marker(index)
	if marker != null:
		return marker.global_position
	if player_spawn_positions.is_empty():
		return Vector3.ZERO
	return player_spawn_positions[index % player_spawn_positions.size()]


func get_player_spawn_yaw(index: int) -> float:
	var marker := _arrival_marker(index)
	if marker != null:
		return marker.global_rotation.y
	if player_spawn_yaws.is_empty():
		return 0.0
	return player_spawn_yaws[index % player_spawn_yaws.size()]


func get_player_spawn_count() -> int:
	var markers := get_node_or_null(arrival_spawns_path)
	if markers != null and markers.get_child_count() > 0:
		return markers.get_child_count()
	return player_spawn_positions.size()


func _arrival_marker(index: int) -> Marker3D:
	var markers := get_node_or_null(arrival_spawns_path)
	if markers == null or markers.get_child_count() == 0:
		return null
	return markers.get_child(index % markers.get_child_count()) as Marker3D


func get_seed_packet_spawn_transform() -> Transform3D:
	return (get_node(seed_packet_spawn_path) as Marker3D).global_transform


func get_elevator_backup_fuse_spawn_transform() -> Transform3D:
	return (get_node(elevator_backup_fuse_spawn_path) as Marker3D).global_transform


func get_bunk_item_drop_transform(player_slot: int) -> Transform3D:
	if bunk_item_drop_transforms.is_empty():
		return Transform3D.IDENTITY
	return bunk_item_drop_transforms[
		clampi(player_slot, 0, bunk_item_drop_transforms.size() - 1)
	]


func get_respawn_transform(player_slot: int) -> Transform3D:
	var state := get_node_or_null("BaseGameplayController") as BaseGameplayController
	if state == null or not state.main_breaker_on:
		return Transform3D(Basis(Vector3.UP, get_player_spawn_yaw(player_slot)), get_player_spawn_position(player_slot))
	return get_day_start_transform(player_slot)

func get_day_start_transform(player_slot: int) -> Transform3D:
	if day_start_transforms.is_empty():
		return Transform3D.IDENTITY
	return day_start_transforms[
		clampi(player_slot, 0, day_start_transforms.size() - 1)
	]


func spawn_standalone_gameplay() -> void:
	var supplies := get_supply_loot()
	for index in supplies.size():
		var loot := supplies[index]
		var item := (SUPPLY_PICKUP_SCENES[loot.type] as PackedScene).instantiate() as WorldItemPickup
		item.setup_spawn({"pickup_name": "SupplyLoot%d" % index, "item_type": loot.type, "item_state": loot.state, "transform": loot.transform})
		add_child(item)
	var recipe = preload("res://assets/config/flamethrower_recipe.tres")
	if not has_node("CraftLoot0"):
		var craft_loot := get_flamethrower_loot()
		for index in craft_loot.size():
			var loot := craft_loot[index]
			var scene: PackedScene = load(recipe.pickup_scenes[loot.type]) if loot.type != &"tape" else preload("res://scenes/objects/items/tool_pickup.tscn")
			var pickup := scene.instantiate() as WorldItemPickup
			pickup.setup_spawn({"pickup_name": "CraftLoot%d" % index, "item_type": loot.type, "item_state": {}, "transform": global_transform.affine_inverse() * loot.transform})
			add_child(pickup)
	var state := get_node("BaseGameplayController") as BaseGameplayController
	if not state.plant_seed_planted and not has_node("KitchenSeedPacket"):
		var packet := preload("res://scenes/objects/items/seed_packet_pickup.tscn").instantiate() as WorldItemPickup
		packet.setup_spawn({"pickup_name": "KitchenSeedPacket", "transform": get_seed_packet_spawn_transform()})
		add_child(packet)
	if not state.elevator_backup_installed and not has_node("ElevatorBackupFuse"):
		var fuse := preload("res://scenes/objects/items/fuse_pickup.tscn").instantiate() as WorldItemPickup
		fuse.setup_spawn({"pickup_name": "ElevatorBackupFuse", "transform": get_elevator_backup_fuse_spawn_transform()})
		add_child(fuse)
	for index in WEAPON_LOOT.size():
		var loot: Dictionary = WEAPON_LOOT[index]
		var scene: PackedScene = preload("res://scenes/objects/items/pistol_pickup.tscn") if loot.type==&"pistol" else preload("res://scenes/objects/items/m4a1_pickup.tscn") if loot.type==&"m4a1" else preload("res://scenes/objects/items/weapon_pickup.tscn")
		var pickup := scene.instantiate()
		pickup.setup_spawn({"pickup_name": "WeaponLoot%d" % index, "item_type": loot.type, "item_state": loot.state, "transform": loot_transform(loot)})
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
			tool.setup_spawn({"pickup_name": "StandaloneTool%d" % index, "item_type": loot.type, "item_state": loot.state, "transform": loot_transform(loot)})
			add_child(tool)
		var fuel_transforms := get_fuel_can_spawn_transforms()
		for index in 3:
			var fuel_can := FUEL_PICKUP_SCENE.instantiate() as WorldItemPickup
			fuel_can.setup_spawn({"pickup_name": "StandaloneFuelCan" if index == 0 else "ReserveFuelCan%d" % index, "item_type": GamePlayer.FUEL_ITEM, "item_state": {"fuel_liters": 20.0}, "transform": fuel_transforms[index]})
			add_child(fuel_can)
	for index in EXTRA_LOOT.size():
		var loot: Dictionary = EXTRA_LOOT[index]
		var scene: PackedScene = FLASHLIGHT_PICKUP_SCENE if loot.type == &"flashlight" else preload("res://scenes/objects/items/battery_pickup.tscn") if loot.type == &"battery" else preload("res://scenes/objects/items/weapon_pickup.tscn")
		var item := scene.instantiate() as WorldItemPickup
		item.setup_spawn({"pickup_name": "ExtraLoot%d" % index, "item_type": loot.type, "item_state": loot.state, "transform": loot_transform(loot)})
		add_child(item)


## Shared editor markers for both F6 and the authoritative session spawner.
func get_flamethrower_loot() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for marker: Marker3D in $FlamethrowerLootSpawns.get_children():
		result.append({"type": StringName(marker.get_meta("item_type")), "transform": marker.global_transform, "state": {}})
	return result


## Authored editor markers; the session owns spawning and persistence.
func get_supply_loot() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for marker: Marker3D in $BaseSupplySpawns.get_children():
		result.append({"type": StringName(marker.get_meta("item_type")), "transform": marker.global_transform, "state": marker.get_meta("item_state", {}).duplicate(true)})
	return result
