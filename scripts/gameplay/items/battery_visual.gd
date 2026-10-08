extends Node3D
## Selects an authored mesh; never changes geometry or material parameters.

@export var variants: MeshLibrary
@export_range(0,8) var variant_id := 0:
	set(value):
		variant_id = value
		if is_node_ready(): _apply_variant()

func _ready() -> void: _apply_variant()

func _apply_variant() -> void:
	if variants != null and variants.get_item_list().has(variant_id):
		$Body.mesh = variants.get_item_mesh(variant_id)
