extends SceneTree
func _initialize():
 var st:=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
 for i in 16:
  for j in 12:
   for ij in [Vector2(i,j),Vector2(i+1,j),Vector2(i,j+1),Vector2(i+1,j),Vector2(i+1,j+1),Vector2(i,j+1)]:
    var t:float=ij.x/16;var s:float=ij.y/12
    var width:=lerpf(.90,.63,t);var x:=lerpf(-40.25,-38.8,t)
    var z:float=3+(s*2-1)*width
    var y:=-.034+.024*sin(t*PI)*pow(sin(s*PI),.7)-.06*smoothstep(.65,1,t)
    st.set_uv(Vector2(x,z)/2.4);st.add_vertex(Vector3(x,y,z))
 st.generate_normals();var mesh:=st.commit();assert(ResourceSaver.save(mesh,"res://assets/models/architecture/arctic_base_rebuild/entry_snow_tongue.res")==OK)
 print("PASS entrance snow tongue generated");quit()
