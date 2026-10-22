extends SceneTree
## Offline product renders for journal cards and geometry review.
const NAMES = ["flamethrower","large_cylinder","small_cylinder","cola_can","pipe_bundle","hardware_box","pressure_gauge","valve","tape"]
func _initialize() -> void: run.call_deferred()
func run() -> void:
	root.get_node("GameMenu").force_close_menu()
	DirAccess.make_dir_recursive_absolute("res://assets/ui/journal_crafting")
	var viewport := SubViewport.new(); viewport.size=Vector2i(640,480); viewport.transparent_bg=true
	viewport.own_world_3d=true; viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS; root.add_child(viewport)
	var environment := WorldEnvironment.new(); environment.environment=Environment.new()
	environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color=Color.WHITE; environment.environment.ambient_light_energy=.7; viewport.add_child(environment)
	var key := DirectionalLight3D.new(); key.rotation_degrees=Vector3(-40,-35,0); key.light_energy=1.6; viewport.add_child(key)
	var fill := DirectionalLight3D.new(); fill.rotation_degrees=Vector3(20,130,0); fill.light_energy=.8; viewport.add_child(fill)
	var camera := Camera3D.new(); camera.projection=Camera3D.PROJECTION_ORTHOGONAL; camera.current=true; viewport.add_child(camera)
	for label: String in NAMES:
		var path := "res://scenes/art/crafting/"+label+".tscn"
		if label=="flamethrower": path="res://scenes/objects/items/flamethrower_model.tscn"
		if label=="tape": path="res://scenes/objects/items/tape_model.tscn"
		var model: Node3D=load(path).instantiate(); viewport.add_child(model)
		var bounds := AABB(); var first:=true
		for node: MeshInstance3D in model.find_children("*","MeshInstance3D",true,false):
			var value: AABB=node.global_transform*node.mesh.get_aabb()
			bounds=value if first else bounds.merge(value); first=false
		print("BOUNDS ",label," ",bounds)
		camera.size=maxf(bounds.size.length()*1.4,.08)
		var angle:=Vector3(.85,.65,1.1) if label!="flamethrower" else Vector3(1,.6,-.45)
		if label=="pressure_gauge": angle=Vector3(-.45,.25,-1)
		if label=="flamethrower": angle=Vector3(1,.32,.12); camera.size=bounds.size.length()*1.08
		camera.position=bounds.get_center()+angle.normalized()*bounds.size.length()*3
		camera.look_at(bounds.get_center())
		if label=="flamethrower": camera.rotate_object_local(Vector3.FORWARD,deg_to_rad(-15))
		for frame in 5: await process_frame
		await RenderingServer.frame_post_draw
		viewport.get_texture().get_image().save_png("res://assets/ui/journal_crafting/"+label+".png")
		model.free()
	viewport.queue_free(); await process_frame
	print("CRAFT_RENDERS_READY"); quit()

