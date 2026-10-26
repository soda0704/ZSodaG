extends SceneTree
var checks:=0
var failures:Array[String]=[]
func check(ok:bool,message:String):
	checks+=1
	if not ok:failures.append(message);print("FAIL ",message)
func _initialize():run.call_deferred()
func run():
	root.get_node("GameMenu/GraphicsQuality").set_process(false)
	var camera:=Camera3D.new();root.add_child(camera);camera.current=true
	var world:=Node3D.new();root.add_child(world)
	var cave=load("res://scenes/levels/cave_day7.tscn").instantiate();world.add_child(cave)
	var snow=load("res://scenes/levels/snow_exterior.tscn").instantiate();snow.set_script(null);world.add_child(snow)
	snow.get_node("Terrain3D").collision_mode=Terrain3DCollision.FULL_GAME
	for frame in 6:await physics_frame
	var space:PhysicsDirectSpaceState3D=world.get_world_3d().direct_space_state
	var curve:Curve3D=cave.get_node("AuthoredRoute").curve
	var total:=curve.get_baked_length()
	check(total>790 and total<810,"Reference-length route")
	var capsule:=CapsuleShape3D.new();capsule.radius=0.35;capsule.height=1.15
	var query:=PhysicsShapeQueryParameters3D.new();query.shape=capsule;query.collision_mask=1;query.margin=0.001
	var low_count:=0;var bad_floor:=0;var blocked:=0;var missing_roof:=0
	var floor_min:=100.0;var floor_max:=-100.0
	for i in range(0,ceili(total*2)-1):
		var d:=i*0.5;var at:=curve.sample_baked(d,true)
		var floor_hit:=space.intersect_ray(PhysicsRayQueryParameters3D.create(at+Vector3.UP*0.9,at-Vector3.UP*1.2,1))
		if floor_hit.is_empty() or absf(floor_hit.position.y-at.y)>0.65:
			bad_floor+=1
			if bad_floor<8:print("BAD_FLOOR ",d," ",floor_hit)
		if floor_hit.is_empty():continue
		floor_min=minf(floor_min,floor_hit.position.y-at.y);floor_max=maxf(floor_max,floor_hit.position.y-at.y)
		at.y=floor_hit.position.y
		var roof:=space.intersect_ray(PhysicsRayQueryParameters3D.create(at+Vector3.UP*0.9,at+Vector3.UP*12,1))
		if roof.is_empty() and d>5 and d<total-8:missing_roof+=1
		if not roof.is_empty() and roof.position.y-at.y<1.65:low_count+=1
		query.transform=Transform3D(Basis.IDENTITY,at+Vector3.UP*0.625)
		var hits:=space.intersect_shape(query,4)
		if not hits.is_empty():
			blocked+=1
			if blocked<12:print("BLOCKED ",d," ",at," ",hits.map(func(hit):return str(hit.collider.get_path())))
	check(bad_floor==0,"Continuous supporting floor: %d failures"%bad_floor)
	check(blocked==0,"Crouching capsule clearance: %d blocked samples"%blocked)
	check(missing_roof==0,"Enclosed roof before mouth: %d missing samples"%missing_roof)
	check(floor_max-floor_min>0.4,"Floor has real vertical relief, not only an albedo: %.2fm"%(floor_max-floor_min))
	var gaps:=0
	for distance in range(12,ceili(total)-12,3):
		var p:=curve.sample_baked(distance,true)
		var side:Vector3=(curve.sample_baked(distance+0.4,true)-curve.sample_baked(distance-0.4,true)).cross(Vector3.UP).normalized()
		for sign_side in [-1.0,1.0]:
			var at:Vector3=p+side*sign_side*0.55+Vector3.UP*0.85
			if space.intersect_ray(PhysicsRayQueryParameters3D.create(at,at-Vector3.UP*1.8,1)).is_empty():gaps+=1
			var origin:=p+Vector3.UP*0.8
			if space.intersect_ray(PhysicsRayQueryParameters3D.create(origin,origin+side*sign_side*25,1)).is_empty():gaps+=1
	check(gaps==0,"Off-centre floor and side walls are enclosed: %d gaps"%gaps)
	check(low_count>12,"Crouch passages actually lower than standing capsule")
	var open_cap:=0
	for x in range(325,338):
		for z in range(-3,8):
			var region=snow.get_node("Terrain3D").data.get_region(Vector2i(floori(x/256.0),floori(z/256.0)))
			var native_height:float=region.get_height_map().get_pixel(posmod(x,256),posmod(z,256)).r
			var top:=space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(x,-125,z),Vector3(x,native_height-.15,z),1))
			if top.is_empty():
				open_cap+=1
				if open_cap<16:print("PORTAL_CAP_GAP ",x," ",z," native ",native_height)
	check(open_cap==0,"Top and both sides of the terrain mouth are covered by rock: %d gaps"%open_cap)
	var shaft_gaps:=0
	for y in range(-155,-92,4):
		for angle_index in 16:
			var a:=angle_index*TAU/16;var p:=Vector3(-33.5,y,-21)
			if space.intersect_ray(PhysicsRayQueryParameters3D.create(p,p+Vector3(cos(a),0,sin(a))*15,1)).is_empty():shaft_gaps+=1
	check(shaft_gaps==0,"Shaft walls enclosed around the cage axis: %d gaps"%shaft_gaps)
	var exit:Vector3=cave.get_node("ExitThreshold").global_position+Vector3.UP*1.3
	for back in [63.0,80.0,91.0,110.0,160.0]:
		var at:=curve.sample_baked(total-back,true)+Vector3.UP*1.3
		check(not space.intersect_ray(PhysicsRayQueryParameters3D.create(at,exit+Vector3.RIGHT*6,1)).is_empty(),"Stone screen blocks exterior sightline from %.0fm before exit"%back)
	var data=snow.get_node("Terrain3D").data
	check(data.get_region_count()==48,"48 authored Terrain3D regions")
	for at in [Vector3(350,0,2),Vector3(600,0,0),Vector3(1200,0,400),Vector3(1400,0,-600)]:
		check(is_finite(data.get_height(at)),"Terrain exists at "+str(at))
	check(absf(data.get_height(Vector3(350,0,2))+156.39)<0.2,"Exterior apron joins cave floor")
	check(snow.get_node("WorldSafetyBoundary/DepthBarrier").position.y< -210,"Safety plane below cave")
	var lighting:=WorldLighting.new();var sun:=DirectionalLight3D.new();sun.name="OvercastSun";lighting.add_child(sun)
	lighting.process_mode=Node.PROCESS_MODE_DISABLED
	world.add_child(lighting)
	lighting.lower_exterior_bounds=snow.get_node("LowerValleyOutdoorRegion/LowerValleyOutdoorBounds")
	check(not lighting.is_covered(Vector3(360,-153,2)),"Lower valley classified outdoors")
	check(lighting.is_covered(curve.sample_baked(total-91)+Vector3.UP*1.5),"Lair classified indoors")
	print("CAVE_ENVIRONMENT_CHECKS ",checks," FAILURES ",failures.size()," length ",total," floor samples ",ceili(total*2)," low samples ",low_count)
	quit(0 if failures.is_empty() else 1)
