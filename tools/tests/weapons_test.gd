extends SceneTree

var failed := false
var visual := false
func _initialize() -> void:
	ProjectSettings.set_setting(BaseGameplayController.TEST_SAVE_PATH_SETTING, "user://weapons_test.cfg")
	visual = OS.get_cmdline_user_args().has("visual")
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	if not value:
		failed = true
		push_error("WEAPONS_TEST: " + message)

func capture(id: String) -> void:
	if not visual:
		return
	await create_timer(0.35).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OS.get_environment("TEMP").path_join("NorthernLab-Weapon-" + id + ".png"))

func _run() -> void:
	BaseGameplayController.delete_progress_save()
	await root.get_node("GameMenu").start_standalone_flow()
	var world := current_scene
	await world._enter_v3_level()
	var player: Node3D = world.get_node("Players/1")
	player.set_physics_process(false)
	player.survival.set_physics_process(false)
	var weapon: Node = player.weapon
	for id: StringName in [&"pistol", &"m4a1", &"kitchen_knife"]:
		var count := 0
		for pickup in world.world_items.get_children():
			if pickup.item_type == id:
				count += 1
		check(count == 1, "Exactly one initial " + str(id))
	var checkpoint: Dictionary = world.capture_inventory_checkpoint()
	check(checkpoint.get("weapon_layout_version", 0) == 1, "Loot migration marker persisted")
	world._base_gameplay_controller.inventory_checkpoint = checkpoint
	for pickup in world.world_items.get_children():
		pickup.free()
	world._v3_items_spawned = false
	world.spawn_v3_world_items()
	check(world.world_items.get_child_count() == checkpoint.pickups.size(), "Reload does not duplicate weapon layout")
	player.teleport_authoritative(Vector3(0, 10, 0), 0.0)
	check(world.get_node("V3Level").get_node_or_null("WeaponRange") == null, "No range fixtures in the game")
	var target: Node3D = load("res://scripts/gameplay/weapon_target.gd").new()
	world.add_child(target)
	target.global_position = Vector3(0, 11.3, -6)
	target.rotation.y = PI/2.0
	var preview_light := OmniLight3D.new()
	player.head.add_child(preview_light)
	preview_light.omni_range = 15.0
	preview_light.light_energy = 3.0
	player.head.look_at(target.global_position)
	await physics_frame
	check(player.pickup_world_item_authoritative(&"pistol", {}), "Pistol pickup")
	check(player.pickup_world_item_authoritative(&"pistol_ammo", {"amount": 24}), "Loose pistol ammunition pickup")
	check(player.pickup_world_item_authoritative(&"rifle_magazine", {"rounds": 30}), "Rifle magazine pickup")
	check(weapon.rounds == 12, "Pistol has 12-round magazine")
	check(weapon.perform_action(&"fire"), "Pistol fires")
	check(weapon.rounds == 11, "Firing consumes one round")
	check(not weapon.perform_action(&"fire"), "Server enforces fire rate")
	check(target.health < 100.0, "Hitscan damages target")
	var second_player := preload("res://scenes/characters/player.tscn").instantiate()
	second_player.setup(2, "Friendly fire target", Vector3(3, 10, 0), Color.WHITE)
	world.get_node("Players").add_child(second_player)
	second_player.set_physics_process(false)
	second_player.survival.set_physics_process(false)
	second_player.apply_weapon_damage(35.0)
	check(
		is_equal_approx(second_player.survival.health, 65.0),
		"Authoritative weapon damage applies to another network player"
	)
	await capture("pistol")
	check(weapon.perform_action(&"reload"), "Reload starts")
	check(not weapon.perform_action(&"fire"), "Cannot fire during reload")
	check(not weapon.perform_action(&"reload"), "Cannot stack reloads")
	check(weapon.rounds == 11, "Reload does not fill instantly")
	await create_timer(1.5).timeout
	check(weapon.rounds == 12 and weapon.pistol_ammo == 23, "Reload consumes only the missing pistol rounds")
	weapon.pistol_ammo = 0
	weapon.rounds = 5
	check(not weapon.perform_action(&"reload"), "No reload without reserve")
	weapon.pistol_ammo = 23
	weapon.rounds = 0
	weapon._cooldown = 0.0
	check(not weapon.perform_action(&"fire"), "Empty magazine cannot fire")
	check(weapon.perform_action(&"reload"), "Empty magazine reloads")
	player.pickup_world_item_authoritative(&"m4a1", {})
	await create_timer(2.2).timeout
	check(weapon.kind == &"m4a1" and weapon.rounds == 30, "Switch interrupts old reload")
	await capture("m4a1")
	if visual:
		print("WEAPON_PREVIEW hud=", weapon._hud.get_global_rect(), " visible=", weapon._hud.is_visible_in_tree(), " menu=", root.get_node("GameMenu").is_menu_open())
	check(weapon.perform_action(&"fire"), "Rifle fires")
	await create_timer(0.12).timeout
	check(weapon.perform_action(&"fire") and weapon.rounds == 28, "Rifle automatic cadence")
	var saved: Dictionary = player.get_inventory_snapshot()
	check(weapon.perform_action(&"reload"), "Magazine replacement starts")
	await create_timer(2.2).timeout
	check(weapon.rounds == 30 and weapon.rifle_magazines.has(28), "Partial rifle magazine returns to reserve")
	check(saved.weapon_rounds == 28, "Magazine is in checkpoint snapshot")
	var dropped: Dictionary = player.get_held_item_state()
	check(dropped.rounds == 30, "Dropped magazine retains ammo")
	player.pickup_world_item_authoritative(&"kitchen_knife", {})
	await create_timer(0.2).timeout
	check(not weapon.perform_action(&"reload"), "Knife has no reload")
	check(weapon.perform_action(&"fire"), "Knife attacks")
	await capture("knife")
	player.teleport_authoritative(target.global_position + Vector3(-1.0, -1.2, 0), -PI/2.0)
	player.head.look_at(target.global_position)
	await create_timer(0.6).timeout
	target._sync(100.0)
	check(weapon.perform_action(&"fire") and target.health == 50.0, "Knife damages within reach")
	saved.revision = player.get_inventory_snapshot().revision + 1
	player.apply_inventory_snapshot(saved)
	check(weapon.kind == &"m4a1" and weapon.rounds == 28, "Snapshot restores weapon and ammo")
	weapon.perform_action(&"reload")
	player.survival.damage(100.0, "Weapon test")
	await create_timer(2.2).timeout
	check(weapon.rounds == 28 and weapon.reload_left == 0.0, "Death cancels reload without giving ammo")
	check(not weapon.perform_action(&"fire"), "Dead players cannot attack")
	world.free()
	BaseGameplayController.delete_progress_save()
	print("WEAPONS_TEST: " + ("FAIL" if failed else "PASS"))
	quit(1 if failed else 0)
