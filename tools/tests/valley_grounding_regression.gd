extends SceneTree
## Run with a graphical renderer: the test reads saved MultiMesh transforms.
## The temporary collision mesh exists only in this test to validate visual grounding.
func _initialize(): run.call_deferred()
func run():
	var world = load("res://scenes/levels/snow_exterior.tscn").instantiate()
	root.add_child(world)
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.current=true
	var valley: Node3D=world.get_node("CliffValley")
	var ground_mesh: Mesh=valley.get_node("DistantValleyFloor").mesh
	var terrain=world.get_node("Terrain3D")
	var body := StaticBody3D.new()
	body.collision_layer=1<<19
	body.collision_mask=0
	var collider := CollisionShape3D.new()
	collider.shape=ground_mesh.create_trimesh_shape()
	body.add_child(collider)
	world.add_child(body)
	await physics_frame
	await physics_frame
	var perimeter_errors:=0
	for radius in [512.0,900.0,1800.0,2600.0]:
		for i in 32:
			var direction:=Vector2(cos(i*TAU/32),sin(i*TAU/32))
			var point:Vector2=direction/maxf(absf(direction.x),absf(direction.y))*radius
			var hit:Dictionary=world.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(point.x,600,point.y),Vector3(point.x,-250,point.y),1<<19))
			if hit.is_empty():
				# Jolt can reject a ray exactly on a shared triangle edge.
				# Require support on both sides within five centimetres.
				for shift in [Vector2(0.05,0.05),Vector2(-0.05,-0.05)]:
					var nearby:Vector2=point+shift
					var neighbor:Dictionary=world.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(nearby.x,600,nearby.y),Vector3(nearby.x,-250,nearby.y),1<<19))
					if neighbor.is_empty(): perimeter_errors+=1

	print("PERIMETER COVERAGE ERRORS ",perimeter_errors)
	var count:=0
	var errors:=perimeter_errors
	var worst:=0.0
	var columns: Dictionary = {}
	for forest in valley.find_children("Forest*","MultiMeshInstance3D",false,false):
		for i in forest.multimesh.instance_count:
			var t: Transform3D=forest.multimesh.get_instance_transform(i)
			var p: Vector3=forest.transform*t.origin
			if not p.is_finite():
				errors+=1
				continue
			columns[p.x]=int(columns.get(p.x,0))+1
			var terrain_height: float=terrain.data.get_height(p)
			var hit: Dictionary=world.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(p.x,1000,p.z),Vector3(p.x,-250,p.z),1<<19))
			if is_finite(terrain_height) and maxf(absf(p.x),absf(p.z))<=510.0: hit={"position":Vector3(p.x,terrain_height,p.z)}
			if hit.is_empty():
				errors+=1
				print("MISSING GROUND ",p)
				continue
			var ground: float=hit.position.y
			var deviation:=absf(p.y-ground-0.18)
			worst=maxf(worst,deviation)
			if deviation>0.3: errors+=1
			count+=1
	var largest_column:=0
	for amount in columns.values(): largest_column=maxi(largest_column,int(amount))
	if largest_column>8: errors+=1
	print("LARGEST EXACT-X COLUMN ",largest_column)
	print("TREES ",count," GROUNDING ERRORS ",errors," MAX DEVIATION ",worst)
	quit(0 if errors==0 else 1)

