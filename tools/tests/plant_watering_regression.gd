extends SceneTree

var checks := 0
var failures := 0
var base: Node3D
var state: BaseGameplayController
var player: GamePlayer
var container: Node3D
var button: PlantWateringButton
var cycles := 0
var capture := false

func _initialize() -> void:
	ProjectSettings.set_setting(ExpeditionSaveStore.ROOT_SETTING, "user://plant_watering_regression_%d" % OS.get_process_id())
	ProjectSettings.set_setting(ExpeditionSaveStore.LEGACY_PATHS_SETTING, {})
	# Permit persistence in the disposable F6 scene while still using the real
	# expedition-slot store under the isolated root above, not a flat test file.
	ProjectSettings.set_setting(BaseGameplayController.TEST_SAVE_PATH_SETTING, "")
	BaseGameplayController.save_scope = "solo"
	capture = "--capture" in OS.get_cmdline_user_args()
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	print("PASS " if ok else "FAIL ", label)
	if not ok: failures += 1

func settle() -> void:
	for frame in 8: await physics_frame

func boot() -> void:
	base = load("res://scenes/levels/Base_Blockout_v03.tscn").instantiate()
	root.add_child(base)
	current_scene = base
	await settle()
	state = base.get_node("BaseGameplayController")
	state.set_process(false)
	player = get_first_node_in_group("local_player")
	player.set_physics_process(false)
	player.survival.set_physics_process(false)
	player.survival.debug_invincible = true
	container = base.get_node("Floor_0_Base_Blockout/East_Living/Art/CommonRoomArt/Visual/PlantGrowingContainer")
	button = container.get_node("WateringButton")
	button.animation.animation_started.connect(func(name: StringName):
		if name == &"water": cycles += 1)
	root.get_node("GameMenu").force_close_menu()
	await visit()

func visit() -> void:
	player.teleport_authoritative(Vector3(button.global_position.x, 0.04, button.global_position.z + 1.05), 0)
	player.camera.look_at(button.interaction_point.global_position)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	await settle()

func powered() -> void:
	var snapshot := state.get_snapshot()
	snapshot.phase = BaseGameplayController.BasePhase.ACTIVE_DAY
	snapshot.main_breaker_on = true
	snapshot.fuel_delivered = true
	snapshot.fuel_liters = 20
	snapshot.elevator_backup_installed = true
	snapshot.maintenance = {}
	state._broadcast_snapshot(snapshot)

func screenshot(name: String, during_water: bool = false) -> void:
	if not capture or DisplayServer.get_name() == "headless": return
	player.camera.global_position = container.global_position + Vector3(0.1, 0.8, 1.85)
	player.camera.look_at(container.global_position + Vector3(0.095, 0.77, 0.35))
	player.interaction_prompt_label.hide()
	if during_water:
		for frame in 12: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tools/.local/plant-%s.png" % name)
	await visit()

