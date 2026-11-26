extends SceneTree
var failures: Array[String] = []
func _initialize(): run.call_deferred()
func check(value: bool, label: String):
	print("PASS " if value else "FAIL ",label)
	if not value: failures.append(label)
func run():
	ProjectSettings.set_setting(BaseGameplayController.TEST_SAVE_PATH_SETTING,"user://audio_graphics_test.cfg")
	var quality = root.get_node("GameMenu/GraphicsQuality")
	var original: Dictionary = quality.values.duplicate()
	var light := OmniLight3D.new()
	light.shadow_enabled = true
	root.add_child(light)
	var untouched := OmniLight3D.new()
	root.add_child(untouched)
	var zone := WorldEnvironment.new()
	zone.environment = Environment.new()
	zone.environment.fog_enabled = false
	zone.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	zone.environment.ambient_light_energy = 0.025
	root.add_child(zone)
	zone.set_process(false)
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.make_current()
	quality.apply({"Scale":70,"LocalShadows":false,"AOQuality":0,"SSR":false,"FPS":60})
	quality.apply_node(camera)
	check(is_equal_approx(root.scaling_3d_scale,0.7) and Engine.max_fps==60,"render scale and FPS limit apply")
	check(light.shadow_enabled and not untouched.shadow_enabled,"legacy quality flags preserve authored shadow states")
	check(not camera.environment.ssao_enabled and not camera.environment.ssr_enabled,"environment effects disabled")
	quality.apply({"LocalShadows":true,"SSR":true})
	check(not light.is_queued_for_deletion(),"quality changes keep authored world lights")
	check(not camera.environment.ssr_enabled and not camera.environment.fog_enabled and is_equal_approx(camera.environment.ambient_light_energy,0.025),"screen effects stay disabled while authored ambient is preserved")
	var source := Environment.new()
	source.ssao_enabled = true
	source.glow_enabled = true
	source.fog_enabled = true
	source.volumetric_fog_enabled = true
	source.fog_density = 0.004
	zone.environment = source
	camera.environment = source
	quality.apply({"AOQuality": 0, "Bloom": false, "FogQuality": 0, "Gamma": 130, "Brightness": 115})
	var runtime := camera.environment
	check(runtime != source and source.ssao_enabled and source.glow_enabled and source.volumetric_fog_enabled, "quality preserves the authored environment")
	check(not runtime.ssao_enabled and not runtime.glow_enabled and not runtime.volumetric_fog_enabled and runtime.fog_enabled and is_equal_approx(runtime.fog_density, 0.004), "quality disables optional effects while preserving authored distance fog")
	check(is_equal_approx(runtime.adjustment_brightness, 1.15) and runtime.adjustment_color_correction == load("res://assets/environments/calibration/gamma_130.tres"), "brightness and gamma affect the active camera")

	check(NorthernSettingsMenu.CATEGORIES.size() == 4, "settings are separated into four categories")
	camera.free()
	zone.free()
	var elevator = load("res://scenes/objects/elevator/elevator_functional_blockout.tscn").instantiate()
	root.add_child(elevator)
	await process_frame
	var sound: AudioStreamPlayer3D = elevator.get_node("CabinMoving/TravelAudio")
	check(elevator.cabin.get_meta("footstep_surface", "") == "metal", "elevator cabin has metal footsteps")
	check(sound.stream.loop,"elevator stream imported as loop")
	elevator._set_state(elevator.ElevatorState.MOVING)
	await create_timer(0.7).timeout
	check(sound.playing and is_equal_approx(sound.volume_db,-9.0),"travel sound fades in")
	elevator._set_state(elevator.ElevatorState.ARRIVING)
	await create_timer(0.6).timeout
	check(not sound.playing,"travel sound stops after fade")
	var cabin = load("res://scenes/objects/lobby/cabin_sound.tscn").instantiate()
	root.add_child(cabin)
	check(cabin.get_node("CabinLoop").stream.loop,"helicopter stream imported as loop")
	check(not cabin.get_node("CabinLoop").autoplay and not cabin.get_node("CabinLoop").playing,"cabin stays silent until the cooperative session explicitly starts it")
	cabin.get_node("CabinLoop").play()
	cabin.get_node("FadePlayer").play("arrival")
	await create_timer(3.8).timeout
	check(not cabin.get_node("CabinLoop").playing,"helicopter arrival fade stops audio")
	var footsteps = load("res://scenes/characters/footstep_audio.tscn").instantiate()
	check(not footsteps.floor_sounds.is_empty() and not footsteps.snow_sounds.is_empty() and not footsteps.metal_sounds.is_empty(),"all footstep surfaces have clips")
	footsteps.free()
	var console = load("res://scripts/ui/developer_console.gd").new()
	check(console._help_text().contains("Телепортироваться: управление") and console._help_text().contains("Создать батарейку"),"command descriptions identify actions and items")
	console.free()
	var delays := {}
	var pitches := {}
	var voice_scene: PackedScene = load("res://scenes/objects/monster_audio.tscn")
	for i in 10:
		var actor := VoiceTestActor.new()
		root.add_child(actor)
		var voice := voice_scene.instantiate()
		actor.add_child(voice)
		delays[voice.countdown] = true
		pitches[voice.voice_pitch] = true
		actor.free()
	check(delays.size() == 10 and pitches.size() == 10, "ten monster voices have independent timing and pitch")
	quality.apply(original)
	print("RESULT ",failures)
	quit(0 if failures.is_empty() else 1)

class VoiceTestActor extends Node3D:
	var health := 100.0
	var model_id := "smily"
