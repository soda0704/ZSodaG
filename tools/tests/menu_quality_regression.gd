extends SceneTree
var failures: Array[String] = []
var redraws := 0
func _initialize() -> void:
	ProjectSettings.set_setting("northern_lab/testing/settings_path", "user://quality_settings_%d.json" % OS.get_process_id())
	run.call_deferred()
func check(ok: bool, label: String) -> void:
	print("PASS " if ok else "FAIL ", label)
	if not ok: failures.append(label)
func run() -> void:
	await process_frame
	var menu = root.get_node("GameMenu")
	var quality = menu.get_node("GraphicsQuality")
	var original: Dictionary = quality.values.duplicate()
	check(menu._settings_data.GraphicsPresetRevision == quality.PRESET_REVISION, "fresh settings use the current preset revision before their first save")
	var legacy: Dictionary = quality.LEGACY_HIGH.duplicate()
	legacy.merge({"FPS": 144, "Gamma": 120, "HDRWhite": 100}, true)
	var migrated: Dictionary = quality.migrate_saved(legacy, 0)
	check(quality.preset_index(migrated) == 3 and migrated.AOQuality == 2 and migrated.GIQuality == 2 and migrated.MSAA == 1 and migrated.ShadowQuality == 3, "previous High preset migrates to measured budgets while retaining detail and AA")
	check(migrated.FPS == 144 and migrated.Gamma == 120 and migrated.HDRWhite == 100 and legacy.GIQuality == 3, "migration preserves calibration and frame cap without mutating its input")
	var custom: Dictionary = legacy.duplicate()
	custom.TrackCount = 320
	check(quality.migrate_saved(custom, 0) == custom and quality.migrate_saved(legacy, quality.PRESET_REVISION) == legacy, "custom settings and explicit current-revision full-quality choices are not downgraded")
	var file := FileAccess.open(menu.get_settings_path(), FileAccess.WRITE)
	file.store_string(JSON.stringify({"Graphics": legacy, "MasterVolume": 71}))
	file.close()
	var loaded: Dictionary = menu.load_settings_data()
	check(loaded.GraphicsPresetRevision == quality.PRESET_REVISION and quality.preset_index(loaded.Graphics) == 3 and loaded.MasterVolume == 71, "loading a saved old High profile performs the migration through GameMenu")
	menu._settings_data = loaded
	menu.save_settings_data()
	var reloaded: Dictionary = menu.load_settings_data()
	check(reloaded.GraphicsPresetRevision == quality.PRESET_REVISION and quality.preset_index(reloaded.Graphics) == 3 and reloaded.Graphics.FPS == 144 and reloaded.Graphics.Gamma == 120 and reloaded.MasterVolume == 71, "migrated profile survives saving and reloading")
	check(quality.normalized({"ShadowDistance":120}).ShadowDistance == 96, "legacy shadow distance is normalized to the actual authored range in both UI and renderer")
	var environment := Environment.new()
	environment.ambient_light_energy = 0.025
	environment.fog_enabled = true
	environment.fog_density = 0.4
	environment.fog_depth_begin = 150.0
	environment.volumetric_fog_density = 0.0015
	environment.glow_intensity = 0.12
	environment.ssao_enabled = true
	environment.volumetric_fog_enabled = true
	environment.glow_enabled = true
	quality.apply({"AOQuality": 0, "FogQuality": 0, "Bloom": false})
	quality.apply_environment(environment)
	check(not environment.ssao_enabled and not environment.volumetric_fog_enabled and not environment.glow_enabled, "optional postprocessing can actually be disabled")
	quality.apply({"AOQuality": 3, "FogQuality": 3, "GIQuality": 3, "Bloom": true})
	quality.apply_environment(environment)
	check(environment.ssao_enabled and environment.volumetric_fog_enabled and environment.glow_enabled, "postprocessing can be restored after applying changes")
	var cabin := Environment.new()
	quality.apply_environment(cabin)
	check(not cabin.ssao_enabled and not cabin.volumetric_fog_enabled and not cabin.glow_enabled, "High quality does not add unauthored fog or glow to the helicopter cabin")
	check(is_equal_approx(environment.fog_density, 0.4) and environment.fog_enabled and is_equal_approx(environment.ambient_light_energy, 0.025) and is_equal_approx(environment.volumetric_fog_density, 0.0015) and is_equal_approx(environment.glow_intensity, 0.12), "quality preserves the new authored lighting and horizon haze")
	var view := SubViewport.new()
	view.name = "ViewmodelViewport"
	root.add_child(view)
	quality.apply({"MSAA": 1, "FXAA": false})
	check(view.msaa_3d == Viewport.MSAA_2X and view.screen_space_aa == Viewport.SCREEN_SPACE_AA_DISABLED, "viewmodel follows AA settings instead of a hidden fixed 4x cost")
	view.free()
	var picking := SubViewport.new()
	picking.size = Vector2i(2, 2)
	root.add_child(picking)
	var picking_camera := Camera3D.new()
	picking_camera.environment = Environment.new()
	picking.add_child(picking_camera)
	quality.apply({"AOQuality": 3, "FogQuality": 3, "Bloom": true})
	await process_frame
	check(not picking_camera.environment.ssao_enabled and not picking_camera.environment.glow_enabled and not picking_camera.environment.volumetric_fog_enabled, "utility picking camera keeps its own environment without screen-space effects")
	picking.free()
	menu.open_settings()
	await create_timer(0.7).timeout
	var settings = menu.settings_panel
	settings.select_category(1)
	var before: Dictionary = menu._settings_data.duplicate(true)
	for index in [1, 2, 3]:
		settings._preset(index)
		check(quality.preset_index(settings.draft.Graphics) == index and settings.rows.find_child("Preset", true, false).selected == index, "preset %d correctly identifies its staged values" % index)
		check(menu._settings_data == before, "preset %d waits for Apply" % index)
	settings._set_value("TrackCount", 320, true)
	check(settings.rows.find_child("Preset", true, false).selected == 0, "manual edit changes preset label to Custom")
	settings._set_value("FPS", 60, true)
	settings._preset(1)
	check(settings.draft.Graphics.FPS == 60, "presets preserve the chosen frame limiter")
	settings.apply(false)
	check(not settings.has_changes() and settings.apply_button.disabled, "applying a preset clears pending changes")
	check(quality.values.ShadowQuality == 1 and is_equal_approx(root.scaling_3d_scale, 0.75), "Apply commits the complete lighting and rendering preset")
	var image := NorthernMenuStyle.cursor_image()
	check(image.get_pixel(4, 4).r > 0.9 and image.get_pixel(3, 4).r < 0.1 and image.get_pixel(3, 4).a == 1.0, "cursor has both light core and opaque dark outline for notebook paper")
	var monotonic := true
	var previous := 0.0
	for index in 1001:
		var value := NorthernMenuStyle.ease(index / 1000.0)
		if value < previous or value > 1.0: monotonic = false
		previous = value
	check(monotonic and NorthernMenuStyle.ease(0) == 0 and NorthernMenuStyle.ease(1) == 1, "cached animation curve has exact endpoints and no overshoot")
	if DisplayServer.get_name() != "headless":
		var row = settings.rows.get_child(0)
		row.get_child(1).grab_focus()
		await create_timer(1.0).timeout
		row.draw.connect(func(): redraws += 1)
		await create_timer(0.3).timeout
		check(redraws <= 1, "settled settings row does not redraw every frame")
		row.pulse()
		await create_timer(0.1).timeout
		check(redraws > 1, "click highlight still animates after idle")
	menu.force_close_menu()
	quality.apply(original)
	print("MENU QUALITY RESULT ", failures)
	quit(0 if failures.is_empty() else 1)
