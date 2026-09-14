@tool
extends Node3D

const EXTERIOR_LAYER := 1 << 18
const EXTERIOR_ROOF_GROUP := &"exterior_snow_roof"

func _ready() -> void:
	_finish_setup.call_deferred()

func _finish_setup() -> void:
	# Native collision aliases are not serialized by Terrain3D 1.0.2.
	# Full terrain collision also supports remote players away from the host camera.
	if not Engine.is_editor_hint():
		$Terrain3D.collision_mode = Terrain3DCollision.FULL_GAME
	var level_root := get_parent()
	if level_root == null:
		return
	var floor_level := level_root.get_node_or_null("Floor_0_Base_Blockout")
	if floor_level == null:
		return
	for geometry in floor_level.find_children("*", "GeometryInstance3D", true, false):
		geometry.layers |= EXTERIOR_LAYER
	if not has_node("RoofSnow"):
		var caps := Node3D.new()
		caps.name = "RoofSnow"
		add_child(caps)
		var snow := StandardMaterial3D.new()
		snow.albedo_color = Color("dce6ed")
		snow.roughness = 1.0
		for roof_node in get_tree().get_nodes_in_group(EXTERIOR_ROOF_GROUP):
			var roof := roof_node as CSGBox3D
			if roof == null or not floor_level.is_ancestor_of(roof):
				continue
			var mesh := MeshInstance3D.new()
			var box := BoxMesh.new()
			box.size = Vector3(roof.size.x + 0.12, 0.16, roof.size.z + 0.12)
			box.material = snow
			mesh.mesh = box
			mesh.layers = 1 | EXTERIOR_LAYER
			caps.add_child(mesh)
			mesh.global_transform = roof.global_transform
			mesh.global_position.y += roof.size.y * 0.5 + 0.06

func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	var camera := get_viewport().get_camera_3d()
	if camera != null:
		camera.far = maxf(camera.far, 750.0)
