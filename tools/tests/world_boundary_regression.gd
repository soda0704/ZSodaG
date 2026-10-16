extends SceneTree
class BoundaryProbe extends CharacterBody3D:
	func is_sleeping_in_bunk() -> bool: return false
	func is_local_player() -> bool: return false
class BoundaryLevel extends Node3D:
	var fall_out_depth:float=-235.0
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
	var sky_material:Material=world.get_node("OvercastDayEnvironment").environment.sky.sky_material
	var sky_panorama:Texture2D=sky_material.panorama if sky_material is PanoramaSkyMaterial else sky_material.get_shader_parameter("panorama")
	check(sky_panorama!=null and sky_panorama.resource_path.ends_with(".exr"), "authored HDR panorama assigned")
	var terrain = world.get_node("Terrain3D")
	check(terrain.data.get_height(Vector3(250,0,0))-terrain.data.get_height(Vector3(350,0,0)) > 90.0, "east cliff has a substantial drop")
	check(absf(terrain.data.get_height(Vector3(-125,0,95))-8.0)<0.1, "arrival platform terrain preserved")
	for endpoint in [Vector3(-550,250,0),Vector3(1600,250,0),Vector3(0,250,-800),Vector3(0,250,800)]:
		var hit := world.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(0,250,0),endpoint,1))
		check(not hit.is_empty() and hit.collider == world.get_node("WorldSafetyBoundary"), "invisible safety boundary: %s" % endpoint)
	var boundary := world.get_node("WorldSafetyBoundary")
	for height in [-210.0, 250.0, 690.0]:
		for i in 32:
			var start := Vector3(0,height,0)
			var endpoint := start + Vector3(cos(i*TAU/32),0,sin(i*TAU/32))*2300.0
			var hit := world.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(start,endpoint,1))
			check(not hit.is_empty() and hit.collider==boundary,"closed perimeter at height %.0f, direction %d" % [height,i])
	for endpoint in [Vector3(0,720,0),Vector3(0,-250,0)]:
		var start := Vector3(0,690,0) if endpoint.y>0 else Vector3(0,-210,0)
		var hit := world.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(start,endpoint,1))
		check(not hit.is_empty() and hit.collider==boundary,"vertical barrier: %s" % endpoint)
	var fixture:=BoundaryLevel.new();root.add_child(fixture);fixture.add_to_group("expedition_level")
	var probe := BoundaryProbe.new()
	world.add_child(probe)
	var shape := CollisionShape3D.new()
	shape.shape=CapsuleShape3D.new()
	probe.add_child(shape)
	var survival := PlayerSurvival.new()
	probe.add_child(survival)
	survival.set_physics_process(false)
	for point in [Vector3(-300,250,0),Vector3(0,250,300),Vector3(0,250,-300),Vector3(0,-162,0),Vector3(0,690,0)]:
		probe.position=point
		survival._sync_time=0.0
		survival._physics_process(0.01)
		check(survival.health==100.0 and not survival.dead,"coordinates do not kill player: %s" % point)
	probe.position=Vector3(0,250,0)
	var collision := probe.move_and_collide(Vector3(-700,0,0))
	check(collision!=null and collision.get_collider()==boundary and probe.position.x > -505.0,"character cannot walk through boundary")
	probe.queue_free()
	check(world.get_node("BoundaryDressing").get_child_count()==17,"lower decoration retained: five logs and twelve ice blocks")
	var panorama: Texture2D = sky_panorama
	check(panorama.get_width()==4096 and panorama.get_height()==2048,"4K HDR panorama imported")
	var valley := world.get_node("CliffValley")
	check(valley.get_node("DistantValleyFloor").mesh.get_aabb().end.x >= 2500,"distant valley continues beyond terrain edge")
	for effect in ["ValleyWindMist", "CliffSnowstorm"]:
		var particles: GPUParticles3D = valley.get_node(effect)
		check(particles.emitting and particles.process_material != null and particles.draw_pass_1 != null,"wind effect configured: " + effect)
	print("RESULT ",failures)
	quit(0 if failures.is_empty() else 1)

