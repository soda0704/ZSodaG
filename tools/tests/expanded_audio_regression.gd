extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
	run.call_deferred()

func check(value: bool, label: String) -> void:
	print("PASS " if value else "FAIL ", label)
	if not value:
		failures.append(label)

func run() -> void:
	ProjectSettings.set_setting(BaseGameplayController.TEST_SAVE_PATH_SETTING, "user://expanded_audio_test.cfg")
	var world = load("res://scenes/levels/Base_Blockout_v03.tscn").instantiate()
	root.add_child(world)
	root.get_node("GameMenu").force_close_menu()
	await process_frame
	await process_frame
	var player: GamePlayer = get_first_node_in_group("network_players")
	player.set_physics_process(false)
	player.weapon.set_physics_process(false)
	player.survival.set_physics_process(false)
	var audio = player.player_audio
	audio.set_process(false)
	for clip in ["wind", "blizzard", "generator", "ventilation", "snowmobile_idle", "snowmobile_snow", "breath_calm"]:
		var stream = load("res://assets/audio/gameplay/%s.ogg" % clip)
		check(stream.loop and stream.get_length() > 5.0, clip + " has native loop")
	for clip in ["pistol_reload", "rifle_reload", "battery_insert", "breath_short", "breath_long", "pickup", "flashlight_on", "flashlight_off", "impact_metal", "snowmobile_stop", "pistol_empty", "rifle_empty", "ice_slide"]:
		check(not load("res://assets/audio/gameplay/%s.ogg" % clip).loop, clip + " is a single event")
	var weapon := player.weapon
	weapon._play_effect(true, &"pistol")
	check(weapon._mechanism_audio.playing and weapon._mechanism_audio.stream == weapon.pistol_reload_sound, "pistol reload selects its recording")
	check(absf(weapon.pistol_reload_sound.get_length() - 1.35) < 0.06, "pistol audio fits existing reload timing")
	weapon._play_effect(true, &"m4a1")
	check(weapon._mechanism_audio.stream == weapon.rifle_reload_sound and absf(weapon.rifle_reload_sound.get_length() - 2.1) < 0.06, "rifle reload recording fits existing timing")
	weapon.apply_state(&"pistol", 0, 0)
	weapon._cooldown = 0.0
	weapon.perform_action(&"fire")
	check(weapon._mechanism_audio.stream == weapon.pistol_empty_sound and weapon._mechanism_audio.playing and weapon.rounds == 0, "empty trigger clicks without firing or consuming ammo")
	check(weapon._cooldown > 0 and not weapon.perform_action(&"fire"), "empty trigger is rate limited")
	weapon.apply_state(&"m4a1", 0, 0)
	check(not weapon._mechanism_audio.playing, "changing weapon cancels its old mechanism sound")
	weapon._cooldown = 0
	weapon.perform_action(&"fire")
	check(weapon._mechanism_audio.stream == weapon.rifle_empty_sound, "rifle empty trigger selects rifle clip")
	player._has_flashlight = true
	player._held_item_type = &"flashlight"
	player._battery_charge = 1.0
	player.toggle_flashlight_authoritative()
	check(audio.get_node("FlashlightOff").playing, "successful flashlight off plays click")
	player.toggle_flashlight_authoritative()
	check(audio.get_node("FlashlightOn").playing, "successful flashlight on plays click")
	player._play_battery_action()
	check(audio.get_node("Battery").playing, "battery animation event plays insertion")
	player._spare_batteries.clear()
	var pickup = load("res://scenes/objects/items/battery_pickup.tscn").instantiate()
	world.add_child(pickup)
	pickup.global_position = player.global_position
	pickup.network_interact(player.owner_peer_id, player)
	check(audio.get_node("Pickup").playing and player._spare_batteries.size() == 1, "accepted world pickup plays once")
	var before := root.get_child_count()
	weapon._impact(Vector3.ZERO, Vector3.UP, world.get_path(), Vector3.ZERO, &"metal")
	var impact := root.get_child(root.get_child_count() - 1) as AudioStreamPlayer3D
	check(root.get_child_count() == before + 1 and impact != null and impact.stream == weapon.metal_impact_sound and impact.playing, "metal hit produces spatial impact at hit position")
	impact.stop()
	impact.queue_free()
	var surface := Node3D.new()
	surface.set_meta("impact_surface", "metal")
	var child := Node3D.new()
	surface.add_child(child)
	check(ContactSurface.classify(child, true) == &"metal", "surface tags are inherited from collision ancestors")
	check(ContactSurface.classify(world.get_node("SnowExterior/Terrain3D"), true) == &"snow", "terrain hits choose snow impact")
	surface.free()
	audio.update_breathing(1.0, false, true)
	check(audio.calm.playing and not audio.recovery.playing, "calm breathing loops for local living player")
	audio.update_breathing(0.8, true, true)
	audio.update_breathing(0.1, false, true)
	check(audio.recovery.playing and audio.recovery.stream == audio.short_breath, "short sprint uses short recovery")
	audio.update_breathing(4.0, true, true)
	audio.update_breathing(0.1, false, true)
	check(audio.recovery.stream == audio.long_breath, "long sprint uses long recovery")
	var level: float = audio.recovery.volume_db
	audio.update_breathing(0.1, true, true)
	check(audio.recovery.volume_db < level, "resumed sprint fades out old recovery")
	audio.update_breathing(15.0, false, false)
	check(not audio.calm.playing and not audio.recovery.playing, "remote dead sleeping and driving players remain silent")
	var ambience = world.get_node("BaseAmbience")
	ambience.set_process(false)
	ambience.set_physics_process(false)
	ambience.outside_blend = 1.0
	var power: BaseGameplayController = world.get_node("BaseGameplayController")
	power.main_breaker_on = false
	ambience.mix_audio(2.0, Vector3.ZERO)
	check(ambience.wind.playing, "outdoor wind plays with power off")
	var outdoor_volume: float = ambience.wind.volume_db
	ambience.outside_blend = 0.0
	power.main_breaker_on = true
	ambience.mix_audio(3.0, Vector3.ZERO)
	check(ambience.wind.volume_db < outdoor_volume and ambience.muffled_wind.playing, "indoors wind fades down to filtered sheltered wind")
	for side in ["CliffSnowstorm", "PerimeterSnow_North_0", "PerimeterSnow_West_0", "PerimeterSnow_South_0"]:
		var volume = world.get_node("SnowExterior/CliffValley/StormHaze_" + side)
		check(ambience.storm_intensity(volume.global_position) > 0.99, side + " has storm audio coverage")
	check(ambience.storm_intensity(Vector3.ZERO) < 0.01, "storm does not fill the quiet centre of map")
	var generator = world.get_node("Floor_0_Base_Blockout/South_Technical/Art/GeneratorRoomArt/Blockout/Generator_Room/Power_Generation/Technical_Main_Generator_Blockout/GeneratorAudio")
	generator.set_process(false)
	generator._process(2.0)
	check(generator.playing, "powered generator fades in positional loop")
	power.main_breaker_on = false
	generator._process(10.0)
	check(not generator.playing, "power loss fades out generator")
	var vehicle = load("res://scenes/objects/vehicles/snowmobile.tscn").instantiate()
	vehicle.set_physics_process(false)
	world.add_child(vehicle)
	vehicle.global_position = Vector3(-85, 0, 80)
	var terrain = world.get_node("SnowExterior/Terrain3D")
	vehicle.global_position.y = terrain.data.get_height(vehicle.global_position) - 0.08
	vehicle.driver_peer = player.owner_peer_id
	vehicle.fuel_liters = 2.0
	vehicle._speed = 4.0
	vehicle._update_engine_audio(1.0)
	check(vehicle._snow_audio.playing, "snowmobile scraping plays while moving on actual Terrain3D snow")
	var snow_volume: float = vehicle._snow_audio.volume_db
	vehicle._speed = 0.0
	vehicle._update_engine_audio(0.1)
	check(vehicle._snow_audio.volume_db < snow_volume, "snow contact fades down when stopped")
	vehicle.global_position.y = 100
	vehicle._speed = 4.0
	vehicle._update_engine_audio(4.0)
	check(not vehicle._snow_audio.playing, "airborne vehicle has no snow scraping")
	print("RESULT ", failures)
	quit(0 if failures.is_empty() else 1)
