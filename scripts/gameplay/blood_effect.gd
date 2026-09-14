extends RefCounted

static func spawn(source: Node3D, point: Vector3) -> void:
	var world: Node = source.get_tree().current_scene
	if world == null:
		world = source.get_parent()
	var particles := CPUParticles3D.new()
	particles.emitting = false
	particles.one_shot = true
	particles.amount = 36
	particles.lifetime = 0.95
	particles.explosiveness = 1.0
	particles.direction = Vector3.UP
	particles.spread = 100.0
	particles.initial_velocity_min = 1.0
	particles.initial_velocity_max = 3.0
	particles.gravity = Vector3(0, -7, 0)
	var mesh := SphereMesh.new()
	mesh.radius = 0.045
	mesh.height = 0.09
	mesh.radial_segments = 6
	mesh.rings = 3
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.32, 0.006, 0.012)
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material = material
	particles.mesh = mesh
	world.add_child(particles)
	particles.global_position = point
	particles.finished.connect(particles.queue_free)
	particles.restart()
	particles.emitting = true
	var hit := source.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(point, point + Vector3.DOWN * 4.0, 1))
	if not hit.is_empty():
		var stain := MeshInstance3D.new()
		var disc := CylinderMesh.new()
		disc.top_radius = 0.28
		disc.bottom_radius = 0.28
		disc.height = 0.003
		disc.radial_segments = 9
		disc.material = material
		stain.mesh = disc
		stain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		world.add_child(stain)
		stain.global_position = hit.position + hit.normal * 0.009
		stain.scale = Vector3(1.0, 1.0, 0.65)
		stain.rotation.y = randf() * TAU
		source.get_tree().create_timer(25.0).timeout.connect(stain.queue_free)
