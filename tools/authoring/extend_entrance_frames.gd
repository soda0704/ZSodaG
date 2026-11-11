extends SceneTree
func _initialize():
 var model=load("res://assets/models/architecture/arctic_base_rebuild/arctic_base_rebuild.glb").instantiate()
 var node=model.get_node("Fitted_Entrance_Reveals")
 var result:=ArrayMesh.new();var changed:=0
 print("FRAME AABB ",node.mesh.get_aabb()," transform ",node.transform)
 for s in node.mesh.get_surface_count():
  var arrays=node.mesh.surface_get_arrays(s)
  var vertices:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
  for i in vertices.size():
   if vertices[i].y<-.15:
    vertices[i].y-=.5;changed+=1
  arrays[Mesh.ARRAY_VERTEX]=vertices
  result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
  result.surface_set_material(s,node.mesh.surface_get_material(s))
 assert(changed>0)
 assert(ResourceSaver.save(result,"res://assets/models/architecture/arctic_base_rebuild/entrance_reveals_extended.res")==OK)
 print("PASS extended frame foot vertices=",changed," bottom=",result.get_aabb().position.y)
 model.free();quit()
