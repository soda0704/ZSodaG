extends Node
## Instance-only emission keeps the modular library's shared materials intact.
@export_node_path("Node3D") var fixtures_path := NodePath("../../Floor_0_Base_Blockout/Center_Hub/Art/CenterHubShellArt/Light")
var _materials: Array[Dictionary] = []
var _standard: Node3D
var _emergency: Node3D

func _ready() -> void:
	_bind_fixtures.call_deferred()

func _bind_fixtures() -> void:
	var fixtures := get_node_or_null(fixtures_path)
	_standard = get_node_or_null("../Standard") as Node3D
	_emergency = get_node_or_null("../Emergency") as Node3D
	if fixtures == null or _standard == null or _emergency == null: return
	for mesh: MeshInstance3D in fixtures.find_children("*", "MeshInstance3D", true, false):
		if mesh.mesh == null: continue
		for surface in mesh.mesh.get_surface_count():
			var source := mesh.get_active_material(surface) as StandardMaterial3D
			if source == null or not source.emission_enabled: continue
			var material := source.duplicate() as StandardMaterial3D
			mesh.set_surface_override_material(surface, material)
			_materials.append({"material": material, "color": source.emission, "energy": source.emission_energy_multiplier})
	_standard.visibility_changed.connect(_update_emission)
	_emergency.visibility_changed.connect(_update_emission)
	_update_emission()

func _update_emission() -> void:
	if not is_instance_valid(_standard) or not is_instance_valid(_emergency): return
	var powered := _standard.is_visible_in_tree()
	var backup := _emergency.is_visible_in_tree()
	for entry in _materials:
		var material: StandardMaterial3D = entry.material
		material.emission_enabled = powered or backup
		material.emission = entry.color if powered else Color(1.0, 0.12, 0.035)
		material.emission_energy_multiplier = float(entry.energy) * (1.0 if powered else 0.25 if backup else 0.0)
