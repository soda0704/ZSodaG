extends RefCounted

static func spawn(source: Node3D, point: Vector3) -> void:
	var particles := CPUParticles3D.new()
	source.get_tree().root.add_child(particles)
	particles.global_position = point
	particles.one_shot = true
	particles.amount = 24
	particles.lifetime = 0.65
	particles.explosiveness = 1.0
	particles.direction = Vector3.UP
	particles.spread = 100.0
	particles.initial_velocity_min = 1.0
	particles.initial_velocity_max = 3.0
	particles.gravity = Vector3(0, -7, 0)
	var mesh := SphereMesh.new()
	mesh.radius = 0.025
	mesh.height = 0.05
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.38, 0.005, 0.01)
	mesh.material = material
	particles.mesh = mesh
	particles.emitting = true
	particles.finished.connect(particles.queue_free)
