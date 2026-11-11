extends SceneTree
## Real imported shell, fixed cameras, GPU images and actual power controller.
var checks := 0
var failures := 0
var base: Node3D
var lighting: WorldLighting
var camera: Camera3D
var output := "res://tools/.local/lighting-review-2026-11-11/"
func _initialize():
	var prefix := "user://light_visibility_%d" % OS.get_process_id()
	ProjectSettings.set_setting(BaseGameplayController.TEST_SAVE_PATH_SETTING, prefix + ".cfg")
	ProjectSettings.set_setting("northern_lab/testing/settings_path", prefix + ".json")
	ProjectSettings.set_setting(JournalReadingStore.ROOT_SETTING, prefix)
	if not OS.get_environment("NORTHERNLAB_EXPORT_CAPTURE_DIR").is_empty(): output = OS.get_environment("NORTHERNLAB_EXPORT_CAPTURE_DIR") + "/"
	create_timer(160).timeout.connect(func(): quit(2))
	run.call_deferred()
func check(ok: bool, label: String):
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)
func capture(label: String) -> Image:
	for frame in 60: await process_frame
	await RenderingServer.frame_post_draw
	var picture := root.get_texture().get_image()
	picture.save_png(output + label + ".png")
	return picture
func mean(picture: Image, rect: Rect2i) -> float:
	var energy := 0.0;var count := 0
	for x in range(rect.position.x, rect.end.x, 5):
		for y in range(rect.position.y, rect.end.y, 5): energy += picture.get_pixel(x,y).get_luminance();count += 1
	return energy / maxi(1,count)
func set_power(value: bool):
	var state: BaseGameplayController = base.get_node("BaseGameplayController")
	var snap := state.get_snapshot();snap.main_breaker_on = value;snap.fuel_delivered = true;snap.fuel_liters = 30.0;snap.containment["fault"] = false
	state._broadcast_snapshot(snap)
