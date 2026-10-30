extends SceneTree
var failures := 0
var checks := 0
var base: Node3D
var state: BaseGameplayController
var breaker: BaseMainBreaker
var player: GamePlayer
var save_path: String
var capture := false

func _initialize() -> void:
	save_path = "user://breaker_wiring_%d.cfg" % OS.get_process_id()
	ProjectSettings.set_setting(BaseGameplayController.TEST_SAVE_PATH_SETTING, save_path)
	capture = "--capture" in OS.get_cmdline_user_args()
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	print("PASS " if ok else "FAIL ", label)
	if not ok: failures += 1

func settle() -> void:
	for frame in 6:
		# Movement is frozen by this fixture; keep the real presentation updating.
		if is_instance_valid(player): player.update_character_animation(1.0 / 60.0)
		await physics_frame

func boot() -> void:
	base = load("res://scenes/levels/base_blockout_v03.tscn").instantiate()
	root.add_child(base)
	current_scene = base
	await settle()
	state = base.get_node("BaseGameplayController")
	breaker = get_first_node_in_group("main_breaker")
	player = get_first_node_in_group("local_player")
	player.set_physics_process(false)
	player.survival.set_physics_process(false)
	player.survival.debug_invincible = true
	root.get_node("GameMenu").force_close_menu()
	await visit()

func visit() -> void:
	player.teleport_authoritative(breaker.global_position - breaker.global_basis.z * 2.0 - Vector3.UP*1.3, breaker.global_rotation.y + PI)
	player.camera.look_at(breaker.interaction_point.global_position)
	await settle()

func click(contact: WiringContact) -> void:
	var at := breaker.wiring.camera.unproject_position(contact.global_position)
	check(breaker.wiring.contact_at(at) == contact, "real camera ray reaches " + contact.name)
	var event := InputEventMouseButton.new()
	event.position = root.get_final_transform() * at
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	Input.parse_input_event(event)
	await settle()
	event.pressed = false
	Input.parse_input_event(event)
	await settle()

func screenshot(label: String) -> void:
	if not capture or DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tools/.local/breaker-" + label + ".png")

