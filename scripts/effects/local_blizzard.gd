extends Node3D
## One local snow field with spatial fog; WorldLighting owns camera Environment.
@export var enabled := true
@export_range(8.0, 40.0) var calm_visibility := 22.8
@export_range(5.0, 25.0) var gust_visibility := 12.54
@export var fog_color := Color(0.64, 0.71, 0.76)
@export_range(4.0, 60.0) var gust_period := 18.0
var gust := 0.0
var outside_weight := 0.0
var _elapsed := 0.0
var _camera: Camera3D
var _last_position := Vector3.ZERO
@onready var flakes: GPUParticles3D = $Flakes
@onready var snow_material: ShaderMaterial = flakes.draw_pass_1.material
var fog_material: ShaderMaterial
var fog_quad: MeshInstance3D

func _ready() -> void:
	add_to_group("local_blizzard")
	# Mutable opacity and speed belong to this world instance only.
	flakes.draw_pass_1 = flakes.draw_pass_1.duplicate()
	flakes.draw_pass_1.material = snow_material.duplicate()
	snow_material = flakes.draw_pass_1.material
	# Weather covers ordinary transparent surfaces too; local flakes draw last.
	snow_material.render_priority = 127
	var base := get_parent().get_parent() as Node3D
	fog_material = ShaderMaterial.new()
	fog_material.render_priority = 126
	fog_material.shader = preload("res://assets/shaders/exterior_blizzard.gdshader")
	# Current upper-floor footprint, in base-local coordinates; both passes share it.
	for material: ShaderMaterial in [fog_material, snow_material]:
		material.set_shader_parameter("clear_min", PackedVector3Array([Vector3(-38.15,-3,-10.1),Vector3(-9.4,-3,-9.3),Vector3(9.85,-3,-10.1),Vector3(-10.1,-3,-27.55),Vector3(-10.1,-3,9.85),Vector3(-10.55,-3,-2.72),Vector3(7.65,-3,-2.72),Vector3(-2.72,-3,-10.55),Vector3(-2.72,-3,7.65)]))
		material.set_shader_parameter("clear_max", PackedVector3Array([Vector3(-9.85,6.45,10.1),Vector3(9.3,9.05,9.3),Vector3(35.55,6.45,10.1),Vector3(10.1,6.45,-9.85),Vector3(10.1,6.45,27.55),Vector3(-7.65,8.95,2.72),Vector3(10.55,8.95,2.72),Vector3(2.72,8.95,-7.65),Vector3(2.72,8.95,10.55)]))
		material.set_shader_parameter("base_inverse", base.global_transform.affine_inverse())
	fog_quad = MeshInstance3D.new()
	fog_quad.name = "ExteriorFog"
	var quad := QuadMesh.new()
	quad.size = Vector2(2,2)
	fog_quad.mesh = quad
	fog_quad.material_override = fog_material
	fog_quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	fog_quad.extra_cull_margin = 16384
	add_child(fog_quad)

func advance(camera: Camera3D, indoor_mix: float, delta: float, sheltered: bool = false) -> void:
	_elapsed += delta
	var wave := sin(_elapsed * TAU / maxf(gust_period, 4.0) - 0.8) * 0.5 + 0.5
	gust = smoothstep(0.25, 0.95, wave)
	outside_weight = (1.0 - indoor_mix) if enabled else 0.0
	var point := camera.get_global_transform_interpolated().origin
	var reset := camera != _camera or point.distance_to(_last_position) > 8.0
	global_position = point + Vector3(-3.0, 1.5, -1.0)
	_camera = camera
	_last_position = point
	var was_exposed := flakes.visible
	var exposed := enabled
	if sheltered:
		for portal: AcousticPortal in get_tree().get_nodes_in_group("acoustic_portals"):
			if point.distance_to(portal.global_position) < 18.0:
				global_position = portal.global_position - portal.global_basis.z * 6.0 + Vector3.UP * 2.0
				break
	flakes.visible = exposed
	flakes.emitting = exposed
	if exposed and (reset or not was_exposed): flakes.restart()
	flakes.speed_scale = lerpf(0.8, 1.35, gust)
	snow_material.set_shader_parameter("opacity", lerpf(0.5, 0.8, gust) * 0.87)
	fog_quad.global_position = point
	fog_quad.visible = enabled
	fog_material.set_shader_parameter("visibility_distance", visibility_distance())
	fog_material.set_shader_parameter("storm_color", fog_color)

func visibility_distance() -> float:
	return lerpf(calm_visibility, gust_visibility, gust)

func local_storm_intensity() -> float:
	return lerpf(0.55, 1.0, gust) * outside_weight * 0.87 if enabled else 0.0