func run():
	DirAccess.make_dir_recursive_absolute(output)
	Engine.max_fps = 60;root.size = Vector2i(1280,720);root.content_scale_size = root.size
	base = load("res://scenes/levels/base_blockout_v03.tscn").instantiate();root.add_child(base);current_scene = base
	for frame in 30: await physics_frame
	root.get_node("GameMenu").force_close_menu()
	var actor: GamePlayer = get_first_node_in_group("local_player")
	actor.set_physics_process(false);actor.survival.set_physics_process(false);actor.body_animator.hide();actor.get_node("PlayerUI").hide();actor.teleport_authoritative(Vector3(-90,0,45),0)
	base.get_node("BaseGameplayController").set_process(false);base.get_node("SnowExterior/Blizzard").enabled = false
	lighting = base.get_node("WorldLighting");lighting.set_process(false)
	camera = Camera3D.new();base.add_child(camera);camera.current = true;camera.fov = 80
	root.get_node("GameMenu/GraphicsQuality").set_gi_quality(2)
	camera.position = Vector3(-6,1.7,15.5);camera.look_at(Vector3(1,2,10.1))
	var hull := base.get_node("Floor_0_Base_Blockout/ArcticBase_ExteriorShell")
	var diagnostic := Node3D.new();base.add_child(diagnostic)
	for mesh: MeshInstance3D in hull.get_node("Model").get_children():
		if not mesh.visible: continue
		var body := StaticBody3D.new();body.collision_layer = 1 << 25
		var shape := CollisionShape3D.new();shape.shape = mesh.mesh.create_trimesh_shape()
		body.add_child(shape);diagnostic.add_child(body);body.global_transform = mesh.global_transform
	for frame in 3: await physics_frame
	for pixel in [Vector2(470,260),Vector2(690,320)]:
		var direction := camera.project_ray_normal(pixel)
		var distance := 6.25 if pixel.x < 600 else 10.28
		var ray := PhysicsRayQueryParameters3D.create(camera.position,camera.position + direction * distance,1 << 25)
		print("SHEET MESH ", pixel, " ", base.get_world_3d().direct_space_state.intersect_ray(ray))
		check(base.get_world_3d().direct_space_state.intersect_ray(ray).is_empty(), "former connector sheet no longer intersects the room at " + str(pixel))
		ray.collision_mask = 1
		var hit := base.get_world_3d().direct_space_state.intersect_ray(ray)
		print("SHEET COLLISION ", pixel, " ", hit)
		check(hit.is_empty() or not hull.is_ancestor_of(hit.collider), "no invisible exterior collision remains at " + str(pixel))
	# All four junctions used the same two deep side sheets. Test the visible
	# imported model and the actual collision independently across room height.
	for route in [["west", Vector3(-9.1,0,0), Vector3.FORWARD], ["east", Vector3(9.1,0,0), Vector3.FORWARD], ["north", Vector3(0,0,-9.1), Vector3.RIGHT], ["south", Vector3(0,0,9.1), Vector3.RIGHT]]:
		var mesh_clear := true;var collision_clear := true;var roof_retained := true
		for side in [-1,1]:
			for height in [.5,1.7,3.8,5.0]:
				var center: Vector3 = route[1] + route[2] * 2.82 * side + Vector3.UP * height
				var ray := PhysicsRayQueryParameters3D.create(center-route[2]*.35,center+route[2]*.35,1<<25)
				mesh_clear = mesh_clear and base.get_world_3d().direct_space_state.intersect_ray(ray).is_empty()
				ray.collision_mask = 1
				var hit := base.get_world_3d().direct_space_state.intersect_ray(ray)
				collision_clear = collision_clear and (hit.is_empty() or not hull.is_ancestor_of(hit.collider))
			var top: Vector3 = route[1] + route[2] * 2.82 * side + Vector3.UP * 5.8
			roof_retained = roof_retained and not base.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(top-route[2]*.35,top+route[2]*.35,1<<25)).is_empty()
		check(mesh_clear, route[0]+" junction: both shell sheets clear the room at four heights")
		check(collision_clear, route[0]+" junction: no invisible shell collision below ceiling")
		check(roof_retained, route[0]+" junction: upper roof bridge retained on both sides")
	diagnostic.queue_free()
	lighting.set_debug_darkness(0);await capture("bars-after");lighting.set_debug_darkness(1)
	set_power(true)
	for frame in 60: lighting._process(1.0/60.0);await process_frame
	var lit := await capture("room-after")
	var indirect := base.get_node("WorldIndirectLighting")
	indirect.set_debug_disabled(true)
	var direct_only := await capture("room-without-gi")
	var region := Rect2i(220,160,840,490)
	var delta := absf(mean(lit,region) - mean(direct_only,region))
	check(delta > .001, "advanced reflection isolation preserves visible VoxelGI bounce (difference " + str(delta) + ")")
	indirect.set_debug_disabled(false)
	set_power(false)
	var alarm := lighting.get_node("EmergencyAlarm")
	alarm.stream_paused = true
	for lamp in lighting._lamps: lamp.hide();lamp.light_energy = 0
	lighting.get_node("OvercastSun").hide()
	var dark := await capture("room-no-sources")
	check(mean(dark,region) < .003, "visible room walls stay dark without sun or local sources")
	var freecam = actor.debug_free_camera
	freecam.set_enabled(true);freecam.set_process(false)
	freecam.global_transform = camera.global_transform
	lighting._process(0.0)
	for lamp in lighting._lamps: lamp.hide();lamp.light_energy = 0
	check(root.get_camera_3d() == freecam, "the real player inspection camera becomes current")
	var inspected := await capture("freecam-no-sources")
	check(mean(inspected,region) < .003, "freecam does not make the unlit modular room glow")
	check(base.get_node("WorldIndirectLighting").get_active_probe_count() == 0, "freecam keeps the backup circuit's direct-only profile")
	freecam.set_enabled(false);camera.make_current()
	check(root.get_camera_3d() == camera, "leaving freecam restores the controlled comparison camera")
	lighting.get_node("OvercastSun").show()
	# Open the actual route; stop proximity updates so the camera is the only variable.
	var manager := base.get_node("Floor_0_Base_Blockout/Doors/AutomaticDoors")
	manager.set_process(false)
	for door in manager._doors: manager._apply_door_state(door,true,true)
	camera.position = Vector3(-35.6,1.7,5);camera.look_at(Vector3(-22,2,4.5))
	lighting._lamp_pool.invalidate()
	for frame in 70:
		lighting.emergency_intensity = 1.0;lighting._update_lamps(camera.position,1.0/60.0);await process_frame
	var far := 0
	for lamp in lighting._resident_lamps:
		print("RESIDENT ",lamp.name," at ",lamp.global_position," energy ",lamp.light_energy)
		if lamp.global_position.distance_to(camera.position) > 10 and lamp.light_energy > .01: far += 1
	print("FAR VIEW residents=",lighting._resident_lamps.size()," distant=",far)
	check(far > 0, "real vestibule view already contains active emergency lamps beyond 10 metres")
	await capture("entrance-distant-alarm")
	for frame in 60:
		lighting.emergency_intensity = 0.0;lighting._update_lamps(camera.position,1.0/60.0);await process_frame
	check(lighting._lamps.all(func(lamp):return is_zero_approx(lamp.light_energy)), "distant selection does not bypass the alarm's zero-energy pause")
	current_scene = null;base.queue_free()
	for frame in 12: await process_frame
	print("LIGHT VISIBILITY CHECKS ",checks," FAILURES ",failures);quit(1 if failures else 0)
