class_name WiringContact
extends Area3D

@export_range(0, 3) var row := 0
@export var is_output := false
@onready var label: Label3D = $Label
@onready var ring: MeshInstance3D = $Ring
@onready var focus_ring: MeshInstance3D = $Focus

func set_focus(value: bool) -> void:
	focus_ring.visible = value
