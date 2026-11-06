extends SceneTree
## Remove the obsolete corridor, replace the old fading backdrop, retire old weather sheets.
const DIR := "res://assets/environments/snow/expanded_terrain/"
const BACKUP := "res://tools/.local/snow-material-review/before-edge-fix/"
func polar_height(p:Vector2)->float:
	var upper:=8.0*smoothstep(45.0,160.0,p.length())
	var phase:=p.x*.075+p.y*.12+sin(p.x*.017-p.y*.011)*1.6
	var wind:=pow(.5+.5*sin(phase),3.0)*(.22+.10*sin(p.x*.009+p.y*.005))
	return lerpf(upper,-160.0,smoothstep(210.0,360.0,p.x))+wind+sin(p.x*.006+p.y*.004)*.22
func _initialize():run.call_deferred()
func run():
	if DirAccess.dir_exists_absolute(BACKUP):push_error("Edge backup already exists");quit(1);return
	DirAccess.make_dir_recursive_absolute(BACKUP)
	for file in ["terrain3d-01_00.res","terrain3d-01-01.res"]:DirAccess.copy_absolute(DIR+file,BACKUP+file)
	DirAccess.copy_absolute("res://scenes/art/environment/cliff_valley.tscn",BACKUP+"cliff_valley.tscn")
	var level:=Node3D.new();root.add_child(level)
	var camera:=Camera3D.new();level.add_child(camera);camera.current=true
	var scene=load("res://scenes/levels/snow_exterior.tscn").instantiate();level.add_child(scene)
	var data=scene.get_node("Terrain3D").data
	var originals:Dictionary={}
	for file in ["terrain3d-01_00.res","terrain3d-01-01.res"]:
		originals[file]=load("res://tools/.local/snow-material-review/before-polar-plain/"+file).get_height_map()
	var changed:=0
	for x in range(-105,-34):
		for z in range(-6,106):
			var p:=Vector2(x,z)
			var nearest:=Geometry2D.get_closest_point_to_segment(p,Vector2(-92,95),Vector2(-41,3))
			if p.distance_to(nearest)>5.1:continue
			var at:=Vector3(x,0,z)
			if data.get_control_hole(at):continue
			var file:="terrain3d-01-01.res" if z<0 else "terrain3d-01_00.res"
			var old:float=originals[file].get_pixel(posmod(x,256),posmod(z,256)).r
			var box_distance:=Vector2(maxf(absf(x+2.0)-42.0,0),maxf(absf(float(z))-31.0,0)).length()
			var keep:=1.0-smoothstep(0.0,14.0,box_distance)
			keep=maxf(keep,1.0-smoothstep(18.0,36.0,p.distance_to(Vector2(-125,95))))
			data.set_height(at,lerpf(polar_height(p),old,keep));changed+=1
	data.update_maps();data.save_directory(DIR)
	var perimeter:Array[Vector2]=[]
	for x in range(-510,1534):perimeter.append(Vector2(x,-766))
	for z in range(-766,766):perimeter.append(Vector2(1534,z))
	for x in range(1534,-510,-1):perimeter.append(Vector2(x,766))
	for z in range(766,-766,-1):perimeter.append(Vector2(-510,z))
	var vertices:=PackedVector3Array();var uv:=PackedVector2Array();var indices:=PackedInt32Array()
	var distances:Array[float]=[0.0,4.0,32.0,128.0,512.0,2048.0,6000.0]
	for distance in distances:
		for inner in perimeter:
			var unit:=(inner-Vector2(512,0))/Vector2(1022,766)
			var p:Vector2=Vector2(512,0)+unit*(Vector2(1022,766)+Vector2.ONE*distance)
			var correction:float=data.get_height(Vector3(inner.x,0,inner.y))-polar_height(inner)
			var height:=polar_height(p)+correction*(1.0-smoothstep(0,32,distance))-.05*(1.0-smoothstep(0,8,distance))
			vertices.append(Vector3(p.x,height,p.y));uv.append(Vector2(p.x,-p.y))
	var n:=perimeter.size()
	for ring in range(distances.size()-1):
		for i in n:
			var a:=ring*n+i;var b:=ring*n+(i+1)%n;var c:=a+n;var d:=b+n
			indices.append_array(PackedInt32Array([a,c,b,b,c,d]))
	var arrays:=[];arrays.resize(Mesh.ARRAY_MAX);arrays[Mesh.ARRAY_VERTEX]=vertices;arrays[Mesh.ARRAY_TEX_UV]=uv;arrays[Mesh.ARRAY_INDEX]=indices
	var temp:=ArrayMesh.new();temp.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var surface:=SurfaceTool.new();surface.create_from(temp,0);surface.generate_normals();surface.generate_tangents()
	var material:=ShaderMaterial.new();material.shader=load("res://assets/environments/snow/polar_backdrop.gdshader")
	material.set_shader_parameter("entry_snow_albedo",load("res://assets/environments/snow/snow006/runtime_albedo_ao.res"))
	material.set_shader_parameter("entry_snow_normal_rough",load("res://assets/environments/snow/snow006/runtime_normal_rough.res"))
	material.set_shader_parameter("entry_snow_height",load("res://assets/environments/snow/snow006/runtime_height.res"))
	material.set_shader_parameter("entry_snow_tile_size",2.4)
	material.set_shader_parameter("entry_snow_relief_metres",0.03)
	var mesh:=surface.commit();mesh.surface_set_material(0,material)
	ResourceSaver.save(mesh,"res://assets/environments/snow/meshes/polar_backdrop.res",ResourceSaver.FLAG_COMPRESS)
	print("EDGE FIX corridor samples=",changed," backdrop vertices=",vertices.size())
	quit()
