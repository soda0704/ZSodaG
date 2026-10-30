extends SceneTree
## Bake both existing rigs and reusable scene clips. No runtime bone solver.
func _initialize() -> void: run.call_deferred()
func snapshot(sk: Skeleton3D) -> Array:
	var pose:=[]
	for bone in sk.get_bone_count(): pose.append([sk.get_bone_pose_position(bone),sk.get_bone_pose_rotation(bone)])
	return pose
func run() -> void:
	DirAccess.make_dir_recursive_absolute("res://assets/animations/bunk")
	for variant in ["a","b"]:
		var path: String="res://scenes/characters/visuals/tactical_%s/body.tscn"%variant
		var model: Node3D=load(path).instantiate();root.add_child(model)
		var tree: AnimationTree=model.get_node("AnimationTree");tree.active=false
		var sk: Skeleton3D=model.get_node("Skeleton3D")
		for modifier in sk.get_children():
			if modifier is SkeletonModifier3D: modifier.active=false
		var ap: AnimationPlayer=model.get_node("AnimationPlayer")
		ap.play("Idle");ap.advance(0);ap.pause()
		var stand:=snapshot(sk)
		ap.play("Sleep");ap.advance(0);ap.pause()
		var lying:=snapshot(sk)
		# Sit on the side before swinging the feet onto the mattress.
		ap.play("Vehicle");ap.advance(0);ap.pause()
		var seated:=snapshot(sk)
		var helper=load("res://tools/authoring/character_animation_author.gd").new();helper.initialize(sk,{"meshes":[]},{})
		for bone in sk.get_bone_count():
			sk.set_bone_pose_position(bone,seated[bone][0]);sk.set_bone_pose_rotation(bone,seated[bone][1])
		helper.global_rotation(0,Basis(Vector3.UP,PI*.5))
		sk.set_bone_pose_position(0,Vector3(.45,-.47,-.50));sk.force_update_all_bone_transforms()
		for side in ["Left","Right"]:
			var sign_value:float=-1.0 if side=="Left" else 1.0
			helper.two_bone(side+"UpLeg",side+"Leg",side+"Foot",Vector3(.98,-.49,-.5+sign_value*.14),Vector3(1.1,.15,-.5+sign_value*.14))
			helper.global_rotation(sk.find_bone(side+"Foot"),Basis(Vector3.UP,-PI*.5)*helper.rests[sk.find_bone(side+"Foot")].basis)
			helper.two_bone(side+"Arm",side+"ForeArm",side+"Hand",Vector3(.46,.12,-.5+sign_value*.32),Vector3(.85,.55,-.5+sign_value*.40))
			helper.global_rotation(sk.find_bone(side+"Hand"),Basis(Quaternion(Vector3.DOWN,Vector3.RIGHT))*helper.hand_basis(side,0,false))
		helper.fingers(.12)
		seated=snapshot(sk)
		var clip:=Animation.new();clip.length=2.5
		for bone in sk.get_bone_count():
			for type in [Animation.TYPE_POSITION_3D,Animation.TYPE_ROTATION_3D]:
				var track:=clip.add_track(type);clip.track_set_path(track,NodePath("Skeleton3D:"+sk.get_bone_name(bone)))
				for frame in 76:
					var t:=frame/30.0
					var leg:=0 if t<.48 else 1 if t<1.25 else 2 if t<2.02 else 3
					var poses: Array=[stand,seated,lying,seated,stand]
					var limits: Array=[0.,.48,1.25,2.02,2.5]
					var weight:=smoothstep(limits[leg],limits[leg+1],t)
					var from: Array=poses[leg][bone];var to: Array=poses[leg+1][bone]
					clip.track_insert_key(track,t,from[0].lerp(to[0],weight) if type==Animation.TYPE_POSITION_3D else from[1].slerp(to[1],weight))
		var library:=AnimationLibrary.new();library.add_animation(&"Bed",clip)
		assert(ResourceSaver.save(library,"res://assets/animations/bunk/%s_body_library.res"%variant,ResourceSaver.FLAG_COMPRESS)==OK)
		var graph: AnimationNodeBlendTree=tree.tree_root.duplicate(true)
		if not graph.has_node("BunkBlend"):
			var links: Array=graph.get("node_connections");var previous: StringName
			for i in range(0,links.size(),3):
				if str(links[i])=="output":previous=links[i+2]
			var node:=AnimationNodeAnimation.new();node.animation=&"bunk/Bed"
			graph.add_node("BunkClip",node);graph.add_node("BunkTime",AnimationNodeTimeSeek.new());graph.connect_node("BunkTime",0,"BunkClip")
			graph.disconnect_node("output",0);graph.add_node("BunkBlend",AnimationNodeBlend2.new());graph.connect_node("BunkBlend",0,previous);graph.connect_node("BunkBlend",1,"BunkTime");graph.connect_node("output",0,"BunkBlend")
		assert(ResourceSaver.save(graph,"res://assets/animations/bunk/%s_body_graph.res"%variant,ResourceSaver.FLAG_COMPRESS)==OK)
		# Change only resource references; preserve the authored scene and all other clips.
		var text:=FileAccess.get_file_as_string(path)
		if not text.contains('id="bunk_library"'):
			var anchor:='[sub_resource '
			var at:=text.find(anchor);assert(at>=0)
			text=text.insert(at,'[ext_resource type="AnimationLibrary" path="res://assets/animations/bunk/%s_body_library.res" id="bunk_library"]\n[ext_resource type="AnimationNodeBlendTree" path="res://assets/animations/bunk/%s_body_graph.res" id="bunk_graph"]\n\n'%[variant,variant])
			text=text.replace('libraries/ladder = ExtResource("ladder_library")','libraries/ladder = ExtResource("ladder_library")\nlibraries/bunk = ExtResource("bunk_library")')
		text=text.replace('tree_root = ExtResource("ladder_graph")','tree_root = ExtResource("bunk_graph")')
		var file:=FileAccess.open(path,FileAccess.WRITE);file.store_string(text);file.close()
		model.queue_free();await process_frame
	print("BUNK ANIMATIONS AUTHORED");quit()
