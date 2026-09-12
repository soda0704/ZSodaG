class_name DeveloperTestRoom
extends Node3D

const ROOM_POSITION := Vector3(110.0, 64.0, 110.0)
const HALF_SIZE := Vector3(16.0, 4.0, 12.0)


func _ready() -> void:
	name = "DeveloperTestRoom"
	position = ROOM_POSITION
	add_to_group("developer_test_room")
	var wall_material := StandardMaterial3D.new()
	wall_material.albedo_color = Color("626f79")
	wall_material.roughness = 0.82
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color("788690")
	floor_material.roughness = 0.7
	_add_surface("Floor", Vector3(32, 0.4, 24), Vector3(0, -0.2, 0), floor_material)
	_add_surface("Ceiling", Vector3(32, 0.35, 24), Vector3(0, 8.0, 0), wall_material)
	_add_surface("NorthWall", Vector3(32, 8, 0.4), Vector3(0, 4, -12), wall_material)
	_add_surface("SouthWall", Vector3(32, 8, 0.4), Vector3(0, 4, 12), wall_material)
	_add_surface("WestWall", Vector3(0.4, 8, 24), Vector3(-16, 4, 0), wall_material)
	_add_surface("EastWall", Vector3(0.4, 8, 24), Vector3(16, 4, 0), wall_material)
	for x in [-10.0, 0.0, 10.0]:
		for z in [-6.0, 6.0]:
			var light := OmniLight3D.new()
			light.position = Vector3(x, 6.8, z)
			light.light_color = Color("e6f2ff")
			light.light_energy = 8.0
			light.omni_range = 15.0
			light.omni_attenuation = 0.65
			light.shadow_enabled = true
			add_child(light)
	var label := Label3D.new()
	label.text = "DEV TEST ROOM\n/testroom — вернуться"
	label.position = Vector3(0, 3.2, -11.75)
	label.font_size = 72
	label.outline_size = 10
	add_child(label)


func _add_surface(node_name: String, size: Vector3, at: Vector3, material: Material) -> void:
	var body := StaticBody3D.new()
	body.name = node_name
	body.position = at
	add_child(body)
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	box.material = material
	mesh.mesh = box
	body.add_child(mesh)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)


func contains(point: Vector3) -> bool:
	var local := to_local(point)
	return absf(local.x) < HALF_SIZE.x and absf(local.z) < HALF_SIZE.z and local.y > -1.0 and local.y < 9.0


func spawn_position(index: int) -> Vector3:
	return to_global(Vector3(-1.2 + (index % 4) * 0.8, 0.15, 0.0))
