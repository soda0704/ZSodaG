extends SceneTree
## Graphical comparison of the local snow sample, plus ground/decoration checks.
var checks := 0
var failures := 0
var output := "res://tools/.local/snow-material-review/captures/"
var actor: GamePlayer

func _initialize() -> void:
	var prefix := "user://entry_snow_%d" % OS.get_process_id()
	ProjectSettings.set_setting(BaseGameplayController.TEST_SAVE_PATH_SETTING, prefix + ".cfg")
	ProjectSettings.set_setting("northern_lab/testing/settings_path", prefix + ".json")
	ProjectSettings.set_setting(JournalReadingStore.ROOT_SETTING, prefix)
	if not OS.get_environment("NORTHERNLAB_EXPORT_CAPTURE_DIR").is_empty():
		output = OS.get_environment("NORTHERNLAB_EXPORT_CAPTURE_DIR") + "/"
	create_timer(110).timeout.connect(func(): quit(2))
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)

func shot(label: String) -> Image:
	await create_timer(0.65).timeout
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	image.save_png(output + label + ".png")
	return image

func difference(a: Image, b: Image) -> float:
	var result := 0.0
	var count := 0
	for y in range(400, 850, 6):
		for x in range(350, 1250, 6):
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			result += absf(ca.r-cb.r) + absf(ca.g-cb.g) + absf(ca.b-cb.b)
			count += 1
	return result / (count * 3)

func ground_luminance(image: Image) -> float:
	var value := 0.0
	for y in range(480,660,4):
		for x in range(650,1050,4): value += image.get_pixel(x,y).get_luminance()
	return value / 4500.0

