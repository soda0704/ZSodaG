extends SceneTree
## Offline environment authoring. Saves native meshes/scenes; never runs in game.
const OUT := "res://assets/environments/cave/geology_v2/"
const SCENE := "res://scenes/levels/cave_day7.tscn"
const ENTRY := Vector3(-33.5,-162,-21)
var world: Node3D
var route: Curve3D
var rock: Material
var rough := FastNoiseLite.new()
var rng := RandomNumberGenerator.new()
var total := 0.0
var samples: Array[Dictionary] = []

func _initialize(): run.call_deferred()
func own(node: Node, parent: Node, owner_node: Node) -> void:
	parent.add_child(node)
	node.owner=owner_node
func save_scene(node: Node, path: String) -> void:
	var packed:=PackedScene.new()
	assert(packed.pack(node)==OK)
	assert(ResourceSaver.save(packed,path)==OK)
func material() -> ShaderMaterial:
	var m:=ShaderMaterial.new();m.shader=load("res://assets/environments/cave/material_studies/cave_stone_v2.gdshader")
	m.set_shader_parameter("limestone_albedo",load("res://assets/environments/cave/material_studies/limestone_albedo_v2.png"))
	m.set_shader_parameter("damp_albedo",load("res://assets/environments/cave/material_studies/damp_rock_albedo_v2.png"))
	m.set_shader_parameter("scree_albedo",load("res://assets/environments/cave/material_studies/scree_floor_albedo_v2.png"))
	return m
func mesh_from(vertices: PackedVector3Array, indices: PackedInt32Array) -> ArrayMesh:
	var normals:=PackedVector3Array()
	normals.resize(vertices.size())
	for i in range(0,indices.size(),3):
		var a:=indices[i]; var b:=indices[i+1]; var c:=indices[i+2]
		var n:Vector3=-(vertices[b]-vertices[a]).cross(vertices[c]-vertices[a])
		normals[a]+=n; normals[b]+=n; normals[c]+=n
	var welded:Dictionary={}
	for i in vertices.size():
		var key:Vector3=(vertices[i]*10000).round()
		welded[key]=Vector3(welded.get(key,Vector3.ZERO))+normals[i]
	for i in normals.size():normals[i]=Vector3(welded[(vertices[i]*10000).round()]).normalized()
	var arrays:=[]
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=vertices
	arrays[Mesh.ARRAY_NORMAL]=normals
	arrays[Mesh.ARRAY_INDEX]=indices
	var mesh:=ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	mesh.surface_set_material(0,rock)
	return mesh
func mesh_body(mesh: ArrayMesh, label: String, parent: Node, collide:=true) -> Node3D:
	var body:Node3D=StaticBody3D.new() if collide else Node3D.new()
	body.name=label
	if body is StaticBody3D:
		body.collision_layer=1
		body.collision_mask=0
	body.set_meta("footstep_surface","concrete")
	own(body,parent,world)
	var visual:=MeshInstance3D.new()
	visual.name="RockSurface"
	visual.mesh=mesh
	own(visual,body,world)
	if collide:
		var shape:=mesh.create_trimesh_shape()
		shape.backface_collision=true
		ResourceSaver.save(shape,OUT+label.to_snake_case()+"_collision.res",ResourceSaver.FLAG_COMPRESS)
		shape.take_over_path(OUT+label.to_snake_case()+"_collision.res")
		var collision:=CollisionShape3D.new()
		collision.name="RockCollision"
		collision.shape=shape
		own(collision,body,world)
	return body
func route_position(d:float) -> Vector3:
	var at:=route.sample_baked(clampf(d,0,total),true)
	if d>total:at+=(route.sample_baked(total,true)-route.sample_baked(total-0.5,true)).normalized()*(d-total)
	return at
