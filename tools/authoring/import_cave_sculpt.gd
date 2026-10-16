extends SceneTree
## Editor-side import of a static offline sculpt; never attached to a game node.
const SOURCE := "res://tools/.local/cave-reference/volume_bake/"
const OUT := "res://assets/environments/cave/sculpted/"
func _initialize():run.call_deferred()
func attach(child:Node,parent:Node,owner_node:Node):
	parent.add_child(child);child.owner=owner_node
func run():
	root.get_node("GameMenu/GraphicsQuality").set_process(false)
	DirAccess.make_dir_recursive_absolute(OUT)
	var manifest:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(SOURCE+"manifest.json"))
	var cave:Node3D=load("res://scenes/levels/Cave_Day7.tscn").instantiate()
	root.add_child(cave)
	for child in cave.get_children():
		if child.name in ["AuthoredRoute","ReviewPoints","CaveArrival","Lair","ExitBeforeScreen","ExitThreshold"]:continue
		cave.remove_child(child);child.free()
	var material:=ShaderMaterial.new();material.shader=load("res://assets/environments/cave/pbr/cave_rock.gdshader")
	material.set_shader_parameter("rock_albedo",load("res://assets/environments/cave/pbr/rock_06_diff_2k.jpg"))
	material.set_shader_parameter("rock_normal",load("res://assets/environments/cave/pbr/rock_06_nor_gl_2k.jpg"))
	material.set_shader_parameter("rock_roughness",load("res://assets/environments/cave/pbr/rock_06_rough_2k.jpg"))
	material.set_shader_parameter("floor_albedo",load("res://assets/environments/cave/material_studies/scree_floor_albedo_v2.png"))
	ResourceSaver.save(material,OUT+"limestone.tres");material.take_over_path(OUT+"limestone.tres")
	var geology:=Node3D.new();geology.name="ContinuousGeology";attach(geology,cave,cave)
	for tile in manifest.tiles:
		var raw:=FileAccess.get_file_as_bytes(SOURCE+tile.name+".vertices").to_float32_array()
		var indices:=FileAccess.get_file_as_bytes(SOURCE+tile.name+".indices").to_int32_array()
		var vertices:=PackedVector3Array();var normals:=PackedVector3Array();var colors:=PackedColorArray()
		for i in tile.vertices:
			vertices.append(Vector3(raw[i*7],raw[i*7+1],raw[i*7+2]))
			normals.append(Vector3(raw[i*7+3],raw[i*7+4],raw[i*7+5]))
			colors.append(Color(raw[i*7+6],0,0,1))
		var arrays:=[];arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX]=vertices;arrays[Mesh.ARRAY_NORMAL]=normals;arrays[Mesh.ARRAY_INDEX]=indices;arrays[Mesh.ARRAY_COLOR]=colors
		var mesh:=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays);mesh.surface_set_material(0,material)
		var file:String=OUT+tile.name+".res"
		ResourceSaver.save(mesh,file,ResourceSaver.FLAG_COMPRESS);mesh.take_over_path(file)
		var shape:=mesh.create_trimesh_shape();shape.backface_collision=true
		file=OUT+tile.name+"_collision.res";ResourceSaver.save(shape,file,ResourceSaver.FLAG_COMPRESS);shape.take_over_path(file)
		var body:=StaticBody3D.new();body.name=tile.name;body.collision_layer=1;body.collision_mask=0;body.set_meta("footstep_surface","concrete");attach(body,geology,cave)
		var visual:=MeshInstance3D.new();visual.name="Bedrock";visual.mesh=mesh;attach(visual,body,cave)
		var collision:=CollisionShape3D.new();collision.name="SolidRock";collision.shape=shape;attach(collision,body,cave)
	cave.set_meta("editor_description","Continuous volumetric limestone sculpt: irregular floor, galleries, natural shaft and terrain-overlapping external mouth. Static native resources, no runtime sculpting.")
	cave.set_meta("sculpt_grid_m",manifest.step)
	cave.set_meta("triangle_count",manifest.triangles)
	var scene:=PackedScene.new();assert(scene.pack(cave)==OK)
	var destination:String="res://tools/.local/cave-reference/Cave_Sculpt_Study.tscn" if manifest.sample else "res://scenes/levels/Cave_Day7.tscn"
	assert(ResourceSaver.save(scene,destination)==OK)
	print("IMPORTED_SCULPT ",manifest.tiles.size()," tiles; ",manifest.triangles," triangles; ",destination)
	quit()
