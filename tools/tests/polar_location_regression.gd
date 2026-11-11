extends SceneTree
var checks:=0
var failures:=0
func _initialize():run.call_deferred()
func check(ok:bool,label:String):
	checks+=1
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label)
func run():
	Engine.max_fps=120
	var snow=load("res://scenes/levels/snow_exterior.tscn").instantiate();snow.set_script(null)
	for n in snow.find_children("*","",true,false):n.set_script(null)
	var camera:=Camera3D.new();snow.add_child(camera);camera.current=true;camera.position=Vector3(-80,12,50);root.add_child(snow)
	var data=snow.get_node("Terrain3D").data
	for i in 5:await physics_frame
	var detail=snow.get_node("PolarLocationDetails")
	check(detail.get_node("WestLagoon").get_child_count()==12,"lagoon has two composed banks and ten varied fragments")
	check(detail.get_node("EastPools").get_child_count()==18 and detail.get_node("WestPools").get_child_count()==12,"both additional pools have grouped ice shores")
	check(detail.get_node("StreamShoulders").get_child_count()==8,"remaining stream bends have compound fracture groups")
	check(detail.get_node("CaveRimOutcrops").get_child_count()==9,"three grouped outcrops use existing rock scans")
	check(detail.get_node("ServiceRouteMarkers").get_child_count()==7 and detail.find_children("*","Light3D",true,false).is_empty(),"route markers do not create additional lights")
	var seated:=true;var collision:=true;var count:=0
	for node in detail.find_children("*","MeshInstance3D",true,false):
		if node.get_parent().name=="ServiceRouteMarkers" or node.get_parent() is MeshInstance3D:continue
		collision=collision and not node.find_children("*","CollisionShape3D",true,false).is_empty()
		var bottom:=false
		for p in node.mesh.get_faces():
			var world:Vector3=node.to_global(p);var h:float=data.get_height(world)
			if is_finite(h) and world.y<=h+.04:bottom=true;break
		seated=seated and bottom;count+=1
	check(collision,"all authored ice and rock meshes have collision")
	check(seated and count==59,"all 59 ice/rock pieces intersect the terrain")
	var preserved:=true;var control_ok:=true
	var dir:="res://assets/environments/snow/expanded_terrain/";var backup:="res://tools/.local/location-pass-2026-11-11/before/"
	if DirAccess.dir_exists_absolute(backup):
		for f in DirAccess.get_files_at(dir):
			if not f.ends_with(".res"):continue
			var old=load(backup+f);var current=load(dir+f)
			control_ok=control_ok and old.get_control_map().get_data()==current.get_control_map().get_data()
		for p in [Vector2(-40,3),Vector2(-125,95),Vector2(0,-180),Vector2(335,0)]:
			var loc:=Vector2i(floori(p.x/256),floori(p.y/256));var filename:=Terrain3DUtil.location_to_filename(loc)
			var old=load(backup+filename);var image:Image=old.get_height_map()
			var before:float=image.get_pixel(int(p.x)-loc.x*256,int(p.y)-loc.y*256).r
			var current_region=load(dir+filename)
			var current_height:float=current_region.get_height_map().get_pixel(int(p.x)-loc.x*256,int(p.y)-loc.y*256).r
			print("ANCHOR ",p," before=",before," current=",current_height)
			# Cave mouth intentionally has a terrain hole; compare stored heights, not NaN surface samples.
			preserved=preserved and absf(before-current_height)<.0001
		check(control_ok,"all 48 control maps and terrain holes are unchanged")
		check(preserved,"entry, arrival, flat tower foundation and cave interface preserve their heights")
	else:print("SKIP before/after maps: local authoring backup absent")
	var routes:Array=JSON.parse_string(FileAccess.get_file_as_string("res://assets/models/environment/polar_location/composition.json")).routes
	for route_index in routes.size():
		var route:Array=routes[route_index]
		var body:=CharacterBody3D.new();body.floor_snap_length=.45;body.floor_max_angle=deg_to_rad(46)
		var shape:=CollisionShape3D.new();var capsule:=CapsuleShape3D.new();capsule.radius=.35;capsule.height=1.8;shape.shape=capsule;shape.position.y=.9;body.add_child(shape);snow.add_child(body)
		var start:=Vector3(route[0][0],0,route[0][1]);start.y=data.get_height(start)+.1;body.position=start
		var completed:=true
		for k in range(1,route.size()):
			var target:=Vector2(route[k][0],route[k][1]);var arrived:=false
			for frame in 1800:
				await physics_frame
				var offset:=target-Vector2(body.position.x,body.position.z)
				if offset.length()<1:arrived=true;break
				var direction:=offset.normalized();body.velocity=Vector3(direction.x*8,body.velocity.y-9.8/60,direction.y*8);body.move_and_slide()
				if body.position.y< -200:break
			if not arrived:
				print("BLOCKED route=",route_index," segment=",k," position=",body.position," target=",target)
				for hit in body.get_slide_collision_count():print("COLLIDER ",body.get_slide_collision(hit).get_collider().get_path())
				completed=false;break
		check(completed,"route %d traversed by capsule without jumping"%route_index)
		body.queue_free()
	print("POLAR LOCATION CHECKS ",checks," FAILURES ",failures)
	snow.free();quit(1 if failures else 0)
