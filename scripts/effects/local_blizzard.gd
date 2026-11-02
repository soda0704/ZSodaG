extends Node3D
## One local snow field; WorldLighting remains the sole owner of camera fog.
@export var enabled := true
@export_range(8.0, 40.0) var calm_visibility := 20.0
@export_range(5.0, 25.0) var gust_visibility := 11.0
@export var fog_color := Color(0.64, 0.71, 0.76)
@export_range(4.0, 60.0) var gust_period := 18.0
var gust := 0.0
var outside_weight := 0.0
var _elapsed := 0.0
var _camera: Camera3D
var _last_position := Vector3.ZERO
@onready var flakes: GPUParticles3D = $Flakes
@onready var snow_material: StandardMaterial3D = flakes.draw_pass_1.material

func _ready() -> void:
	add_to_group("local_blizzard")
	# Mutable opacity and speed belong to this world instance only.
	flakes.draw_pass_1 = flakes.draw_pass_1.duplicate()
	flakes.draw_pass_1.material = snow_material.duplicate()
	snow_material = flakes.draw_pass_1.material

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
	var exposed := outside_weight > 0.5 and not sheltered
	flakes.visible = exposed
	flakes.emitting = exposed
	if exposed and (reset or not was_exposed): flakes.restart()
	flakes.speed_scale = lerpf(0.8, 1.35, gust)
	snow_material.albedo_color.a = outside_weight * lerpf(0.5, 0.8, gust)

func visibility_distance() -> float:
	return lerpf(calm_visibility, gust_visibility, gust)

func local_storm_intensity() -> float:
	return lerpf(0.55, 1.0, gust) * outside_weight if enabled else 0.0