func cross_point_original(d:float,angle:float) -> Vector3:
	var center:=route_position(d)
	var along:Vector3=(route_position(d+0.4)-route_position(maxf(0,d-0.4))).normalized()
	var side:=along.cross(Vector3.UP).normalized()
	var width:=4.4+1.1*sin(d*0.033)+0.45*sin(d*0.11)
	var height:=3.5+0.65*sin(d*0.049)+0.35*cos(d*0.021)
	width+=6.9*exp(-pow((d-(total-91.0))/15.0,2))
	height+=2.3*exp(-pow((d-(total-91.0))/19.0,2))
	# Brief native low ceilings; the central walking line remains continuous.
	for low in [total*0.24,total*0.58]:
		height=lerpf(height,1.37,exp(-pow((d-low)/4.2,4)))
	if d<14:
		width=lerpf(7.0,width,smoothstep(0,14,d))
		height=lerpf(5.2,height,smoothstep(0,14,d))
	if d>total-65:
		width=3.4+0.2*sin(d*0.1)
		height=2.8+0.12*cos(d*0.1)
	var sx:=cos(angle)
	var sy:=sin(angle)
	var y:=maxf(0.0,(sy+0.57)/1.57)*height
	var noise:=rough.get_noise_3d(center.x+sx*3.7,center.y+y*1.9,center.z+sin(angle)*2.5)
	var strata:=sin(y*3.7+center.x*0.06+center.z*0.08)*0.16
	var jitter:=0.0 if sy< -0.57 else noise*1.05+strata
	jitter*=smoothstep(1.5,2.5,height)
	var offset:=0.34*sin(d*0.18)*maxf(0.0,sy+0.57)
	# A continuous shared profile keeps seams closed while walls vary asymmetrically.
	return center+side*(sx*(width*0.5+jitter)+offset)+Vector3.UP*(y+(0.025*sin(d*0.31) if sy< -0.57 else jitter*0.7))
func cross_point(d:float,angle:float) -> Vector3:
	var original:=cross_point_original(d,angle)
	var center:=route_position(d)
	var height:=cross_point_original(d,PI/2).y-center.y
	if height<2.3 or d<17 or d>total-70:return original
	var points:=PackedVector2Array([Vector2(0.95,0.43),Vector2(0.96,0.63),Vector2(0.8,0.72),Vector2(0.82,0.91),Vector2(0.59,0.92),Vector2(0.3,0.96),Vector2(0,1),Vector2(-0.33,0.94),Vector2(-0.66,0.97),Vector2(-0.72,0.78),Vector2(-1.04,0.74),Vector2(-0.91,0.53),Vector2(-1,0.34),Vector2(-0.86,0.17),Vector2(-0.7,0.06),Vector2(-0.6,0),Vector2(-0.4,0),Vector2(-0.2,0),Vector2(0,0),Vector2(0.2,0),Vector2(0.4,0),Vector2(0.6,0),Vector2(0.82,0.13),Vector2(0.98,0.28)])
	var fractional:=fposmod(angle,TAU)/TAU*24
	var index:=floori(fractional)
	var profile:Vector2=points[index].lerp(points[(index+1)%24],fposmod(fractional,1))
	var along:Vector3=(route_position(d+0.4)-route_position(maxf(0,d-0.4))).normalized()
	var side:=along.cross(Vector3.UP).normalized()
	var half_width:=absf((cross_point_original(d,0)-center).dot(side))*1.5
	var relief:=rough.get_noise_3dv(center+Vector3(profile.x*13,profile.y*9,0))*0.55
	var y:=profile.y*height*1.35
	if profile.y>0.04:y+=relief
	else:y=0.025*sin(d*0.31)
	var reshaped:=center+side*(profile.x*half_width+relief*0.65)+Vector3.UP*y
	var blend:=smoothstep(17,30,d)*(1-smoothstep(total-85,total-70,d))*smoothstep(2.3,2.7,height)
	return original.lerp(reshaped,blend)
func geological_detail() -> void:
	var group:=Node3D.new();group.name="GeologicalRelief";own(group,world,world)
	for section in ceili(total/24):
		var vertices:=PackedVector3Array();var indices:=PackedInt32Array()
		for raw_d in range(section*24+2,section*24+24,5):
			var d:=float(raw_d)
			if d<30 or d>total-90:continue
			var center:=route_position(d)
			var height:=cross_point(d,PI/2).y-center.y
			if height<2.8:continue
			var along:Vector3=(route_position(d+0.4)-route_position(d-0.4)).normalized()
			var side:=along.cross(Vector3.UP).normalized()
			for sign_side in [-1.0,1.0]:
				var inward:Vector3=-side*sign_side
				var basis:=Basis(Vector3.UP.cross(inward).normalized(),Vector3.UP,inward).scaled(Vector3(0.8,0.65,0.65))
				var at:=cross_point(d,0 if sign_side>0 else PI)-inward*0.3
				at.y=center.y+minf(2.0,height*0.45)
				var patch:Mesh=load(OUT+"rock_patch_%02d.res"%rng.randi_range(0,3))
				var faces:=patch.get_faces()
				for i in range(0,faces.size(),3):
					var triangle:Array[Vector3]=[at+basis*faces[i],at+basis*faces[i+1],at+basis*faces[i+2]]
					var probes:Array[Vector3]=triangle.duplicate()
					probes.append((triangle[0]+triangle[1]+triangle[2])/3)
					probes.append((triangle[0]+triangle[1])/2);probes.append((triangle[1]+triangle[2])/2);probes.append((triangle[0]+triangle[2])/2)
					var reserved:=false
					for p in probes:
						var nearest:=route_position(route.get_closest_offset(p))
						if Vector2(p.x-nearest.x,p.z-nearest.z).length()<1.1 and p.y>nearest.y-0.2 and p.y<nearest.y+2.15:reserved=true;break
					if reserved:continue
					for p in triangle:vertices.append(p);indices.append(indices.size())
		if vertices.is_empty():continue
		var mesh:=mesh_from(vertices,indices)
		var file:=OUT+"geological_relief_%02d.res"%section
		ResourceSaver.save(mesh,file,ResourceSaver.FLAG_COMPRESS);mesh.take_over_path(file)
		mesh_body(mesh,"GeologicalRelief_%02d"%section,group)
