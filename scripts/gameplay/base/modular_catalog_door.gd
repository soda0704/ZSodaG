@tool
extends Node3D
## Original scene retained for rollback/audio only, with no render or physics presence.
var _leaf_materials: Array[ShaderMaterial] = []
var _last_transform := Transform3D.IDENTITY

func _ready() -> void:
 $LegacyFrame.hide()
 $LegacyFrame.process_mode = Node.PROCESS_MODE_DISABLED
 for body in $LegacyFrame.find_children("*", "CollisionObject3D", true, false):
  body.collision_layer = 0
  body.collision_mask = 0
 for csg in $LegacyFrame.find_children("*", "CSGShape3D", true, false): csg.use_collision = false
 var audio := $LegacyFrame.get_node_or_null("DoorAudio")
 if audio != null and not has_node("DoorAudio"):
  var copy := audio.duplicate()
  copy.name = "DoorAudio"
  add_child(copy)

 for mesh: MeshInstance3D in $ClosedPreview.find_children("*", "MeshInstance3D", true, false):
  for surface in mesh.mesh.get_surface_count():
   var source := mesh.mesh.surface_get_material(surface) as StandardMaterial3D
   if source == null: continue
   var material := ShaderMaterial.new()
   material.shader = preload("res://assets/shaders/catalog_door_leaf.gdshader")
   material.set_shader_parameter("albedo", source.albedo_color)
   material.set_shader_parameter("albedo_texture", source.albedo_texture)
   material.set_shader_parameter("orm_texture", source.roughness_texture)
   material.set_shader_parameter("normal_texture", source.normal_texture)
   material.set_shader_parameter("metallic", source.metallic)
   material.set_shader_parameter("roughness", source.roughness)
   material.set_shader_parameter("normal_scale", source.normal_scale)
   material.set_shader_parameter("normal_enabled", source.normal_enabled)
   material.set_shader_parameter("ao_enabled", source.ao_enabled)
   material.set_shader_parameter("ao_light_affect", source.ao_light_affect)
   material.set_shader_parameter("uv_scale", source.uv1_scale)
   material.set_shader_parameter("uv_offset", source.uv1_offset)
   var size: Vector3 = get_meta("passage_size")
   material.set_shader_parameter("aperture", Vector2(size.x,size.y))
   mesh.set_surface_override_material(surface,material)
   _leaf_materials.append(material)
 _sync_clip_transform()

func _sync_clip_transform() -> void:
 _last_transform = global_transform
 for material in _leaf_materials:
  material.set_shader_parameter("door_world_to_local", global_transform.affine_inverse())

func _process(_delta: float) -> void:
 if global_transform != _last_transform: _sync_clip_transform()
