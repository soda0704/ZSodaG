extends SceneTree

var failures: Array[String] = []
var restart_settings := ""

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--restart-settings="): restart_settings = argument.trim_prefix("--restart-settings=")
	var prefix := "user://light_swap_%d" % OS.get_process_id()
	ProjectSettings.set_setting("northern_lab/testing/settings_path", prefix+".json" if restart_settings.is_empty() else restart_settings)
	ProjectSettings.set_setting("northern_lab/testing/controls_path", prefix+"_controls.cfg")
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	print("PASS " if ok else "FAIL ", label)
	if not ok: failures.append(label)

func make_environment() -> Environment:
	var env := Environment.new()
	env.ssao_enabled = true
	env.volumetric_fog_enabled = true
	env.glow_enabled = true
	env.fog_enabled = true
	env.ambient_light_energy = 0.025
	return env

func run() -> void:
	await process_frame
	var menu = root.get_node("GameMenu")
	var quality = menu.get_node("GraphicsQuality")
	var console = root.get_node("DeveloperConsole")
	check(quality.advanced_lighting_enabled, "every launch starts with advanced lighting")
	if not restart_settings.is_empty():
		check(FileAccess.file_exists(menu.get_settings_path()), "restart reads the profile saved during ordinary lighting")
		check(quality.values == quality.normalized(menu._settings_data.Graphics), "saved graphics load without restoring the temporary lighting mode")
		print("LIGHT SWAP RESTART RESULT ",failures)
		quit(0 if failures.is_empty() else 1)
		return
	check(not FileAccess.file_exists(menu.get_settings_path()), "fresh computer profile needs no saved mode to start advanced")
	check(menu.save_settings_data(), "baseline graphics profile is saved")
	var profile_before := FileAccess.get_file_as_string(menu.get_settings_path())
	var saved: Dictionary = quality.values.duplicate(true)
	var world := Node3D.new()
	root.add_child(world)
	var environment := WorldEnvironment.new()
	environment.environment = make_environment()
	world.add_child(environment)
	var indirect = load("res://scenes/levels/world_indirect_lighting.tscn").instantiate()
	world.add_child(indirect)
	indirect.set_process(false)
	var lights := Node3D.new()
	lights.name = "WorldLighting"
	var standard := Node3D.new()
	standard.name = "Standard"
	lights.add_child(standard)
	var lamp := OmniLight3D.new()
	lamp.light_energy = 3.0
	lamp.light_color = Color(0.8, 0.9, 1.0)
	lamp.shadow_enabled = true
	standard.add_child(lamp)
	var emergency := Node3D.new()
	emergency.name = "Emergency"
	lights.add_child(emergency)
	world.add_child(lights)
	var power := BasePowerLightingController.new()
	world.add_child(power)
	power.apply_power_state(true)
	for frame in 3: await process_frame
	indirect.update_floor(3.0)
	check(environment.environment.ssao_enabled and environment.environment.volumetric_fog_enabled and environment.environment.glow_enabled and indirect.get_active_probe_count()>0, "fresh environments start with authored advanced effects and GI")
	check(console.execute("/light_swap").contains("Обычный"), "ordinary mode requires an explicit session command")
	check(not environment.environment.ssao_enabled and not environment.environment.volumetric_fog_enabled and not environment.environment.glow_enabled, "ordinary mode disables costly environment effects")
	check(indirect.get_active_probe_count() == 0 and indirect.get_children().all(func(probe): return probe.data == null), "ordinary mode releases GI data instead of merely hiding the volumes")
	check(environment.environment.fog_enabled and is_equal_approx(environment.environment.ambient_light_energy, 0.025), "ordinary mode preserves distance haze and authored ambient")
	check(root.positional_shadow_atlas_size == 2048 and lamp.shadow_enabled, "ordinary mode reduces the shadow atlas but retains occlusion")
	check(console.execute("/light_swap").contains("Продвинутый"), "console toggles to advanced lighting")
	indirect.update_floor(3.0)
	check(environment.environment.ssao_enabled and environment.environment.volumetric_fog_enabled and environment.environment.glow_enabled, "advanced mode restores authored effects")
	check(indirect.get_active_probe_count() > 0, "advanced mode restores nearby GI volumes")
	check(quality.values == saved, "switching does not overwrite the user's graphics settings")
	check(is_equal_approx(lamp.light_energy, 3.0) and lamp.light_color.is_equal_approx(Color(0.8, 0.9, 1.0)) and standard.visible and not emergency.visible, "switching preserves the lamps and the powered circuit")
	power.apply_power_state(false)
	console.execute("/light_swap")
	check(not standard.visible and emergency.visible and not power.is_standard_powered, "lighting mode cannot repair or alter a power outage")
	check(not quality.advanced_lighting_enabled and indirect.get_active_probe_count() == 0, "a second command restores ordinary lighting")
	quality.apply(quality.PRESETS[3])
	check(not environment.environment.ssao_enabled and not indirect._quality_enabled, "applying High does not silently override ordinary lighting")
	console.execute("/light_swap advanced")
	quality.apply({"AOQuality": 0, "FogQuality": 0, "Bloom": false})
	check(not environment.environment.ssao_enabled and not environment.environment.glow_enabled, "advanced mode still respects explicitly disabled user effects")
	quality.apply(quality.PRESETS[3])
	check(environment.environment.ssao_enabled and environment.environment.glow_enabled, "advanced mode follows newly applied quality settings")
	indirect.set_debug_disabled(true)
	indirect.update_floor(3.0)
	check(indirect.get_active_probe_count() == 0, "fullbright override can still suppress GI")
	console.execute("/light_swap basic; /light_swap advanced")
	indirect.update_floor(3.0)
	check(indirect.get_active_probe_count() == 0, "switching quality does not cancel the independent fullbright override")
	indirect.set_debug_disabled(false)
	indirect.update_floor(3.0)
	check(indirect.get_active_probe_count() > 0, "GI returns after the debug override ends")
	indirect.prepare_loading()
	console.execute("/light_swap basic")
	await indirect.finish_loading(3.0)
	check(indirect.get_active_probe_count() == 0 and indirect.get_children().all(func(probe): return probe.data == null), "arrival loading cannot reactivate GI in ordinary mode")
	console.execute("/light_swap advanced")
	indirect.update_floor(3.0)
	check(indirect.get_active_probe_count() > 0, "advanced mode can restore GI after arrival loading")
	console.execute("/light_swap basic")
	var late_environment := WorldEnvironment.new()
	late_environment.environment = make_environment()
	world.add_child(late_environment)
	for frame in 2: await process_frame
	check(not late_environment.environment.ssao_enabled, "newly loaded environments inherit the selected mode")
	check(console.execute("/light_swap invalid").contains("Использование") and not quality.advanced_lighting_enabled, "invalid commands do not change the mode")
	check(console._help_text().contains("/light_swap") and "/light_swap advanced" in console.LIGHTING_COMMANDS, "command appears in help and completion")
	quality.apply(saved)
	check(menu.save_settings_data(), "settings can be saved during ordinary lighting")
	check(FileAccess.get_file_as_string(menu.get_settings_path()) == profile_before, "temporary ordinary lighting never changes the settings file")
	quality.apply(menu.load_settings_data().Graphics)
	check(not quality.advanced_lighting_enabled, "reloading graphics keeps the temporary mode for this launch")
	var output: Array = []
	var code := OS.execute(OS.get_executable_path(),PackedStringArray(["--headless","--path",ProjectSettings.globalize_path("res://"),"--script","res://tools/tests/light_swap_regression.gd","--","--restart-settings="+menu.get_settings_path()]),output,true)
	for line in output: print(line)
	check(code==0,"a new process resets ordinary lighting to advanced with the same saved profile")
	world.queue_free()
	await process_frame
	print("LIGHT SWAP RESULT ", failures)
	quit(0 if failures.is_empty() else 1)
