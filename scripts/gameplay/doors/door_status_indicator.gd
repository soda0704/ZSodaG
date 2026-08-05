class_name DoorStatusIndicator
extends Node3D

@export var locked_color: Color = Color(1.0, 0.025, 0.008, 1.0)
@export var unlocked_color: Color = Color(0.015, 0.95, 0.035, 1.0)

@onready var front_lens: MeshInstance3D = %FrontLens
@onready var back_lens: MeshInstance3D = %BackLens
@onready var status_light: OmniLight3D = %StatusLight

var is_unlocked: bool = false
var _lens_material: StandardMaterial3D


func _ready() -> void:
	_lens_material = (
		front_lens.get_active_material(0).duplicate()
		as StandardMaterial3D
	)
	front_lens.material_override = _lens_material
	back_lens.material_override = _lens_material
	set_unlocked(false)


func set_unlocked(value: bool) -> void:
	is_unlocked = value
	var next_color := unlocked_color if is_unlocked else locked_color
	status_light.light_color = next_color
	_lens_material.albedo_color = next_color.darkened(0.35)
	_lens_material.emission_enabled = true
	_lens_material.emission = next_color
	_lens_material.emission_energy_multiplier = 4.0