func run() -> void:
	if DisplayServer.get_name() == "headless": quit(2); return
	DirAccess.make_dir_recursive_absolute(output)
	Engine.max_fps = 60
	root.size = Vector2i(1600, 900); root.content_scale_size = root.size
	root.get_node("GameMenu/GraphicsQuality").set_process(false)
	var base = load("res://scenes/levels/base_blockout_v03.tscn").instantiate()
	root.add_child(base); current_scene = base
	for frame in 30: await physics_frame
	root.get_node("GameMenu").force_close_menu()
	actor = get_first_node_in_group("local_player")
	actor.set_physics_process(false); actor.survival.set_physics_process(false)
	actor.get_node("PlayerUI/CameraPostProcess").effect_enabled = false
	base.get_node("BaseGameplayController").set_process(false)
	var exterior = base.get_node("SnowExterior")
	var terrain = exterior.get_node("Terrain3D")
	var material = terrain.material
	var weather = exterior.get_node("Blizzard")
	weather.enabled = false
	check(terrain.data.get_region_locations().size() == 48, "all 48 terrain regions retained")
	for name in ["Landscape", "BoundaryDressing", "SouthPassForest", "WestPassForest"]:
		check(not exterior.has_node(name), "removed decoration and its collision subtree: " + name)
	check(exterior.get_node("CliffValley").find_children("Forest*", "MultiMeshInstance3D", true, false).is_empty(), "distant billboard forest removed")
	var debris := 0
	for node in exterior.find_children("*", "Node", true, false):
		if node is MultiMeshInstance3D or str(node.name).begins_with("Pine") or str(node.name).begins_with("RockVariant") or str(node.name).begins_with("FallenPine"):
			debris += 1
	check(debris == 0, "no tree/rock meshes or collision nodes remain in the exterior")
	var instances := 0
	for location in terrain.data.get_region_locations():
		var region = terrain.data.get_region(location)
		if region.has_method("get_instances"):
			instances += region.get_instances().size()
	check(instances == 0, "Terrain3D region data contains no hidden vegetation instance batches")
	check(exterior.get_node("WorldSafetyBoundary").get_child_count() == 6, "six physical world boundaries retained")
	check(base.has_node("Cave_Day7/ContinuousGeology") and base.has_node("Cave_Day7/AuthoredOutcrops/Mouth_Bedrock"), "cave and structural mouth rock retained")
	for name in ["entry_snow_albedo", "entry_snow_normal_rough"]:
		var texture: Texture2D = material.get_shader_param(name)
		var image := texture.get_image()
		check(texture.get_width() == 2048 and texture.get_height() == 2048 and image.has_mipmaps() and image.is_compressed(), "2K BC7 texture with mip chain: " + name)
	var space = base.get_world_3d().direct_space_state
	var missing := 0
	for i in 21:
		var point := Vector3(-88, 0, 80).lerp(Vector3(-42, 0, 3), i / 20.0)
		var h: float = terrain.data.get_height(point)
		var hit: Dictionary = space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(point.x, h+2, point.z), Vector3(point.x, h-2, point.z), 1, [actor.get_rid()]))
		if not is_finite(h) or hit.is_empty(): missing += 1
	check(missing == 0, "continuous collision along approach: 21 ground probes")
	var at := Vector3(-54, 0, 9)
	at.y = terrain.data.get_height(at) + 0.05
	actor.teleport_authoritative(at, 0)
	actor.camera.rotation = Vector3.ZERO
	actor.head.look_at(Vector3(-47, terrain.data.get_height(Vector3(-47,0,3))+0.2, 3))
	material.set_shader_param("entry_snow_enabled", false)
	var before := await shot("entry-day-before")
	material.set_shader_param("entry_snow_enabled", true)
	var after := await shot("entry-day-after")
	var change := difference(before, after)
	print("DAY MATERIAL DIFFERENCE ", change)
	check(change > 0.003, "new material visibly renders in the actual approach")
	# Powder now covers the full exterior, including the former trial boundary.
	at = Vector3(-180, 0, 110); at.y = terrain.data.get_height(at) + 0.05
	actor.teleport_authoritative(at, 0)
	actor.head.look_at(Vector3(-188, terrain.data.get_height(Vector3(-188,0,110)), 110))
	material.set_shader_param("entry_snow_enabled", false)
	before = await shot("outside-before")
	material.set_shader_param("entry_snow_enabled", true)
	after = await shot("outside-after")
	check(difference(before, after) > 0.003, "powder material continues beyond the former trial boundary")
	# Drive real player contacts through the existing track sampler, not a placed decal fixture.
	var tracks = exterior.get_node("SnowTracks")
	tracks.set_physics_process(false); tracks._actors.clear()
	var count_before: int = tracks._marks.size()
	for step in 11:
		var foot := Vector3(-51.0 - step * 0.7, 0, 7)
		foot.y = terrain.data.get_height(foot) + 0.04
		actor.global_position = foot; actor.rotation.y = PI * 0.5
		await physics_frame
		tracks._sample(actor, false)
	check(tracks._marks.size() >= count_before + 9, "walking contacts produce alternating boot marks on actual Terrain3D")
	var boot: Decal = tracks._marks[-1].node
	check(boot.texture_normal != null and boot.texture_orm != null, "boot impressions have relief and roughness maps")
	at = Vector3(-55,0,10); at.y = terrain.data.get_height(at) + 0.04
	actor.teleport_authoritative(at,0)
	actor.head.look_at(Vector3(-55,terrain.data.get_height(Vector3(-55,0,7)),7))
	after = await shot("bootprints-day")
	for mark in tracks._marks: mark.node.visible = false
	before = await shot("bootprints-hidden")
	check(difference(before,after) > 0.00015, "boot prints visibly affect the rendered snow")
	for mark in tracks._marks: mark.node.visible = true
	var mark_count: int = tracks._marks.size()
	actor.global_position = Vector3(-20,0.04,0)
	tracks._actors.clear(); tracks._sample(actor,false)
	actor.global_position.x += 0.8; tracks._sample(actor,false)
	check(tracks._marks.size() == mark_count, "no boot marks generated on the base floor")
	# Existing player equipment, with controlled night ambient light.
	at = Vector3(-54, 0, 9); at.y = terrain.data.get_height(at) + 0.05
	actor.teleport_authoritative(at, 0)
	actor.head.look_at(Vector3(-49, terrain.data.get_height(Vector3(-49,0,5)), 5))
	var lighting = base.get_node("WorldLighting")
	lighting.set_process(false)
	var original_environment: Environment = actor.camera.environment
	var environment: Environment = original_environment.duplicate()
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.5,0.6,0.75)
	environment.ambient_light_energy = 0.035
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	environment.background_energy_multiplier = 0.025
	actor.camera.environment = environment
	for light in base.find_children("*", "DirectionalLight3D", true, false): light.visible = false
	actor.flashlight.malfunction_enabled = false
	actor.pickup_world_item_authoritative(&"flashlight", {"battery_charge": 1.0})
	actor.update_character_animation(1.0/60.0)
	if not actor.flashlight.beam.is_visible_in_tree(): actor.toggle_flashlight_authoritative()
	# Fixed beam pose isolates material response from the procedural hand rig.
	actor.flashlight.beam.reparent(actor.camera, false)
	actor.flashlight.beam.transform = Transform3D(Basis.IDENTITY, Vector3(0.18,-0.12,-0.7))
	actor.flashlight.spill.reparent(actor.camera, false)
	actor.flashlight.spill.transform = actor.flashlight.beam.transform
	# Player shadow/hand poses are not under test. Isolate snow's BRDF response.
	actor.flashlight.beam.shadow_enabled = false
	actor.flashlight.spill.shadow_enabled = false
	actor.flashlight.beam.light_energy = 4.0
	actor.flashlight.beam.show(); actor.flashlight.spill.show()
	material.set_shader_param("entry_snow_enabled", false)
	await shot("entry-flashlight-before")
	material.set_shader_param("entry_snow_enabled", true)
	after = await shot("entry-flashlight-after")
	actor.flashlight.beam.hide(); actor.flashlight.spill.hide()
	before = await shot("entry-night-no-flashlight")
	print("SNOW LIGHT luminance on=",ground_luminance(after)," off=",ground_luminance(before)," beam=",actor.flashlight.beam.global_transform)
	check(ground_luminance(after) > ground_luminance(before) + 0.01, "snow responds to a fixed directed light (test pose, shadows disabled)")
	# Restore the actual scene profile and capture the playable weather/camera view.
	actor.camera.environment = original_environment
	lighting.set_process(true)
	for light in base.find_children("*", "DirectionalLight3D", true, false): light.visible = true
	weather.enabled = true
	actor.get_node("PlayerUI/CameraPostProcess").effect_enabled = true
	await shot("entry-gameplay-storm")
	actor = null; current_scene = null; base.queue_free()
	for frame in 4: await process_frame
	print("ENTRY SNOW CHECKS ", checks, " FAILURES ", failures)
	quit(1 if failures else 0)
