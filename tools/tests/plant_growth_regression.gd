extends "res://tools/tests/plant_watering_regression.gd"

func fixture(day: int, planted: bool, stage: int, dead: bool = false) -> void:
	var snapshot := state.get_snapshot()
	snapshot.day_index = day
	snapshot.phase = BaseGameplayController.BasePhase.ACTIVE_DAY
	snapshot.main_breaker_on = true
	snapshot.fuel_delivered = true
	snapshot.fuel_liters = 40
	snapshot.elevator_backup_installed = true
	snapshot.maintenance = {}
	snapshot.quest_stage = BaseGameplayController.QuestStage.DELIVERED
	snapshot.containment = {"level2":true,"trials":true,"level3":true,"resolved":true,"shaft":true,"cave_exited":true}
	snapshot.plant_seed_planted = planted
	snapshot.plant_growth_stage = stage
	snapshot.plant_withered = dead
	snapshot.plant_last_watered_day = 0
	snapshot.end_day_ready_peer_ids = []
	snapshot.sleeping_peer_ids = []
	state._broadcast_snapshot(snapshot)

func sleep_once() -> bool:
	return state.set_end_day_ready_authoritative(1, true) and state.set_peer_sleeping_authoritative(1, true) and state.advance_day_authoritative()

func visible_stages(kind: String) -> Array[int]:
	var result: Array[int] = []
	var nodes := container.get_node("PlantGrowth/" + kind)
	for index in nodes.get_child_count():
		if (nodes.get_child(index) as Node3D).visible: result.append(index + 1)
	return result

func run() -> void:
	Engine.max_fps = 60
	await boot()
	var lamp := container.get_node("UVLamp")
	var emitter := lamp.get_node("Emitter") as MeshInstance3D
	check(not lamp.get_node("Active").visible and not (emitter.material_override as StandardMaterial3D).emission_enabled, "UV fixture starts dark without base power")
	fixture(1, false, 0)
	check(lamp.get_node("Active").visible and (emitter.material_override as StandardMaterial3D).emission_enabled, "main power enables native UV light and emissive tube")
	var fault := state.get_snapshot()
	fault.containment["fault"] = true
	state._broadcast_snapshot(fault)
	check(not lamp.get_node("Active").visible and not (emitter.material_override as StandardMaterial3D).emission_enabled, "lighting circuit fault extinguishes UV light and glow")
	fault.containment.erase("fault")
	state._broadcast_snapshot(fault)
	check(lamp.get_node("Active").visible, "cleared lighting fault restores UV fixture")
	check(state.deactivate_main_breaker_authoritative(1) and not lamp.get_node("Active").visible, "actual breaker shutdown extinguishes UV fixture")
	for stage in [6,7]:
		var plant := container.get_node("PlantGrowth/Dead/Stage%d"%stage)
		var bounds:AABB
		var first := true
		for visual in plant.get_children():
			if visual is MeshInstance3D:
				var box: AABB = plant.transform * visual.transform * visual.get_aabb()
				bounds = box if first else bounds.merge(box)
				first = false
		check(plant.has_node("HeadVolume") and bounds.size.z <= .2, "dry stage %d gains head volume while fitting chamber depth"%stage)
	fixture(1, false, 0)
	check(sleep_once() and not state.plant_withered and state.plant_growth_stage == 0, "unplanted soil does not dry into a dead plant")
	fixture(1, true, 0)
	check(not state.advance_day_authoritative(), "growth cannot bypass sleep consensus")
	for expected in range(1, 8):
		# Resolve the existing day-two outage and story goals independently of plant care.
		powered()
		var goals := state.get_snapshot()
		goals.quest_stage = BaseGameplayController.QuestStage.DELIVERED
		state._broadcast_snapshot(goals)
		await visit()
		check(state.water_plant_authoritative(1), "shared watering before growth stage %d" % expected)
		check(state.plant_growth_stage == expected - 1 and not state.water_plant_authoritative(1), "watering alone cannot advance or repeat stage %d" % expected)
		check(sleep_once() and state.plant_growth_stage == expected and not state.plant_withered, "one real sleep advances exactly to stage %d" % expected)
		check(visible_stages("Live") == [expected] and visible_stages("Dead").is_empty(), "native scene selects only live stage %d" % expected)
		check(not container.get_node("PlantedSeed").visible, "sprout replaces planting seed at stage %d" % expected)
	check(state.day_index == 8 and state.plant_growth_stage == 7, "day one sowing reaches full growth on day eight")
	check(state.load_saved_snapshot().plant_growth_stage == 7, "growth is persisted in host save")
	base.queue_free()
	await process_frame
	await boot()
	check(state.day_index == 8 and visible_stages("Live") == [7], "re-entering day eight restores mature native model")
	await visit()
	check(state.water_plant_authoritative(1) and sleep_once() and state.day_index == 9 and state.plant_growth_stage == 7, "post-expedition sleep continues while mature growth remains capped")
	for stage in range(0, 8):
		fixture(8, true, stage)
		check(sleep_once() and state.plant_withered and state.plant_growth_stage == stage, "missed watering dries stage %d next morning" % stage)
		check(visible_stages("Dead") == [maxi(stage,1)] and visible_stages("Live").is_empty(), "matching dry model replaces live stage %d" % stage)
		await visit()
		check(not state.water_plant_authoritative(1) and button.get_interaction_hint_for(player).is_empty(), "withered stage %d cannot be revived by watering" % stage)
		check(sleep_once() and state.plant_withered, "further sleep cannot revive stage %d" % stage)
	check(state.load_saved_snapshot().plant_withered, "withered state persisted")
	fixture(9, true, 0)
	await visit()
	check(state.water_plant_authoritative(1) and sleep_once() and state.plant_growth_stage == 1, "late planting ages from planting, not calendar day")
	fixture(6, false, 0)
	var data := state.get_snapshot()
	data.containment.erase("shaft")
	data.containment.erase("cave_exited")
	state._broadcast_snapshot(data)
	check(not state.can_end_current_day(), "day six needs actual shaft visit")
	var shaft := base.get_node("Floor_Minus5_Expedition_Shaft_Blockout/InvestigationZone") as Area3D
	player.teleport_authoritative(shaft.global_position - Vector3(0,1.9,0), 0)
	await settle()
	check(state.containment.get("shaft",false) and state.can_end_current_day(), "authored shaft area unlocks ordinary sleep")
	check(sleep_once() and state.day_index == 7 and not state.can_end_current_day(), "day seven cannot sleep before cave exit")
	var exit := base.get_node("Cave_Day7/ExitZone") as Area3D
	player.survival.dead = true
	player.teleport_authoritative(exit.global_position - Vector3(0,1.9,0), 0)
	await settle()
	check(not state.containment.get("cave_exited",false), "dead body cannot complete cave exit")
	player.teleport_authoritative(exit.global_position + Vector3(0,0,12), 0)
	await settle()
	player.survival.dead = false
	player.teleport_authoritative(exit.global_position - Vector3(0,1.9,0), 0)
	await settle()
	check(state.containment.get("cave_exited",false) and state.can_end_current_day(), "actual living player exit silently unlocks sleep")
	check(sleep_once() and state.day_index == 8 and sleep_once() and state.day_index == 9, "cave completion permits repeat ordinary sleep after seventh day")
	state.reset_day_one_authoritative()
	check(not state.plant_withered and state.plant_growth_stage == 0 and not state.plant_seed_planted, "new expedition resets complete plant lifecycle")
	base.queue_free()
	await process_frame
	print("PLANT GROWTH CHECKS ",checks," FAILURES ",failures)
	quit(1 if failures else 0)
