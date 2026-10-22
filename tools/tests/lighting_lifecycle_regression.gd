extends SceneTree
## Lighting lifecycle cases independent of the level's current decoration.
var failures := 0
var checks := 0

func _initialize() -> void:
	ProjectSettings.set_setting("northern_lab/testing/settings_path", "user://lighting_lifecycle_%d.json" % OS.get_process_id())
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)

func frames(count := 2) -> void:
	for frame in count: await process_frame

func run() -> void:
	Engine.max_fps = 60
	root.get_node("GameMenu").force_close_menu()
	var world := Node3D.new()
	root.add_child(world)
	var exterior := Node3D.new()
	exterior.name = "SnowExterior"
	world.add_child(exterior)
	var lighting := WorldLighting.new()
	lighting.name = "WorldLighting"
	var sun := DirectionalLight3D.new()
	sun.name = "OvercastSun"
	lighting.add_child(sun)
	var circuit := Node3D.new()
	circuit.name = "Standard"
	lighting.add_child(circuit)
	var hidden_group := Node3D.new()
	hidden_group.visible = false
	circuit.add_child(hidden_group)
	var inner_group := Node3D.new()
	hidden_group.add_child(inner_group)
	var hidden := SpotLight3D.new()
	inner_group.add_child(hidden)
	var disabled := SpotLight3D.new()
	disabled.visible = false
	circuit.add_child(disabled)
	world.add_child(lighting)
	lighting.set_process(false)
	lighting._update_lamps(Vector3.ZERO, 1.0)
	check(float(lighting._levels[hidden]) == 0.0, "hidden ancestors cannot consume lamp or shadow slots")
	check(not disabled.visible and float(lighting._levels[disabled]) == 0.0, "authored disabled lamp stays off")
	check(hidden.get_child_count() == 0 and disabled.get_child_count() == 0, "lamp registration never creates glowing squares or extra geometry")
	hidden_group.show()
	lighting._update_lamps(Vector3.ZERO, 1.0)
	check(hidden.visible and float(lighting._levels[hidden]) > 0.0, "restoring an ancestor restores its enabled lamps")
	lighting._update_lamps(Vector3(100, 0, 0), 1.0)
	lighting.set_lamp_enabled(hidden, false)
	lighting._update_lamps(Vector3.ZERO, 1.0)
	check(not hidden.visible, "distant culled lamp can be explicitly disabled before returning")
	lighting.set_lamp_enabled(hidden, true)
	lighting._update_lamps(Vector3.ZERO, 1.0)
	check(hidden.visible, "explicit re-enable returns a culled lamp to the pool")
	var added := SpotLight3D.new()
	added.light_energy = 2.5
	circuit.add_child(added)
	await frames()
	check(lighting._lamps.has(added), "new lamp joins the runtime pool")
	if lighting._lamps.has(added):
		lighting._update_lamps(Vector3.ZERO, 1.0)
		check(added.visible and is_equal_approx(added.light_energy, 2.5), "new lamp uses its authored brightness")
		added.hide()
		lighting._update_lamps(Vector3.ZERO, 1.0)
		check(not added.visible, "explicit runtime hide is respected by the pool")
		added.show()
		lighting._update_lamps(Vector3.ZERO, 1.0)
		check(added.visible, "explicit runtime show enables the lamp again")
		added.reparent(world)
		check(not lighting._lamps.has(added) and is_equal_approx(added.light_energy, 2.5), "detaching lamp releases pool state and restores authored output")
		added.reparent(circuit)
		await frames()
		added.free()
		check(lighting._lamps.size() == 2, "deleted lamp leaves no stale pool reference")
	var transient := SpotLight3D.new()
	circuit.add_child(transient)
	transient.free()
	await frames()
	check(lighting._lamps.size() == 2, "lamp freed before deferred registration is ignored safely")
	world.queue_free()
	await frames()
	var arena := load("res://tools/tests/fixtures/character_test_arena.tscn").instantiate() as Node3D
	root.add_child(arena)
	current_scene = arena
	var player := load("res://scenes/characters/player.tscn").instantiate() as GamePlayer
	player.setup(1, "Lighting lifecycle", Vector3(0, 0.1, 0), Color.WHITE)
	arena.get_node("Players").add_child(player)
	player.survival.set_physics_process(false)
	player.set_physics_process(false)
	player.apply_inventory_snapshot({"held_item": &"m4a1", "has_flashlight": true,
		"weapon_light_mounted": true, "battery_charge": 0.75, "flashlight_enabled": true})
	player.update_character_animation(1.0 / 60.0)
	await frames(5)
	check(player.weapon._mounted_beam.is_visible_in_tree(), "mounted lamp really illuminates before fault")
	check(not player.flashlight.malfunction_timer.is_stopped() and not player.flashlight.malfunction_timer.paused, "mounted lamp runs the same fault timer as the handheld lamp")
	player.toggle_flashlight_authoritative()
	await frames()
	check(player.flashlight.malfunction_timer.paused, "switching off mounted lamp pauses contact timer")
	var remaining := player.flashlight.malfunction_timer.time_left
	var charge := player._battery_charge
	await create_timer(0.15).timeout
	player.update_authoritative_flashlight_battery(1.0)
	check(is_equal_approx(player._battery_charge, charge) and is_equal_approx(player.flashlight.malfunction_timer.time_left, remaining), "switched-off mounted lamp consumes neither battery nor fault interval")
	player.toggle_flashlight_authoritative()
	await frames()
	check(not player.flashlight.malfunction_timer.paused and player.flashlight.malfunction_timer.time_left <= remaining, "switching on mounted lamp resumes rather than rerolls its interval")
	player.flashlight.begin_malfunction(true)
	await frames()
	check(player._flashlight_malfunctioning and not player._flashlight_enabled and player.needs_flashlight_shake(), "mounted contact fault reaches authoritative inventory and repair hint")
	for tap in 6:
		player._last_flashlight_shake_msec = -1000
		player.shake_flashlight_authoritative()
	await frames()
	check(not player._flashlight_malfunctioning and player.weapon._mounted_beam.is_visible_in_tree() and not player.flashlight.malfunction_timer.paused, "six repair taps restore mounted beam and start a fresh fault interval")
	player.weapon._mounted_lamp.hide()
	player.update_authoritative_flashlight_battery(1.0)
	check(is_equal_approx(player._battery_charge, charge), "hidden mounted lamp cannot silently drain battery")
	player.queue_free()
	arena.queue_free()
	await frames()
	print("LIGHTING LIFECYCLE CHECKS ", checks, " FAILURES ", failures)
	quit(0 if failures == 0 else 1)
