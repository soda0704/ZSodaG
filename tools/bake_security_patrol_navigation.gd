extends SceneTree
## Offline authoring only. Existing floor collisions include furniture and door frames.
func _initialize() -> void:
	ProjectSettings.set_setting(BaseGameplayController.TEST_SAVE_PATH_SETTING,"user://security_navigation_authoring_only.cfg")
	run.call_deferred()

func run() -> void:
	var base = load("res://scenes/levels/base_blockout_v03.tscn").instantiate()
	base.network_runtime_managed = true
	root.add_child(base); current_scene = base
	base.get_node("BaseGameplayController").progress_persistence_enabled = false
	base.get_node("BaseGameplayController").set_process(false)
	for actor in get_nodes_in_group("hostile_monsters"): actor.set_physics_process(false)
	for frame in 6: await physics_frame
	var floor: Node3D = base.get_node("Floor_Minus1_Control_Security_Blockout")
	# Moving door leaves and their runtime blockers must not be baked shut.
	# Authored room-wall openings remain the route's clearance geometry.
	for branch in floor.get_children():
		if branch.name != &"Doors": branch.add_to_group("security_patrol_navigation_source")
	for door in floor.get_node("Doors").get_children():
		var frame := door.find_child("Frame",true,false)
		if frame != null: frame.add_to_group("security_patrol_navigation_source")
	for manager in get_nodes_in_group("base_auto_door_managers"):
		if manager.get_parent() != floor.get_node("Doors"): continue
		manager.set_process(false)
		for door in manager._doors:
			# Runtime physics blockers are disposable in this isolated authoring scene.
			# Removing instances does not edit any authored door or scene file.
			door.blocker.get_parent().free()
	await physics_frame
	var region: NavigationRegion3D = base.get_node("PatrolRoutes/SecurityNavigation")
	region.navigation_mesh = region.navigation_mesh.duplicate()
	region.navigation_mesh.geometry_collision_mask = 1
	region.navigation_mesh.filter_baking_aabb = AABB(Vector3(-67,-19,-20),Vector3(67,5,40))
	region.bake_navigation_mesh(true)
	await region.bake_finished
	var result := ERR_INVALID_DATA
	if region.navigation_mesh.get_polygon_count() > 0:
		result = ResourceSaver.save(region.navigation_mesh,"res://assets/navigation/security_patrol.tres")
	print("SECURITY PATROL NAVIGATION: ",region.navigation_mesh.get_polygon_count()," polygons, save result ",result)
	base.queue_free(); await process_frame
	quit(0 if result == OK else 1)
