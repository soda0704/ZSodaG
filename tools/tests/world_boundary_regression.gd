extends SceneTree
var failures: Array[String] = []
func _initialize(): run.call_deferred()
func check(ok: bool, message: String):
	print("PASS " if ok else "FAIL ", message)
	if not ok: failures.append(message)
func run():
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.current = true
	var world: Node3D = load("res://scenes/levels/snow_exterior.tscn").instantiate()
	root.add_child(world)
	await physics_frame
	await physics_frame
	check(not world.has_node("DistantMountains"), "distant mountain meshes removed")
	check(world.get_node("OvercastDayEnvironment").environment.sky.sky_material.panorama.resource_path.ends_with("alpine_overcast_panorama.exr"), "generated HDR panorama assigned")
	var terrain = world.get_node("Terrain3D")
	check(terrain.data.get_height(Vector3(275,0,0))-terrain.data.get_height(Vector3(325,0,0)) > 80.0, "east cliff has a substantial drop")
	check(absf(terrain.data.get_height(Vector3(-125,0,95))-8.0)<0.1, "arrival platform terrain preserved")
	for endpoint in [Vector3(-500,250,0),Vector3(500,250,0),Vector3(0,250,-500),Vector3(0,250,500)]:
		var hit := world.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(0,250,0),endpoint,1))
		check(not hit.is_empty() and hit.collider == world.get_node("WorldSafetyBoundary"), "invisible safety boundary: %s" % endpoint)
	check(world.get_node("BoundaryDressing").get_child_count()==30,"nine logs and twenty-one ice blocks authored")
	var panorama: Texture2D = world.get_node("OvercastDayEnvironment").environment.sky.sky_material.panorama
	check(panorama.get_width()==8192 and panorama.get_height()==4096,"8K HDR panorama imported")
	var valley := world.get_node("CliffValley")
	check(valley.get_node("DistantValleyFloor").mesh.get_aabb().end.x >= 2500,"distant valley continues beyond terrain edge")
	for effect in ["ValleyWindMist", "CliffSnowstorm"]:
		var particles: GPUParticles3D = valley.get_node(effect)
		check(particles.emitting and particles.process_material != null and particles.draw_pass_1 != null,"wind effect configured: " + effect)
	print("RESULT ",failures)
	quit(0 if failures.is_empty() else 1)
