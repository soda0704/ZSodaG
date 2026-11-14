class_name PlayerInventoryActions
extends RefCounted
## Stateless inventory commands. Equipment, supplies and weapons own their data.


static func pickup_world_item_authoritative(player: GamePlayer,
	item_type: StringName,
	item_state: Dictionary
) -> bool:
	if not player.multiplayer.is_server() or player.survival.dead or player.is_bunk_busy() or player.is_driving() or player.is_climbing() or player.is_carrying_corpse() or player.get_node("ItemDrag").is_heavy_carrying():
		return false
	var stacks := item_type in [&"journal",&"battery",&"pistol_ammo",&"rifle_magazine",&"tape"] or player.CRAFT_RECIPE.pickup_scenes.has(item_type)
	if not stacks and player._held_item_type not in [player.NO_ITEM,player.FLASHLIGHT_ITEM] and ItemDropPlacement.find_pose(player,get_item_pickup_scene(player, player._held_item_type),player._held_item_type,get_held_item_drop_transform(player))==null: return false
	if item_type == &"journal":
		if player.has_journal: return false
		player.has_journal = true
		player._publish_inventory()
		return true

	if item_type == &"pistol_ammo":
		var amount := int(item_state.get("amount", 12))
		if amount <= 0 or player.weapon.pistol_ammo + amount > 240:
			return false
		player.weapon.pistol_ammo += amount
		player._publish_inventory()
		return true
	if item_type == &"rifle_magazine":
		var amount := int(item_state.get("rounds", 30))
		if amount <= 0 or amount > 30 or player.weapon.rifle_magazines.size() >= 10:
			return false
		player.weapon.rifle_magazines.append(amount)
		player._publish_inventory()
		return true

	if item_type in [player.BATTERY_ITEM, &"tape", &"crowbar"] or player.CRAFT_RECIPE.pickup_scenes.has(item_type):
		if not player._supplies.try_add(item_type, item_state, player.CRAFT_RECIPE.pickup_scenes, player.MAX_SPARE_BATTERIES): return false
		player._publish_inventory()
		return true

	if item_type not in [player.FLASHLIGHT_ITEM, player.FUSE_ITEM, player.FUEL_ITEM, player.SEED_ITEM, &"flamethrower"] and not WeaponController.TYPES.has(item_type):
		return false
	if item_type == player.FLASHLIGHT_ITEM:
		if player.weapon_light_mounted or player._battery_action_busy:
			return false
		if player._has_flashlight:
			spawn_dropped_item_authoritative(player, player.FLASHLIGHT_ITEM, {"battery_charge": player._battery_charge, "malfunctioning": player._flashlight_malfunctioning})
		player._has_flashlight = true
		player._battery_charge = clampf(float(item_state.get("battery_charge", 1.0)), 0.0, 1.0)
		if player._held_item_type == player.NO_ITEM:
			player._held_item_type = player.FLASHLIGHT_ITEM
		player._handheld_flashlight_drawn = player._held_item_type not in [player.NO_ITEM, player.FLASHLIGHT_ITEM, &"m4a1", &"flamethrower"]
		player._flashlight_malfunctioning = bool(item_state.get("malfunctioning", false))
		player._flashlight_shake_presses = 0
		player._flashlight_enabled = player._held_item_type not in [&"m4a1", &"flamethrower"] and player._battery_charge > 0.0 and not player._flashlight_malfunctioning
	else:
		var keep_handheld := player.is_handheld_flashlight_drawn()
		# Equipment is pocketed, only another bulky hand item is dropped.
		if player._held_item_type not in [player.NO_ITEM, player.FLASHLIGHT_ITEM]:
			spawn_dropped_item_authoritative(player, player._held_item_type, get_held_item_state(player))
			if player.weapon_light_mounted:
				player._has_flashlight = false
				player._battery_charge = 0.0
				player.weapon_light_mounted = false
		player._held_item_type = item_type
		if item_type == &"flamethrower":
			player.weapon.flame.fuel_liters = clampf(float(item_state.get("fuel_liters",player.weapon.flame.capacity_liters)),0,player.weapon.flame.capacity_liters)
		if item_type == player.FUEL_ITEM:
			player.fuel_liters = clampf(float(item_state.get("fuel_liters", 20.0)), 0.0, 20.0)
		if WeaponController.TYPES.has(item_type):
			if item_state.has("mounted_charge") and item_type != &"kitchen_knife":
				if player._has_flashlight:
					spawn_dropped_item_authoritative(player, player.FLASHLIGHT_ITEM, {"battery_charge": player._battery_charge, "malfunctioning": player._flashlight_malfunctioning})
				player._has_flashlight = true
				player.weapon_light_mounted = item_type == &"m4a1"
				keep_handheld = not player.weapon_light_mounted
				player._battery_charge = clampf(float(item_state.mounted_charge), 0.0, 1.0)
				player._flashlight_malfunctioning = bool(item_state.get("mounted_malfunctioning", false))
			player.weapon.reload_left = 0.0
			player.weapon.rounds = clampi(int(item_state.get("rounds", WeaponController.CAPACITY[item_type])), 0, WeaponController.CAPACITY[item_type])
		player._handheld_flashlight_drawn = keep_handheld and player._has_flashlight and item_type not in [&"m4a1", &"flamethrower"]
		player._flashlight_enabled = (player.weapon_light_mounted or player._handheld_flashlight_drawn) and player._battery_charge > 0.0 and not player._flashlight_malfunctioning
	player._publish_inventory()
	return true

