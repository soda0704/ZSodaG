extends SceneTree
## Real hub geometry, light budgeting and both electrical circuits.
var failures := 0
var fault_sounds := 0

func _initialize() -> void:
	ProjectSettings.set_setting(BaseGameplayController.TEST_SAVE_PATH_SETTING, "res://tools/.local/hub_lighting_test.cfg")
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	print("PASS " if ok else "FAIL ", label)
	if not ok: failures += 1

func run() -> void:
	var level: Node3D = load("res://scenes/levels/base_blockout_v03.tscn").instantiate()
	level.network_runtime_managed = true
	root.add_child(level)
	var state: BaseGameplayController = level.get_node("BaseGameplayController")
	state.progress_persistence_enabled = false
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
	var lamps: Array[Light3D] = []
	for circuit in ["Standard", "Emergency"]:
		var count := 0
		for lamp: Light3D in lighting.get_node(circuit).get_children():
			if not str(lamp.name).begins_with("Hub"): continue
			count += 1
			lamps.append(lamp)
			check(lamp is OmniLight3D or (-lamp.global_basis.z).dot(Vector3.DOWN) > 0.99, circuit + "/" + str(lamp.name) + " faces the floor")
			var target := Vector3(signf(lamp.global_position.x) * 5.3, 1.2, signf(lamp.global_position.z) * 5.3)
			var offset := target - lamp.global_position
			var query := PhysicsRayQueryParameters3D.create(lamp.global_position, target, 1)
			check(offset.length() < WorldLighting.lamp_range(lamp) and (lamp is OmniLight3D or (-lamp.global_basis.z).angle_to(offset) < deg_to_rad(lamp.spot_angle)) and level.get_world_3d().direct_space_state.intersect_ray(query).is_empty(), circuit + "/" + str(lamp.name) + " reaches its sector without ceiling or elevator obstruction")
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
			check(material.emission_enabled and (material.emission.is_equal_approx(entry.color) if powered else material.emission.is_equal_approx(WorldLighting.EMERGENCY_COLOR)), "fixture emission follows the electrical circuit")
	check_fault_audio(state, level.get_node("BasePowerLightingController/FaultAudio"))
	check_first_night_fault_audio(state, level.get_node("BasePowerLightingController/FaultAudio"))
	check_audio_settings(level.get_node("BasePowerLightingController/FaultAudio"), "EffectsVolume")
	var interior_audio: AudioStreamPlayer = level.get_node("BaseInteriorAmbience")
	check_base_ambience(interior_audio, level)
	check_audio_settings(interior_audio, "AmbienceVolume")
	lighting.get_node("Standard").hide()
	lighting.get_node("Emergency").hide()
	var dark := true
	for entry in fixtures._materials: dark = dark and not entry.material.emission_enabled
	check(dark, "fixtures extinguish when both circuits are disabled")
	level.queue_free()
	for frame in 5: await process_frame
	print("HUB LIGHTING FAILURES ", failures)
	quit(1 if failures else 0)

func check_fault_audio(state: BaseGameplayController, audio: AudioStreamPlayer) -> void:
	state.lighting_fault_started.connect(func() -> void: fault_sounds += 1)
	check(audio.stream.resource_path == "res://assets/audio/gameplay/lighting_fault.wav" and audio.bus == &"Effects" and not audio.autoplay, "fault uses the supplied recording on Effects without autoplay")
	check(audio.stream is AudioStreamWAV and audio.stream.loop_mode == AudioStreamWAV.LOOP_DISABLED, "fault recording does not loop")
	var snapshot := state.get_snapshot()
	snapshot.day_index = state.CONTAINMENT_DAY_INDEX
	snapshot.fuel_delivered = true
	snapshot.fuel_liters = 20.0
	snapshot.main_breaker_on = true
	snapshot.maintenance = {}
	snapshot.containment = {}
	state._receive_snapshot(snapshot, false)
	check(not audio.playing and fault_sounds == 0, "ordinary power restoration is silent")
	snapshot.containment = {"fault": true}
	state._receive_snapshot(snapshot, false)
	check(audio.playing and fault_sounds == 1, "live fault snapshot plays the production audio once")
	audio.stop()
	state._receive_snapshot(snapshot, false)
	snapshot.main_breaker_on = false
	state._receive_snapshot(snapshot, false)
	snapshot.main_breaker_on = true
	state._receive_snapshot(snapshot, false)
	check(not audio.playing and fault_sounds == 1, "repeated snapshots and breaker changes do not replay the fault")
	snapshot.containment = {}
	state._receive_snapshot(snapshot, false)
	check(not audio.playing, "repairing the fault does not play the impact")
	snapshot.containment = {"fault": true}
	state._receive_snapshot(snapshot, false)
	check(audio.playing and fault_sounds == 2, "another live fault after repair plays again")
	audio.stop()
	snapshot.containment = {}
	state._apply_snapshot(snapshot, true, false)
	snapshot.containment = {"fault": true}
	state._apply_snapshot(snapshot, true, false)
	check(not audio.playing and fault_sounds == 2, "loading a saved fault does not replay the impact")
	snapshot.containment = {}
	state._receive_snapshot(snapshot, false)
	snapshot.containment = {"fault": true}
	state._receive_snapshot(snapshot, false, true)
	check(not audio.playing and fault_sounds == 2, "late-join initial sync does not replay an earlier fault")
	snapshot.containment = {}
	state._receive_snapshot(snapshot, false)
	snapshot.containment = {"fault": true}
	state._receive_snapshot(snapshot, false)
	check(audio.playing and fault_sounds == 3, "live faults still play after initial sync")
	audio.stop()

