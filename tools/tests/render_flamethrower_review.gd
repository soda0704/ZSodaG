extends SceneTree
func _initialize() -> void: run.call_deferred()
var failures:=0
func record_pose(sk: Skeleton3D) -> void:
	var sockets: Node3D=sk.get_node("RightHand/Equipment")
	var gun: Node3D=sockets.get_node("flamethrower")
	var right:=sk.get_bone_global_pose(sk.find_bone("RightHand"))
	var left:=sk.get_bone_global_pose(sk.find_bone("LeftHand"))
	var weapon:=right*sockets.transform*gun.transform
	var grip: Transform3D=weapon*gun.get_node("LeftHandGrip").transform
	var rest:=sk.get_bone_global_rest(sk.find_bone("LeftHand"))
	var distal: Vector3=(sk.get_bone_global_rest(sk.find_bone("LeftHandMiddle1")).origin-rest.origin).normalized()
	var across: Vector3=sk.get_bone_global_rest(sk.find_bone("LeftHandPinky1")).origin-sk.get_bone_global_rest(sk.find_bone("LeftHandIndex1")).origin
	across=(across-distal*across.dot(distal)).normalized()
	var palm:=left.basis*rest.basis.inverse()*Basis(across,distal,across.cross(distal)).orthonormalized()
	sk.set_meta("review_pose",{"left_error":left.origin.distance_to(grip.origin),"angle_error":rad_to_deg(left.basis.get_rotation_quaternion().angle_to(grip.basis.get_rotation_quaternion())),"right_error":right.origin.distance_to(weapon*gun.get_node("RightHandGrip").position),"direction":-weapon.basis.z.normalized(),"palm_up":palm.z.normalized().dot(weapon.basis.y.normalized())})
func run() -> void:
	root.get_node("GameMenu").force_close_menu()
	Engine.max_fps=60;root.size=Vector2i(1280,900)
	var world: Node3D=load("res://tools/tests/fixtures/character_test_arena.tscn").instantiate();root.add_child(world);current_scene=world
	world.get_node("Environment").environment.ambient_light_energy=1.1
	var review: Camera3D=world.get_node("ReviewCamera");review.projection=Camera3D.PROJECTION_ORTHOGONAL;review.size=1.0;review.near=.01
	for variant in [0,1]:
		var actor: GamePlayer=load("res://scenes/characters/player.tscn").instantiate();actor.name="1";actor.setup(1,"",Vector3(0,.05,0),Color.WHITE,0,variant);world.get_node("Players").add_child(actor)
		actor.set_physics_process(false);actor.survival.set_physics_process(false);actor.set_process_unhandled_input(false)
		actor.pickup_world_item_authoritative(&"flamethrower",{})
		for rig in [actor.body_animator.model,actor.body_animator.first_person.model]:
			var sk: Skeleton3D=rig.get_node("Skeleton3D")
			sk.skeleton_updated.connect(record_pose.bind(sk))
		for view in ["first_person","right","left"]:
			actor.body_animator.set_external_view(view!="first_person")
			if view=="first_person":actor.camera.current=true
			else:
				review.current=true;review.position=Vector3(1.1 if view=="right" else -1.1,1.6,-.45);review.look_at(Vector3(.05,1.4,-.26))
			for frame in 40:
				actor.body_animator.update_context(.016,{"held_item":&"flamethrower","grounded":true,"velocity":Vector3.ZERO,"yaw":0.0,"pitch":0.0})
				await process_frame
			var rig: Node3D=actor.body_animator.model if view!="first_person" else actor.body_animator.first_person.model
			var pose: Dictionary=rig.get_node("Skeleton3D").get_meta("review_pose",{})
			print("FINAL_POSE ",variant," ",view," ",pose)
			if pose.is_empty() or absf(pose.direction.y)>.08 or pose.left_error>.025 or pose.right_error>.002 or pose.angle_error>5 or pose.palm_up<.8:
				failures+=1
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(OS.get_environment("TEMP").path_join("NorthernLab-flamethrower-"+str(variant)+"-"+view+".png"))
		for scenario in [
			{"label":"look_down","pitch":-.5},
			{"label":"look_up","pitch":.5},
			{"label":"crouch","crouching":true},
			{"label":"run","velocity":Vector3(0,0,-6)},
			{"label":"rifle","held_item":&"m4a1"},
			{"label":"journal","journal_phase":2}]:
			var context: Dictionary={"held_item":&"flamethrower","grounded":true,"velocity":Vector3.ZERO,"yaw":0.0,"pitch":0.0}
			context.merge(scenario,true)
			for frame in 50:
				actor.body_animator.update_context(.016,context)
				await process_frame
			for rig in [actor.body_animator.model,actor.body_animator.first_person.model]:
				var sk: Skeleton3D=rig.get_node("Skeleton3D")
				var pose: Dictionary=sk.get_meta("review_pose",{})
				var wrist: CopyTransformModifier3D=sk.get_node("FlamethrowerWrist")
				var holding: bool=context.held_item==&"flamethrower" and int(context.get("journal_phase",0))==0
				var valid: bool=(pose.left_error<.03 and pose.angle_error<3 and pose.palm_up>.8) if holding else wrist.influence<.01
				print("POSE_SCENARIO ",variant," ",scenario.label," ","FP" if rig==actor.body_animator.first_person.model else "BODY"," ",valid," ",pose)
				if not valid:failures+=1
		actor.queue_free();await process_frame
	world.queue_free();await process_frame;print("POSE_REVIEW_FAILURES ",failures);quit(1 if failures else 0)
