extends SceneTree
const OUT:="res://scenes/characters/grip_studies/pistol/"
func _initialize():run.call_deferred()
func run():
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	for entry in [[1,false],[1,true]]:
		var style:int=entry[0];var first:bool=entry[1]
		var model:Node3D=load("res://scenes/characters/visuals/tactical_b/"+("first_person" if first else "body")+".tscn").instantiate();root.add_child(model)
		model.get_node("AnimationTree").active=false
		var sk:Skeleton3D=model.get_node("Skeleton3D")
		for modifier in sk.get_children():
			if modifier is SkeletonModifier3D:modifier.active=false
		var ap:AnimationPlayer=model.get_node("AnimationPlayer");ap.play("PistolIdle" if first else "PistolAim0");ap.advance(0);ap.pause();sk.force_update_all_bone_transforms()
		var author=load("res://tools/authoring/pistol_grip_study_author.gd").new();author.initialize(sk,{"meshes":[]},{})
		author.fp_authoring=first;author.pistol_pose(style,first)
		var sockets:Node3D=sk.get_node("RightHand/Equipment")
		for item in sockets.get_children():if item is Node3D:item.visible=false
		sockets.basis=author.shooting_basis().inverse()
		var gun:Node3D=sockets.get_node("pistol");gun.visible=true;gun.position=-author.RIGHT_GRIP
		gun.get_node("RightHandGrip").position=author.RIGHT_GRIP
		gun.get_node("RightHandGrip").basis=author.shooting_basis()
		for marker in ["LeftHandGrip","SupportHand"]:
			gun.get_node(marker).position=author.support_grip(style)
			gun.get_node(marker).basis=sk.get_bone_global_pose(sk.find_bone("LeftHand")).basis
		var clip:=Animation.new();clip.length=1.0;clip.loop_mode=Animation.LOOP_LINEAR
		for bone in sk.get_bone_count():
			var rt:=clip.add_track(Animation.TYPE_ROTATION_3D);clip.track_set_path(rt,NodePath("Skeleton3D:"+sk.get_bone_name(bone)));clip.rotation_track_insert_key(rt,0,sk.get_bone_pose_rotation(bone))
			var pt:=clip.add_track(Animation.TYPE_POSITION_3D);clip.track_set_path(pt,NodePath("Skeleton3D:"+sk.get_bone_name(bone)));clip.position_track_insert_key(pt,0,sk.get_bone_pose_position(bone))
		var library:=AnimationLibrary.new();library.add_animation("Grip",clip)
		for key in ap.get_animation_library_list():ap.remove_animation_library(key)
		ap.add_animation_library("",library);ap.play("Grip");ap.advance(0)
		var packed:=PackedScene.new();assert(packed.pack(model)==OK)
		assert(ResourceSaver.save(packed,OUT+("fp_" if first else "")+("a" if style==0 else "b")+".tscn")==OK)
		print("SAVED STUDY ",style," FP ",first)
		for side in ["Right","Left"]:
			var desired:Basis=author.shooting_basis() if side=="Right" else author.palm_basis("Left",Vector3(0,.38,-.925),Vector3.RIGHT)
			var actual:Basis=sk.get_bone_global_pose(sk.find_bone(side+"Hand")).basis
			print(side," grip orientation deviation ",rad_to_deg((actual*desired.inverse()).get_rotation_quaternion().get_angle()))
		model.queue_free();await process_frame
	quit()
