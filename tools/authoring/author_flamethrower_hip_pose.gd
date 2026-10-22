extends SceneTree
## Offline rig authoring. Saves ordinary Animation clips; no runtime bone solving is added.
const OUT:="res://assets/animations/flamethrower/"
func _initialize() -> void:run.call_deferred()
func arm_bone(label: String) -> bool:
	return label in ["LeftArm","RightArm","LeftForeArm","RightForeArm","LeftHand","RightHand"] or label.begins_with("LeftHand") or label.begins_with("RightHand") or "Elbow_Pads" in label
func sync_native_transform(path: String, section: String, transform: Transform3D) -> void:
	# Keep the native modifier-cycle target in sync with the editor-authored item grip.
	var source:=FileAccess.get_file_as_string(path)
	var at:=source.find(section)
	if at<0:return
	at=source.find("transform = ",at)
	var end:=source.find("\n",at)
	var updated:=source.substr(0,at)+"transform = "+var_to_str(transform)+source.substr(end)
	if updated!=source:
		var file:=FileAccess.open(path,FileAccess.WRITE);file.store_string(updated)
func run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	for variant in ["a","b"]:
		for fp in [false,true]:
			var path: String="res://scenes/characters/visuals/tactical_%s/%s.tscn" % [variant,"first_person" if fp else "body"]
			var model: Node3D=load(path).instantiate();root.add_child(model)
			var tree: AnimationTree=model.get_node("AnimationTree");tree.active=false
			var sk: Skeleton3D=model.get_node("Skeleton3D")
			for node in sk.get_children():
				if node is SkeletonModifier3D:node.active=false
			var ap: AnimationPlayer=model.get_node("AnimationPlayer")
			ap.play("RifleIdle" if fp else "RifleAim0");ap.advance(0);ap.pause();sk.force_update_all_bone_transforms()
			var helper=load("res://tools/authoring/rifle_grip_study_author.gd").new();helper.initialize(sk,{"meshes":[]},{})
			var library:=AnimationLibrary.new()
			var blend:=AnimationNodeBlendSpace1D.new();blend.min_space=-.62;blend.max_space=.62
			for point in ([0] if fp else [-1,0,1]):
				var source_name: String="RifleIdle" if fp else "RifleAim"+str(point)
				ap.play(source_name);ap.advance(0);ap.pause();sk.force_update_all_bone_transforms()
				var originals: Dictionary={}
				for bone in sk.get_bone_count():originals[bone]=sk.get_bone_pose_rotation(bone)
				var turn:=Basis(Vector3.RIGHT,float(point)*.62)
				var pivot:=Vector3(0,1.10,0)
				var resting_wrist:=Vector3(.23,1.16,-.06) if fp else Vector3(.21,1.10,-.015)
				var at:=pivot+turn*(resting_wrist-pivot)
				if not fp:at+=Vector3(0,.20,.08)*maxf(0,-point)
				var sockets: Node3D=sk.get_node("RightHand/Equipment")
				var gun_node: Node3D=sockets.get_node("flamethrower")
				gun_node.position=-(gun_node.basis*gun_node.get_node("RightHandGrip").position)
				# Fit a level barrel first; solve the wrist around its authored attachment.
				var desired_hand:=turn*Basis(Vector3.UP,.06)*(sockets.basis*gun_node.basis).inverse()
				helper.fit_rifle_arm("Right",at,desired_hand)
				# Keep the baked barrel level after the generic rifle wrist limiter.
				var hand_id:=sk.find_bone("RightHand")
				var parent_basis:=sk.get_bone_global_pose(sk.get_bone_parent(hand_id)).basis
				sk.set_bone_pose_rotation(hand_id,(parent_basis.inverse()*desired_hand).orthonormalized().get_rotation_quaternion())
				sk.force_update_all_bone_transforms()
				var grip: Node3D=sockets.get_node("flamethrower/LeftHandGrip")
				var gun: Node3D=sockets.get_node("flamethrower")
				var left: Vector3=(sk.get_bone_global_pose(sk.find_bone("RightHand"))*sockets.transform*gun.transform*grip.transform).origin
				var support_basis: Basis=(sk.get_bone_global_pose(hand_id)*sockets.transform*gun.transform).basis*grip.basis
				helper.support_pole=Vector3(-.38,1.02,.08)
				helper.arm("Left",left,0)
				helper.two_bone("LeftArm","LeftForeArm","LeftHand",left,helper.support_pole)
				var left_id:=sk.find_bone("LeftHand")
				var left_parent:=sk.get_bone_global_pose(sk.get_bone_parent(left_id)).basis
				sk.set_bone_pose_rotation(left_id,(left_parent.inverse()*support_basis).orthonormalized().get_rotation_quaternion())
				sk.force_update_all_bone_transforms()
				for finger in ["Index","Middle","Ring","Pinky"]:
					helper.fit_finger("Left",finger,[45.,72.,48.])
				helper.pose_hand("Right","Rifle_Right")
				var gun_frame: Transform3D=sk.get_bone_global_pose(hand_id)*sockets.transform*gun.transform
				helper.aim_finger("Left","Thumb",[gun_frame*Vector3(-.03,.115,-.31),gun_frame*Vector3(0,.13,-.325),gun_frame*Vector3(.015,.13,-.35)])
				for finger in ["Middle","Ring","Pinky"]:helper.fit_finger("Right",finger,[70.,85.,45.])
				helper.aim_finger("Right","Index",[gun_frame*Vector3(.035,.012,-.025),gun_frame*Vector3(.018,.005,-.058),gun_frame*Vector3(-.008,.005,-.06)])
				helper.aim_finger("Right","Thumb",[gun_frame*Vector3(-.005,.012,.025),gun_frame*Vector3(-.025,.005,0),gun_frame*Vector3(-.028,-.01,-.02)])
				if not fp and variant=="b":helper.seat_elbow_shells()
				var correction: Dictionary={}
				for bone in sk.get_bone_count():
					if arm_bone(sk.get_bone_name(bone)):correction[sk.get_bone_name(bone)]=sk.get_bone_pose_rotation(bone)*originals[bone].inverse()
				var clip: Animation=ap.get_animation(source_name).duplicate(true)
				for track in clip.get_track_count():
					var bone_name:=String(clip.track_get_path(track)).get_slice(":",1)
					if clip.track_get_type(track)!=Animation.TYPE_ROTATION_3D or not correction.has(bone_name):continue
					for key in clip.track_get_key_count(track):clip.track_set_key_value(track,key,(correction[bone_name]*clip.track_get_key_value(track,key)).normalized())
				var label: String="HipIdle" if fp else "HipAim"+str(point)
				library.add_animation(label,clip)
				var animation:=AnimationNodeAnimation.new();animation.animation="flamethrower/"+label
				blend.add_blend_point(animation,float(point)*.62)
				print("HIP_POSE ",variant," FP ",fp," pitch ",point," right ",sk.get_bone_global_pose(sk.find_bone("RightHand")).origin," left_error_mm ",sk.get_bone_global_pose(sk.find_bone("LeftHand")).origin.distance_to(left)*1000)
			var resource_path: String=OUT+variant+("_fp" if fp else "_body")+".res"
			assert(ResourceSaver.save(library,resource_path,ResourceSaver.FLAG_COMPRESS)==OK);library.take_over_path(resource_path)
			if ap.has_animation_library(&"flamethrower"):ap.remove_animation_library(&"flamethrower")
			ap.add_animation_library(&"flamethrower",library)
			var equipment: Node3D=sk.get_node("RightHand/Equipment")
			var item: Node3D=equipment.get_node("flamethrower")
			sync_native_transform(path,'[node name="flamethrower"',item.transform)
			sync_native_transform(path,'[node name="Grip" type="Marker3D" parent="Skeleton3D/FlamethrowerGripTarget"]',equipment.transform*item.transform*item.get_node("LeftHandGrip").transform)
			if tree.tree_root.has_node("Flamethrower"):
				# Subsequent pose iterations replace only the external animation library.
				model.queue_free();await process_frame
				continue
			var graph: AnimationNodeBlendTree=tree.tree_root.duplicate(true);tree.tree_root=graph
			if graph.has_node("Flamethrower"):graph.remove_node("Flamethrower")
			graph.add_node("Flamethrower",blend,Vector2(0,800))
			var transition: AnimationNodeTransition=graph.get_node("Equipment")
			var count: int=transition.get("input_count")
			var slot: int=-1
			for input in count:
				if transition.get("input_%d/name"%input)=="Flamethrower":slot=input
			if slot<0:
				slot=count;transition.set("input_count",count+1);transition.set("input_%d/name"%slot,"Flamethrower")
			graph.connect_node("Equipment",slot,"Flamethrower")
			ap.stop();sk.reset_bone_poses()
			for node in sk.get_children():
				if node is SkeletonModifier3D:node.active=true
			tree.active=true
			var packed:=PackedScene.new();assert(packed.pack(model)==OK);assert(ResourceSaver.save(packed,path)==OK)
			model.queue_free();await process_frame
	print("FLAMETHROWER_HIP_CLIPS_READY");quit()