func run() -> void:
	Engine.max_fps = 60
	root.size = Vector2i(1280, 800)
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(Vector2i(1280, 800))
		DisplayServer.window_set_position(Vector2i(-1600, 30))
	await boot()
	check(breaker.get_node("%Housing").mesh.resource_path.ends_with("housing.obj"), "supplied assembled control housing used")
	check(player.get_interaction_target() == breaker, "normal player ray reaches replacement breaker")
	player.try_authoritative_interaction()
	check(not state.main_breaker_on, "switch still refuses startup without fuel")
	state.refill_authoritative(1, 30)
	player.try_authoritative_interaction()
	check(state.main_breaker_on, "normal interaction powers the base")
	state.set_process(false)
	var before_off := state.fuel_liters
	check(breaker.get_interaction_prompt() == "Выключить главный щит", "powered switch offers manual shutdown")
	breaker.network_interact(2, player)
	check(state.main_breaker_on, "wrong owner cannot switch off another player's interaction")
	player.try_authoritative_interaction()
	check(not state.main_breaker_on and state.fuel_delivered and is_equal_approx(state.fuel_liters, before_off), "normal E switches off without losing gasoline")
	state._process(2.0)
	check(is_equal_approx(state.fuel_liters, before_off), "manual shutdown stops generator consumption")
	check(not base.get_node("BasePowerLightingController").is_standard_powered and not base.get_node("Elevator_Functional_Blockout").is_powered, "manual shutdown reaches lights and lift without reserve")
	check(state.save_progress_authoritative(false, "manual", "Breaker regression"), "explicit daily save records manual shutdown")
	check(not state.load_saved_snapshot().main_breaker_on, "manual off state is saved")
	var reserve_snapshot := state.get_snapshot()
	reserve_snapshot.elevator_backup_installed = true
	state._broadcast_snapshot(reserve_snapshot)
	check(state.is_elevator_powered() and base.get_node("Elevator_Functional_Blockout").is_powered, "installed reserve keeps lift powered while main switch is off")
	player.try_authoritative_interaction()
	check(state.main_breaker_on, "manual off can be followed by normal E startup")
	state.set_process(true)
	await create_timer(0.7).timeout
	await screenshot("closed-on")
	var snapshot := state.get_snapshot()
	snapshot.day_index = 2
	snapshot.main_breaker_on = false
	snapshot.phase = BaseGameplayController.BasePhase.RESTORING_POWER
	snapshot.maintenance = {"wires_required": true, "wire_order": [2, 0, 3, 1], "wire_links": []}
	state._broadcast_snapshot(snapshot)
	await create_timer(0.7).timeout
	check(not state.main_breaker_on and not breaker.get_node("Wiring/Board").visible, "day-two failure keeps service door shut until E")
	check(not state.activate_main_breaker_authoritative(1), "unrepaired circuits block main power")
	var original_camera := player.camera
	player.pickup_world_item_authoritative(&"flashlight", {"battery_charge": 1.0})
	player.try_authoritative_interaction()
	await create_timer(0.55).timeout
	check(breaker.wiring.active and root.get_camera_3d() == breaker.wiring.camera, "production interaction opens 3D repair camera")
	var repair_beam := breaker.wiring.get_node("RepairCamera/RepairBeam") as SpotLight3D
	check(repair_beam.is_visible_in_tree() and is_zero_approx(repair_beam.position.x) and is_zero_approx(repair_beam.position.y), "repair beam follows the exact camera center")
	check(not player.flashlight.beam.visible and not player.flashlight.spill.visible, "repair suppresses the old off-axis handheld beam")
	var charge_before := player._battery_charge
	player.update_authoritative_flashlight_battery(0.5)
	check(player._battery_charge < charge_before, "centered repair light still consumes the real battery")
	var cover_deadline := Time.get_ticks_msec() + 1500
	while breaker.cover_animation.is_playing() and Time.get_ticks_msec() < cover_deadline: await process_frame
	check(breaker._cover_open and breaker.get_node("Wiring/Board").visible and absf(breaker.cover.rotation.y + 1.95) < 0.05, "E opens the hinged physical cover")
	player.refresh_crosshair_visibility()
	Input.action_press("move_forward")
	player.collect_local_input()
	check(player._input_move == Vector2.ZERO and not player.crosshair.visible, "repair blocks movement and first-person crosshair")
	Input.action_release("move_forward")
	await screenshot("repair-empty")
	await click(breaker.wiring.get_node("Board/Source0"))
	await click(breaker.wiring.get_node("Board/Output1"))
	check(state.maintenance.wire_links.is_empty() and breaker.wiring.selected == 0, "wrong terminal preserves plug and makes no progress")
	await click(breaker.wiring.get_node("Board/Output2"))
	check(state.maintenance.wire_links == [0], "real mouse interaction confirms only the correct circuit")
	var seat: AnimationPlayer = breaker.wiring.get_node("Board/Output2/SeatAnimation")
	var tip: Node3D = breaker.wiring.get_node("Board/Output2/InsertionTip")
	seat.play(&"seat"); seat.seek(0, true); seat.advance(.08)
	check(tip.visible and tip.position.z > .02 and tip.position.z < .12, "native connection clip moves the physical plug into the socket")
	await screenshot("connector-seating")
	seat.advance(.3)
	check(not tip.visible, "connection clip leaves no overlapping temporary plug")
	check(not state.connect_wire_authoritative(1, 0, 2), "duplicate connection rejected")
	check(not state.connect_wire_authoritative(2, 1, 0) and not state.connect_wire_authoritative(1, 4, 0), "unregistered peer and invalid row rejected")
	await screenshot("repair-partial")
	var escape := InputEventAction.new()
	escape.action = &"pause"
	escape.pressed = true
	Input.parse_input_event(escape)
	await settle()
	check(not breaker.wiring.active and root.get_camera_3d() == original_camera and get_first_node_in_group("wiring_ui") == null, "Escape returns camera and unlocks player")
	check(not root.get_node("GameMenu").is_menu_open(), "closing repair does not also open pause menu")
	check(not breaker._cover_open, "leaving service view closes cover")
	check(not repair_beam.visible and player.flashlight.beam.is_visible_in_tree(), "leaving repair restores the handheld beam")
	player.apply_held_item_inventory(&"m4a1", {})
	player.weapon.apply_state(&"m4a1", 12, 0)
	player.tape_count = 1
	check(player.perform_inventory_action_authoritative(&"mount_light"), "repair test attaches the real flashlight to M4A1")
	player.try_authoritative_interaction()
	await settle()
	check(repair_beam.is_visible_in_tree() and not player.weapon._mounted_beam.visible, "mounted flashlight also transfers to the centered repair beam")
	player._flashlight_enabled = false
	await settle()
	check(not repair_beam.visible, "repair cannot produce light from a switched-off flashlight")
	player._flashlight_enabled = true
	player._battery_charge = 0.0
	await settle()
	check(not repair_beam.visible, "repair cannot produce light from an empty battery")
	player._battery_charge = 0.9
	await settle()
	breaker.wiring.close()
	await settle()
	check(not repair_beam.visible and player.weapon._mounted_beam.is_visible_in_tree(), "leaving repair restores the mounted beam")
	player.survival.dead = true
	check(not state.connect_wire_authoritative(1, 1, 0), "dead player cannot repair")
	player.survival.dead = false
	player._is_sleeping_in_bunk = true
	check(not state.connect_wire_authoritative(1, 1, 0), "sleeping player cannot repair")
	player._is_sleeping_in_bunk = false
	player.teleport_authoritative(breaker.global_position - breaker.global_basis.z * 10, 0)
	check(not state.connect_wire_authoritative(1, 1, 0), "distant repair rejected")
	await visit()
	var wall := load("res://tools/tests/fixtures/terminal_occluder.tscn").instantiate() as Node3D
	base.add_child(wall)
	wall.global_position = (player.camera.global_position + breaker.interaction_point.global_position)*0.5
	wall.global_rotation.y = breaker.global_rotation.y
	await settle()
	check(not state.connect_wire_authoritative(1, 1, 0), "wall blocks authoritative wire requests")
	breaker.network_interact(1, player)
	check(not breaker.wiring.active, "wall also blocks opening the repair view")
	wall.queue_free()
	await settle()
	player.try_authoritative_interaction()
	await settle()
	check(state.save_progress_authoritative(), "partial repair can be saved while camera is active")
	base.queue_free()
	await settle()
	check(get_first_node_in_group("wiring_ui") == null, "scene unload releases repair input lock")
	await boot()
	check(state.maintenance.wire_links == [0] and state.maintenance.wires_required and not breaker.wiring.active, "continue restores partial circuits without reopening camera")
	check(not breaker.cover_animation.is_playing(), "continue applies cover pose without replaying animation")
	check(not breaker.wiring.connector_audio.playing and not breaker.wiring.get_node("Board/Output2/SeatAnimation").is_playing() and not breaker.wiring.get_node("Board/Output2/InsertionTip").visible, "continue never replays connection audio or plug movement")
	check(not breaker._cover_open and not breaker.get_node("Wiring/Board").visible, "continue restores a closed door until a new interaction")
	player.try_authoritative_interaction()
	await create_timer(0.45).timeout
	for pair in [[1, 0], [2, 3], [3, 1]]:
		await click(breaker.wiring.get_node("Board/Source%d" % pair[0]))
		await click(breaker.wiring.get_node("Board/Output%d" % pair[1]))
	check(state.maintenance.wire_links.size() == 4 and not state.maintenance.wires_required, "all four physical connections finish existing maintenance task")
	check(not state.main_breaker_on and breaker.wiring.active, "completion leaves main switch off for the player to operate")
	await screenshot("repair-complete")
	breaker.wiring.close()
	player.try_authoritative_interaction()
	check(state.main_breaker_on, "normal switch works again after 3D repair")
	await create_timer(0.7).timeout
	check(not breaker.get_node("Wiring/Board").visible, "powered breaker closes service compartment")
	await screenshot("repaired-on")
	base.queue_free()
	await settle()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	print("WIRING CHECKS ", checks, " FAILURES ", failures)
	quit(1 if failures else 0)
