extends SceneTree
## Verify cabin lamps against the actual hull, not an empty test room.
var failures: Array[String] = []

func _initialize() -> void:
	ProjectSettings.set_setting("northern_lab/testing/settings_path", "user://cabin_light_%d.json" % OS.get_process_id())
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	print("PASS " if ok else "FAIL ", label)
	if not ok: failures.append(label)

func run() -> void:
	var cabin: Node3D = load("res://scenes/objects/lobby/chinook.tscn").instantiate()
	root.add_child(cabin)
	await physics_frame
	await physics_frame
	for lamp_name in ["CabinRearLamp", "CabinFrontLamp"]:
		var lamp: SpotLight3D = cabin.get_node(lamp_name)
		check(absf(lamp.position.z) < 1.0 and absf(lamp.position.x) > 2.0 and lamp.position.y < 3.2, "%s is inside the cabin and placed along its length" % lamp_name)
		check(lamp.shadow_enabled and is_equal_approx(lamp.light_energy, 1.2) and lamp.light_color.is_equal_approx(Color(0.66, 0.76, 0.9)), "%s retains authored power, colour and shadows" % lamp_name)
		for target in [Vector3(lamp.position.x, 1.5, 0), Vector3(0, 1.5, 0)]:
			var offset: Vector3 = target - lamp.global_position
			check(offset.length() < lamp.spot_range and (-lamp.global_basis.z).angle_to(offset) < deg_to_rad(lamp.spot_angle), "%s cone reaches cabin floor %s" % [lamp_name, target])
			var query := PhysicsRayQueryParameters3D.create(lamp.global_position, target, 1)
			var hit := cabin.get_world_3d().direct_space_state.intersect_ray(query)
			check(hit.is_empty(), "%s light path is not blocked by the hull at %s" % [lamp_name, target])
	cabin.queue_free()
	await process_frame
	print("CABIN LIGHTING RESULT ", failures)
	quit(0 if failures.is_empty() else 1)
