extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
	run.call_deferred()

func check(value: bool, label: String) -> void:
	print("PASS " if value else "FAIL ", label)
	if not value:
		failures.append(label)

func run() -> void:
	var surface := StaticBody3D.new()
	root.add_child(surface)
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(100, 1, 100)
	collision.shape = box
	collision.position.y = -0.5
	surface.add_child(collision)
	var actor := CharacterBody3D.new()
	root.add_child(actor)
	var camera := Camera3D.new()
	actor.add_child(camera)
	var tracks = load("res://scripts/effects/snow_tracks.gd").new()
	tracks.terrain_path = NodePath("../" + str(surface.name))
	tracks.footprint_scene = load("res://scenes/objects/effects/snow_footprint.tscn")
	tracks.tread_scene = load("res://scenes/objects/effects/snow_tread.tscn")
	tracks.ski_scene = load("res://scenes/objects/effects/snow_ski.tscn")
	root.add_child(tracks)
	tracks.set_physics_process(false)
	await physics_frame
	await process_frame
	for yaw in [0.0, PI * 0.5, -PI * 0.75]:
		actor.rotation.y = yaw
		var forward := -actor.global_basis.z
		var right := actor.global_basis.x
		for direction in [forward, -forward, right, -right, (forward + right).normalized()]:
			tracks._actors.clear()
			actor.position = Vector3.ZERO
			tracks._sample(actor, false)
			actor.position += direction * 0.8
			camera.rotation = Vector3(0.7, 1.4, 0.2)
			var before: int = tracks._marks.size()
			tracks._sample(actor, false)
			check(tracks._marks.size() == before + 1, "movement creates one contact mark")
			if tracks._marks.size() != before + 1:
				continue
			var mark: Decal = tracks._marks[-1].node
			check((-mark.global_basis.z).dot(forward) > 0.999, "toes follow body heading at yaw %.2f, movement %s" % [yaw, direction])
			check((mark.global_position - actor.global_position).dot(right) < -0.12, "left step stays on body's left")
			actor.position += direction * 0.8
			tracks._sample(actor, false)
			mark = tracks._marks[-1].node
			check((mark.global_position - actor.global_position).dot(right) > 0.12, "right step stays on body's right")
	var before: int = tracks._marks.size()
	tracks._sample(actor, false)
	check(tracks._marks.size() == before, "turning camera while stationary creates no new marks")
	actor.position += Vector3(10, 0, 0)
	tracks._sample(actor, false)
	check(tracks._marks.size() == before, "teleport creates no connecting marks")
	actor.position.y = 3
	tracks._sample(actor, false)
	actor.position.x += 0.8
	tracks._sample(actor, false)
	check(tracks._marks.size() == before, "airborne movement creates no marks")
	actor.position = Vector3.ZERO
	tracks._actors.clear()
	tracks._sample(actor, true)
	actor.position += actor.global_basis.x
	tracks._sample(actor, true)
	check(tracks._marks.size() == before + 3, "vehicle still creates a tread and two ski marks")
	if tracks._marks.size() == before + 3:
		var tread: Decal = tracks._marks[-3].node
		check((-tread.global_basis.z).dot(-actor.global_basis.z) > 0.999, "vehicle tracks retain vehicle heading")
	print("RESULT ", failures)
	quit(0 if failures.is_empty() else 1)
