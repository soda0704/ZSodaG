extends SceneTree
## Sightlines use the rendered triangles, not the opaque physics boxes of the grate.
const VISUAL_MASK := 1 << 29
const ENCLOSURE_MASK := 1 << 30
var checks := 0
var failures := 0
var lift: FunctionalElevatorController
var shapes := {}
var proxies: Node3D

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)

func settle() -> void:
	for frame in 6: await physics_frame

func build_visual_proxies() -> void:
	if is_instance_valid(proxies):
		proxies.free()
	proxies = Node3D.new()
	root.add_child(proxies)
	for visual in lift.find_children("*", "MeshInstance3D", true, false):
		# The test must work even when all sightlines pass through the cage's holes.
		if "SurfaceShaftGuard" in str(visual.get_path()) or not visual.is_visible_in_tree() or not visual.mesh: continue
		var id: int = visual.mesh.get_rid().get_id()
		if not shapes.has(id):
			var shape: ConcavePolygonShape3D = visual.mesh.create_trimesh_shape()
			shape.backface_collision = true
			shapes[id] = shape
		var body := StaticBody3D.new()
		body.collision_layer = VISUAL_MASK; body.collision_mask = 0
		body.set_meta("source", str(lift.get_path_to(visual)))
		proxies.add_child(body); body.global_transform = visual.global_transform
		var collision := CollisionShape3D.new(); collision.shape = shapes[id]
		body.add_child(collision)

func hit_visual(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3) -> bool:
	var ray := PhysicsRayQueryParameters3D.create(from, to, VISUAL_MASK)
	if not space.intersect_ray(ray).is_empty(): return true
	# Shared triangle-edge precision: verify a second ray only 0.1 mm away.
	ray.from += Vector3(0.0001, 0, 0.0001); ray.to += Vector3(0.0001, 0, 0.0001)
	return not space.intersect_ray(ray).is_empty()

func run() -> void:
	lift = load("res://scenes/objects/elevator/elevator_functional_blockout.tscn").instantiate()
	root.add_child(lift)
	lift.set_physics_process(false); lift.set_day(7)
	await settle()
	var space := lift.get_world_3d().direct_space_state
	for parked_floor in [1, 4, 5]:
		lift.restore_checkpoint_floor(parked_floor)
		await settle()
		build_visual_proxies()
		await settle()
		for height in [0.25, 1.65, 2.8, 4.4, 6.0, 9.0, 12.0]:
			var leaks := 0
			var samples := 0
			for angle_index in 16:
				var angle := TAU * angle_index / 16.0
				var radial := Vector3(cos(angle), 0, sin(angle))
				radial /= maxf(absf(radial.x), absf(radial.z))
				for distance in [3.46, 3.95, 5.0]:
					var from: Vector3 = radial * distance + Vector3.UP * height
					for x in range(-4, 5):
						for z in range(-4, 5):
							var aperture := Vector3(x * 0.84, -0.081, z * 0.84)
							var to: Vector3 = from + (aperture - from).normalized() * 300.0
							samples += 1
							if not hit_visual(space, from, to):
								leaks += 1
								if leaks <= 3: print("LEAK floor ",parked_floor," from ",from," aperture ",aperture)
			check(leaks == 0, "%d rendered sightlines, height %.2f, cabin floor %d: %d escapes to outside world" % [samples,height,parked_floor,leaks])
	proxies.free(); shapes.clear()
	lift.restore_checkpoint_floor(0)
	await settle()
	lift.get_node("SurfaceRockLining").collision_layer = ENCLOSURE_MASK
	lift.get_node("ShaftDepthEnclosure").collision_layer = ENCLOSURE_MASK
	for collider in lift.cabin.find_children("*", "CollisionShape3D", true, false):
		if collider.get_parent() is Area3D: continue
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = collider.shape; query.transform = collider.global_transform
		query.motion = Vector3(0,-90,0); query.collision_mask = ENCLOSURE_MASK
		check(space.intersect_shape(query).is_empty() and space.cast_motion(query)[0] == 1.0, "full 0–5 cabin stroke clears enclosure: " + str(lift.cabin.get_path_to(collider)))
	for floor in 6:
		var capsule := CapsuleShape3D.new(); capsule.radius = 0.35; capsule.height = 1.8
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = capsule; query.transform.origin = Vector3(-6,-18*floor+0.95,0)
		query.motion = Vector3(5,0,0); query.collision_mask = ENCLOSURE_MASK
		check(space.cast_motion(query)[0] == 1.0, "landing %d retains capsule clearance through doorway" % floor)
	lift.queue_free(); await process_frame
	print("SHAFT VISIBILITY CHECKS ",checks," FAILURES ",failures)
	quit(1 if failures else 0)
