extends SceneTree
## Exercise roof detection and the environment across the actual technical wing.
var failures: Array[String] = []

func _initialize() -> void:
	ProjectSettings.set_setting("northern_lab/testing/settings_path", "user://generator_lighting_%d.json" % OS.get_process_id())
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	print("PASS " if ok else "FAIL ", label)
	if not ok: failures.append(label)

func run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	current_scene = world
	world.add_child(load("res://scenes/levels/floor_0_base_blockout.tscn").instantiate())
	var exterior := Node3D.new()
	exterior.name = "SnowExterior"
	var environment := WorldEnvironment.new()
	environment.name = "OvercastDayEnvironment"
	environment.environment = Environment.new()
	environment.environment.fog_enabled = true
	environment.environment.fog_density = 0.01
	exterior.add_child(environment)
	world.add_child(exterior)
	var lighting := WorldLighting.new()
	var sun := DirectionalLight3D.new()
	sun.name = "OvercastSun"
	lighting.add_child(sun)
	world.add_child(lighting)
	lighting.set_process(false)
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.make_current()
	for frame in 4: await physics_frame
	for point in [Vector3(0, 1.75, 8), Vector3(0, 1.75, 11), Vector3(-3.5, 1.75, 17.5), Vector3(-3.5, 1.75, 19), Vector3(4, 1.75, 22), Vector3(-5, 1.75, 24)]:
		camera.position = point
		camera.reset_physics_interpolation()
		await process_frame
		lighting._process(0.5)
		check(lighting.is_covered(point), "technical route %s stays indoors" % point)
		check(is_equal_approx(camera.environment.ambient_light_energy, lighting.indoor_ambient) and is_zero_approx(camera.environment.fog_density), "technical route %s keeps indoor ambient and no outdoor haze" % point)
	check(not lighting.is_covered(Vector3(0, 1.75, 29)), "open exterior beyond the technical wing stays outdoors")
	check(not lighting.is_covered(Vector3(0, 7, 22)), "camera above the technical roof stays outdoors")
	world.queue_free()
	await process_frame
	print("GENERATOR LIGHTING RESULT ", failures)
	quit(0 if failures.is_empty() else 1)
