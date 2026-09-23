extends SceneTree
var world: Node3D
var player: CharacterBody3D
var terrain: Node3D
var tracks: Node3D
var failures: Array[String] = []
func _initialize(): run.call_deferred()
func check(ok: bool, message: String):
	print("PASS " if ok else "FAIL ",message)
	if not ok: failures.append(message)
func settle(frames := 30):
	for i in frames:
		await physics_frame
		player.velocity = Vector3(0,-3,0)
		player.move_and_slide()
func walk_to(target: Vector3, seconds: float):
	for i in int(seconds * 60):
		await physics_frame
		var direction := (target-player.position); direction.y=0
		if direction.length()<0.15: break
		player.velocity = direction.normalized()*4 + Vector3.DOWN*3
		player.move_and_slide()
func run():
	world = load("res://scenes/levels/Base_Blockout_v03.tscn").instantiate()
	root.add_child(world)
	root.get_node("GameMenu").force_close_menu()
	await create_timer(2).timeout
	player = get_first_node_in_group("network_players")
	player.set_physics_process(false)
	terrain = world.get_node("SnowExterior/Terrain3D")
	tracks = world.get_node("SnowExterior/SnowTracks")
	check(terrain.data.get_region_locations().size()==16,"16 terrain regions")
	check(world.get_node("ArrivalSite/Chinook/RearRamp").opened,"landed helicopter ramp starts open")
	for i in 2:
		player.position=world.get_player_spawn_position(i)
		await settle()
		check(player.is_on_floor() and player.position.y>11,"spawn %d on platform"%i)
	player.position=Vector3(-117,11.4,95)
	await settle()
	await walk_to(Vector3(-92,8,95),8)
	check(player.position.x > -92.3,"walk down ramp without jumping: " + str(player.position))
	await walk_to(Vector3(-117,11.4,95),9)
	check(player.position.x < -116.7,"walk up ramp without jumping: " + str(player.position))
	var before: int = tracks._marks.size()
	await walk_to(Vector3(-121,11.4,98),2)
	check(tracks._marks.size()==before,"no marks on metal deck")
	player.position=Vector3(-88,8.2,80)
	player.position.y=terrain.data.get_height(player.position)+0.1
	await settle()
	before=tracks._marks.size()
	await walk_to(Vector3(-80,0,64),6)
	check(tracks._marks.size()>before+10,"walking creates snow footprints")
	before=tracks._marks.size()
	await settle()
	check(tracks._marks.size()==before,"stationary character adds no marks")
	player.debug_fly=true
	await walk_to(Vector3(-75,0,60),2)
	check(tracks._marks.size()==before,"flight adds no marks")
	player.debug_fly=false
	player.position.y+=3
	await physics_frame
	check(tracks._marks.size()==before,"airborne character adds no marks")
	var vehicle: CharacterBody3D = load("res://scenes/objects/vehicles/snowmobile.tscn").instantiate()
	root.add_child(vehicle)
	vehicle.set_physics_process(false)
	await process_frame
	vehicle.position=Vector3(-86,8,88)
	vehicle.position.y=terrain.data.get_height(vehicle.position)-0.08
	for i in 120:
		await physics_frame
		vehicle.position.z-=0.1
		vehicle.position.y=terrain.data.get_height(vehicle.position)-0.08
	check(tracks._marks.size()>before+20,"snowmobile creates tread and two ski tracks")
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.position=Vector3(-80,17,85)
	camera.look_at(Vector3(-85,7,80))
	camera.current=true
	root.size=Vector2i(1400,900)
	await create_timer(0.5).timeout
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("user://snow_expansion_tracks.png")
	tracks.max_marks=20
	for i in 80:
		await physics_frame
		vehicle.position.z-=0.15
		vehicle.position.y=terrain.data.get_height(vehicle.position)-0.08
	check(tracks._marks.size()<=20,"decal count bounded")
	tracks.lifetime=0.1
	await create_timer(0.3).timeout
	check(tracks._marks.is_empty(),"old marks expire")
	player.position=Vector3(-92,8.1,95)
	await settle()
	for point in [Vector3(-78,5.8,60),Vector3(-55,2.2,25),Vector3(-41,-0.15,3)]:
		await walk_to(point,14)
		var offset: Vector3 = player.position-point
		offset.y=0
		check(offset.length()<0.4,"graded route to base: " + str(point))
	print("RESULT ",failures)
	quit(0 if failures.is_empty() else 1)
