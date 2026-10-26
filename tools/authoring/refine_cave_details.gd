extends SceneTree
## LOCAL, OFFLINE art pass. Saves editor-visible rock instances and edits only
## the failed external lip. Does not regenerate or straighten the cave route.
const SCENE := "res://scenes/levels/cave_day7.tscn"
const OUT := "res://assets/environments/cave/rocks/"
const BACKUP := "res://tools/.local/cave-reference/sculpt_before_local/"
var cave:Node3D
var terrain:Node3D
var curve:Curve3D
var models:Array[Mesh]=[]
var rng:=RandomNumberGenerator.new()
var group:Node3D
var lip_shape:Shape3D
func _initialize():run.call_deferred()
func attach(child:Node,parent:Node):
	parent.add_child(child);child.owner=cave
func native_height(p:Vector3)->float:
	var values:Array[float]=[]
	for offset in [Vector2i(0,0),Vector2i(1,0),Vector2i(0,1),Vector2i(1,1)]:
		var x:int=floori(p.x)+offset.x;var z:int=floori(p.z)+offset.y
		var region=terrain.data.get_region(Vector2i(floori(x/256.0),floori(z/256.0)))
		values.append(region.get_height_map().get_pixel(posmod(x,256),posmod(z,256)).r)
	return lerpf(lerpf(values[0],values[1],fposmod(p.x,1)),lerpf(values[2],values[3],fposmod(p.x,1)),fposmod(p.z,1))
func normals_for(vertices:PackedVector3Array,indices:PackedInt32Array)->PackedVector3Array:
	var normals:=PackedVector3Array();normals.resize(vertices.size())
	for i in range(0,indices.size(),3):
		var a:=indices[i];var b:=indices[i+1];var c:=indices[i+2]
		var n:Vector3=-(vertices[b]-vertices[a]).cross(vertices[c]-vertices[a])
		normals[a]+=n;normals[b]+=n;normals[c]+=n
	var welded:Dictionary={}
	for i in vertices.size():
		var key:Vector3=(vertices[i]*10000).round()
		welded[key]=Vector3(welded.get(key,Vector3.ZERO))+normals[i]
	for i in normals.size():normals[i]=Vector3(welded[(vertices[i]*10000).round()]).normalized()
	return normals
func adjust_lip(visual:MeshInstance3D):
	var original:Mesh=visual.mesh
	if original.get_faces().is_empty():
		# Also remove the old collision owner of an already-empty visual.
		var empty_body:=visual.get_parent();empty_body.get_parent().remove_child(empty_body);empty_body.free();return
	if original.get_aabb().end.x<298:return
	var file:String=original.resource_path
	var backup:=BACKUP+file.get_file()
	if not FileAccess.file_exists(backup):
		assert(DirAccess.copy_absolute(file,backup)==OK)
	original=ResourceLoader.load(backup,"",ResourceLoader.CACHE_MODE_IGNORE)
	var arrays:=original.surface_get_arrays(0)
	var vertices:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
	var colors:PackedColorArray=arrays[Mesh.ARRAY_COLOR]
	var source_normals:PackedVector3Array=arrays[Mesh.ARRAY_NORMAL]
	var old_indices:PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
	var indices:=PackedInt32Array()
	for i in range(0,old_indices.size(),3):
		var a:=vertices[old_indices[i]];var b:=vertices[old_indices[i+1]];var c:=vertices[old_indices[i+2]]
		# The former hard exterior-field boundary made an enormous vertical
		# sheet at X300. Remove its exposed portion; the cut stays underground.
		var at:Vector3=(a+b+c)/3
		if at.x>299:
			var centre:=curve.sample_baked(curve.get_closest_offset(at),true)
			var n:Vector3=(source_normals[old_indices[i]]+source_normals[old_indices[i+1]]+source_normals[old_indices[i+2]]).normalized()
			var inside_direction:Vector3=centre+Vector3.UP*1.6-at
			# Retain the cave's inward-facing structural surface. Discard the
			# failed outer snow shell and its long apron instead of deforming it.
			if n.dot(inside_direction)< -0.05 or at.x>343.5 or Vector2(at.x-centre.x,at.z-centre.z).length()>7:continue
			if at.x<301 and at.y>native_height(at)-1.0:continue
		indices.append_array(PackedInt32Array([old_indices[i],old_indices[i+1],old_indices[i+2]]))
	if indices.is_empty():
		# Godot interprets an empty index buffer as NON-INDEXED triangles;
		# retaining the unused vertex buffer would draw unrelated giant fins.
		var body:=visual.get_parent();body.get_parent().remove_child(body);body.free();return
	arrays[Mesh.ARRAY_VERTEX]=vertices;arrays[Mesh.ARRAY_COLOR]=colors;arrays[Mesh.ARRAY_INDEX]=indices
	arrays[Mesh.ARRAY_NORMAL]=normals_for(vertices,indices)
	var mesh:=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays);mesh.surface_set_material(0,original.surface_get_material(0))
	ResourceSaver.save(mesh,file,ResourceSaver.FLAG_COMPRESS);mesh.take_over_path(file);visual.mesh=mesh
	var collision:CollisionShape3D=visual.get_parent().get_node("SolidRock")
	var collision_file:String=collision.shape.resource_path
	var shape:=mesh.create_trimesh_shape();shape.backface_collision=true
	ResourceSaver.save(shape,collision_file,ResourceSaver.FLAG_COMPRESS);shape.take_over_path(collision_file);collision.shape=shape
