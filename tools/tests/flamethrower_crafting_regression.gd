extends SceneTree
const RECIPE = preload("res://assets/config/flamethrower_recipe.tres")
var checks:=0
var failures:=0
var base: Node3D
var state: BaseGameplayController
var player: GamePlayer
var bench: HeavyCarryProp
func _initialize() -> void:
	ProjectSettings.set_setting(BaseGameplayController.TEST_SAVE_PATH_SETTING,"user://crafting_%d.cfg" % OS.get_process_id())
	run.call_deferred()
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failures+=1
	print("PASS " if ok else "FAIL ",label)
func settle(frames:=8) -> void:
	for frame in frames: await physics_frame
func aim(target: Vector3) -> void:
	var offset := target-player.head.global_position
	player.rotation.y=atan2(-offset.x,-offset.z)
	player.head.rotation.x=atan2(offset.y,Vector2(offset.x,offset.z).length())
func approach_bench(side := -1.0) -> void:
	var approach := bench.global_position + bench.global_basis.x.normalized() * side * 1.6
	approach.y = .04
	player.teleport_authoritative(approach,0)
	await settle()
	aim(bench.get_interaction_position())
func run() -> void:
	base=load("res://scenes/levels/Base_Blockout_v03.tscn").instantiate(); root.add_child(base); current_scene=base
	await settle()
	root.get_node("GameMenu").force_close_menu()
	state=base.get_node("BaseGameplayController"); state.set_process(false)
	player=get_first_node_in_group("local_player"); player.set_physics_process(false); player.survival.set_physics_process(false)
	player.survival.debug_invincible=true
	bench=base.get_node("FlamethrowerWorkbench")
	var journal = root.get_node("QuestJournal"); journal._bind_controller(); journal._refresh_inventory()
	check(not journal._cards[&"flame_recipe"].visible,"recipe is hidden before hive discovery")
	await approach_bench()
	check(player.get_interaction_target()==bench,"existing equipment table is reachable through native E ray")
	check(bench.get_interaction_prompt()=="" and not bench.craft_authoritative(player),"bench cannot craft before discovery")
	var original := []
	for node in get_nodes_in_group("world_items"):
		if String(node.name).begins_with("CraftLoot"): original.append(node)
	check(original.size()==18,"floor four contains two complete part sets and four extra tapes")
	await settle(50)
	for node in original:
		check(node.global_position.y > -72.5 and node.global_position.y < -70,"authored loot %s remains on level four" % node.name)
		var center: Vector3=node.get_node("CollisionShape3D").global_position
		for side in [Vector3(0,0,1.2),Vector3(0,0,-1.2),Vector3(1.2,0,0),Vector3(-1.2,0,0)]:
			player.teleport_authoritative(Vector3(center.x,-71.95,center.z)+side,0); await settle(2); aim(center)
			if player.get_interaction_target()==node: break
		if player.get_interaction_target()!=node: print("RAY_BLOCKER ",node.name," ",player.get_interaction_target()," ",player.interaction_ray.get_collision_point())
		check(player.get_interaction_target()==node,"native pickup ray reaches "+String(node.name))
		# Real E uses ItemDrag's tap-on-release path before reaching the inventory.
		# A direct try_authoritative_interaction() used to miss floor-pivot rejection.
		var drag = player.get_node("ItemDrag")
		if node.item_type in [&"flame_pipe_bundle",&"flame_hardware_box"]:
			var wall: StaticBody3D=load("res://tools/tests/fixtures/flame_test_wall.tscn").instantiate()
			base.add_child(wall);wall.global_position=(player.head.global_position+node.get_interaction_position())*.5
			await settle(2)
			check(drag._valid_item(node.get_path())==null,"real wall blocks component tap "+String(node.name))
			drag._pickup(node.get_path())
			check(not node._collected,"blocked tap cannot collect through wall "+String(node.name))
			wall.queue_free();await settle(2)
		check(drag.begin_interaction(),"E tap captures component "+String(node.name))
		check(drag._valid_item(node.get_path())==node,"tap pickup sees body above its supporting surface "+String(node.name))
		if DisplayServer.get_name()=="headless":
			# Headless windows cannot capture the mouse; still exercise the exact tap handler.
			drag._pickup(drag.pending);drag.cancel()
		else:
			Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
			Input.action_release("interact")
			drag._physics_process(.016)
		await settle(2)
		check(not is_instance_valid(node) or node._collected,"E collects component "+str(center))
	for type in RECIPE.requirements:
		check(int(RECIPE.available(player).get(type,0))>=2,"two recipes own "+String(type))
	var inventory := player.get_inventory_snapshot(); player.apply_inventory_snapshot(inventory)
	check(RECIPE.can_craft(player),"component inventory survives snapshot restoration")
	var part_type: StringName=&"flame_valve"
	var before: int=player.crafting_parts[part_type]
	check(player.perform_inventory_action_authoritative(&"drop_part:flame_valve"),"component can be dropped for a partner")
	check(int(player.crafting_parts[part_type])==before-1,"dropping spends one component")
	player.pickup_world_item_authoritative(part_type,{})
	state.debug_set_day_authoritative(7)
	var snapshot := state.get_snapshot(); snapshot.containment["cave_hives_found"]=true; snapshot.containment["cave_visited"]=true; snapshot.main_breaker_on=true; snapshot.fuel_liters=30.0
	state._broadcast_snapshot(snapshot)
	journal._refresh_content(); journal._select_item(&"flame_recipe")
	check(journal._cards[&"flame_recipe"].visible and journal._cards[&"tape"].visible,"discovery exposes native recipe and requirement cards")
	check("Собрать огнемёт" in str(journal.get_hud_summary().tasks),"HUD receives assembly objective after discovery")
	await approach_bench()
	var saved_parts: Dictionary=player.crafting_parts.duplicate()
	player.crafting_parts.erase(&"flame_pressure_gauge")
	check(not bench.craft_authoritative(player) and bench.crafted_count()==0,"missing gauge cannot consume other components")
	player.crafting_parts=saved_parts
	var parts_before_outage := player.crafting_parts.duplicate()
	var outage := state.get_snapshot()
	outage.main_breaker_on=false
	state._broadcast_snapshot(outage)
	check(not bench.craft_authoritative(player) and player.crafting_parts==parts_before_outage,"unpowered workbench cannot consume parts or craft")
	check(not bench.get_node("WorkbenchVisual").material_override.emission_enabled,"native workbench animation turns indicators off without power")
	outage.main_breaker_on=true
	state._broadcast_snapshot(outage)
	check(bench.get_node("WorkbenchVisual").material_override.emission_enabled,"native workbench animation restores powered indicators")
	var crafting_drag = player.get_node("ItemDrag")
	check(crafting_drag.begin_interaction(),"E tap captures the movable powered workbench")
	crafting_drag._pickup(bench.get_path())
	crafting_drag.cancel()
	check(bench.crafted_count()==1,"first real table interaction assembles flamethrower")
	check(player.has_held_item(&"flamethrower") and bench.crafted_count()==1,"first finished item is awarded to hands")
	check(not player.weapon.perform_action(&"fire") and not player.weapon.perform_action(&"reload"),"generic bullet controller cannot fire or reload the continuous-jet item")
	var gun_inventory:=player.get_inventory_snapshot(); player.apply_inventory_snapshot(gun_inventory)
	check(player.has_held_item(&"flamethrower"),"finished item survives inventory restoration")
	check(player.drop_current_item_authoritative(),"finished item can be dropped")
	await settle(2)
	# The dropped weapon may obstruct the old aim ray; approach the opposite
	# end rather than granting the craft interaction through a physical item.
	await approach_bench(1.0)
	check(bench.craft_authoritative(player) and bench.crafted_count()==2,"second recipe produces second flamethrower")
	for type in RECIPE.pickup_scenes: player.pickup_world_item_authoritative(type,{})
	var extras := player.crafting_parts.duplicate()
	check(not bench.craft_authoritative(player) and player.crafting_parts==extras,"global two-item limit does not consume excess parts")
	var saved := state.load_saved_snapshot()
	check(int(saved.maintenance.flamethrower_crafting.crafted)==2,"global assembly count persists in expedition state")
	# Both character variants have native equipment instances and support-hand markers.
	for rig in ["tactical_a","tactical_b"]:
		for kind in ["body","first_person"]:
			var model: Node3D=load("res://scenes/characters/visuals/"+rig+"/"+kind+".tscn").instantiate()
			check(model.has_node("Skeleton3D/RightHand/Equipment/flamethrower/LeftHandGrip"),rig+" "+kind+" has authored held item")
			model.free()
	if DisplayServer.get_name()!="headless":
		journal.open_journal(); journal._select_item(&"flame_recipe")
		for frame in 25: await process_frame
		await RenderingServer.frame_post_draw
		journal._ink_viewport.get_texture().get_image().save_png(OS.get_environment("TEMP").path_join("NorthernLab-crafting-journal.png"))
	print("FLAMETHROWER CRAFT CHECKS ",checks," FAILURES ",failures)
	journal.force_close(); base.queue_free(); await process_frame; await process_frame
	quit(1 if failures else 0)