func check_first_night_fault_audio(state: BaseGameplayController, audio: AudioStreamPlayer) -> void:
	var sounds_before := fault_sounds
	var snapshot := state.get_snapshot()
	snapshot.day_index = 1
	snapshot.phase = BaseGameplayController.BasePhase.ENDING_DAY
	snapshot.fuel_delivered = true
	snapshot.fuel_liters = 20.0
	snapshot.main_breaker_on = true
	snapshot.elevator_backup_installed = true
	snapshot.sleeping_peer_ids = [state.multiplayer.get_unique_id()]
	snapshot.end_day_ready_peer_ids = snapshot.sleeping_peer_ids.duplicate()
	snapshot.containment = {}
	snapshot.maintenance = {}
	state._receive_snapshot(snapshot, false)
	check(state.advance_day_authoritative() and state.day_index == 2 and bool(state.maintenance.get("wires_required", false)), "first sleep triggers the real wiring failure on day two")
	check(audio.playing and fault_sounds == sounds_before + 1, "first-night wiring failure plays the same impact once")
	audio.stop()
	var fault_snapshot := state.get_snapshot()
	state._receive_snapshot(fault_snapshot, false)
	fault_snapshot.maintenance["wire_links"] = [0]
	state._receive_snapshot(fault_snapshot, false)
	check(not audio.playing and fault_sounds == sounds_before + 1, "wiring progress and repeated snapshots do not replay the impact")
	var repaired := fault_snapshot.duplicate(true)
	repaired.maintenance = {}
	state._apply_snapshot(repaired, true, false)
	state._apply_snapshot(fault_snapshot, true, false)
	check(not audio.playing and fault_sounds == sounds_before + 1, "restoring a saved wiring failure is silent")
	state._apply_snapshot(repaired, true, false)
	state._receive_snapshot(fault_snapshot, false, true)
	check(not audio.playing and fault_sounds == sounds_before + 1, "joining during the first-night wiring failure is silent")

func check_audio_settings(audio: AudioStreamPlayer, setting: String) -> void:
	var menu := root.get_node("GameMenu")
	var original: Dictionary = menu._settings_data.duplicate(true)
	var bus := AudioServer.get_bus_index(audio.bus)
	var available := false
	for spec in NorthernSettingsMenu.AUDIO:
		available = available or spec[0] == setting
	check(available, setting + " has a visible sound-settings control")
	for percent in [0.0, 25.0, 100.0]:
		menu._settings_data[setting] = percent
		menu.apply_settings_data()
		check(AudioServer.is_bus_mute(bus) == is_zero_approx(percent), setting + " mutes at zero and restores above zero")
		if percent > 0.0:
			check(is_equal_approx(AudioServer.get_bus_volume_db(bus), linear_to_db(percent / 100.0)), setting + " follows the applied settings percentage")
	menu._settings_data = original
	menu.apply_settings_data()

func check_base_ambience(audio: AudioStreamPlayer, level: Node3D) -> void:
	audio.set_process(false)
	check(audio.bus == &"Ambience" and audio.stream is AudioStreamMP3 and audio.stream.loop, "supplied metal ambience loops on the adjustable Ambience bus")
	check(audio.stream.resource_path == "res://assets/audio/gameplay/base_metal_clangs.mp3", "base ambience uses the supplied recording")
	for region: VoxelGI in level.get_node("WorldIndirectLighting").get_children():
		check(audio.contains_point(region.global_position), "metal ambience covers the " + str(region.name) + " floor")
	for height in [1.7, -14.0, -23.0, -41.0, -59.0, -77.0, -89.0]:
		check(audio.contains_point(level.to_global(Vector3(0, height, 0))), "elevator travel keeps the base ambience at height " + str(height))
	check(not audio.contains_point(level.to_global(Vector3(180, 2, 180))) and not audio.contains_point(level.to_global(Vector3(-30, -150, 0))), "exterior and deep cave positions do not activate base ambience")
	audio.mix_presence(10.0, false)
	check((not audio.playing or audio.stream_paused) and audio.volume_db <= -80.0, "base ambience starts silent outside")
	audio.mix_presence(0.1, true)
	var entry_volume: float = audio.volume_db
	check(audio.playing and not audio.stream_paused and entry_volume < audio.ambience_volume_db - 20.0, "entry starts quietly instead of jumping to full volume")
	audio.mix_presence(audio.fade_seconds * 0.5, true)
	var middle_volume: float = audio.volume_db
	check(middle_volume > entry_volume and middle_volume < audio.ambience_volume_db, "entry gradually raises the recording")
	audio.mix_presence(0.05, false)
	check(audio.volume_db < middle_volume and audio.volume_db > middle_volume - 2.0, "sudden exit reverses smoothly without cutting off")
	audio.mix_presence(0.05, true)
	check(is_equal_approx(audio.volume_db, middle_volume), "quick re-entry continues the fade without restarting")
	audio.mix_presence(audio.fade_seconds, true)
	check(is_equal_approx(audio.volume_db, audio.ambience_volume_db), "remaining inside reaches the authored background level")
	audio.mix_presence(audio.fade_seconds, false)
	check(audio.stream_paused and audio.volume_db <= -80.0, "exit fades fully before pausing the recording")
