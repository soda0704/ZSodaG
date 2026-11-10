extends SceneTree
## Fixed cameras in all ten zones; compare actual rendered light against blackout.
var checks := 0
var failures := 0
var base: Node3D
var lighting: WorldLighting
var camera: Camera3D
var alarm: AudioStreamPlayer
var phase := 0.0
var output := "res://tools/.local/base-lighting-2026-11-10/captures/"

func _initialize() -> void:
	var prefix := "user://base_light_render_%d" % OS.get_process_id()
	ProjectSettings.set_setting(BaseGameplayController.TEST_SAVE_PATH_SETTING, prefix + ".cfg")
	ProjectSettings.set_setting("northern_lab/testing/settings_path", prefix + ".json")
	ProjectSettings.set_setting(JournalReadingStore.ROOT_SETTING, prefix)
	if not OS.get_environment("NORTHERNLAB_EXPORT_CAPTURE_DIR").is_empty(): output = OS.get_environment("NORTHERNLAB_EXPORT_CAPTURE_DIR") + "/"
	create_timer(170).timeout.connect(func(): quit(2))
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)

func capture(label: String, at: Vector3, target: Vector3, powered: bool, pulse: float) -> Vector2:
	camera.position = at
	camera.look_at(target)
	camera.reset_physics_interpolation()
	var state: BaseGameplayController = base.get_node("BaseGameplayController")
	var snapshot := state.get_snapshot()
	snapshot.main_breaker_on = powered
	snapshot.fuel_delivered = true
	snapshot.fuel_liters = 30.0
	snapshot.containment["fault"] = false
	state._broadcast_snapshot(snapshot)
	if not powered:
		alarm.play(phase)
		await process_frame
		alarm.stream_paused = true
	for frame in 70:
		lighting._process(1.0 / 60.0)
		if not powered:
			lighting.emergency_intensity = pulse
			lighting.emergency_intensity_changed.emit(pulse)
			lighting._update_lamps(at, 1.0 / 60.0)
		await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	image.save_png(output + label + ".png")
	# A central/lower rectangle avoids sky/HUD and catches room floor and walls.
	var energy := 0.0
	var red := 0.0
	var count := 0
	for x in range(200, 1080, 8):
		for y in range(280, 650, 8):
			energy += image.get_pixel(x, y).get_luminance()
			red += image.get_pixel(x, y).r
			count += 1
	print("RENDER ", label, " luminance=", energy / count, " red=", red / count, " residents=", lighting._resident_lamps.size())
	return Vector2(energy / count, red / count)

func run() -> void:
	DirAccess.make_dir_recursive_absolute(output)
	root.size = Vector2i(1280, 720)
	root.content_scale_size = root.size
	Engine.max_fps = 60
	base = load("res://scenes/levels/base_blockout_v03.tscn").instantiate()
	root.add_child(base)
	current_scene = base
	for frame in 30: await physics_frame
	root.get_node("GameMenu").force_close_menu()
	var actor: GamePlayer = get_first_node_in_group("local_player")
	actor.set_physics_process(false)
	actor.survival.set_physics_process(false)
	actor.body_animator.hide()
	actor.get_node("PlayerUI").hide()
	actor.teleport_authoritative(Vector3(-90, 0, 45), 0)
	base.get_node("BaseGameplayController").set_process(false)
	base.get_node("SnowExterior/Blizzard").enabled = false
	lighting = base.get_node("WorldLighting")
	lighting.set_process(false)
	alarm = lighting.get_node("EmergencyAlarm")
	var animation: Animation = alarm.animation.get_animation("alarm")
	for key in animation.track_get_key_count(0):
		if animation.track_get_key_value(0, key) == 1.0:
			phase = animation.track_get_key_time(0, key)
			break
	camera = Camera3D.new()
	base.add_child(camera)
	camera.current = true
	camera.fov = 80
	var quality = root.get_node("GameMenu/GraphicsQuality")
	quality.set_process(false)
	quality.set_advanced_lighting_enabled(true)
	var routes := [
		["entrance", Vector3(-27, 1.7, -2), Vector3(-20, 2, 0)],
		["hub", Vector3(-6, 1.75, 6), Vector3(4, 1.7, 5.8)],
		["living", Vector3(20, 1.7, 0), Vector3(27, 1.7, 0)],
		["north", Vector3(0, 1.7, -15), Vector3(-6, 1.7, -20)],
		["south", Vector3(-3, 1.7, 15), Vector3(3, 1.7, 22)],
		["control", Vector3(-31, -16.3, 0), Vector3(-43, -16.3, 0)],
		["life", Vector3(-35, -34.3, 0), Vector3(-45, -34.3, 0)],
		["trials", Vector3(-25, -52.3, 1), Vector3(-30, -52.3, -10)],
		["containment", Vector3(-5.5, -70.3, 2), Vector3(-11, -70.3, 0)],
		["expedition", Vector3(-28, -88.3, 0), Vector3(-33.5, -88.3, -12)]
	]
	for route in routes:
		var normal := await capture(route[0] + "-normal", route[1], route[2], true, 1.0)
		var backup := await capture(route[0] + "-emergency", route[1], route[2], false, 1.0)
		check(normal.x > 0.008, route[0] + " normal light reaches rendered room surfaces")
		check(backup.x > 0.002, route[0] + " emergency burst reaches rendered room surfaces")
	for advanced in [true, false]:
		quality.set_advanced_lighting_enabled(advanced)
		var mode := "advanced" if advanced else "basic"
		var route: Array = routes[1]
		var bright := await capture(mode + "-hub-burst", route[1], route[2], false, 1.0)
		var dark := await capture(mode + "-hub-blackout", route[1], route[2], false, 0.0)
		# Measure the red signal itself. A luminance threshold intended for white
		# lamps understates a deliberately saturated red alarm by almost 5x.
		check(bright.y > dark.y + 0.01 and dark.x < 0.003, mode + " preserves red alarm contrast and a dark pause")
	current_scene = null
	base.queue_free()
	for frame in 10: await process_frame
	print("BASE LIGHT RENDER CHECKS ", checks, " FAILURES ", failures)
	quit(1 if failures else 0)