func tube(start:float,finish:float,caps:=false) -> ArrayMesh:
	var rings:=maxi(2,ceili((finish-start)/1.8))
	var v:=PackedVector3Array(); var ind:=PackedInt32Array()
	for i in rings+1:
		var d:=lerpf(start,finish,float(i)/rings)
		for j in 24: v.append(cross_point(d,TAU*j/24.0))
	for i in rings:
		for j in 24:
			var a:=i*24+j; var b:=i*24+(j+1)%24; var c:=a+24; var e:=b+24
			# Keep a single topological winding, including concave rock profiles.
			# Choosing orientation per triangle would produce a non-manifold union.
			ind.append_array(PackedInt32Array([a,c,b,b,c,e]))
	if caps:
		for index in [0,rings]:
			var base:int=index*24
			var d:float=start if index==0 else finish
			var along:Vector3=(route_position(d+0.1)-route_position(maxf(0,d-0.1))).normalized()
			var side:=along.cross(Vector3.UP).normalized()
			var outline:=PackedVector2Array()
			for j in 24:outline.append(Vector2(v[base+j].dot(side),v[base+j].y))
			var cap:=Geometry2D.triangulate_polygon(outline)
			for j in range(0,cap.size(),3):
				ind.append_array(PackedInt32Array([base+cap[j],base+cap[j+1],base+cap[j+2]] if index==0 else [base+cap[j],base+cap[j+2],base+cap[j+1]]))
	return mesh_from(v,ind)
func outward_tube(start:float,finish:float,padded:=false)->ArrayMesh:
	var source:=tube(start,finish,true)
	var arrays:=source.surface_get_arrays(0)
	if padded:
		var vertices:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
		for i in vertices.size():
			var center:=route_position(route.get_closest_offset(vertices[i]))+Vector3.UP*1.4
			vertices[i]=center+(vertices[i]-center)*1.08
		arrays[Mesh.ARRAY_VERTEX]=vertices
	var indices:PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
	for i in range(0,indices.size(),3):var swap:=indices[i+1];indices[i+1]=indices[i+2];indices[i+2]=swap
	arrays[Mesh.ARRAY_INDEX]=indices
	var mesh:=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	return mesh