func prepare_model(id:String,target:int)->Mesh:
	var source:Node3D=load(OUT+id+"/"+id+".gltf").instantiate()
	var visual:MeshInstance3D=source.find_children("*","MeshInstance3D",true,false)[0]
	var mesh:Mesh=visual.mesh
	var importer:=ImporterMesh.new()
	var arrays:=mesh.surface_get_arrays(0)
	var center:=mesh.get_aabb().get_center()
	var vertices:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
	var normals:PackedVector3Array=arrays[Mesh.ARRAY_NORMAL]
	for i in vertices.size():
		vertices[i]-=center
		# These scans face -Z. Store a consistent +Z exposed face so the
		# photographed rock relief, rather than the cut back, faces the passage.
		vertices[i]=Vector3(-vertices[i].x,vertices[i].y,-vertices[i].z)
		normals[i]=Vector3(-normals[i].x,normals[i].y,-normals[i].z)
	arrays[Mesh.ARRAY_VERTEX]=vertices
	arrays[Mesh.ARRAY_NORMAL]=normals
	var mat:StandardMaterial3D=mesh.surface_get_material(0).duplicate()
	mat.albedo_color=Color(0.72,0.77,0.80);mat.normal_scale=0.75
	var mat_path:=OUT+id+"/cave_material.tres";ResourceSaver.save(mat,mat_path);mat.take_over_path(mat_path)
	importer.add_surface(Mesh.PRIMITIVE_TRIANGLES,arrays,[],{},mat)
	importer.generate_lods(25,60,[])
	var choice:=PackedInt32Array();var error:=100000000
	for lod in importer.get_surface_lod_count(0):
		var candidate:=importer.get_surface_lod_indices(0,lod)
		if absi(candidate.size()/3-target)<error:
			error=absi(candidate.size()/3-target);choice=candidate
	if not choice.is_empty():arrays[Mesh.ARRAY_INDEX]=choice
	var result:=ArrayMesh.new();result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays);result.surface_set_material(0,mat)
	var file:=OUT+id+"/cave_mesh.res";ResourceSaver.save(result,file,ResourceSaver.FLAG_COMPRESS);result.take_over_path(file)
	print("ROCK_ASSET ",id," ",result.get_faces().size()/3," triangles; ",result.get_aabb())
	source.free();return result
func fit_structural_lip()->Mesh:
	var file:="res://assets/environments/cave/portal_rock.res"
	var backup:=BACKUP+"original_portal_rock.res"
	if not FileAccess.file_exists(backup):assert(DirAccess.copy_absolute(file,backup)==OK)
	var source:Mesh=ResourceLoader.load(backup,"",ResourceLoader.CACHE_MODE_IGNORE)
	var arrays:=source.surface_get_arrays(0)
	var vertices:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
	var normals:PackedVector3Array=arrays[Mesh.ARRAY_NORMAL]
	var old_indices:PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
	var expanded_vertices:=PackedVector3Array();var expanded_normals:=PackedVector3Array();var expanded_indices:=PackedInt32Array()
	for i in range(0,old_indices.size(),3):
		var a:=old_indices[i];var b:=old_indices[i+1];var c:=old_indices[i+2]
		var points:Array[Vector3]=[vertices[a],vertices[b],vertices[c],(vertices[a]+vertices[b])*.5,(vertices[b]+vertices[c])*.5,(vertices[c]+vertices[a])*.5]
		var ns:Array[Vector3]=[normals[a],normals[b],normals[c],(normals[a]+normals[b]).normalized(),(normals[b]+normals[c]).normalized(),(normals[c]+normals[a]).normalized()]
		var start:=expanded_vertices.size();expanded_vertices.append_array(points);expanded_normals.append_array(ns)
		for index in [0,3,5,3,1,4,5,4,2,3,4,5]:expanded_indices.append(start+index)
	vertices=expanded_vertices;normals=expanded_normals;arrays[Mesh.ARRAY_INDEX]=expanded_indices
	var noise:=FastNoiseLite.new();noise.seed=1627;noise.frequency=.8
	for i in vertices.size():
		var p:=vertices[i]
		if normals[i].y>0.05 and p.y> -152:
			var target:=maxf(native_height(p)+.25,-151.4+.18*sin(p.x*.8+p.z*.5))
			p.y=minf(p.y,target)+absf(noise.get_noise_3dv(p))*.45;vertices[i]=p
	var clean:=[];clean.resize(Mesh.ARRAY_MAX)
	clean[Mesh.ARRAY_VERTEX]=vertices
	clean[Mesh.ARRAY_INDEX]=expanded_indices
	clean[Mesh.ARRAY_NORMAL]=normals_for(vertices,expanded_indices)
	var mesh:=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,clean);mesh.surface_set_material(0,source.surface_get_material(0))
	assert(mesh.get_surface_count()==1,"Mouth sculpt must have a valid surface before saving")
	ResourceSaver.save(mesh,file,ResourceSaver.FLAG_COMPRESS);mesh.take_over_path(file)
	lip_shape=mesh.create_trimesh_shape();lip_shape.backface_collision=true
	ResourceSaver.save(lip_shape,"res://assets/environments/cave/cave_mouth_collision.res",ResourceSaver.FLAG_COMPRESS);lip_shape.take_over_path("res://assets/environments/cave/cave_mouth_collision.res")
	return mesh
