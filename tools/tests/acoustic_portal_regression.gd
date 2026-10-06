extends SceneTree
var failures: Array[String] = []
func _initialize() -> void: run.call_deferred()
func check(value: bool, label: String) -> void:
	print("PASS " if value else "FAIL ", label)
	if not value: failures.append(label)
func run() -> void:
	ProjectSettings.set_setting(BaseGameplayController.TEST_SAVE_PATH_SETTING, "user://acoustic_portal_test.cfg")
	var world = load("res://scenes/levels/Base_Blockout_v03.tscn").instantiate()
	root.add_child(world)
	root.get_node("GameMenu").force_close_menu()
	await physics_frame
	await physics_frame
	await process_frame
	var acoustics: ExteriorAcoustics = world.get_node("BaseAmbience")
	acoustics.set_physics_process(false)
	var portals := get_nodes_in_group("acoustic_portals")
	check(portals.size() == 2, "both garage and pedestrian exterior entrances have narrow portals")
	check(get_nodes_in_group("indoor_audio_zone").is_empty() and world.get_node_or_null("IndoorAudioZones") == null, "all broad indoor dome zones removed")
	var floor = world.get_node("Floor_0_Base_Blockout")
	var portal: AcousticPortal = floor.get_node("Doors/GarageWindPassage")
	portal.set_physics_process(false)
	var gate = floor.get_node("Doors/West_Vehicle_Exterior_Gate_Visual_Prototype")
	gate.set_physics_process(false)
	gate.progress = 0.0
	gate._apply_pose(true)
	check(portal.openness() == 0, "closed garage blocks direct wind")
	gate.progress = 1.0
	gate._apply_pose(true)
	check(is_equal_approx(portal.openness(), 1.0), "open garage admits direct wind")
	gate.animation.play("open")
	gate.animation.seek(2.0, true)
	check(portal.openness() > 0 and portal.openness() < 1, "garage wind follows actual animated opening")
	gate.animation.pause()
	check(portal.openness() > 0 and portal.openness() < 1, "paused gate still exposes its actual aperture")
	var outside := portal.to_global(Vector3(0, 1.7, -1))
	var inside := portal.to_global(Vector3(0, 1.7, 1))
	check(portal.crossing(outside, inside) == 1 and portal.crossing(inside, outside) == 0, "door threshold distinguishes entry and exit")
	check(portal.crossing(outside + Vector3.UP * 10, inside + Vector3.UP * 10) == -1, "passing above roof cannot trigger portal")
	acoustics._previous = outside
	acoustics.is_inside = false
	acoustics.outside_blend = 1.0
	acoustics.update_listener(inside, 0.1)
	check(acoustics.is_inside and acoustics.outside_blend > 0 and acoustics.outside_blend < 1, "entry smoothly reduces outside sound")
	acoustics.is_inside = true
	var listener := root.get_camera_3d()
	listener.global_position = inside
	gate.progress = 1.0
	gate._apply_pose(true)
	portal.update_audio(1.0)
	check(portal.wind.playing, "open doorway emits positional wind inside")
	var wall := StaticBody3D.new()
	world.add_child(wall)
	wall.global_transform = Transform3D(portal.global_basis, portal.to_global(Vector3(0, 1.7, 0.65)))
	var wall_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.6, 2.0, 0.12)
	wall_shape.shape = box
	wall.add_child(wall_shape)
	await physics_frame
	await physics_frame
	await process_frame
	check(not portal.wind_path_clear(listener), "physical wall blocks wind path from an open entrance")
	var unblocked_level: float = portal.wind.volume_db
	portal.update_audio(0.3)
	check(portal.wind.volume_db < unblocked_level, "occluded entrance wind fades down")
	wall.queue_free()
	await physics_frame
	await process_frame
	check(portal.wind_path_clear(listener), "removing obstruction restores entrance wind path")
	gate.progress = 0.0
	gate._apply_pose(true)
	var level: float = portal.wind.volume_db
	portal.update_audio(0.1)
	check(portal.wind.volume_db < level, "closing door fades positional wind")
	portal.update_audio(8.0)
	check(not portal.wind.playing, "closed door stops direct wind loop")
	var pedestrian: AcousticPortal = floor.get_node("Doors/PedestrianWindPassage")
	var manager = floor.get_node("Doors/AutomaticDoors")
	manager.set_physics_process(false)
	for door in manager._doors:
		if door.anchor == pedestrian._door:
			manager._apply_door_state(door, false, true)
			check(pedestrian.openness() < 0.01, "closed sliding door uses actual leaf pose")
			manager._apply_door_state(door, true, true)
			check(pedestrian.openness() > 0.99, "open sliding door uses actual leaf pose")
	check(acoustics.has_roof(Vector3(0, 1.65, 0)), "spawn indoors recognized by existing physical roof")
	check(not acoustics.has_roof(Vector3(0, 15, 0)), "above roof recognized as outdoors")
	check(not acoustics.has_roof(Vector3(-90, 15, 80)), "open exterior recognized without volume")
	acoustics.is_inside = true
	acoustics._previous = Vector3(-90, 15, 80)
	acoustics._last_roof_probe = Vector3(-94, 15, 80)
	acoustics.update_listener(Vector3(-89, 15, 80), 1.0)
	check(not acoustics.is_inside, "leaving an unmarked shelter recovers exterior sound by geometry")
	var camera := root.get_camera_3d()
	var environment = world.get_node("SnowExterior/OvercastDayEnvironment").environment
	var old_environment: Environment = camera.environment
	var old_brightness: float = environment.adjustment_brightness
	acoustics.update_listener(Vector3(0, 1.65, 0), 2.0, true)
	acoustics.mix_audio(2.0, Vector3(0, 1.65, 0))
	check(acoustics.is_inside and acoustics.muffled_wind.playing, "indoor teleport restores filtered quiet wind")
	acoustics.update_listener(Vector3(-90, 15, 80), 2.0, true)
	check(not acoustics.is_inside, "outdoor teleport resets shelter state")
	check(camera.environment == old_environment and environment.adjustment_brightness == old_brightness, "acoustics leaves camera and brightness untouched")
	check(world.get_node("SnowExterior/OvercastDaySun").light_cull_mask == 1048575, "sun uses normal geometry and shadow layers")
	var bus := AudioServer.get_bus_index("MuffledWeather")
	check(bus >= 0 and AudioServer.get_bus_effect(bus, 0) is AudioEffectLowPassFilter, "sheltered wind has native low-pass filtering")
	var power = world.get_node("BaseGameplayController")
	var vents: Array[Node] = world.find_children("VentilationAudio", "AudioStreamPlayer3D", true, false)
	check(vents.size() == 6, "ventilation comes from six existing vents and air scrubbers")
	power.main_breaker_on = true
	for vent in vents:
		vent.set_process(false)
		vent._process(2.0)
		check(vent.playing, "powered vent starts spatial loop")
	power.main_breaker_on = false
	for vent in vents:
		vent._process(12.0)
		check(not vent.playing, "power loss fades spatial vent out")
	print("RESULT ", failures)
	quit(0 if failures.is_empty() else 1)