static func perform_inventory_action_authoritative(player: GamePlayer, action: StringName) -> bool:
	if player.is_climbing(): return false
	if player.handoff.is_offering() or player.get_node("ItemDrag").is_heavy_carrying(): return false
	if player.is_driving() or player.is_carrying_corpse():
		return false
	if player.survival.dead:
		return false
	if not player.multiplayer.is_server() or player.is_bunk_busy():
		return false
	if String(action).begins_with("drop_part:"):
		var type := StringName(String(action).trim_prefix("drop_part:"))
		if not player.CRAFT_RECIPE.pickup_scenes.has(type) or int(player.crafting_parts.get(type,0)) <= 0: return false
		player._supplies.try_take(type, {}, player.CRAFT_RECIPE.pickup_scenes)
		spawn_dropped_item_authoritative(player, type,{})
		player._publish_inventory()
		return true
	match action:
		&"refuel_flamethrower":
			return player.weapon.flame.refuel_authoritative()
		&"mount_light":
			if player.tape_count <= 0 or not player._has_flashlight or player.weapon_light_mounted or player._held_item_type != &"m4a1":
				return false
			player._supplies.try_take(&"tape", {}, player.CRAFT_RECIPE.pickup_scenes)
			player.weapon_light_mounted = true
			player._handheld_flashlight_drawn = false
			player._flashlight_enabled = player._battery_charge > 0.0 and not player._flashlight_malfunctioning
		&"detach_light":
			if not player.weapon_light_mounted:
				return false
			player.weapon_light_mounted = false
			player._flashlight_enabled = false
		&"drop_crowbar":
			if player.crowbar_uses <= 0:
				return false
			spawn_dropped_item_authoritative(player, &"crowbar", {"uses": player.crowbar_uses})
			player._supplies.try_take(&"crowbar", {}, player.CRAFT_RECIPE.pickup_scenes)
		&"drop_tape":
			if player.tape_count <= 0:
				return false
			spawn_dropped_item_authoritative(player, &"tape", {})
			player._supplies.try_take(&"tape", {}, player.CRAFT_RECIPE.pickup_scenes)
		&"drop_hand_item":
			return drop_current_item_authoritative(player)
		&"replace_battery":
			if not player._has_flashlight or player._spare_batteries.is_empty():
				return false
			# Choose the fullest cell; replacing never reduces the current charge.
			var best_charge: float = player._spare_batteries.max()
			if best_charge <= player._battery_charge:
				return false
			player._battery_charge = player._supplies.exchange_best_battery(player._battery_charge)
			player._flashlight_enabled = (player.is_handheld_flashlight_drawn() or player.weapon_light_mounted) and not player._flashlight_malfunctioning
		&"shake_flashlight":
			return shake_flashlight_authoritative(player)
		&"drop_battery":
			if player._spare_batteries.is_empty():
				return false
			spawn_dropped_item_authoritative(player, player.BATTERY_ITEM, {"charge_amount": player._supplies.take_last_battery()})
		&"drop_flashlight":
			if not player._has_flashlight:
				return false
			spawn_dropped_item_authoritative(player, player.FLASHLIGHT_ITEM, {"battery_charge": player._battery_charge, "malfunctioning": player._flashlight_malfunctioning})
			player._has_flashlight = false
			player._handheld_flashlight_drawn = false
			player.weapon_light_mounted = false
			player._battery_charge = 0.0
			player._flashlight_enabled = false
			player._flashlight_malfunctioning = false
			if player._held_item_type == player.FLASHLIGHT_ITEM:
				player._held_item_type = player.NO_ITEM
		_:
			return false
	player._publish_inventory()
	return true

