extends SceneTree
## Cross-section probes include slanted roofs and walls away from the route centre.
var report := {"physical_gaps": [], "backface_gaps": []}
func _initialize() -> void:
	run.call_deferred()
func run() -> void:
	var cave: Node3D = load("res://scenes/levels/cave_day7.tscn").instantiate()
	cave.get_node("HiveEncounter").set_script(null)
	root.add_child(cave)
	for frame in 3: await physics_frame
	var curve: Curve3D = cave.get_node("AuthoredRoute").curve
	var space := cave.get_world_3d().direct_space_state
	var total := curve.get_baked_length()
	for metre in range(20, floori(total) - 10, 2):
		var centre := curve.sample_baked(metre, true) + Vector3.UP * 0.8
		var side := (curve.sample_baked(metre + 0.2, true) - curve.sample_baked(metre - 0.2, true)).cross(Vector3.UP).normalized()
		for angle in 72:
			var direction := side * cos(angle * TAU / 72) + Vector3.UP * sin(angle * TAU / 72)
			var query := PhysicsRayQueryParameters3D.create(centre, centre + direction * 35, 1)
			query.hit_back_faces = true
			var hit := space.intersect_ray(query)
			if hit.is_empty():
				report.physical_gaps.append({"metre": metre, "angle": angle, "origin": [centre.x, centre.y, centre.z], "direction": [direction.x, direction.y, direction.z]})
			else:
				query.hit_back_faces = false
				if space.intersect_ray(query).is_empty(): report.backface_gaps.append({"metre": metre, "angle": angle})
	var file := FileAccess.open("res://tools/.local/cave-shell-audit.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report))
	print("CAVE SHELL physical gaps=", report.physical_gaps.size(), " backface gaps=", report.backface_gaps.size())
	# Snapshot actual saved topology, independent of old authoring caches.
	var faces := PackedVector3Array()
	var bodies := cave.get_node("ContinuousGeology").get_children()
	if cave.has_node("GeologySeamRepairs"): bodies.append(cave.get_node("GeologySeamRepairs"))
	for body in bodies:
		var mesh: MeshInstance3D = body.get_node("Bedrock")
		for vertex in mesh.mesh.get_faces(): faces.append(mesh.transform * vertex)
	var raw := FileAccess.open("res://tools/.local/cave-shell-faces.bin", FileAccess.WRITE)
	raw.store_buffer(faces.to_byte_array())
	print("CAVE SHELL triangles=", faces.size() / 3)
	cave.queue_free()
	await process_frame
	quit(0 if report.physical_gaps.is_empty() and report.backface_gaps.is_empty() else 1)
