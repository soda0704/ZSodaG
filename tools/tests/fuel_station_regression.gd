extends SceneTree
var failures := 0
var checks := 0
var state: BaseGameplayController
var base: Node3D
var player: GamePlayer
var tank: BaseFuelSocket
var save_path: String
var capture := false

func _initialize() -> void:
	save_path = "user://fuel_station_%d.cfg" % OS.get_process_id()
	ProjectSettings.set_setting(BaseGameplayController.TEST_SAVE_PATH_SETTING, save_path)
	capture = "--capture" in OS.get_cmdline_user_args()
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	print("PASS " if ok else "FAIL ", label)
	if not ok: failures += 1

func settle() -> void:
	for frame in 6: await physics_frame

func visit() -> void:
	player.teleport_authoritative(tank.global_position + Vector3(0, 0, -2.8), PI)
	player.camera.look_at(tank.interaction_point.global_position)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	await settle()

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
	tank = base.get_node("Floor_0_Base_Blockout/Gameplay/FuelFillInteractable")
	root.get_node("GameMenu").force_close_menu()
	await visit()

func screenshot(label: String) -> void:
	if not capture or DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tools/.local/fuel-" + label + ".png")

func run() -> void:
	Engine.max_fps = 60
	root.size = Vector2i(1280, 800)
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(Vector2i(1280, 800))
		DisplayServer.window_set_position(Vector2i(-1600, 30))
	await boot()
	check(tank.get_node("Tank").scene_file_path.contains("fuel_tank") and tank.get_node("Gauge/Model").scene_file_path.contains("pressure_gauge"), "supplied tank and gauge are authored instances")
	var dial_mesh: MeshInstance3D = tank.get_node("Gauge/Model/Sketchfab_model/root/GLTF_SceneRootNode/Back_0/Object_5")
	var visible_dial := dial_mesh.get_active_material(0) as StandardMaterial3D
	var surface_dial := dial_mesh.mesh.surface_get_material(0) as StandardMaterial3D
	check(visible_dial.albedo_texture.resource_path.ends_with("fuel_dial.svg") and surface_dial.albedo_texture.resource_path.ends_with("fuel_dial.svg"), "visible dial and native surface both use fuel liters without pressure fallback")
	check(base.find_child("Technical_Fuel_Tank_Blockout", true, false) == null and tank.find_children("*", "Label3D", true, false).is_empty(), "old blockout tank and textual gauge removed")
	check(player.get_interaction_target() == tank, "normal E ray reaches new tank")
	check(is_zero_approx(tank.gauge.current_animation_position), "empty fuel poses needle at zero")
	await screenshot("empty")
	var curve: Curve3D = tank.get_node("FuelLinePath").curve
	check(curve.point_count == 4 and curve.get_point_position(3).y < 0 and tank.get_node("FuelLine").get_meshes().size() == 2, "authored pipe is baked and enters the floor")
	player.refresh_interaction_prompt()
	check(not player.interaction_prompt_label.visible, "bare hands show no fuel prompt")
	tank.network_interact(1, player)
	check(is_zero_approx(state.fuel_liters), "bare hands cannot refill")
	player.pickup_world_item_authoritative(&"fuel_can", {"fuel_liters": 0.0})
	player.refresh_interaction_prompt()
	check(not player.interaction_prompt_label.visible, "empty canister hides E")
	tank.network_interact(1, player)
	check(is_zero_approx(state.fuel_liters), "empty canister transfers nothing")
	player.fuel_liters = 20.0
	player.refresh_interaction_prompt()
	var action_hint: String = root.get_node("SteamInput").get_action_hint(&"interact")
	check(tank.get_interaction_hint_for(player) == action_hint and (DisplayServer.get_name() == "headless" or (player.interaction_prompt_label.visible and player.interaction_prompt_label.text == action_hint)), "nonempty canister shows only action glyph")
	player.try_authoritative_interaction()
	await settle()
	check(is_equal_approx(state.fuel_liters, 20) and is_zero_approx(player.fuel_liters), "production E transfers full canister without losing fuel")
	check(is_equal_approx(tank.gauge.current_animation_position, 1.0/3.0), "native gauge poses at shared 20 L")
	check(tank.filler_animation.is_playing(), "refill uses authored cap clip")
	tank.network_interact(1, player)
	check(is_equal_approx(state.fuel_liters, 20), "repeat empty-canister E cannot duplicate fuel")
	player.fuel_liters = 7.25
	player.try_authoritative_interaction()
	check(is_equal_approx(state.fuel_liters, 27.25) and is_zero_approx(player.fuel_liters), "partly used canister transfers exact remainder")
	var snapshot := state.get_snapshot()
	snapshot.fuel_liters = 56.5
	snapshot.fuel_delivered = true
	state._broadcast_snapshot(snapshot)
	player.fuel_liters = 20.0
	player.try_authoritative_interaction()
	await settle()
	check(is_equal_approx(state.fuel_liters, 60) and is_equal_approx(player.fuel_liters, 16.5), "nearly full tank retains unused gasoline in canister")
	check(is_equal_approx(tank.gauge.current_animation_position, 1.0), "full tank puts needle at 60 L")
	player.refresh_interaction_prompt()
	check(not player.interaction_prompt_label.visible, "full tank hides unavailable refill action")
	tank.network_interact(1, player)
	check(is_equal_approx(player.fuel_liters, 16.5), "full tank consumes no extra fuel")
	await screenshot("full")
	snapshot = state.get_snapshot()
	snapshot.fuel_liters = 30.0
	state._broadcast_snapshot(snapshot)
	var before := state.fuel_liters
	tank.network_interact(2, player)
	check(is_equal_approx(state.fuel_liters, before), "wrong peer cannot use another player's canister")
	player.survival.dead = true
	tank.network_interact(1, player)
	check(is_equal_approx(state.fuel_liters, before), "dead player cannot refill")
	player.survival.dead = false
	player._is_sleeping_in_bunk = true
	tank.network_interact(1, player)
	check(is_equal_approx(state.fuel_liters, before), "sleeping player cannot refill")
	player._is_sleeping_in_bunk = false
	player.teleport_authoritative(tank.global_position + Vector3(0, 0, -12), PI)
	tank.network_interact(1, player)
	check(is_equal_approx(state.fuel_liters, before), "distant refill rejected by host")
	await visit()
	var wall := load("res://tools/tests/fixtures/terminal_occluder.tscn").instantiate() as Node3D
	base.add_child(wall)
	wall.global_position = (player.camera.global_position + tank.interaction_point.global_position)*0.5
	await settle()
	tank.network_interact(1, player)
	check(is_equal_approx(state.fuel_liters, before), "wall prevents remote refill")
	wall.queue_free()
	await settle()
	player.fuel_liters = NAN
	tank.network_interact(1, player)
	check(is_equal_approx(state.fuel_liters, before), "invalid fuel amount rejected")
	player.fuel_liters = 9.5
	player._publish_inventory()
	state.save_progress_authoritative()
	base.queue_free()
	await settle()
	await boot()
	check(is_equal_approx(state.fuel_liters, 30) and is_equal_approx(tank.gauge.current_animation_position, 0.5), "continue restores fuel and native needle pose")
	var needle_mesh: MeshInstance3D = tank.get_node("Gauge/Model/Sketchfab_model/root/GLTF_SceneRootNode/Needle_3/Object_12")
	var vertices: PackedVector3Array = needle_mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var tip := Vector3.ZERO
	for vertex in vertices:
		if Vector2(vertex.x, vertex.y).length_squared() > Vector2(tip.x, tip.y).length_squared(): tip = vertex
	var direction: Vector3 = needle_mesh.to_global(tip) - tank.get_node("Gauge").global_position
	var projected := Vector2(direction.dot(tank.global_basis.x), direction.dot(tank.global_basis.y)).normalized()
	check(projected.y > 0.999, "physical needle tip points at the 30 L tick at half capacity")
	await screenshot("half")
	if capture and DisplayServer.get_name() != "headless":
		player.teleport_authoritative(tank.global_position + Vector3(0, 0, -1.65), PI)
		player.camera.look_at(tank.get_node("Gauge").global_position)
		await settle()
		await screenshot("gauge-detail")
		await visit()
	state.main_breaker_on = true
	state._process(5.0)
	await settle()
	await process_frame
	await process_frame
	check(state.fuel_liters < 30 and tank.gauge.current_animation_position < .5, "consumption updates physical gauge")
	player.pickup_world_item_authoritative(&"pistol", {"rounds":12})
	player.refresh_interaction_prompt()
	check(not player.interaction_prompt_label.visible, "another held item hides refill prompt")
	base.queue_free()
	await settle()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	print("FUEL STATION CHECKS ", checks, " FAILURES ", failures)
	quit(1 if failures else 0)
