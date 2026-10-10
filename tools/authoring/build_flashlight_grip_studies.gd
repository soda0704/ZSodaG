extends SceneTree
const OUT:="res://scenes/characters/grip_studies/flashlight/"
func _initialize():run.call_deferred()
func run():
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	for entry in [[0,false],[0,true]]:
		var style:int=entry[0];var first:bool=entry[1]
		var model:Node3D=load("res://scenes/characters/visuals/tactical_b/"+("first_person" if first else "body")+".tscn").instantiate();root.add_child(model)
		model.get_node("AnimationTree").active=false
		var sk:Skeleton3D=model.get_node("Skeleton3D")
		for modifier in sk.get_children():
			if modifier is SkeletonModifier3D:modifier.active=false
		var ap:AnimationPlayer=model.get_node("AnimationPlayer");ap.play("FlashlightIdle" if first else "FlashlightAim0");ap.advance(0);ap.pause();sk.force_update_all_bone_transforms()
		var author=load("res://tools/authoring/flashlight_grip_study_author.gd").new();author.initialize(sk,{"meshes":[]},{})
		author.fp_authoring=first;author.flashlight_pose(first)
		if not first:rigid_elbow_shells(model,sk)
		var sockets:Node3D=sk.get_node("RightHand/Equipment")
		for item in sockets.get_children():if item is Node3D:item.visible=false
		sockets.basis=sk.get_bone_global_pose(sk.find_bone("RightHand")).basis.inverse()
		print("FLASH hand deviation ",rad_to_deg((sk.get_bone_global_pose(sk.find_bone("RightHand")).basis*author.flashlight_hand_basis().inverse()).get_rotation_quaternion().get_angle()))
		var gun:Node3D=load("res://scenes/objects/equipment/flashlight_model.tscn").instantiate();gun.name="FlashlightStudy";sockets.add_child(gun);gun.owner=model
		gun.basis=author.flashlight_item_basis();gun.position=-(author.flashlight_item_basis()*author.FLASHLIGHT_RIGHT_GRIP)
		for child in gun.get_children():
			child.owner=model
			if child is MeshInstance3D:child.layers=1<<19 if first else 1|(1<<18)
		gun.get_node("Grip").position=author.FLASHLIGHT_RIGHT_GRIP
		gun.get_node("Grip").basis=author.flashlight_item_basis().inverse()*author.flashlight_hand_basis()
		var beam:=SpotLight3D.new();beam.name="Beam";gun.add_child(beam);beam.owner=model;beam.position=Vector3(0,0,-.166);beam.light_energy=2.6;beam.light_color=Color(1,.92,.8);beam.spot_range=10.5;beam.spot_angle=19;beam.light_cull_mask=1;beam.visible=false
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
		model.queue_free();await process_frame
	quit()

func rigid_elbow_shells(model:Node3D,sk:Skeleton3D)->void:
	var body:MeshInstance3D=model.get_node("Skeleton3D/Body")
	var original:=body.mesh;var rebuilt:=ArrayMesh.new()
	for surface in original.get_surface_count():
		var arrays:=original.surface_get_arrays(surface).duplicate(true)
		var ids:PackedInt32Array=arrays[Mesh.ARRAY_BONES];var weights:PackedFloat32Array=arrays[Mesh.ARRAY_WEIGHTS]
		var shell:=false
		for slot in ids.size():
			if weights[slot]>.01 and "Elbow_Pads" in sk.get_bone_name(ids[slot]):shell=true;break
		if shell:
			var vertices:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
			for vertex in vertices.size():
				var pad:=sk.find_bone(("Left" if vertices[vertex].x<0 else "Right")+"_Elbow_Pads")
				var pad_weight:=0.0
				for slot in 4:
					if ids[vertex*4+slot]==pad:pad_weight+=weights[vertex*4+slot]
				if pad_weight<.8:continue
				for slot in 4:ids[vertex*4+slot]=pad;weights[vertex*4+slot]=1.0 if slot==0 else 0.0
			arrays[Mesh.ARRAY_BONES]=ids;arrays[Mesh.ARRAY_WEIGHTS]=weights
			print("RIGID ELBOW SHELL surface ",surface," vertices ",vertices.size())
		rebuilt.add_surface_from_arrays(original.surface_get_primitive_type(surface),arrays)
		rebuilt.surface_set_material(surface,original.surface_get_material(surface))
	body.mesh=rebuilt

