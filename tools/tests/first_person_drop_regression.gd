extends SceneTree
var actor:GamePlayer
var failures:=0
var poses:Array[Transform3D]=[]
func record(sk:Skeleton3D):
	poses.clear()
	for bone in sk.get_bone_count():poses.append(sk.get_bone_global_pose(bone))
const OUT:="res://tools/.local/fp-rebuild-review/"
func _initialize(): run.call_deferred()
func ticks(n:int):
	for i in n:await physics_frame
func capture(label:String):
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT+label+".png")
func check(ok:bool,label:String):
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func run():
	if DisplayServer.get_name()=="headless": push_error("Run with a graphical renderer.");quit(1);return
	Engine.max_fps=60;root.size=Vector2i(1280,720)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	root.get_node("GameMenu").force_close_menu()
	var service=root.get_node("SteamInput");service.set_process(false);service.set_process_input(false);service.native_input_available=false
	var world=load("res://tools/tests/fixtures/character_test_arena.tscn").instantiate();root.add_child(world)
	for id in [0,1]:
		actor=load("res://scenes/characters/player.tscn").instantiate();actor.name="1";actor.setup(1,"",Vector3(0,.1,0),Color.WHITE,0,id);world.get_node("Players").add_child(actor)
		actor.survival.set_physics_process(false);actor.camera.current=true
		var sk:Skeleton3D=actor.body_animator.first_person_model.get_node("Skeleton3D");sk.skeleton_updated.connect(record.bind(sk))
		for action in InputMap.get_actions():InputMap.action_erase_events(action)
		var pads:=0
		var mesh:ArrayMesh=sk.get_node("Arms").mesh
		for surface in mesh.get_surface_count():
			if "Pads" in mesh.surface_get_material(surface).resource_name:pads+=1
			var arrays:=mesh.surface_get_arrays(surface)
			for vertex in arrays[Mesh.ARRAY_INDEX]:
				for slot in 4:
					if "Elbow_Pads" in sk.get_bone_name(arrays[Mesh.ARRAY_BONES][vertex*4+slot]) and arrays[Mesh.ARRAY_WEIGHTS][vertex*4+slot]>.05:pads+=1
		check(pads==0,"no detached elbow pads in FP mesh %d"%id)
		await ticks(40)
		var fp=actor.body_animator.first_person
		check(not fp.overlay.visible,"initial empty has no cut sleeves %d"%id)
		await capture("%d-empty"%id)
		for kind in [&"pistol",&"m4a1",&"kitchen_knife"]:
			actor.apply_held_item_inventory(kind,{},false);actor.weapon.apply_state(kind,12,0);await ticks(40)
			await capture("%d-%s-hip"%[id,kind])
			var held:Node3D=actor.body_animator.equipment_root().get_node(String(kind))
			check(absf((actor.camera.global_basis.inverse()*held.global_basis).get_euler().z)<deg_to_rad(1),"level hip pose %d %s"%[id,kind])
			if kind!=&"kitchen_knife":
				var grip:Node3D=held.get_node("LeftHandGrip")
				var error:=sk.to_global(poses[sk.find_bone("LeftHand")].origin).distance_to(grip.global_position)
				print("SUPPORT ERROR ",id," ",kind," ",error," shoulder ",poses[sk.find_bone("LeftArm")].origin," target ",sk.to_local(grip.global_position))
				check(error<.015,"hip support contact %d %s"%[id,kind])
				Input.action_press("weapon_aim");await ticks(40)
				var item:Node3D=actor.body_animator.equipment_root().get_node(String(kind))
				var b:=actor.camera.global_basis.inverse()*item.global_basis
				print("ITEM AXIS ",id," ",kind," ",b.get_euler()*180/PI)
				check(absf(b.get_euler().z)<deg_to_rad(1),"level ADS %d %s"%[id,kind])
				await capture("%d-%s-ads"%[id,kind]);Input.action_release("weapon_aim");await ticks(20)
			var event:=InputEventAction.new();event.action=&"drop_item";event.pressed=true;Input.parse_input_event(event);await ticks(1)
			event=InputEventAction.new();event.action=&"drop_item";event.pressed=false;Input.parse_input_event(event)
			await capture("%d-%s-drop-01"%[id,kind]);await ticks(7);await capture("%d-%s-drop-08"%[id,kind]);await ticks(30)
			check(fp.kind=="Relaxed" and not fp.overlay.visible,"actual drop clears sleeves %d %s"%[id,kind]);await capture("%d-%s-dropped"%[id,kind])
		for pitch in [-1.48,1.48,0.0]:
			actor._input_pitch=pitch;Input.action_press("move_forward");await ticks(12)
			check(not fp.overlay.visible,"empty stays clear while moving at pitch %.2f variant %d"%[pitch,id])
		Input.action_release("move_forward");actor._input_pitch=0;await ticks(15)
		var journal:QuestJournalUI=root.get_node("QuestJournal");journal.open_journal();await ticks(75)
		check(fp.overlay.visible,"journal works from empty %d"%id);await capture("%d-book"%id);journal.close_journal();await ticks(75)
		check(not fp.overlay.visible,"journal returns to empty %d"%id)
		actor.queue_free();await process_frame
	print("FP DROP AND LEVEL FAILURES ",failures);quit(1 if failures else 0)