static func get_held_item_state(player: GamePlayer) -> Dictionary:
	if player._held_item_type == &"flamethrower":
		return {"fuel_liters":player.weapon.flame.fuel_liters}
	if player._held_item_type == player.FUEL_ITEM:
		return {"fuel_liters": player.fuel_liters}
	if WeaponController.TYPES.has(player._held_item_type):
		var state := {"rounds": player.weapon.rounds}
		if player.weapon_light_mounted:
			state["mounted_charge"] = player._battery_charge
			state["mounted_malfunctioning"] = player._flashlight_malfunctioning
		return state
	if player._held_item_type == player.FLASHLIGHT_ITEM:
		return {"battery_charge": player._battery_charge, "malfunctioning": player._flashlight_malfunctioning}
	return {}

static func get_held_item_drop_transform(player: GamePlayer) -> Transform3D:
	var forward := -player.head.global_basis.z.normalized()
	var start := player.head.global_position
	var desired := start + forward * 0.7 + Vector3.DOWN * 0.35
	# Sweep a conservative item volume, not a ray: never spawn beyond a wall
	# or beneath the floor when looking down next to a surface.
	var shape := SphereShape3D.new()
	shape.radius = 0.3
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis.IDENTITY, start)
	query.motion = desired - start
	query.collision_mask = 1
	query.exclude = [player.get_rid()]
	var fractions := player.get_world_3d().direct_space_state.cast_motion(query)
	if fractions.size() > 0:
		desired = start + query.motion * maxf(fractions[0] - 0.03, 0.0)
	return Transform3D(
		player.head.global_basis.orthonormalized(),
		desired
	)

static func get_held_item_drop_linear_velocity(player: GamePlayer) -> Vector3:
	return player.velocity + -player.head.global_basis.z.normalized() * 1.1

static func drop_current_item_authoritative(player: GamePlayer) -> bool:
	if player.is_climbing(): return false
	if player.get_node("ItemDrag").is_heavy_carrying(): return false
	if player.is_carrying_corpse():
		return player.carried_corpse.drop_from_shoulder(player.owner_peer_id)
	if player.survival.dead:
		return false
	return drop_current_item_at_authoritative(player,
		get_held_item_drop_transform(player),
		get_held_item_drop_linear_velocity(player)
	)

static func drop_current_item_at_authoritative(player: GamePlayer,
	drop_transform: Transform3D,
	drop_velocity: Vector3 = Vector3.ZERO
) -> bool:
	if not player.multiplayer.is_server() or player._held_item_type == player.NO_ITEM:
		return false

	var safe: Variant=ItemDropPlacement.find_pose(player,get_item_pickup_scene(player, player._held_item_type),player._held_item_type,drop_transform)
	if safe==null: return false
	drop_transform=safe
	player.handoff.cancel_authoritative()
	var released := release_held_item_authoritative(player)
	spawn_dropped_item_authoritative(player, released.type, released.state, drop_transform, drop_velocity)
	return true

static func release_held_item_authoritative(player: GamePlayer) -> Dictionary:
	if not player.multiplayer.is_server() or player._held_item_type == player.NO_ITEM: return {}
	var dropped_item_type := player._held_item_type
	var dropped_item_state := get_held_item_state(player)
	var keep_handheld := player.is_offhand_flashlight_drawn()
	player._held_item_type = player.NO_ITEM
	if dropped_item_type == player.FLASHLIGHT_ITEM or player.weapon_light_mounted:
		player.weapon_light_mounted = false
		player._has_flashlight = false
		player._battery_charge = 0.0
	player._handheld_flashlight_drawn = false
	if keep_handheld:
		player._held_item_type = player.FLASHLIGHT_ITEM
	else:
		player._flashlight_enabled = false
		if not player._has_flashlight:
			player._flashlight_malfunctioning = false
	player._publish_inventory()
	return {"type": dropped_item_type, "state": dropped_item_state}

