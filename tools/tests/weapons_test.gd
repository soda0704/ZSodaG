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
	player.teleport_authoritative(Vector3(-35, 0.1, 4.35), -PI/2.0)
	var target: Node3D = world.get_node("V3Level/WeaponRange/Target1")
	player.head.look_at(target.global_position)
	await physics_frame
	check(player.pickup_world_item_authoritative(&"pistol", {}), "Pistol pickup")
	check(weapon.rounds == 12, "Pistol has 12-round magazine")
	check(weapon.perform_action(&"fire"), "Pistol fires")
	check(weapon.rounds == 11, "Firing consumes one round")
	check(not weapon.perform_action(&"fire"), "Server enforces fire rate")
	check(target.health < 100.0, "Hitscan damages target")
	await capture("pistol")
	check(weapon.perform_action(&"reload"), "Reload starts")
	check(not weapon.perform_action(&"fire"), "Cannot fire during reload")
	check(not weapon.perform_action(&"reload"), "Cannot stack reloads")
	check(weapon.rounds == 11, "Reload does not fill instantly")
	await create_timer(1.5).timeout
	check(weapon.rounds == 12, "Reload fills from infinite reserve")
	weapon.rounds = 0
	weapon._cooldown = 0.0
	check(not weapon.perform_action(&"fire"), "Empty magazine cannot fire")
	check(weapon.perform_action(&"reload"), "Empty magazine reloads")
	player.pickup_world_item_authoritative(&"m4a1", {})
	await create_timer(2.2).timeout
	check(weapon.kind == &"m4a1" and weapon.rounds == 30, "Switch interrupts old reload")
	await capture("m4a1")
	if visual:
		print("WEAPON_PREVIEW camera=", root.get_camera_3d().global_transform, " pose=", weapon._pose.global_transform, " visible=", weapon._pose.is_visible_in_tree())
	check(weapon.perform_action(&"fire"), "Rifle fires")
	await create_timer(0.12).timeout
	check(weapon.perform_action(&"fire") and weapon.rounds == 28, "Rifle automatic cadence")
	var saved: Dictionary = player.get_inventory_snapshot()
	check(saved.weapon_rounds == 28, "Magazine is in checkpoint snapshot")
	var dropped: Dictionary = player.get_held_item_state()
	check(dropped.rounds == 28, "Dropped magazine retains ammo")
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