func make_route() -> void:
	if "--from-scene" in OS.get_cmdline_user_args():
		var current:Node3D=load(SCENE).instantiate()
		route=current.get_node("AuthoredRoute").curve.duplicate(true)
		current.free()
		total=route.get_baked_length()
		var saved_path:=Path3D.new();saved_path.name="AuthoredRoute";saved_path.curve=route;own(saved_path,world,world)
		world.set_meta("route_length_m",total)
		return
	route=Curve3D.new()
	route.bake_interval=0.7
	var points:Array[Vector3]=[
		ENTRY,Vector3(-18,-162,-21),Vector3(6,-163,-8),Vector3(35,-164,-35),Vector3(58,-161,-80),
		Vector3(38,-164,-125),Vector3(-20,-165,-165),Vector3(-28,-163,-205),Vector3(5,-164,-240),
		Vector3(55,-165,-220),Vector3(100,-163,-180),Vector3(110,-162,-130),Vector3(85,-160,-85),
		Vector3(112,-161,-40),Vector3(160,-159,-25),Vector3(190,-158,-60),Vector3(175,-160,-105),
		Vector3(200,-158,-140),Vector3(245,-157,-125),Vector3(265,-156,-75),Vector3(245,-155,-40),
		Vector3(258,-155,-5),Vector3(282,-155,10),Vector3(300,-156,0),Vector3(300,-156,-18),
		Vector3(319,-156,-18),Vector3(319,-156,2),Vector3(342,-156,2)]
	var low:=0.1; var high:=1.0
	for attempt in 15:
		route.clear_points()
		var factor:float=(low+high)*0.5
		var adjusted:Array[Vector3]=points.duplicate()
		for i in range(1,23): adjusted[i].z=ENTRY.z+(points[i].z-ENTRY.z)*factor
		for i in adjusted.size():
			var tangent:=Vector3.ZERO
			if i>0 and i<adjusted.size()-1:
				tangent=(adjusted[i+1]-adjusted[i-1]).normalized()*minf(adjusted[i].distance_to(adjusted[i-1]),adjusted[i+1].distance_to(adjusted[i]))*0.26
			route.add_point(adjusted[i],-tangent,tangent)
		if route.get_baked_length()>796.43: high=factor
		else:low=factor
	total=route.get_baked_length()
	var path:=Path3D.new()
	path.name="AuthoredRoute"
	path.curve=route
	own(path,world,world)
	world.set_meta("route_length_m",total)
func rock_spire() -> ArrayMesh:
	var v:=PackedVector3Array(); var ind:=PackedInt32Array()
	for i in 5:
		var y:=float(i)/4
		for j in 8:
			var angle:=TAU*j/8.0
			var radius:=lerpf(0.26,0.018,y)*(1+0.12*sin(j*2.4+i))
			v.append(Vector3(cos(angle)*radius+sin(y*2)*0.12,y,sin(angle)*radius))
	for i in 4:
		for j in 8:
			var a:=i*8+j; var b:=i*8+(j+1)%8
			ind.append_array(PackedInt32Array([a,b,a+8,b,b+8,a+8]))
	return mesh_from(v,ind)
func details() -> void:
	var decor:=Node3D.new(); decor.name="AuthoredRockDetails"; own(decor,world,world)
	var spire:=rock_spire()
	var ceiling:=MultiMesh.new(); ceiling.transform_format=MultiMesh.TRANSFORM_3D; ceiling.mesh=spire; ceiling.instance_count=int(total/9)
	for i in ceiling.instance_count:
		var d:=rng.randf_range(22,total-70)
		var angle:=rng.randf_range(0.4,2.7)
		var at:=cross_point(d,angle)
		var length:=rng.randf_range(0.45,1.35)
		if cross_point(d,PI/2).y-route.sample_baked(d).y<2.5: length=0.12
		var basis:=Basis.from_euler(Vector3(PI+rng.randf_range(-0.15,0.15),rng.randf()*TAU,0)).scaled(Vector3(1,length,1))
		ceiling.set_instance_transform(i,Transform3D(basis,at))
	var mesh:=MultiMeshInstance3D.new(); mesh.name="Stalactites"; mesh.multimesh=ceiling; own(mesh,decor,world)
	for kind in 6:
		var stones:=MultiMesh.new(); stones.transform_format=MultiMesh.TRANSFORM_3D
		stones.mesh=load("res://assets/environments/snow/meshes/rock_%d.res"%kind)
		stones.instance_count=32
		for i in stones.instance_count:
			var d:=rng.randf_range(18,total-70)
			var a:=PI if i%2 else 0.0
			var wall:=cross_point(d,a)
			wall.y=route.sample_baked(d,true).y-0.1
			var scale:=rng.randf_range(0.15,0.4)
			stones.set_instance_transform(i,Transform3D(Basis.from_euler(Vector3(0,rng.randf()*TAU,0)).scaled(Vector3.ONE*scale),wall))
		var visual:=MultiMeshInstance3D.new(); visual.name="LooseStone%d"%kind; visual.multimesh=stones; visual.material_override=rock
		own(visual,decor,world)
func clip_y(polygon:Array[Vector3],height:float,above:bool) -> Array[Vector3]:
	var result:Array[Vector3]=[]
	if polygon.is_empty():return result
	for i in polygon.size():
		var a:=polygon[i];var b:=polygon[(i+1)%polygon.size()]
		var a_in:bool=a.y>=height if above else a.y<=height
		var b_in:bool=b.y>=height if above else b.y<=height
		if a_in:result.append(a)
		if a_in!=b_in:result.append(a.lerp(b,(height-a.y)/(b.y-a.y)))
	return result
