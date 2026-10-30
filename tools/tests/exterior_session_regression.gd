extends "res://tools/tests/exterior_load_regression.gd"
## Exercise the real arrival twice, with all persistent data isolated.

func _initialize() -> void:
	var prefix:="user://exterior_session_%d"%OS.get_process_id()
	ProjectSettings.set_setting(BaseGameplayController.TEST_SAVE_PATH_SETTING,prefix+".cfg")
	ProjectSettings.set_setting("northern_lab/testing/settings_path",prefix+".json")
	ProjectSettings.set_setting("northern_lab/testing/save_slots_root",prefix+"/slots")
	ProjectSettings.set_setting("northern_lab/testing/legacy_save_paths",{})
	ProjectSettings.set_setting(JournalReadingStore.ROOT_SETTING,prefix)
	create_timer(150).timeout.connect(func():quit(2))
	run.call_deferred()

func run() -> void:
	Engine.max_fps=60
	root.size=Vector2i(1280,720)
	var plan_hash:=FileAccess.get_sha256(Plan.PLAN_PATH)
	var packed:PackedScene=load(LEVEL)
	var native:=packed.instantiate()
	var expected:=snapshot(native)
	native.free()
	var plan:Resource=load(Plan.PLAN_PATH)
	# Runtime normally rebuilds a stale plan and writes it to res:// in editor.
	# Refresh only the cached Resource in this isolated test process.
	if not Plan.current(plan):
		var fresh:Resource=Plan.new().build(packed)
		for key in fresh.get_meta_list():plan.set_meta(key,fresh.get_meta(key))
	var menu:=root.get_node("GameMenu")
	for attempt in 2:
		await menu.start_standalone_flow()
		var session:=current_scene
		await session._enter_v3_level()
		check(not session._v3_transition_in_progress and not session.lobby_hud.flight_transition.visible,"arrival %d finishes and reveals the scene"%attempt)
		var level:Node3D=session.get_node("V3Level")
		var actual:=snapshot(level)
		check(actual.keys()==expected.keys(),"arrival %d retains every exterior mesh"%attempt)
		for key in expected:
			var wanted:Dictionary=expected[key].duplicate()
			var found:Dictionary=actual.get(key,{}).duplicate()
			var layers_match:bool=(int(found.get("layers",0)) & int(wanted.layers))==int(wanted.layers)
			wanted.erase("layers");found.erase("layers")
			check(wanted==found and layers_match,"arrival %d retains authored exterior: %s"%[attempt,key])
		var shell:=level.get_node(SHELL)
		var all_visible:=true
		for mesh:MeshInstance3D in shell.find_children("*","MeshInstance3D",true,false):
			all_visible=all_visible and mesh.is_visible_in_tree()
		check(all_visible,"arrival %d exterior meshes remain visible after readiness"%attempt)
		var player:GamePlayer=get_first_node_in_group("local_player")
		player.set_physics_process(false);player.survival.set_physics_process(false)
		player.teleport_authoritative(Vector3(-53.7224,2.02075,37.8333),0)
		player.camera.look_at(Vector3(-17,2.5,1))
		for frame in 30:await process_frame
		if DisplayServer.get_name()!="headless":
			await RenderingServer.frame_post_draw
			var normal:=root.get_texture().get_image()
			normal.save_png("res://tools/.local/feedback-fixes-2026-10-30/exterior-arrival-%d.png"%attempt)
			if attempt==0:
				shell.visible=false
				for frame in 3:await process_frame
				await RenderingServer.frame_post_draw
				var hidden:=root.get_texture().get_image()
				hidden.save_png("res://tools/.local/feedback-fixes-2026-10-30/exterior-arrival-hidden.png")
				shell.visible=true
				var changed:=0
				var sampled:=0
				for y in range(235,450,2):
					for x in range(330,1040,2):
						var a:=normal.get_pixel(x,y);var b:=hidden.get_pixel(x,y)
						if maxf(absf(a.r-b.r),maxf(absf(a.g-b.g),absf(a.b-b.b)))>.03:changed+=1
						sampled+=1
				var contribution:=float(changed)/sampled
				print("EXTERIOR RENDER CHANGED PIXELS ",contribution)
				check(contribution>.10,"exterior visibly contributes to the rendered building rather than merely existing in the tree")
		check(level.get_node("SnowExterior/Terrain3D").data.get_region_locations().size()==48,"arrival %d loads all authored terrain regions"%attempt)
		if attempt==0:
			menu.return_to_main_menu("",false)
			await scene_changed
			for frame in 3:await process_frame
	check(plan_hash==FileAccess.get_sha256(Plan.PLAN_PATH),"test preserves the existing loading plan file byte for byte")
	print("EXTERIOR SESSION CHECKS ",checks," FAILURES ",failures)
	quit(1 if failures else 0)
