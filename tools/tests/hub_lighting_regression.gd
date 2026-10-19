extends SceneTree
## Real hub geometry, light budgeting and both electrical circuits.
var failures := 0

func _initialize() -> void:
	ProjectSettings.set_setting(BaseGameplayController.TEST_SAVE_PATH_SETTING, "user://hub_lighting_test.cfg")
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	print("PASS " if ok else "FAIL ", label)
	if not ok: failures += 1

func run() -> void:
	var level: Node3D = load("res://scenes/levels/Base_Blockout_v03.tscn").instantiate()
	level.network_runtime_managed = true
	root.add_child(level)
	var state: BaseGameplayController = level.get_node("BaseGameplayController")
	state.set_process(false)
	state.containment = {"fault": false}
	var lighting: WorldLighting = level.get_node("WorldLighting")
	lighting.set_process(false)
	var power: BasePowerLightingController = level.get_node("BasePowerLightingController")
	await process_frame
	await physics_frame
	await physics_frame
	check(not lighting.has_node("Standard/OmniLight3D"), "temporary omni light no longer bypasses the lamp budget")
	var fixtures: Node = lighting.get_node("HubFixtures")
	check(fixtures._materials.size() >= 4, "all four existing modular fixtures have isolated emission materials")
	var fixture_root: Node = fixtures.get_node(fixtures.fixtures_path)
	check(bool(fixture_root.get_meta("dynamic_emission", false)), "future GI bakes exclude the controllable fixture emission")
	for mesh: MeshInstance3D in fixture_root.find_children("*", "MeshInstance3D", true, false):
		for surface in mesh.mesh.get_surface_count():
			var source := mesh.mesh.surface_get_material(surface) as StandardMaterial3D
			if source != null and source.emission_enabled:
				check(mesh.get_active_material(surface) != source, "fixture has a separate material from the modular asset library")
	var lamps: Array[SpotLight3D] = []
	for circuit in ["Standard", "Emergency"]:
		var count := 0
		for lamp: SpotLight3D in lighting.get_node(circuit).get_children():
			if not str(lamp.name).begins_with("Hub"): continue
			count += 1
			lamps.append(lamp)
			check((-lamp.global_basis.z).dot(Vector3.DOWN) > 0.99, circuit + "/" + str(lamp.name) + " faces the floor")
			var target := Vector3(signf(lamp.global_position.x) * 5.3, 1.2, signf(lamp.global_position.z) * 5.3)
			var offset := target - lamp.global_position
			var query := PhysicsRayQueryParameters3D.create(lamp.global_position, target, 1)
			check(offset.length() < lamp.spot_range and (-lamp.global_basis.z).angle_to(offset) < deg_to_rad(lamp.spot_angle) and level.get_world_3d().direct_space_state.intersect_ray(query).is_empty(), circuit + "/" + str(lamp.name) + " reaches its sector without ceiling or elevator obstruction")
		check(count == 4, circuit + " covers all four hub sectors")
	for powered in [true, false, true]:
		power.apply_power_state(powered)
		for step in 20: lighting._update_lamps(Vector3(-5, 1.8, 0), 0.05)
		var correct := true
		for lamp in lamps:
			var active := lamp.get_parent().name == ("Standard" if powered else "Emergency")
			correct = correct and (lamp.light_energy > 0.0 if active else is_zero_approx(lamp.light_energy))
		check(correct, "hub sources follow restored power" if powered else "outage extinguishes normal sources and enables backup")
		check(lighting._resident_lamps.size() <= WorldLighting.MAX_RESIDENT_LAMPS, "hub respects the existing light budget")
		for entry in fixtures._materials:
			var material: StandardMaterial3D = entry.material
			check(material.emission_enabled and (material.emission.is_equal_approx(entry.color) if powered else material.emission.is_equal_approx(Color(1, 0.12, 0.035))), "fixture emission follows the electrical circuit")
	lighting.get_node("Standard").hide()
	lighting.get_node("Emergency").hide()
	var dark := true
	for entry in fixtures._materials: dark = dark and not entry.material.emission_enabled
	check(dark, "fixtures extinguish when both circuits are disabled")
	level.queue_free()
	for frame in 5: await process_frame
	print("HUB LIGHTING FAILURES ", failures)
	quit(1 if failures else 0)