static func drop_all_items_at_authoritative(player: GamePlayer, drop_transform: Transform3D) -> void:
	if not player.multiplayer.is_server():
		return
	player.handoff.cancel_authoritative()
	drop_current_item_at_authoritative(player, drop_transform)
	if player.crowbar_uses > 0:
		spawn_dropped_item_authoritative(player, &"crowbar", {"uses": player.crowbar_uses}, drop_transform, Vector3.ZERO)
	for type in player.crafting_parts:
		for index in int(player.crafting_parts[type]): spawn_dropped_item_authoritative(player, type,{},drop_transform,Vector3.ZERO)
	for index in player.tape_count:
		spawn_dropped_item_authoritative(player, &"tape", {}, drop_transform, Vector3.ZERO)
	if player._has_flashlight:
		spawn_dropped_item_authoritative(player, player.FLASHLIGHT_ITEM, {"battery_charge": player._battery_charge, "malfunctioning": player._flashlight_malfunctioning}, drop_transform, Vector3.ZERO)
	for charge in player._spare_batteries:
		spawn_dropped_item_authoritative(player, player.BATTERY_ITEM, {"charge_amount": charge}, drop_transform, Vector3.ZERO)
	player._has_flashlight = false
	player._handheld_flashlight_drawn = false
	player._battery_charge = 0.0
	player._supplies.clear()
	player._publish_inventory()
	if player.weapon.pistol_ammo > 0:
		spawn_dropped_item_authoritative(player, &"pistol_ammo", {"amount": player.weapon.pistol_ammo}, drop_transform, Vector3.ZERO)
	for magazine: int in player.weapon.rifle_magazines:
		spawn_dropped_item_authoritative(player, &"rifle_magazine", {"rounds": magazine}, drop_transform, Vector3.ZERO)
	player.weapon.pistol_ammo = 0
	player.weapon.rifle_magazines.clear()
	player._publish_inventory()

static func consume_held_item_authoritative(player: GamePlayer, item_type: StringName) -> bool:
	if not player.multiplayer.is_server() or player._held_item_type != item_type:
		return false
	player._held_item_type = player.FLASHLIGHT_ITEM if player.is_offhand_flashlight_drawn() else player.NO_ITEM
	player._handheld_flashlight_drawn = false
	player._publish_inventory()
	return true

static func get_item_pickup_scene(player: GamePlayer, item_type: StringName) -> PackedScene:
	return (
		player.FLASHLIGHT_PICKUP_SCENE
		if item_type == player.FLASHLIGHT_ITEM
		else player.FUSE_PICKUP_SCENE
		if item_type == player.FUSE_ITEM
		else player.SEED_PICKUP_SCENE if item_type == player.SEED_ITEM
		else player.BATTERY_PICKUP_SCENE if item_type == player.BATTERY_ITEM
		else player.FUEL_PICKUP_SCENE if item_type == player.FUEL_ITEM
		else load(player.CRAFT_RECIPE.pickup_scenes[item_type]) if player.CRAFT_RECIPE.pickup_scenes.has(item_type)
		else preload("res://scenes/objects/crafting/flamethrower_pickup.tscn") if item_type == &"flamethrower"
		else preload("res://scenes/objects/items/tool_pickup.tscn") if item_type in [&"tape", &"crowbar"]
		else preload("res://scenes/objects/items/pistol_pickup.tscn") if item_type==&"pistol"
		else preload("res://scenes/objects/items/m4a1_pickup.tscn") if item_type==&"m4a1"
		else preload("res://scenes/objects/items/weapon_pickup.tscn") if WeaponController.TYPES.has(item_type) or item_type in [&"pistol_ammo", &"rifle_magazine"] else null
	)