func shaft(first_end:float) -> void:
	# Boolean union exists only in this authoring process, never in the game.
	var csg:=CSGCombiner3D.new()
	root.add_child(csg)
	var cylinder:=CSGCylinder3D.new()
	cylinder.radius=4.5; cylinder.height=73; cylinder.sides=48
	cylinder.position=Vector3(ENTRY.x,-125.5,ENTRY.z)
	csg.add_child(cylinder)
	var volume:=tube(0,first_end,true)
	var arrays:=volume.surface_get_arrays(0)
	var indices:PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
	for i in range(0,indices.size(),3):
		var swap:=indices[i+1];indices[i+1]=indices[i+2];indices[i+2]=swap
	arrays[Mesh.ARRAY_INDEX]=indices
	var solid:=ArrayMesh.new();solid.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var tunnel:=CSGMesh3D.new();tunnel.mesh=solid;csg.add_child(tunnel)
	for frame in 4: await process_frame
	var baked:ArrayMesh=csg.get_meshes()[1]
	var raw_faces:=baked.get_faces();var faces:=PackedVector3Array()
	for i in range(0,raw_faces.size(),3):
		var polygon:Array[Vector3]=[raw_faces[i],raw_faces[i+1],raw_faces[i+2]]
		var low:=minf(polygon[0].y,minf(polygon[1].y,polygon[2].y));var high:=maxf(polygon[0].y,maxf(polygon[1].y,polygon[2].y))
		if high-low<3:faces.append_array(PackedVector3Array(polygon));continue
		# Shared horizontal cuts give the tall shaft actual rock relief, with no
		# subdivision cracks and no runtime tessellation.
		for level in range(floori(low/2),ceili(high/2)):
			var strip:=clip_y(clip_y(polygon,level*2.0,true),(level+1)*2.0,false)
			for j in range(1,strip.size()-1):faces.append_array(PackedVector3Array([strip[0],strip[j],strip[j+1]]))
	var v:=PackedVector3Array(); var ind:=PackedInt32Array()
	var end:=route.sample_baked(first_end,true)
	var tangent:Vector3=(route.sample_baked(first_end+0.1,true)-route.sample_baked(first_end-0.1,true)).normalized()
	# Cross sections are vertical even when the route slopes downhill.
	tangent.y=0;tangent=tangent.normalized()
	for i in range(0,faces.size(),3):
		var a:=faces[i];var b:=faces[i+1];var c:=faces[i+2]
		if a.y> -89.01 and b.y> -89.01 and c.y> -89.01:continue
		if absf(tangent.dot(a-end))<0.02 and absf(tangent.dot(b-end))<0.02 and absf(tangent.dot(c-end))<0.02:continue
		var offset:=v.size()
		for point in [a,c,b]:
			var radial:Vector3=point-Vector3(ENTRY.x,point.y,ENTRY.z)
			if point.y> -156.0 and point.y< -93.0 and radial.length()<5.0:
				point+=radial.normalized()*(0.22*sin(point.y*0.38+point.x*0.4)+0.13*cos(point.z*0.7-point.y*0.19))
			v.append(point)
		ind.append_array(PackedInt32Array([offset,offset+1,offset+2]))
	var mesh:=mesh_from(v,ind)
	ResourceSaver.save(mesh,OUT+"natural_shaft.res",ResourceSaver.FLAG_COMPRESS)
	mesh.take_over_path(OUT+"natural_shaft.res")
	mesh_body(mesh,"NaturalWinchShaft",world)
	csg.queue_free()
