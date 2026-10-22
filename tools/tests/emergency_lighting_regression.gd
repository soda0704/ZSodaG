extends SceneTree
## Real backup circuit: continuous clock, fixture emission, residency and repair.
var failures := 0

func _initialize() -> void:
	ProjectSettings.set_setting(BaseGameplayController.TEST_SAVE_PATH_SETTING, "res://tools/.local/emergency_lighting_test.cfg")
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	print("PASS " if ok else "FAIL ", label)
	if not ok: failures += 1

func run() -> void:
	var level: Node3D = load("res://scenes/levels/Base_Blockout_v03.tscn").instantiate()
	level.network_runtime_managed = true
	var lighting: WorldLighting = level.get_node("WorldLighting")
	var red := true
	var omni_count := 0
	var backup_lamps := lighting.get_node("Emergency").get_children()
	for lamp: Light3D in backup_lamps:
		red = red and lamp.light_color.is_equal_approx(WorldLighting.EMERGENCY_COLOR)
		if lamp is OmniLight3D: omni_count += 1
	check(backup_lamps.size() == 49 and red, "all 49 authored emergency sources are red before runtime")
	check(omni_count == 36, "backup combines 36 volume sources with 13 directed sources")
	root.add_child(level)
	lighting.set_process(false)
	var state: BaseGameplayController = level.get_node("BaseGameplayController")
	state.progress_persistence_enabled = false
	state.set_process(false)
	state.containment = {"fault": false}
	var power: BasePowerLightingController = level.get_node("BasePowerLightingController")
	for frame in 15: await physics_frame
	var fixtures: Node = lighting.get_node("HubFixtures")
	var at := Vector3(-5.0, 1.8, 0.0)
	power.apply_power_state(false)
	lighting._update_lamps(at, 1.0)
	var minimum := 1.0
	var maximum := 0.0
	var previous := lighting.emergency_intensity
	var smooth := true
	var synchronized := true
	var budget := true
	var stable_membership: Array[Light3D] = lighting._resident_lamps.duplicate()
	for step in 240:
		lighting._advance_emergency(1.0 / 60.0)
		lighting._update_lamps(at, 1.0 / 60.0)
		var intensity := lighting.emergency_intensity
		minimum = minf(minimum, intensity)
		maximum = maxf(maximum, intensity)
		smooth = smooth and absf(intensity - previous) < 0.04
		previous = intensity
		for lamp: Light3D in lighting._resident_lamps:
			if lighting._emergency_lamps.has(lamp):
				var expected := float(lighting._energies[lamp]) * float(lighting._levels[lamp]) * intensity
				synchronized = synchronized and is_equal_approx(lamp.light_energy, expected)
		for entry in fixtures._materials:
			synchronized = synchronized and entry.material.emission.is_equal_approx(WorldLighting.EMERGENCY_COLOR)
			synchronized = synchronized and is_equal_approx(entry.material.emission_energy_multiplier, float(entry.energy) * 0.25 * intensity)
		var slots := 0
		for lamp: Light3D in lighting._resident_lamps: slots += WorldLighting.shadow_slot_cost(lamp)
		budget = budget and slots <= WorldLighting.MAX_RESIDENT_SHADOW_SLOTS and lighting._resident_lamps == stable_membership and lighting._resident_lamps.size() <= WorldLighting.MAX_RESIDENT_LAMPS
	check(minimum < 0.151 and maximum > 0.999, "backup visibly dims and brightens over two complete two-second cycles")
	check(smooth, "pulse has continuous transitions without abrupt flashes")
	check(synchronized and not fixtures._materials.is_empty(), "all resident backup lamps and physical hub fixtures share the same phase")
	check(budget and lighting.get_node("Emergency").visible, "blinking never toggles the power circuit or reallocates shadow slots")
	power.apply_power_state(true)
	lighting._update_lamps(at, 1.0)
	var steady := true
	for step in 120:
		lighting._advance_emergency(1.0 / 60.0)
		lighting._update_lamps(at, 1.0 / 60.0)
		for lamp: Light3D in lighting._resident_lamps:
			if not lighting._emergency_lamps.has(lamp):
				steady = steady and is_equal_approx(lamp.light_energy, float(lighting._energies[lamp]) * float(lighting._levels[lamp]))
		for entry in fixtures._materials:
			steady = steady and entry.material.emission.is_equal_approx(entry.color) and is_equal_approx(entry.material.emission_energy_multiplier, entry.energy)
	check(steady and not lighting.get_node("Emergency").visible, "power restoration returns steady normal light and original fixture emission")
	var ceiling_mounted := true
	var checked := 0
	for lamp: Light3D in lighting._lamps:
		if str(lamp.name).begins_with("Hub") or str(lamp.name) in ["ContainmentWalkway2", "ContainmentWarning2"]: continue
		var query := PhysicsRayQueryParameters3D.create(lamp.global_position, lamp.global_position + Vector3.UP * 2.0, 1)
		var hit := level.get_world_3d().direct_space_state.intersect_ray(query)
		checked += 1
		if hit.is_empty() or hit.normal.dot(Vector3.DOWN) < 0.7 or hit.position.y - lamp.global_position.y > 0.26:
			ceiling_mounted = false
			print("CEILING MISMATCH ", lamp.get_path(), " ", hit)
	check(ceiling_mounted and checked == 128, "128 intact-ceiling sources sit within 26 cm of physical ceiling; hub fixtures and breach preserve their mounting")
	var added := OmniLight3D.new()
	added.light_color = Color.BLUE
	added.light_energy = 2.5
	lighting.get_node("Emergency").add_child(added)
	await process_frame
	await process_frame
	check(lighting._lamps.has(added) and added.light_color.is_equal_approx(WorldLighting.EMERGENCY_COLOR), "dynamically added omni joins the red backup circuit")
	added.reparent(level)
	check(not lighting._lamps.has(added) and not lighting._emergency_lamps.has(added) and added.light_color.is_equal_approx(Color.BLUE) and is_equal_approx(added.light_energy, 2.5), "detaching omni restores original colour and energy and clears pulse state")
	level.queue_free()
	for frame in 5: await process_frame
	print("EMERGENCY LIGHTING FAILURES ", failures)
	quit(1 if failures else 0)