static func spawn_dropped_item_authoritative(player: GamePlayer,
	item_type: StringName,
	item_state: Dictionary,
	drop_transform_override: Variant = null,
	linear_velocity_override: Variant = null
) -> void:
	if not player.multiplayer.is_server():
		return

	var drop_transform := get_held_item_drop_transform(player)
	if drop_transform_override is Transform3D:
		drop_transform = drop_transform_override as Transform3D
	var safe: Variant=ItemDropPlacement.find_pose(player,get_item_pickup_scene(player, item_type),item_type,drop_transform)
	if safe==null: return
	drop_transform=safe
	var drop_velocity := get_held_item_drop_linear_velocity(player)
	if linear_velocity_override is Vector3:
		drop_velocity = linear_velocity_override as Vector3
	var controller := player.get_tree().get_first_node_in_group(
		"network_gameplay_controller"
	)
	if controller != null and controller.has_method("spawn_dropped_item"):
		controller.call(
			"spawn_dropped_item",
			item_type,
			{
				"item_state": item_state.duplicate(true),
				"transform": drop_transform,
				"linear_velocity": drop_velocity,
				"angular_velocity": Vector3(1.4, 0.8, -1.1),
			}
		)
		return

	var pickup_scene := get_item_pickup_scene(player, item_type)
	if pickup_scene == null or player.get_tree().current_scene == null:
		return
	var pickup := pickup_scene.instantiate() as WorldItemPickup
	pickup.setup_spawn({
		"item_type": item_type,
		"item_state": item_state,
		"transform": player.get_tree().current_scene.global_transform.affine_inverse()*drop_transform,
		"linear_velocity": drop_velocity,
		"angular_velocity": Vector3(1.4, 0.8, -1.1),
	})
	player.get_tree().current_scene.add_child(pickup)
	pickup.global_transform = drop_transform

static func update_authoritative_flashlight_battery(player: GamePlayer, delta: float) -> void:
	if (
		not player.multiplayer.is_server()
		or not player._has_flashlight
		or not player._flashlight_enabled
		or player._battery_charge <= 0.0
	):
		return

	# A stowed light (journal, sleep, two-hand reload) does not spend charge.
	if player._journal_phase > 0 or player.is_bunk_busy() or player.survival.dead or player.is_driving() or player.is_carrying_corpse():
		return
	var light_working := player.weapon._mounted_beam.is_visible_in_tree() if player.weapon_light_mounted else player.flashlight.is_enabled
	if not light_working and player.get_tree().get_first_node_in_group("wiring_ui") == null:
		return
	player._battery_charge = maxf(
		player._battery_charge - delta / maxf(player.battery_duration_seconds, 1.0),
		0.0
	)
	player.flashlight.set_battery_charge(player._battery_charge, false)
	player.update_battery_ui()
	if player._battery_charge <= 0.0:
		player._flashlight_enabled = false
		player._publish_inventory()

static func toggle_flashlight_authoritative(player: GamePlayer) -> bool:
	if player.get_node("ItemDrag").is_heavy_carrying(): return false
	if player.survival.dead or player.is_carrying_corpse() or player.is_driving() or player._battery_action_busy:
		return false
	if not player.multiplayer.is_server() or not player._has_flashlight or player.is_bunk_busy():
		return false
	var result := player._equipment.toggle_flashlight()
	if result == player.EQUIPMENT_SCRIPT.FlashlightResult.POCKETED:
		player._show_pocket_light_notice.rpc_id(player.owner_peer_id)
		return false
	if result != player.EQUIPMENT_SCRIPT.FlashlightResult.CHANGED: return false
	player.player_audio.play_cue.rpc(&"flashlight_on" if player._flashlight_enabled else &"flashlight_off")
	player._publish_inventory()
	return true

static func needs_flashlight_shake(player: GamePlayer) -> bool:
	return (
		player._has_flashlight and player._flashlight_malfunctioning and player._battery_charge > 0.0
		and (player.is_handheld_flashlight_drawn() or player.weapon_light_mounted)
		and not player._battery_action_busy and not player.survival.dead and not player.is_bunk_busy()
		and not player.is_driving() and not player.is_carrying_corpse() and player.weapon.reload_left <= 0.0
	)

static func shake_flashlight_authoritative(player: GamePlayer) -> bool:
	if not player.multiplayer.is_server() or not needs_flashlight_shake(player):
		return false
	var now := Time.get_ticks_msec()
	if now - player._last_flashlight_shake_msec < 120:
		return false
	player._last_flashlight_shake_msec = now
	player._flashlight_shake_presses += 1
	if player._flashlight_shake_presses >= player.FLASHLIGHT_SHAKE_PRESSES:
		player._flashlight_malfunctioning = false
		player._flashlight_shake_presses = 0
		player._flashlight_enabled = true
		player.player_audio.play_cue.rpc(&"flashlight_on")
	player._publish_inventory()
	return true