func run() -> void:
	Engine.max_fps = 60
	if capture and DisplayServer.get_name() != "headless":
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(Vector2i(1280, 800))
		DisplayServer.window_set_position(Vector2i(-1600, 30))
		root.size = Vector2i(1280, 800)
	await boot()
	check(is_equal_approx(container.position.y, 0.835), "container raised 20 cm in authored kitchen scene")
	check(state.plant_last_watered_day == 0, "fresh expedition has unused watering")
	check(player.get_interaction_target() == button, "production E ray reaches the original rightmost button")
	check(button.can_use(1, player), "nearby live owner can use button")
	check(not state.water_plant_authoritative(1), "unpowered container cannot water")
	check(button.get_interaction_hint_for(player).is_empty(), "empty container does not advertise watering")
	var planted_fixture := state.get_snapshot()
	planted_fixture.plant_seed_planted = true
	state._broadcast_snapshot(planted_fixture)
	powered()
	check(button.get_interaction_hint_for(player).ends_with("Полить"), "powered button offers watering")
	check(not state.water_plant_authoritative(9999), "unknown peer rejected")
	player.survival.dead = true
	check(not state.water_plant_authoritative(1), "dead player rejected")
	player.survival.dead = false
	player.teleport_authoritative(Vector3(button.global_position.x, 0.04, button.global_position.z + 5), 0)
	check(not state.water_plant_authoritative(1), "remote activation beyond reach rejected")
	await visit()
	var blocker := StaticBody3D.new()
	var blocker_shape := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.5, 0.8, 0.08)
	blocker_shape.shape = shape
	blocker.add_child(blocker_shape)
	base.add_child(blocker)
	blocker.global_position = (player.camera.global_position + button.interaction_point.global_position) * 0.5
	await settle()
	check(not state.water_plant_authoritative(1), "watering through an occluding wall rejected")
	blocker.queue_free()
	await settle()
	await screenshot("watering-ready")
	player.try_authoritative_interaction()
	await settle()
	check(state.plant_last_watered_day == 1, "production E consumes shared watering for day one")
	check(button.animation.current_animation == &"water" and button.animation.is_playing(), "confirmed state starts native watering animation")
	button.animation.advance(0.65)
	check(container.get_node("SprayLeft").emitting and container.get_node("SprayRight").emitting and container.get_node("SoilSplashes").emitting, "native animation starts droplets and ground splashes")
	check(container.get_node("WaterAudio").playing, "native animation starts nearby liquid audio")
	await screenshot("watering-spray", true)
	var cycles_before := cycles
	for i in 4: player.try_authoritative_interaction()
	await settle()
	check(cycles == cycles_before and not state.water_plant_authoritative(1), "repeated and duplicate interactions cannot replay daily watering")
	check(button.get_interaction_hint_for(player) == "Сегодня уже полито", "used button reports shared daily limit")
	check(state.load_saved_snapshot().plant_last_watered_day == 1, "watering included in host progress save")
	var off := state.get_snapshot()
	off.main_breaker_on = false
	state._broadcast_snapshot(off)
	check(not container.get_node("SprayLeft").emitting and not container.get_node("SoilSplashes").emitting and not container.get_node("WaterAudio").playing, "power loss stops native effects")
	powered()
	check(not state.water_plant_authoritative(1), "switching power back on cannot reset daily use")
	base.queue_free()
	await process_frame
	await boot()
	check(state.plant_last_watered_day == 1 and not state.water_plant_authoritative(1), "re-entering game retains shared watering limit")
	check(button.animation.current_animation != &"water" and not container.get_node("SprayLeft").emitting, "loading saved state does not replay historical VFX")
	check(state.set_end_day_ready_authoritative(1, true) and state.set_peer_sleeping_authoritative(1, true), "production sleep consensus ready")
	check(state.advance_day_authoritative() and state.day_index == 2, "production sleep advances actual game day")
	check(state.plant_last_watered_day == 1 and not state.main_breaker_on, "previous use survives day transition and wiring outage")
	powered()
	await visit()
	check(state.water_plant_authoritative(1), "new game day permits exactly one new watering")
	check(state.plant_last_watered_day == 2 and not state.water_plant_authoritative(1), "second day shares the same repeat guard")
	var saved: ConfigFile = ExpeditionSaveStore.read("solo").config
	check(int(saved.get_value("base", "plant_last_watered_day", 0)) == 2, "daily state participates in ordinary expedition save format")
	saved.erase_section_key("base", "plant_last_watered_day")
	ExpeditionSaveStore.select("solo", 2)
	check(ExpeditionSaveStore.write(saved, "solo", "manual"), "legacy-format isolated save written")
	check(state.load_saved_snapshot().plant_last_watered_day == 0, "old saves safely default to unused watering")
	ExpeditionSaveStore.select("solo", 1)
	check(state.reset_day_one_authoritative() and state.plant_last_watered_day == 0, "new expedition resets daily plant care")
	base.queue_free()
	await process_frame
	print("PLANT WATERING CHECKS ", checks, " FAILURES ", failures)
	quit(1 if failures else 0)