func portal() -> void:
	var csg:=CSGCombiner3D.new();root.add_child(csg)
	var mound:=CSGSphere3D.new();mound.radius=14;mound.radial_segments=40;mound.rings=20
	mound.position=Vector3(329,-163,2);mound.scale=Vector3(1.2,1.2,1.25);csg.add_child(mound)
	var hole:=CSGMesh3D.new();hole.mesh=outward_tube(total-40,total+12,true)
	hole.operation=CSGShape3D.OPERATION_SUBTRACTION
	csg.add_child(hole)
	for frame in 4: await process_frame
	var baked:ArrayMesh=csg.get_meshes()[1]
	var vertices:=baked.get_faces()
	var indices:=PackedInt32Array()
	for i in vertices.size():
		var p:=vertices[i]
		# Shared-coordinate distortion preserves all boolean seams.
		var outside_hole:=smoothstep(2.5,4.5,Vector2(p.y+154.6,p.z-2).length())
		var radial:Vector3=(p-mound.position).normalized()
		p+=radial*(rough.get_noise_3dv(p*0.6)*2.5+0.5*sin(p.z*0.6+p.y*0.4))*outside_hole
		vertices[i]=p
		indices.append(i)
	# The rear of this lip is buried in Terrain3D. Clip it before the last
	# straight mouth so the boulder cannot intrude into the preceding S bend.
	var clipped:=PackedVector3Array()
	for i in range(0,vertices.size(),3):
		var polygon:Array[Vector3]=[]
		for j in 3:var p:=vertices[i+j];polygon.append(Vector3(p.y,p.x,p.z))
		var face:=clip_y(polygon,326.0,true)
		for j in range(1,face.size()-1):
			for p in [face[0],face[j],face[j+1]]:clipped.append(Vector3(p.y,p.x,p.z))
	vertices=clipped;indices.resize(vertices.size())
	for i in indices.size():indices[i]=i
	var mesh:=mesh_from(vertices,indices)
	var snow:ShaderMaterial=load("res://assets/environments/snow/rock_snow.tres").duplicate()
	snow.set_shader_parameter("use_rock_texture",true)
	snow.set_shader_parameter("rock_texture",load("res://assets/environments/snow/cliff_granite_albedo.png"))
	snow.set_shader_parameter("rock_texture_scale",0.24)
	snow.set_shader_parameter("rock_color",Color(0.75,0.77,0.78))
	snow.set_shader_parameter("snow_threshold",0.7)
	ResourceSaver.save(snow,OUT+"cave_mouth_snow.tres");snow.take_over_path(OUT+"cave_mouth_snow.tres")
	mesh.surface_set_material(0,snow)
	ResourceSaver.save(mesh,OUT+"portal_rock.res",ResourceSaver.FLAG_COMPRESS)
	var collision:=mesh.create_trimesh_shape();collision.backface_collision=true
	ResourceSaver.save(collision,OUT+"cave_mouth_collision.res",ResourceSaver.FLAG_COMPRESS)
	csg.queue_free()
func markers() -> void:
	var group:=Node3D.new(); group.name="ReviewPoints"; own(group,world,world)
	for i in range(0,ceili(total),4):
		var d:=minf(i,total)
		var p:=route.sample_baked(d,true)
		var marker:=Marker3D.new(); marker.name="Route_%04d"%i; marker.position=p+Vector3.UP*0.08
		marker.set_meta("distance",d)
		marker.set_meta("clearance",cross_point(d,PI/2).y-p.y)
		own(marker,group,world)
	for data in [["CaveArrival",ENTRY],["Lair",route.sample_baked(total-91,true)],["ExitBeforeScreen",route.sample_baked(total-63,true)],["ExitThreshold",route.sample_baked(total,true)]]:
		var marker:=Marker3D.new(); marker.name=data[0]; marker.position=data[1]+Vector3.UP*0.1; own(marker,world,world)
func run():
	if DisplayServer.get_name()=="headless":
		push_error("Use the graphical Godot renderer for authoring: the dummy backend cannot serialize MultiMesh transforms reliably.")
		quit(1);return
	root.get_node("GameMenu/GraphicsQuality").set_process(false)
	DirAccess.make_dir_recursive_absolute(OUT)
	rng.seed=190716
	rough.seed=713
	rough.frequency=0.27
	world=Node3D.new(); world.name="Cave_Day7"
	world.set_meta("editor_description","Authored natural cave. No runtime geometry generation. Daylight is occluded by the two-turn stone exit baffle.")
	root.add_child(world)
	rock=material()
	ResourceSaver.save(rock,OUT+"cave_rock.tres")
	rock.take_over_path(OUT+"cave_rock.tres")
	make_route()
	var segments:=ceili(total/24.0)
	for i in segments:
		if i==0:continue
		var mesh:=tube(total*i/segments,total*(i+1)/segments)
		var path:=OUT+"passage_%02d.res"%i
		ResourceSaver.save(mesh,path,ResourceSaver.FLAG_COMPRESS)
		mesh.take_over_path(path)
		mesh_body(mesh,"Passage_%02d"%i,world)
	details()
	geological_detail()
	await shaft(total/segments)
	markers()
	save_scene(world,SCENE)
	print("AUTHORED_CAVE ",total," metres ",segments," closed-ring sections")
	quit()
