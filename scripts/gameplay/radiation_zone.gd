class_name RadiationZone
extends Node3D

@export var radius: float = 9.0
@export var height: float = 8.0

func _ready() -> void:
	add_to_group("radiation_zones")
	var sign := Label3D.new()
	add_child(sign)
	sign.text = "☢ РАДИАЦИЯ\nОПАСНЫЙ РЕЗЕРВУАР"
	sign.position = Vector3(0, 4.8, 0)
	sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sign.font_size = 60
	sign.modulate = Color("efd15b")
	sign.no_depth_test = false
	var light := OmniLight3D.new()
	add_child(light)
	light.position.y = 1.0
	light.light_color = Color("b6c757")
	light.light_energy = 1.8
	light.omni_range = radius

func intensity_at(world_position: Vector3) -> float:
	var point := to_local(world_position)
	if point.y < -2.0 or point.y > height:
		return 0.0
	var distance := Vector2(point.x, point.z).length()
	if distance >= radius:
		return 0.0
	return lerpf(0.25, 1.0, 1.0 - distance / radius)
