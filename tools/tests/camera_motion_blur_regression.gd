extends SceneTree
## Production camera and settings: motion, reset, Apply and persistence.
var actor: GamePlayer
var checks := 0
var failures := 0

func _initialize() -> void:
	var prefix := "user://camera_blur_%d" % OS.get_process_id()
	ProjectSettings.set_setting("northern_lab/testing/settings_path", prefix + ".json")
	ProjectSettings.set_setting("northern_lab/testing/controls_path", prefix + ".cfg")
	ProjectSettings.set_setting(BaseGameplayController.TEST_SAVE_PATH_SETTING, prefix + "_save.cfg")
	ProjectSettings.set_setting(JournalReadingStore.ROOT_SETTING, prefix + "_journal")
	create_timer(60).timeout.connect(func(): quit(2))
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)

func settle(seconds: float = 0.5) -> void:
	await create_timer(seconds).timeout
	await RenderingServer.frame_post_draw

func turn() -> void:
	for frame in 24:
		actor.head.rotation.y += 0.012
		await process_frame
	await RenderingServer.frame_post_draw

func run() -> void:
	if DisplayServer.get_name() == "headless": quit(2); return
	Engine.max_fps = 60
	var quality = root.get_node("GameMenu/GraphicsQuality")
	quality.set_process(false)
	var legacy: Dictionary = quality.normalized({})
	check(not legacy.MotionBlur and legacy.MotionBlurStrength == 35, "new and missing settings start without blur")
	check(not quality.normalized({"MotionBlur": false}).MotionBlur, "explicit saved disable survives normalization")
	var previous := {"MotionBlur": true, "MotionBlurStrength": 55, "Gamma": 110}
	var migrated: Dictionary = quality.migrate_saved(previous, 2)
	check(not migrated.MotionBlur and migrated.MotionBlurStrength == 55 and migrated.Gamma == 110 and previous.MotionBlur, "previous automatic blur migrates off without changing calibration or its input")
	check(quality.migrate_saved(previous, quality.PRESET_REVISION).MotionBlur, "a later deliberate enable survives loading")
	var arena = load("res://scenes/levels/base_blockout_v03.tscn").instantiate()
	root.add_child(arena); current_scene = arena
	for frame in 25: await physics_frame
	actor = get_first_node_in_group("local_player")
	arena.get_node("BaseGameplayController").set_process(false)
	actor.set_physics_process(false); actor.survival.set_physics_process(false)
	actor.teleport_authoritative(Vector3(0, 0.1, 0), 0)
	actor.camera.set_process(false)
	var menu = root.get_node("GameMenu")
	menu.force_close_menu(); Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var effect = actor.get_node("PlayerUI/CameraPostProcess")
	var mat: ShaderMaterial = effect.get_node("Effect").material
	await settle()
	check(not mat.get_shader_parameter("motion_blur_enabled"), "stationary camera remains sharp")
	await turn()
	check(not mat.get_shader_parameter("motion_blur_enabled"), "default film profile remains sharp while moving")
	var enabled: Dictionary = quality.values.duplicate()
	enabled.MotionBlur = true
	menu._settings_data.Graphics = enabled.duplicate()
	quality.apply(enabled); await settle()
	await turn()
	check(mat.get_shader_parameter("motion_blur_enabled") and Vector2(mat.get_shader_parameter("blur_direction")).length() > 0.0001, "real camera turning activates visible shutter flow")
	check(Vector2(mat.get_shader_parameter("blur_direction")).length() <= 0.01201, "blur remains bounded during motion")
	actor.teleport_authoritative(Vector3(0.5, 0.1, 0), 0)
	check(not mat.get_shader_parameter("motion_blur_enabled"), "even a short authoritative teleport immediately clears blur")
	await settle()
	for frame in 24:
		actor.position -= actor.camera.global_basis.z * 0.06
		await process_frame
	await RenderingServer.frame_post_draw
	check(absf(float(mat.get_shader_parameter("radial_blur"))) > 0.0001, "forward movement also produces radial shutter flow")
	await settle(0.8)
	check(not mat.get_shader_parameter("motion_blur_enabled"), "stopping movement removes blur without accumulated ghosts")
	menu.open_settings(); await settle(1.5)
	var settings = menu.settings_panel
	settings.select_category(1); await process_frame
	var toggle = settings.rows.find_child("MotionBlur", true, false)
	var strength = settings.rows.find_child("MotionBlurStrength", true, false)
	check(toggle is Button and strength is NorthernMenuValue, "graphics menu exposes toggle and numeric strength")
	toggle.pressed.emit(); strength.set_value(55)
	check(effect.motion_blur_enabled and settings.has_changes(), "draft edits do not change the live camera before Apply")
	settings.apply(false)
	check(not effect.motion_blur_enabled and is_equal_approx(effect.motion_blur_strength, 0.55), "Apply updates the existing camera without recreating it")
	var saved: Dictionary = menu.load_settings_data()
	check(not saved.Graphics.MotionBlur and saved.Graphics.MotionBlurStrength == 55, "both settings persist to the actual settings file")
	menu.force_close_menu(); Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	await settle(); await turn()
	check(not mat.get_shader_parameter("motion_blur_enabled"), "disabled blur stays off during real camera movement")
	var data: Dictionary = quality.values.duplicate()
	data.MotionBlur = true; data.MotionBlurStrength = 0
	quality.apply(data); await settle(); await turn()
	check(not mat.get_shader_parameter("motion_blur_enabled"), "zero intensity also disables the sampling path")
	data.MotionBlurStrength = 35; quality.apply(data)
	await settle(); await turn()
	check(mat.get_shader_parameter("motion_blur_enabled"), "re-enabling settings restores movement blur")
	actor.has_journal = true
	root.get_node("QuestJournal").open_journal(); await settle(1.0)
	check(root.get_node("QuestJournal").is_journal_open() and not mat.get_shader_parameter("motion_blur_enabled") and float(mat.get_shader_parameter("lens_amount")) < 0.001, "real journal disables blur and lens warp for readable pages and accurate clicks")
	root.get_node("QuestJournal").force_close(); await settle()
	check(float(mat.get_shader_parameter("lens_amount")) > 0.99, "closing journal smoothly restores bodycam lens")
	actor = null; current_scene = null; arena.queue_free()
	await process_frame
	print("CAMERA MOTION BLUR CHECKS ", checks, " FAILURES ", failures)
	quit(1 if failures else 0)
