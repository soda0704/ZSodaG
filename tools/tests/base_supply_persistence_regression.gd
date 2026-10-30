extends SceneTree
var checks := 0
var failures := 0

func _initialize() -> void:
	var isolated := "user://base_supplies_%d" % OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(isolated))
	ProjectSettings.set_setting(ExpeditionSaveStore.ROOT_SETTING, isolated + "/slots")
	ProjectSettings.set_setting("northern_lab/testing/legacy_save_paths", {})
	ProjectSettings.set_setting("northern_lab/testing/settings_path", isolated + "/settings.json")
	ProjectSettings.set_setting(BaseGameplayController.TEST_SAVE_PATH_SETTING, "")
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ",label)

func frames(count := 3) -> void:
	for i in count: await physics_frame

func run() -> void:
	var menu = root.get_node("GameMenu")
	await menu.start_standalone_flow()
	var session = current_scene
	await session._enter_v3_level()
	var base = session.get_node("V3Level")
	var builder = load("res://scripts/network/level_load_plan.gd")
	var plan = load(builder.PLAN_PATH)
	check(builder.signature(load(builder.ROOT_PATH), plan.get_meta("chunks")[builder.ROOT_PATH]) == plan.get_meta("signatures")[builder.ROOT_PATH], "exported scene matches staged loading plan instead of slow fallback")
	var state: BaseGameplayController = session._base_gameplay_controller
	state.set_process(false)
	var player: GamePlayer = get_first_node_in_group("local_player")
	player.survival.debug_invincible = true
	var counts := {}
	for item in session.world_items.get_children(): counts[item.item_type] = counts.get(item.item_type,0)+1
	check(int(counts.get(&"fuel_can",0)) == 5,"new expedition has five fuel cans including two new reserves")
	check(int(counts.get(&"pistol",0)) == 2 and int(counts.get(&"m4a1",0)) == 2,"new expedition adds one pistol and one rifle")
	check(base.get_supply_loot().size() == 16,"sixteen supply placements share editor markers in F6 and session")
	for marker in base.get_node("BaseSupplySpawns").get_children():
		var hit: Dictionary = base.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(marker.global_position+Vector3.UP*.05,marker.global_position-Vector3.UP*2,1))
		check(not hit.is_empty() and marker.global_position.y-hit.position.y < .45,"authored item has real supporting furniture/floor: "+str(marker.name))
	var ammo: WorldItemPickup
	for item in session.world_items.get_children():
		if item.item_type == &"pistol_ammo" and int(item.item_state.get("amount",0)) == 24: ammo = item
	check(ammo != null,"new garage ammunition exists")
	if ammo != null:
		player.teleport_authoritative(ammo.global_position+Vector3(0,0,1),0)
		ammo.network_interact(player.owner_peer_id,player)
		await frames()
	check(player.weapon.pistol_ammo == 24,"actual supply pickup transfers its ammunition")
	var before: int = session.world_items.get_child_count()
	var encounter = base.get_node("ContainmentEncounter")
	encounter.get_node("Monster3").apply_weapon_damage(13.0)
	check(state.save_progress_authoritative(),"supply collection and authored patrol damage save")
	check(int(state.inventory_checkpoint.get("base_supply_layout_version",0)) == 1,"checkpoint records supply layout version")
	await menu.start_standalone_flow(true)
	session = current_scene
	base = session.get_node("V3Level")
	state = session._base_gameplay_controller
	state.set_process(false)
	player = get_first_node_in_group("local_player")
	player.survival.debug_invincible = true
	check(session.world_items.get_child_count() == before,"Continue restores world loot without duplicating new supplies")
	check(player.weapon.pistol_ammo == 24,"Continue restores collected ammunition")
	check(is_equal_approx(base.get_node("ContainmentEncounter").get_monster_health(3),72.0),"Continue restores authored head health rather than respawning full HP")
	# Simulate an older checkpoint which already consumed all original world loot.
	var legacy := {"pickups":[],"weapon_layout_version":1,"fuel_layout_version":1,"tools_layout_version":1,"discoverable_layout_version":2,"tape_layout_version":1,"prop_layout_version":1,"elevator_backup_layout_version":1,"flamethrower_parts_layout_version":1}
	for item in session.world_items.get_children(): item.queue_free()
	await frames()
	state.inventory_checkpoint = legacy
	session._v3_items_spawned = false
	session.spawn_v3_world_items()
	check(session.world_items.get_child_count() == 16,"old checkpoint receives only new supply placements")
	state.inventory_checkpoint = session.capture_inventory_checkpoint()
	for item in session.world_items.get_children(): item.queue_free()
	await frames()
	session._v3_items_spawned = false
	session.spawn_v3_world_items()
	check(session.world_items.get_child_count() == 16,"supply migration is idempotent after checkpoint capture")
	state.progress_persistence_enabled = false
	session.queue_free(); await frames(6)
	print("BASE SUPPLY PERSISTENCE CHECKS ",checks," FAILURES ",failures)
	quit(1 if failures else 0)
