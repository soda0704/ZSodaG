extends SceneTree
func _initialize():
 var root_node:=Node3D.new();root_node.name="ArcticBase_ExteriorShell"
 var model=load("res://assets/models/architecture/arctic_base_rebuild/arctic_base_rebuild.glb").instantiate();model.name="Model";root_node.add_child(model);model.owner=root_node;root_node.set_editable_instance(model,true)
 var proxy:MeshInstance3D=model.get_node("ShellCollisionProxy")
 var vertices:=proxy.mesh.get_faces();var faces:=PackedVector3Array()
 for i in range(0,vertices.size(),3):
  var a:Vector3=proxy.transform*vertices[i];var b:Vector3=proxy.transform*vertices[i+1];var c:Vector3=proxy.transform*vertices[i+2]
  if (b-a).cross(c-a).length_squared()<.000000001:continue
  faces.append_array(PackedVector3Array([a,b,c]))
 var shape:=ConcavePolygonShape3D.new();shape.set_faces(faces);shape.backface_collision=true
 var path:="res://assets/models/architecture/arctic_base_rebuild/shell_collision.res"
 if ResourceSaver.save(shape,path,ResourceSaver.FLAG_COMPRESS)!=OK:quit(1);return
 if "--collision-only" in OS.get_cmdline_user_args():
  root_node.free();print("SHELL COLLISION REFRESHED");quit();return
 shape=load(path)
 for node in model.find_children("*","GeometryInstance3D",true,false):node.layers=1|(1<<16)|(1<<18)
 proxy.visible=false;proxy.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
 var body:=StaticBody3D.new();body.name="ShellBody";root_node.add_child(body);body.owner=root_node;body.add_to_group("exterior_shell_collision",true)
 var collision:=CollisionShape3D.new();collision.name="CollisionShape3D";collision.shape=shape;body.add_child(collision);collision.owner=root_node
 root_node.editor_description="Rebuilt insulated cassette envelope, curved PBR roof, service details, measured doorway openings; dedicated simplified collision."
 var text:="[gd_scene format=3 uid=\"uid://ojj5yvkr85ou\"]\n\n"
 text+="[ext_resource type=\"PackedScene\" path=\"res://assets/models/architecture/arctic_base_rebuild/arctic_base_rebuild.glb\" id=\"shell\"]\n"
 text+="[ext_resource type=\"Shape3D\" path=\"res://assets/models/architecture/arctic_base_rebuild/shell_collision.res\" id=\"collision\"]\n\n"
 text+="[ext_resource type=\"Material\" path=\"res://assets/models/architecture/arctic_base_rebuild/weathered_coating.tres\" id=\"coating\"]\n\n"
 text+="[node name=\"ArcticBase_ExteriorShell\" type=\"Node3D\"]\n\n[node name=\"Model\" parent=\".\" instance=ExtResource(\"shell\")]\n"
 for child in model.get_children():
  if child is GeometryInstance3D:
   text+="\n[node name=\"%s\" parent=\"Model\" index=\"%d\"]\nlayers = 327681\n"%[child.name,child.get_index()]
   if child is MeshInstance3D and child!=proxy:
    for surface in child.mesh.get_surface_count():
     var material=child.mesh.surface_get_material(surface)
     if material!=null and "Arctic_Powdercoat" in material.resource_name:text+="surface_material_override/%d = ExtResource(\"coating\")\n"%surface
   if child==proxy:text+="visible = false\ncast_shadow = 0\n"
 text+="\n[node name=\"ShellBody\" type=\"StaticBody3D\" parent=\".\" groups=[\"exterior_shell_collision\"]]\n\n[node name=\"CollisionShape3D\" type=\"CollisionShape3D\" parent=\"ShellBody\"]\nshape = ExtResource(\"collision\")\n\n[editable path=\"Model\"]\n"
 FileAccess.open("res://scenes/art/base/exterior/arctic_base_exterior_shell.tscn",FileAccess.WRITE).store_string(text)
 print("REBUILT SHELL collision triangles=",faces.size()/3," meshes=",model.find_children("*","MeshInstance3D",true,false).size());root_node.free();quit()
