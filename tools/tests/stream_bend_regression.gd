extends SceneTree
var failures:=0
var checks:=0
func _initialize():run.call_deferred()
func check(ok:bool,label:String):
	checks+=1
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label)
func run():
	var snow=load("res://scenes/levels/snow_exterior.tscn").instantiate();snow.set_script(null)
	for n in snow.find_children("*","",true,false):n.set_script(null)
	var camera:=Camera3D.new();snow.add_child(camera);camera.position=Vector3(-215,8,-120);camera.current=true
	root.add_child(snow)
	for i in 5:await physics_frame
	var data=snow.get_node("Terrain3D").data
	var bend=snow.get_node("PolarIceLowland/AuthoredStreamBend")
	check(bend.get_child_count()==13,"one continuous bank and twelve varied Blender fracture slabs")
	var bank:MeshInstance3D=bend.get_node("LayeredWestBank")
	var arrays=bank.mesh.surface_get_arrays(0);var normals:PackedVector3Array=arrays[Mesh.ARRAY_NORMAL];var colors:PackedColorArray=arrays[Mesh.ARRAY_COLOR]
	var upward:=true
	for i in normals.size():
		if colors[i].r>.95 and normals[i].y<.1:upward=false
	check(upward,"snow shoulder normals face upward")
	var grounded:=true;var colliders:=true
	for node:MeshInstance3D in bend.get_children():
		colliders=colliders and node.find_children("*","CollisionShape3D",true,false).size()==1
		if node==bank:continue
		var buried:=0
		for p in node.mesh.get_faces():
			if p.y<data.get_height(p):buried+=1
		grounded=grounded and buried>0
	check(grounded,"all fracture slabs intersect ground at their bases")
	check(colliders,"all authored meshes have static collision")
	var reference_path:="res://blender/stream_bend/terrain_reference.json"
	var reference=JSON.parse_string(FileAccess.get_file_as_string(reference_path)) if FileAccess.file_exists(reference_path) else null
	var unchanged:=true
	if reference!=null:
		for j in reference.heights.size():
			for i in reference.heights[j].size():
				var p:=Vector3(reference.x0+i*.5,0,reference.z0+j*.5)
				# Later location work may change surrounding hills; protect the accepted bend footprint.
				if p.x< -215 or p.x> -198 or p.z< -137 or p.z> -108:continue
				if absf(data.get_height(p)-reference.heights[j][i])>.00001:unchanged=false
		check(unchanged,"underlying Terrain3D heights match pre-authoring sample")
	else:print("SKIP terrain comparison: authoring reference not present")
	var old=snow.get_node("PolarIceLowland/FracturedIce_2_1")
	check(not old.visible and old.find_children("*","CollisionShape3D",true,false)[0].disabled,"replaced formation has no duplicate visual or collision")
	# A capsule follows the clear snow shoulder; no jumping or teleporting during movement.
	var body:=CharacterBody3D.new();var shape:=CollisionShape3D.new();var capsule:=CapsuleShape3D.new();capsule.radius=.35;capsule.height=1.8
	shape.shape=capsule;shape.position.y=.9;body.add_child(shape);snow.add_child(body)
	body.position=Vector3(-215,data.get_height(Vector3(-215,0,-131))+.1,-131)
	for i in 150:
		await physics_frame
		body.velocity=Vector3(0,body.velocity.y-9.8/60.0,3.0);body.move_and_slide()
	check(body.position.z>-125 and body.is_on_floor(),"snow shoulder traversed by grounded capsule without jumping")
	print("RESULT checks=",checks," failures=",failures)
	snow.free();quit(0 if failures==0 else 1)
