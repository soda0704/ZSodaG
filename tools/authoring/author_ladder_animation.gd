extends SceneTree
## Bake original character rigs into native clips/graphs, with no runtime bone solver.
func _initialize() -> void: run.call_deferred()
func run() -> void:
	DirAccess.make_dir_recursive_absolute("res://assets/animations/ladder")
	for variant in ["a","b"]:
		for fp in [false,true]:
			var label := "%s_%s" % [variant,"fp" if fp else "body"]
			var path := "res://scenes/characters/visuals/tactical_%s/%s.tscn" % [variant,"first_person" if fp else "body"]
			var model: Node3D=load(path).instantiate(); root.add_child(model)
			var tree: AnimationTree=model.get_node("AnimationTree"); tree.active=false
			var sk: Skeleton3D=model.get_node("Skeleton3D")
			for modifier in sk.get_children():
				if modifier is SkeletonModifier3D: modifier.active=false
			var ap: AnimationPlayer=model.get_node("AnimationPlayer")
			ap.play("RelaxedIdle" if fp else "Idle"); ap.advance(0); ap.pause()
			var positions: Array[Vector3]=[]; var rotations: Array[Quaternion]=[]
			for bone in sk.get_bone_count(): positions.append(sk.get_bone_pose_position(bone)); rotations.append(sk.get_bone_pose_rotation(bone))
			var helper=load("res://tools/authoring/character_animation_author.gd").new()
			helper.initialize(sk,{"meshes":[]},{})
			var clip := Animation.new(); clip.length=1; clip.loop_mode=Animation.LOOP_LINEAR
			for bone in sk.get_bone_count():
				var track := clip.add_track(Animation.TYPE_ROTATION_3D); clip.track_set_path(track,NodePath("Skeleton3D:"+sk.get_bone_name(bone)))
			for frame in 31:
				for bone in sk.get_bone_count(): sk.set_bone_pose_position(bone,positions[bone]); sk.set_bone_pose_rotation(bone,rotations[bone])
				for side in ["Left","Right"]:
					var offset := 0.0 if side=="Left" else .5
					var phase := fposmod(float(frame)/30+offset,1.0)
					# Grip descends relative to ascending body, then reaches the next rung.
					var cycle := 1.8-phase*.6 if phase<.5 else lerpf(1.5,1.8,smoothstep(.5,1.0,phase))
					var sign_value := -1.0 if side=="Left" else 1.0
					var clearance := sin((phase-.5)*TAU)*.12 if phase>.5 else 0.0
					helper.arm(side,Vector3(sign_value*.18,cycle,-.37+clearance),0,true)
					if not fp: helper.foot(side,Vector3(sign_value*.15,cycle-1.5,-.27+clearance),-.15)
					helper.fingers(.65)
				for bone in sk.get_bone_count(): clip.track_insert_key(bone,float(frame)/30,sk.get_bone_pose_rotation(bone))
			var library := AnimationLibrary.new(); library.add_animation(&"Climb",clip)
			assert(ResourceSaver.save(library,"res://assets/animations/ladder/%s_library.res"%label,ResourceSaver.FLAG_COMPRESS)==OK)
			var graph: AnimationNodeBlendTree=tree.tree_root.duplicate(true)
			if not graph.has_node("LadderBlend"):
				var links: Array=graph.get("node_connections"); var previous: StringName
				for i in range(0,links.size(),3):
					if str(links[i])=="output": previous=links[i+2]
				var animation := AnimationNodeAnimation.new(); animation.animation=&"ladder/Climb"
				graph.add_node("LadderClip",animation)
				graph.add_node("LadderTime",AnimationNodeTimeSeek.new()); graph.connect_node("LadderTime",0,"LadderClip")
				graph.disconnect_node("output",0)
				graph.add_node("LadderBlend",AnimationNodeBlend2.new()); graph.connect_node("LadderBlend",0,previous); graph.connect_node("LadderBlend",1,"LadderTime")
				graph.connect_node("output",0,"LadderBlend")
			assert(ResourceSaver.save(graph,"res://assets/animations/ladder/%s_graph.res"%label,ResourceSaver.FLAG_COMPRESS)==OK)
			model.queue_free(); await process_frame
	print("LADDER ANIMATIONS AUTHORED"); quit()