func rock(label:String,type:int,at:Vector3,rotation:Vector3,size:Vector3):
	var body:=StaticBody3D.new();body.name=label;body.position=at;body.rotation=rotation
	body.collision_layer=1;body.collision_mask=0;body.set_meta("footstep_surface","concrete");attach(body,group)
	var view:=MeshInstance3D.new();view.name="NaturalRock";view.mesh=models[type];view.scale=size;attach(view,body)
	var collision:=CollisionShape3D.new();collision.name="SolidRock";collision.scale=size
	# A closed convex collision keeps the scanned rock's unseen back solid;
	# every render fragment is embedded in existing rock, never a wall substitute.
	collision.shape=models[type].create_convex_shape(true,true);attach(collision,body)
func run():
	root.get_node("GameMenu/GraphicsQuality").set_process(false)
	rng.seed=161028
	DirAccess.make_dir_recursive_absolute(BACKUP)
	var camera:=Camera3D.new();root.add_child(camera);camera.current=true
	var snow=load("res://scenes/levels/snow_exterior.tscn").instantiate();snow.set_script(null);root.add_child(snow);terrain=snow.get_node("Terrain3D")
	cave=load(SCENE).instantiate();root.add_child(cave);curve=cave.get_node("AuthoredRoute").curve
	for frame in 6:await physics_frame
	for view in cave.get_node("ContinuousGeology").find_children("Bedrock","MeshInstance3D",true,false):adjust_lip(view)
	if cave.has_node("AuthoredOutcrops"):
		var old=cave.get_node("AuthoredOutcrops");cave.remove_child(old);old.free()
	for frame in 3:await physics_frame
	group=Node3D.new();group.name="AuthoredOutcrops";attach(group,cave)
	models=[prepare_model("rock_face_01",4500),prepare_model("rock_face_02",3500),prepare_model("boulder_01",1200)]
	# Independent thick rock slabs break up the former smooth cap, overlap its
	# seams and grow into the cliff shoulders. Every transform remains editable.
	var lip:=StaticBody3D.new();lip.name="Mouth_Bedrock";lip.collision_layer=1;lip.collision_mask=0;attach(lip,group)
	var lip_view:=MeshInstance3D.new();lip_view.name="RockArch";lip_view.mesh=fit_structural_lip();lip_view.layers=1|(1<<16);lip_view.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;attach(lip_view,lip)
	var lip_collision:=CollisionShape3D.new();lip_collision.name="SolidRock";lip_collision.shape=lip_shape;attach(lip_collision,lip)
	rock("Lip_Rear_Left",2,Vector3(327,-151,-1),Vector3(.2,.12,.18),Vector3(4.8,3.0,3.2))
	rock("Lip_Rear_Right",2,Vector3(327,-151,5.0),Vector3(.35,.7,-.13),Vector3(3.8,2.7,3.1))
	rock("Lip_Central_Bedrock",2,Vector3(331,-151,2.2),Vector3(.3,-.20,-.12),Vector3(4.4,2.5,3.3))
	rock("Rear_Terrain_Join",2,Vector3(325.5,-149.5,2),Vector3(.12,1.1,-.17),Vector3(7.0,4.6,4.4))
	rock("Cliff_Left_Shoulder",2,Vector3(334,-154,-4.8),Vector3(.20,1.4,.09),Vector3(3.9,4.0,2.6))
	rock("Cliff_Right_Shoulder",2,Vector3(334,-153.6,7.5),Vector3(-.10,1.65,-.14),Vector3(3.6,4.8,3.5))
	rock("Cliff_Right_Fracture",2,Vector3(339,-155,8.1),Vector3(.11,1.39,.17),Vector3(2.5,2.7,2.9))
	var space:=cave.get_world_3d().direct_space_state
	for index in 12:
		var d:float=[62,100,113,290,302,365,520,532,690,710,739,758][index]
		var p:=curve.sample_baked(d,true)
		var tangent:Vector3=(curve.sample_baked(d+.4,true)-curve.sample_baked(d-.4,true)).normalized()
		var side:=tangent.cross(Vector3.UP).normalized()*(-1 if index%2 else 1)
		var hit:=space.intersect_ray(PhysicsRayQueryParameters3D.create(p+Vector3.UP*1.3,p+Vector3.UP*1.3+side*20,1))
		if hit.is_empty():continue
		var inward:Vector3=-side
		var orientation:=Basis(Vector3.UP.cross(inward).normalized(),Vector3.UP,inward).get_euler()+Vector3(rng.randf_range(-.16,.16),0,rng.randf_range(-.12,.12))
		rock("Gallery_Outcrop_%02d"%index,index%2,hit.position+side*.75+Vector3.UP*.2,orientation,Vector3(rng.randf_range(.8,1.2),rng.randf_range(.7,1.3),rng.randf_range(.5,.7)))
		var stone_at:Vector3=p+side*1.35
		var floor_hit:=space.intersect_ray(PhysicsRayQueryParameters3D.create(stone_at+Vector3.UP*.8,stone_at-Vector3.UP*1.4,1))
		if not floor_hit.is_empty():rock("Scree_%02d"%index,2,floor_hit.position+Vector3.UP*.10,Vector3(.1,index*1.7,.1),Vector3(.7,.32,.65))
	# Collar edges are buried in solid rock ledges without narrowing the cage.
	for index in 4:
		var angle:=TAU*index/4
		var side:=Vector3(cos(angle),0,sin(angle))
		var inward:Vector3=-side
		var basis:=Basis(Vector3.UP.cross(inward).normalized(),Vector3.UP,inward)
		rock("Collar_Rock_%d"%index,index%2,Vector3(-33.5,-94.1,-21)+side*4.4,basis.get_euler(),Vector3(1.1,.7,.48))
	for frame in 3:await physics_frame
	var excluded:Array[RID]=[]
	for body in group.get_children():
		if body.name!="Mouth_Bedrock":excluded.append(body.get_rid())
	var rejected:Dictionary={}
	var capsule:=CapsuleShape3D.new();capsule.radius=.55
	var query:=PhysicsShapeQueryParameters3D.new();query.shape=capsule;query.collision_mask=1
	for d in range(8,ceili(curve.get_baked_length())-1):
		var p:=curve.sample_baked(d,true)
		var floor_query:=PhysicsRayQueryParameters3D.create(p+Vector3.UP*.85,p-Vector3.UP*1.4,1);floor_query.exclude=excluded
		var floor_hit:=space.intersect_ray(floor_query)
		if floor_hit.is_empty():continue
		var low:bool=absf(d-curve.get_baked_length()*.24)<9 or absf(d-curve.get_baked_length()*.58)<9
		capsule.height=1.15 if low else 1.8
		query.transform=Transform3D(Basis.IDENTITY,Vector3(p.x,floor_hit.position.y+capsule.height*.5+.05,p.z))
		for hit in space.intersect_shape(query,20):
			if hit.collider.get_parent()==group and hit.collider.name!="Mouth_Bedrock":rejected[hit.collider.name]=hit.collider
	for body in rejected.values():
		print("RESERVED_CORRIDOR removed intrusive rock: ",body.name);group.remove_child(body);body.free()
	var triangles:=0
	for visual in cave.find_children("*","MeshInstance3D",true,false):triangles+=visual.mesh.get_faces().size()/3
	cave.set_meta("triangle_count",triangles)
	cave.set_meta("art_pass","Local rock outcrops; old scan sheets and failed exterior shell removed. Terrain and distant backdrop no longer overlap.")
	var scene:=PackedScene.new();assert(scene.pack(cave)==OK);assert(ResourceSaver.save(scene,SCENE)==OK)
	print("LOCAL_CAVE_DETAILS ",group.get_child_count()," authored rock volumes; route preserved")
	quit()
