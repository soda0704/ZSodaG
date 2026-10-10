extends SceneTree
var actor: GamePlayer
var failures:=0
var final_poses:Array[Transform3D]=[]
func record_pose(sk:Skeleton3D):
	final_poses.clear()
	for bone in sk.get_bone_count():final_poses.append(sk.get_bone_global_pose(bone))
const OUT="res://tools/.local/anatomy-review/"
func _initialize(): run.call_deferred()
func run():
	Engine.max_fps=60; root.size=Vector2i(1280,720)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	root.get_node("GameMenu").force_close_menu()
	var input=root.get_node("SteamInput");input.set_process(false);input.set_process_input(false)
	var arena=load("res://tools/tests/fixtures/character_test_arena.tscn").instantiate(); root.add_child(arena)
	var camera: Camera3D=arena.get_node("ReviewCamera");camera.cull_mask=1|(1<<18);camera.fov=36;camera.near=.01
	for variant in [0,1]:
		actor=load("res://scenes/characters/player.tscn").instantiate();actor.name="1";actor.setup(1,"",Vector3.ZERO,Color.WHITE,0,variant);arena.get_node("Players").add_child(actor)
		actor.set_physics_process(false);actor.survival.set_physics_process(false);actor.weapon.set_physics_process(false);actor.set_process_unhandled_input(false)
		actor.body_animator.skeleton.skeleton_updated.connect(record_pose.bind(actor.body_animator.skeleton))
		actor.body_animator.set_external_view(true);camera.current=true
		for state in ["empty","pistol","m4a1","kitchen_knife","flashlight","fuel_can","journal","pistol-up","pistol-down","rifle-up","rifle-down"]:
			var kind=&"pistol" if state.begins_with("pistol") else &"m4a1" if state.begins_with("rifle") else StringName(state) if state not in ["empty","journal"] else &""
			actor.weapon.apply_state(kind,12,0);actor._held_item_type=kind;actor._has_flashlight=true;actor._battery_charge=1;actor._refresh_equipment_visuals()
			var context={"held_item":kind,"grounded":true,"pitch":1.48 if state.ends_with("-up") else -1.48 if state.ends_with("-down") else 0.0,"yaw":0.0,"velocity":Vector3.ZERO,"journal_phase":2 if state=="journal" else 0}
			for i in 80:actor.body_animator.update_context(1.0/60,context);await process_frame
			actor.body_animator._sync_world_items(kind,context.journal_phase)
			var sk: Skeleton3D=actor.body_animator.model.get_node("Skeleton3D")
			for side in ["Left","Right"]:
				var h=sk.find_bone(side+"Hand");var f=sk.find_bone(side+"ForeArm")
				var neutral=final_poses[f].basis*sk.get_bone_global_rest(f).basis.inverse()*sk.get_bone_global_rest(h).basis
				var q=(final_poses[h].basis*neutral.inverse()).get_rotation_quaternion();if q.w<0:q=-q
				var axis=(final_poses[h].origin-final_poses[f].origin).normalized()
				print("ANATOMY ",variant," ",state," ",side," wrist_angle=",rad_to_deg(q.get_angle())," twist=",rad_to_deg(2*atan2(Vector3(q.x,q.y,q.z).dot(axis),q.w)))
				if rad_to_deg(q.get_angle())>49 or absf(rad_to_deg(2*atan2(Vector3(q.x,q.y,q.z).dot(axis),q.w)))>8:
					failures+=1;print("FAIL runtime wrist ",variant," ",state," ",side)
			for view in ["side","front"]:
				camera.global_position=Vector3(1.1,1.37,-.3) if view=="side" else Vector3(.45,1.45,-1.3)
				camera.look_at(Vector3(0.0,1.32,-.20))
				for i in 3:await process_frame
				await RenderingServer.frame_post_draw;root.get_texture().get_image().save_png(OUT+"%d-%s-%s.png"%[variant,state,view])
			if state in ["pistol","m4a1","kitchen_knife"]:
				actor.body_animator.weapon_effect(kind,state!="kitchen_knife")
				context.reloading=state!="kitchen_knife"
				var frames:=126 if state=="m4a1" else 81 if state=="pistol" else 26
				for frame in frames:
					actor.body_animator.update_context(1.0/60,context);await process_frame
					if frame in [int(frames*.25),int(frames*.6),frames-1]:
						await RenderingServer.frame_post_draw
						root.get_texture().get_image().save_png(OUT+"%d-%s-action-%d.png"%[variant,state,frame])
				actor.body_animator.cancel_weapon_action()
		actor.queue_free();await process_frame
	print("THIRD PERSON ANATOMY FAILURES ",failures)
	quit(1 if failures else 0)
