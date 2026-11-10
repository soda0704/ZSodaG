extends SceneTree
## Flat panel at the living-wing junction: shadow acne must not draw false bands.
var checks := 0
var failures := 0
var base: Node3D
var lighting: WorldLighting
var camera: Camera3D
var output := "res://tools/.local/base-lighting-2026-11-10/shadow-quality/"
var energies: Dictionary = {}

func _initialize() -> void:
	var prefix := "user://base_shadow_surface_%d" % OS.get_process_id()
	ProjectSettings.set_setting(BaseGameplayController.TEST_SAVE_PATH_SETTING, prefix + ".cfg")
	ProjectSettings.set_setting("northern_lab/testing/settings_path", prefix + ".json")
	ProjectSettings.set_setting(JournalReadingStore.ROOT_SETTING, prefix)
	if not OS.get_environment("NORTHERNLAB_EXPORT_CAPTURE_DIR").is_empty(): output = OS.get_environment("NORTHERNLAB_EXPORT_CAPTURE_DIR") + "/"
	create_timer(150).timeout.connect(func(): quit(2))
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)

func capture(label: String, shadows: bool) -> Image:
	for lamp: Light3D in lighting._lamps: lamp.shadow_enabled = shadows
	for frame in 65:
		lighting._process(1.0 / 60.0)
		lighting.emergency_intensity = 1.0
		lighting.emergency_intensity_changed.emit(1.0)
		lighting._update_lamps(camera.global_position, 1.0 / 60.0)
		for probe in base.get_node("WorldIndirectLighting").get_children():
			if probe.data == null: continue
			if not energies.has(probe.data): energies[probe.data] = probe.data.energy
			probe.data.energy = 0.0
		await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	image.save_png(output + label + ".png")
	return image

func run() -> void:
	Engine.max_fps = 60
	root.size = Vector2i(1280, 720)
	root.content_scale_size = root.size
	DirAccess.make_dir_recursive_absolute(output)
	base = load("res://scenes/levels/base_blockout_v03.tscn").instantiate()
	root.add_child(base)
	current_scene = base
	for frame in 30: await physics_frame
	root.get_node("GameMenu").force_close_menu()
	root.get_node("GameMenu/FPSCounter").set_enabled(false)
	var actor: GamePlayer = get_first_node_in_group("local_player")
	actor.set_physics_process(false)
	actor.survival.set_physics_process(false)
	actor.body_animator.hide()
	actor.get_node("PlayerUI").hide()
	actor.teleport_authoritative(Vector3(-90, 0, 45), 0)
	base.get_node("BaseGameplayController").set_process(false)
	var state: BaseGameplayController = base.get_node("BaseGameplayController")
	var snapshot := state.get_snapshot()
	snapshot.main_breaker_on = false
	snapshot.containment["fault"] = false
	state._broadcast_snapshot(snapshot)
	base.get_node("SnowExterior/Blizzard").enabled = false
	lighting = base.get_node("WorldLighting")
	lighting.set_process(false)
	check(lighting._lamps.all(func(lamp: Light3D): return lamp.shadow_enabled), "authored base lamps retain real shadow casting")
	var enabled_before := lighting._lamp_enabled.duplicate()
	var grazing := lighting.get_node("Emergency/Coverage_living_30") as SpotLight3D
	for lamp: Light3D in lighting._lamps: lighting.set_lamp_enabled(lamp, lamp == grazing)
	lighting.source_environment().tonemap_exposure = 3.0
	var alarm = lighting.get_node("EmergencyAlarm")
	alarm.play()
	await process_frame
	alarm.stream_paused = true
	camera = Camera3D.new()
	base.add_child(camera)
	camera.position = Vector3(11.165328, 1.635818, -9.0)
	camera.look_at(Vector3(9.965328, 1.635818, -9.0))
	camera.fov = 65
	camera.current = true
	var quality = root.get_node("GameMenu/GraphicsQuality")
	quality.set_process(false)
	var last_shaded: Image
	for advanced in [true, false]:
		quality.set_advanced_lighting_enabled(advanced)
		var mode := "advanced" if advanced else "basic"
		var shaded := await capture(mode + "-surface-shadowed", true)
		last_shaded = shaded
		var reference := await capture(mode + "-surface-reference", false)
		var loss := 0.0
		var bad := 0
		var count := 0
		var reference_energy := 0.0
		# Plain central panel excludes its frame, handles and neighbouring wall.
		for x in range(220, 730, 4):
			for y in range(180, 490, 4):
				var difference := maxf(0.0, reference.get_pixel(x, y).r - shaded.get_pixel(x, y).r)
				loss += difference
				reference_energy += reference.get_pixel(x, y).r
				if difference > 0.05: bad += 1
				count += 1
		print("SHADOW SURFACE ", mode, " reference=", reference_energy / count, " mean_loss=", loss / count, " bad_fraction=", float(bad) / count)
		check(reference_energy / count > 0.15 and loss / count < 0.02 and float(bad) / count < 0.08, mode + " flat wall has no broad false self-shadow bands with GI excluded")
	# A real off-screen caster halfway between the lamp and the panel must
	# still shade the panel. Large bias or disabling shadows cannot pass this.
	var receiver := Vector3(9.965328, 1.635818, -9.0)
	var caster := CSGBox3D.new()
	caster.size = Vector3.ONE * 0.7
	caster.position = grazing.global_position.lerp(receiver, 0.5)
	base.add_child(caster)
	var occluded := await capture("caster-control", true)
	var center := Vector2i(camera.unproject_position(receiver))
	var before := 0.0
	var after := 0.0
	for x in range(center.x - 6, center.x + 7):
		for y in range(center.y - 6, center.y + 7):
			before += last_shaded.get_pixel(x, y).r
			after += occluded.get_pixel(x, y).r
	print("CASTER CONTROL red_ratio=", after / maxf(before, 0.001))
	check(before / 169.0 > 0.15 and after < before * 0.5, "a genuine caster still blocks the lamp after acne correction")
	caster.free()
	quality.set_advanced_lighting_enabled(true)
	for lamp: Light3D in enabled_before: lighting.set_lamp_enabled(lamp, enabled_before[lamp])
	await capture("authored-all-lamps", true)
	for data in energies: data.energy = float(energies[data])
	current_scene = null
	base.queue_free()
	for frame in 10: await process_frame
	print("BASE SHADOW SURFACE CHECKS ", checks, " FAILURES ", failures)
	quit(1 if failures else 0)
