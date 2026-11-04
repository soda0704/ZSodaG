extends SceneTree
## Keep the distant surface on the same packed maps as SnowExterior's Terrain3D.
func _initialize():
 var path:="res://assets/environments/snow/meshes/polar_backdrop.res"
 var mesh:ArrayMesh=load(path)
 var material:ShaderMaterial=mesh.surface_get_material(0)
 material.shader=load("res://assets/environments/snow/polar_backdrop.gdshader")
 material.set_shader_parameter("entry_snow_albedo",load("res://assets/environments/snow/snow006/runtime_albedo_ao.res"))
 material.set_shader_parameter("entry_snow_normal_rough",load("res://assets/environments/snow/snow006/runtime_normal_rough.res"))
 material.set_shader_parameter("entry_snow_tile_size",2.4)
 material.set_shader_parameter("entry_snow_height",load("res://assets/environments/snow/snow006/runtime_height.res"))
 material.set_shader_parameter("entry_snow_relief_metres",0.006)
 material.set_shader_parameter("entry_snow_normal_strength",1.0)
 if ResourceSaver.save(mesh,path,ResourceSaver.FLAG_COMPRESS)!=OK:quit(1);return
 print("BACKDROP SNOW006 ",material.get_shader_parameter("entry_snow_albedo").resource_path)
 quit()
