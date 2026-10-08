extends SceneTree
## Offline import repair and native asset authoring. No runtime bone animation.

const OUT := "res://scenes/characters/visuals/"
const TURN := Basis(Vector3.UP, PI)
const AnimationAuthor := preload("res://tools/authoring/character_animation_author.gd")
var sources: Dictionary = {}
var models: Dictionary = {}

func _initialize() -> void:
	run.call_deferred()

func bone_name(original: String) -> String:
	if original == "_rootJoint": return "Root"
	var expression := RegEx.new()
	expression.compile("_[0-9]+$")
	return expression.sub(original.trim_prefix("mixamorig_"), "")

func own(node: Node, parent: Node, scene: Node, label: String) -> void:
	parent.add_child(node)
	node.name = label
	node.owner = scene

func load_source(id: String) -> Dictionary:
	var instance: Node3D = load("res://assets/characters/tactical_%s/scene.gltf" % id).instantiate()
	root.add_child(instance)
	var rig: Skeleton3D = instance.find_children("*", "Skeleton3D", true, false)[0]
	var meshes: Array = instance.find_children("*", "MeshInstance3D", true, false).filter(func(mesh): return mesh.skin != null)
	var skin: Skin = meshes[0].skin
	var bind_by_bone: Dictionary = {}
	for i in skin.get_bind_count():
		bind_by_bone[rig.find_bone(skin.get_bind_name(i))] = skin.get_bind_pose(i).affine_inverse()
	var head_index := rig.find_bone("mixamorig_Head_06")
	var unit_scale: float = 1.60 / bind_by_bone[head_index].origin.y
	var normalization := Transform3D(TURN.scaled(Vector3.ONE * unit_scale), Vector3.ZERO)
	var reference := -1
	for bone in bind_by_bone:
		if bone_name(rig.get_bone_name(bone))=="LeftHandMiddle3": reference = bone
	var reference_parent := rig.get_bone_parent(reference)
	var local_scale: float = bind_by_bone[reference].origin.distance_to(bind_by_bone[reference_parent].origin)*unit_scale/maxf(rig.get_bone_rest(reference).origin.length(),0.00001)
	var rests: Array[Transform3D] = []
	var names: Array[String] = []
	for i in rig.get_bone_count():
		var transform: Transform3D
		var parent := rig.get_bone_parent(i)
		var invalid_terminal: bool = bind_by_bone.has(i) and i>1 and parent>=0 and bind_by_bone[i].origin.length()<0.00001
		if invalid_terminal:
			var previous := rig.get_bone_parent(parent)
			transform = rests[parent]
			if previous>=0: transform.origin += (rests[parent].origin-rests[previous].origin)*0.6
		elif bind_by_bone.has(i):
			transform = normalization * bind_by_bone[i]
		else:
			# Unweighted terminal joints are absent from inverse binds. Their
			# authored local rest must follow the parent, never become identity.
			var local := rig.get_bone_rest(i)
			local.origin *= local_scale
			transform = rests[parent]*local if parent>=0 else Transform3D.IDENTITY
		transform.basis = transform.basis.orthonormalized()
		rests.append(transform)
		names.append(bone_name(rig.get_bone_name(i)))
	var animation_player: AnimationPlayer = instance.find_children("*", "AnimationPlayer", true, false)[0]
	return {"instance": instance, "rig": rig, "meshes": meshes, "skin": skin, "normalization": normalization, "rests": rests, "names": names, "player": animation_player, "clip": animation_player.get_animation(animation_player.get_animation_list()[0])}

func make_rig(source: Dictionary, scene: Node3D) -> Skeleton3D:
	var rig := Skeleton3D.new()
	own(rig, scene, scene, "Skeleton3D")
	for name in source.names: rig.add_bone(name)
	for i in source.names.size():
		var parent: int = source.rig.get_bone_parent(i)
		rig.set_bone_parent(i, parent)
		rig.set_bone_rest(i, source.rests[parent].affine_inverse() * source.rests[i] if parent >= 0 else source.rests[i])
	rig.reset_bone_poses()
	return rig

func native_skin(rig: Skeleton3D) -> Skin:
	var skin := Skin.new()
	for i in rig.get_bone_count(): skin.add_bind(i, rig.get_bone_global_rest(i).affine_inverse())
	return skin

func repair_accessory(arrays: Array, label: String, source: Dictionary) -> void:
	# The Sketchfab A export contains a detached head/visor and a glove object
	# in an unrelated object space. The source archives remain untouched.
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var bounds := AABB(vertices[0], Vector3.ZERO)
	for vertex in vertices: bounds = bounds.expand(vertex)
	var target := bounds.get_center()
	var scale_factor := 1.0
	if source == sources.a:
		if label == "Head":
			target = Vector3(0, 1.67, -0.015)
			scale_factor = 0.235 / bounds.size.y
		elif label == "Material.001": target = Vector3(0,1.745,-0.015)
		elif label == "material": target = Vector3(0, 1.69, -0.105)
	else:
		if label == "GreenCap": target = Vector3(0, 1.79, 0.015)
		elif label == "HeadphonesT":
			target = Vector3(0,1.70,0.012)
			scale_factor = 0.26/bounds.size.y
	for i in vertices.size(): vertices[i] = (vertices[i] - bounds.get_center()) * scale_factor + target
	arrays[Mesh.ARRAY_VERTEX] = vertices

func arrays_for(mesh: MeshInstance3D, surface: int, source: Dictionary, target: Dictionary) -> Array:
	var arrays := mesh.mesh.surface_get_arrays(surface).duplicate(true)
	# Imported glTF auxiliary float channels are unused by StandardMaterial3D.
	for channel in range(Mesh.ARRAY_CUSTOM0, Mesh.ARRAY_CUSTOM3 + 1): arrays[channel] = null
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var bone_ids: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var tangents: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT]
	for i in vertices.size():
		vertices[i] = source.normalization * vertices[i]
		if normals.size() > i: normals[i] = (TURN * normals[i]).normalized()
		if tangents.size() > i * 4:
			var tangent := TURN * Vector3(tangents[i*4], tangents[i*4+1], tangents[i*4+2])
			tangents[i*4] = tangent.x; tangents[i*4+1] = tangent.y; tangents[i*4+2] = tangent.z
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TANGENT] = tangents
	if source == target:
		for slot in bone_ids.size(): bone_ids[slot] = source.rig.find_bone(mesh.skin.get_bind_name(bone_ids[slot]))
		arrays[Mesh.ARRAY_BONES] = bone_ids
		repair_accessory(arrays, mesh.get_active_material(surface).resource_name, source)
	else:
		# Transfer the second supplied model's intact articulated gloves to A.
		# Bone names, proportions and all finger weights are retained.
		for i in vertices.size():
			var point := Vector3.ZERO
			var normal := Vector3.ZERO
			for slot in 4:
				var at := i*4+slot
				var original: int = source.rig.find_bone(mesh.skin.get_bind_name(bone_ids[at]))
				var mapped: int = target.names.find(source.names[original])
				while mapped < 0 and original > 0:
					original = source.rig.get_bone_parent(original)
					mapped = target.names.find(source.names[original])
				mapped = maxi(mapped, 0)
				var transfer: Transform3D = target.rests[mapped] * source.rests[original].affine_inverse()
				point += transfer * vertices[i] * weights[at]
				normal += transfer.basis * normals[i] * weights[at]
				bone_ids[at] = mapped
			vertices[i] = point
			normals[i] = normal.normalized()
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_BONES] = bone_ids
	return arrays

func save_meshes(id: String, rig: Skeleton3D, scene: Node3D) -> void:
	var source: Dictionary = sources[id]
	var full := ArrayMesh.new()
	var arms := ArrayMesh.new()
	var view_arms := ArrayMesh.new()
	var parts: Array = source.meshes.duplicate()
	if id == "a":
		parts = parts.filter(func(part): return part.get_active_material(0).resource_name != "gloves")
		parts.append(sources.b.meshes.filter(func(part): return String(part.name) == "Object_115")[0])
	for part: MeshInstance3D in parts:
		var input: Dictionary = sources.b if id == "a" and String(part.name) == "Object_115" else source
		for surface in part.mesh.get_surface_count():
			var arrays := arrays_for(part, surface, input, source)
			var material := part.get_active_material(surface).duplicate() as StandardMaterial3D
			if material.resource_name=="Material.001":
				material.albedo_color = Color(0.075,0.075,0.078)
				material.metallic = 0.05
				material.roughness = 0.72
			material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
			material_path(material, id, String(part.name) + "_%d" % surface)
			full.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			full.surface_set_material(full.get_surface_count()-1, material)
			var arm_arrays := arrays.duplicate(true)
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			var arm_indices := PackedInt32Array()
			var view_indices := PackedInt32Array()
			for triangle in range(0, indices.size(), 3):
				var arm_triangle := true
				var view_triangle := true
				for corner in 3:
					var v := indices[triangle+corner]
					var arm_weight := 0.0
					var right_weight := 0.0
					for slot in 4:
						var name: String = source.names[arrays[Mesh.ARRAY_BONES][v*4+slot]]
						if "Arm" in name or "Hand" in name or "Shoulder" in name or "Elbow" in name:
							arm_weight += arrays[Mesh.ARRAY_WEIGHTS][v*4+slot]
							if name.begins_with("Right"): right_weight += arrays[Mesh.ARRAY_WEIGHTS][v*4+slot]
					arm_triangle = arm_triangle and arm_weight > 0.48
					# Keep sleeves and gloves; the deltoid/shoulder belongs to the
					# world body, not the camera rig. Journal arms remain complete.
					var side := "Right" if right_weight > arm_weight*0.5 else "Left"
					var shoulder: Vector3 = source.rests[source.names.find(side+"Arm")].origin
					var elbow: Vector3 = source.rests[source.names.find(side+"ForeArm")].origin
					var upper_arm := elbow-shoulder
					var along: float = (arrays[Mesh.ARRAY_VERTEX][v]-shoulder).dot(upper_arm.normalized())
					view_triangle = view_triangle and along > upper_arm.length()*0.30
				if arm_triangle:
					for corner in 3: arm_indices.append(indices[triangle+corner])
					if view_triangle:
						for corner in 3: view_indices.append(indices[triangle+corner])
			if not arm_indices.is_empty():
				arm_arrays[Mesh.ARRAY_INDEX] = arm_indices
				arms.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arm_arrays)
				arms.surface_set_material(arms.get_surface_count()-1, material)
			if not view_indices.is_empty():
				var view_arrays := arrays.duplicate(true)
				view_arrays[Mesh.ARRAY_INDEX] = view_indices
				view_arms.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,view_arrays)
				view_arms.surface_set_material(view_arms.get_surface_count()-1,material)
	var directory := OUT + "tactical_" + id + "/"
	var lod_mesh := ImporterMesh.new()
	for surface in full.get_surface_count():
		lod_mesh.add_surface(Mesh.PRIMITIVE_TRIANGLES,full.surface_get_arrays(surface),[],{},full.surface_get_material(surface))
	lod_mesh.generate_lods(25.0,60.0,[])
	full = lod_mesh.get_mesh()
	assert(ResourceSaver.save(full, directory + "body.res") == OK)
	assert(ResourceSaver.save(arms, directory + "arms.res") == OK)
	assert(ResourceSaver.save(view_arms, directory + "view_arms.res") == OK)
	full.take_over_path(directory+"body.res")
	arms.take_over_path(directory+"arms.res")
	view_arms.take_over_path(directory+"view_arms.res")
	var visual := MeshInstance3D.new()
	visual.mesh = load(directory + "body.res")
	visual.skin = native_skin(rig)
	visual.skeleton = NodePath("..")
	visual.extra_cull_margin = 0.45
	own(visual, rig, scene, "Body")

func material_path(material: Material, id: String, label: String) -> void:
	var path := OUT + "tactical_" + id + "/materials/" + label + ".tres"
	assert(ResourceSaver.save(material, path) == OK)
	material.take_over_path(path)

func save_scene(scene: Node3D, path: String) -> void:
	var packed := PackedScene.new()
	assert(packed.pack(scene) == OK)
	assert(ResourceSaver.save(packed, path) == OK)

func equipment(rig: Skeleton3D, scene: Node3D, author: RefCounted, first_person: bool = false) -> void:
	var hand := BoneAttachment3D.new()
	hand.bone_name = "RightHand"
	own(hand,rig,scene,"RightHand")
	var equipment_root := Node3D.new()
	equipment_root.transform = Transform3D(author.hand_basis("Right",0.0,true).inverse(),Vector3.ZERO)
	own(equipment_root,hand,scene,"Equipment")
	for kind in ["pistol","m4a1","kitchen_knife"]:
		var model_path := "res://scenes/objects/items/%s_model.tscn"%kind if kind in ["pistol","m4a1"] else "res://assets/models/weapons/%s.glb"%kind
		var model: Node3D = load(model_path).instantiate()
		own(model,equipment_root,scene,kind)
		# Preserve the source ownership: edited meshes are inherited overrides,
		# not replacement nodes that would orphan the source children on load.
		scene.set_editable_instance(model,true)
		model.position = Vector3(0,-0.025,-0.065)
		model.visible = false
		for mesh in model.find_children("*","MeshInstance3D",true,false):
			mesh.layers = (1<<19) if first_person else 1|(1<<18)
			mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if first_person else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		var support := Marker3D.new()
		support.position = Vector3(-0.12,-0.045,-0.12) if kind=="m4a1" else Vector3(-0.045,-0.065,0.005)
		support.basis = author.hand_basis("Left",0,true)
		own(support,model,scene,"SupportHand")
	var lamp: Node3D = load("res://scenes/objects/equipment/mounted_flashlight.tscn").instantiate()
	own(lamp,equipment_root,scene,"MountedLamp")
	scene.set_editable_instance(lamp,true)
	scene.set_editable_instance(lamp.get_node("Model"),true)
	lamp.position = Vector3(0.053,-0.015,-0.225)
	for mesh: MeshInstance3D in lamp.find_children("*","MeshInstance3D",true,false):
		mesh.layers = (1<<19) if first_person else 1|(1<<18)
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if first_person else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	lamp.visible = false
	var muzzle := OmniLight3D.new()
	own(muzzle,equipment_root,scene,"MuzzleFlash")
	muzzle.position = Vector3(0,0.06,-0.55)
	muzzle.light_color = Color(1,0.65,0.22)
	muzzle.light_energy = 3
	muzzle.omni_range = 5
	muzzle.visible = false
	for label in ["FlashlightGrip","FuseGrip","FuelGrip"]:
		var marker := Marker3D.new()
		marker.position = Vector3(0,-0.065,0.16) if label=="FlashlightGrip" else Vector3(0,-0.293,0) if label=="FuelGrip" else Vector3(0,-0.055,-0.065)
		if label=="FuseGrip": marker.rotation.z = PI*0.5
		marker.scale = Vector3.ONE * (0.72 if label=="FuelGrip" else 1.0)
		own(marker,equipment_root,scene,label)
	var journal: Node3D = load("res://scenes/ui/journal/book/articulated_journal.tscn").instantiate()
	own(journal,equipment_root,scene,"Journal")
	journal.position = Vector3(-0.10,-0.025,-0.02)
	journal.rotation.x = -0.85
	journal.visible = false
	for mesh in journal.find_children("*","MeshInstance3D",true,false):
		mesh.layers = (1<<19) if first_person else 1|(1<<18)
	var left_ik := TwoBoneIK3D.new()
	left_ik.set_setting_count(1)
	left_ik.set_root_bone_name(0,"LeftArm")
	left_ik.set_middle_bone_name(0,"LeftForeArm")
	left_ik.set_end_bone_name(0,"LeftHand")
	left_ik.set_pole_direction_vector(0,Vector3(-0.5,-0.5,0.2))
	var pole := Marker3D.new()
	pole.position = Vector3(-0.50,1.02,0.08)
	own(pole,scene,scene,"LeftElbowPole")
	left_ik.active = false
	left_ik.influence = 0.0
	own(left_ik,rig,scene,"SupportHandIK")
	left_ik.set_target_node(0,left_ik.get_path_to(equipment_root.get_node("m4a1/SupportHand")))
	left_ik.set_pole_node(0,left_ik.get_path_to(pole))

func animation_nodes(scene: Node3D, author: RefCounted, library_path: String, first: bool = false) -> void:
	var animation_player := AnimationPlayer.new()
	own(animation_player,scene,scene,"AnimationPlayer")
	animation_player.add_animation_library(&"",load(library_path))
	var animation_tree := AnimationTree.new()
	own(animation_tree,scene,scene,"AnimationTree")
	animation_tree.anim_player = NodePath("../AnimationPlayer")
	animation_tree.tree_root = author.graph(first)
	animation_tree.active = false

func first_person(id: String) -> void:
	var directory := OUT + "tactical_" + id + "/"
	var scene := Node3D.new()
	scene.name = "FirstPersonModel"
	scene.position.y = -1.65
	# Parent camera movement stays interpolated; local animated hands and
	# equipment are sampled together on render frames, without a second lag.
	scene.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	root.add_child(scene)
	var rig := make_rig(sources[id],scene)
	var mesh := MeshInstance3D.new()
	mesh.mesh = load(directory+"view_arms.res")
	mesh.skin = native_skin(rig)
	mesh.skeleton = NodePath("..")
	mesh.layers = 1<<19
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh.extra_cull_margin = 0.45
	own(mesh,rig,scene,"Arms")
	var author := AnimationAuthor.new()
	author.initialize(rig,sources[id],sources)
	var library := author.build(true)
	assert(ResourceSaver.save(library,directory+"first_person_animations.tres") == OK)
	library.take_over_path(directory+"first_person_animations.tres")
	animation_nodes(scene,author,directory+"first_person_animations.tres",true)
	equipment(rig,scene,author,true)
	rig.reset_bone_poses()
	save_scene(scene,directory+"first_person.tscn")
	# The journal viewport shares the same complete arms and actual finger rig.
	scene.get_node("AnimationTree").queue_free()
	scene.get_node("Skeleton3D/RightHand").queue_free()
	scene.get_node("Skeleton3D/SupportHandIK").queue_free()
	await process_frame
	mesh.layers = 1
	mesh.mesh = load(directory+"arms.res")
	var journal_library := AnimationLibrary.new()
	var journal_author := AnimationAuthor.new()
	journal_author.initialize(rig,sources[id],sources)
	var journal_ui := root.get_node("QuestJournal")
	journal_author.add_clip("JournalOpen",1.85,false,func(t): journal_author.journal_view(t,journal_ui))
	journal_author.add_clip("JournalReading",3.0,true,func(t): journal_author.journal_view(1.85,journal_ui))
	journal_author.add_clip("JournalClose",1.85,false,func(t): journal_author.journal_view(1.85-t,journal_ui))
	for name in ["JournalOpen","JournalReading","JournalClose"]:
		var animation: Animation = journal_author.library.get_animation(name).duplicate(true)
		for track in range(animation.get_track_count()-1,-1,-1):
			if not String(animation.track_get_path(track)).begins_with("Skeleton3D:"): animation.remove_track(track)
		journal_library.add_animation(name,animation)
	assert(ResourceSaver.save(journal_library,directory+"journal_animations.tres") == OK)
	journal_library.take_over_path(directory+"journal_animations.tres")
	var journal_player: AnimationPlayer = scene.get_node("AnimationPlayer")
	journal_player.remove_animation_library(&"")
	journal_player.add_animation_library(&"",journal_library)
	save_scene(scene,directory+"journal_arms.tscn")
	scene.queue_free()

func migrate_journal_arms() -> void:
	var journal := root.get_node("QuestJournal")
	var world: Node3D = journal.get_node("JournalRoot/ModelViewport/SubViewport/World")
	var hands: Node3D = world.get_node_or_null("Hands")
	if hands==null:
		hands = Node3D.new()
		world.add_child(hands)
		hands.name = "Hands"
	hands.owner = journal
	for child in hands.get_children(): child.queue_free()
	hands.transform = Transform3D.IDENTITY
	var player: AnimationPlayer = journal.get_node("PresentationAnimation")
	player.play("open")
	player.seek(0.0,true)
	player.pause()
	var animation: Animation = player.get_animation("open")
	for track in range(animation.get_track_count()-1,-1,-1):
		if "/Hands" in String(animation.track_get_path(track)): animation.remove_track(track)
	assert(ResourceSaver.save(animation,"res://scenes/ui/journal/journal_presentation_open.tres") == OK)
	await process_frame
	var packed := PackedScene.new()
	assert(packed.pack(journal) == OK)
	assert(ResourceSaver.save(packed,"res://scenes/ui/quest_journal.tscn") == OK)

func look_modifiers(scene: Node3D, rig: Skeleton3D) -> void:
	var target := Marker3D.new()
	target.position = Vector3(0,1.65,-4)
	own(target,scene,scene,"LookTarget")
	var reading := Marker3D.new()
	reading.position = Vector3(0,1.35,-0.55)
	own(reading,scene,scene,"JournalLookTarget")
	for label in ["Spine2","Neck","Head"]:
		var modifier := LookAtModifier3D.new()
		modifier.bone_name = label
		modifier.forward_axis = SkeletonModifier3D.BONE_AXIS_PLUS_Z
		modifier.use_angle_limitation = true
		modifier.primary_limit_angle = deg_to_rad(30 if label=="Spine2" else 12 if label=="Neck" else 35)
		modifier.secondary_limit_angle = deg_to_rad(20 if label=="Neck" else 45)
		if label=="Spine2": modifier.use_secondary_rotation = false
		modifier.duration = 0.12
		own(modifier,rig,scene,label+"Look")
		modifier.target_node = modifier.get_path_to(target)

func ragdoll(id: String, rig: Skeleton3D) -> void:
	var scene := Node3D.new()
	scene.name = "DeathPhysics"
	scene.set_script(load("res://scripts/gameplay/skeletal_ragdoll.gd"))
	scene.set("exclude_self_collision",true)
	root.add_child(scene)
	var physical := [
		["Hips","Spine",12.0,0.14],["Spine","Spine1",7.0,0.12],["Spine1","Spine2",9.0,0.14],["Spine2","Neck",13.0,0.15],["Head","HeadTop_End",4.5,0.09],
		["LeftArm","LeftForeArm",2.6,0.045],["LeftForeArm","LeftHand",1.8,0.04],["LeftHand","LeftHandMiddle1",0.6,0.038],
		["RightArm","RightForeArm",2.6,0.045],["RightForeArm","RightHand",1.8,0.04],["RightHand","RightHandMiddle1",0.6,0.038],
		["LeftUpLeg","LeftLeg",7.5,0.075],["LeftLeg","LeftFoot",4.5,0.055],["LeftFoot","LeftToeBase",1.2,0.055],
		["RightUpLeg","RightLeg",7.5,0.075],["RightLeg","RightFoot",4.5,0.055],["RightFoot","RightToeBase",1.2,0.055]]
	var bodies := {}
	for part in physical:
		var first := rig.find_bone(part[0]); var end := rig.find_bone(part[1])
		var a := rig.get_bone_global_rest(first).origin
		var b := rig.get_bone_global_rest(end).origin if end>=0 else a+Vector3.UP*0.18
		var body := RigidBody3D.new()
		body.transform = Transform3D(Basis(Quaternion(Vector3.UP,(b-a).normalized())),(a+b)*0.5)
		body.mass = part[2]
		body.collision_layer = 8
		body.collision_mask = 5
		body.freeze = true
		body.continuous_cd = true
		body.linear_damp = 0.45
		body.angular_damp = 1.25
		body.set_meta("bone",part[0]); body.set_meta("end_bone",part[1])
		own(body,scene,scene,part[0])
		var shape := CapsuleShape3D.new()
		shape.radius = part[3]
		shape.height = maxf(shape.radius*2, a.distance_to(b))
		var collision := CollisionShape3D.new()
		collision.shape = shape
		own(collision,body,scene,"CollisionShape3D")
		bodies[first] = body
	for first in bodies:
		var parent := rig.get_bone_parent(first)
		while parent>=0 and not bodies.has(parent): parent = rig.get_bone_parent(parent)
		if parent<0: continue
		var label: String = bodies[first].name
		var joint: Joint3D
		if "ForeArm" in label or label in ["LeftLeg","RightLeg"]:
			var hinge := HingeJoint3D.new()
			hinge.set_flag(HingeJoint3D.FLAG_USE_LIMIT,true)
			hinge.set_param(HingeJoint3D.PARAM_LIMIT_LOWER,-0.08)
			hinge.set_param(HingeJoint3D.PARAM_LIMIT_UPPER,2.45)
			hinge.set_meta("hinge_axis",Vector3.RIGHT if label.ends_with("Leg") else Vector3.BACK if label.begins_with("Left") else Vector3.FORWARD)
			joint = hinge
		else:
			var cone := ConeTwistJoint3D.new()
			cone.swing_span = 1.1 if "Arm" in label or "UpLeg" in label else 0.28 if label=="Head" else 0.35
			cone.twist_span = 0.30 if "Arm" in label or "UpLeg" in label else 0.20
			joint = cone
		joint.position = rig.get_bone_global_rest(first).origin
		joint.set_meta("parent_body",NodePath(bodies[parent].name))
		joint.set_meta("child_body",NodePath(bodies[first].name))
		own(joint,scene,scene,"Joint"+label)
	save_scene(scene,OUT+"tactical_"+id+"/ragdoll.tscn")
	scene.queue_free()

func humanoid_map(rig: Skeleton3D) -> void:
	var profile := SkeletonProfileHumanoid.new()
	var map := BoneMap.new()
	map.profile = profile
	var core := {"Root":"Root","Hips":"Hips","Spine":"Spine","Chest":"Spine1","UpperChest":"Spine2","Neck":"Neck","Head":"Head"}
	for side in ["Left","Right"]:
		for pair in [["Shoulder","Shoulder"],["UpperArm","Arm"],["LowerArm","ForeArm"],["Hand","Hand"],["UpperLeg","UpLeg"],["LowerLeg","Leg"],["Foot","Foot"],["Toes","ToeBase"]]: core[side+pair[0]] = side+pair[1]
		for finger in ["Index","Middle","Ring","Little"]:
			var target: String = "Pinky" if finger=="Little" else finger
			for segment in [["Proximal","1"],["Intermediate","2"],["Distal","3"]]: core[side+finger+segment[0]] = side+"Hand"+target+segment[1]
		for segment in [["Metacarpal","1"],["Proximal","2"],["Distal","3"]]: core[side+"Thumb"+segment[0]] = side+"HandThumb"+segment[1]
	for i in profile.bone_size:
		var role := profile.get_bone_name(i)
		if core.has(role) and rig.find_bone(core[role])>=0: map.set_skeleton_bone_name(role,core[role])
	assert(ResourceSaver.save(map,"res://assets/config/characters/humanoid_bone_map.tres")==OK)

func run() -> void:
	for id in ["a", "b"]:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT + "tactical_" + id + "/materials/"))
		sources[id] = load_source(id)
	await process_frame
	for id in ["a", "b"]:
		var scene := Node3D.new()
		scene.name = "CharacterModel"
		root.add_child(scene)
		var rig := make_rig(sources[id], scene)
		if id=="a": humanoid_map(rig)
		save_meshes(id, rig, scene)
		models[id] = {"scene": scene, "rig": rig}
		var author := AnimationAuthor.new()
		author.initialize(rig, sources[id], sources)
		var library := author.build()
		var directory: String = OUT + "tactical_" + id + "/"
		assert(ResourceSaver.save(library, directory + "animations.tres") == OK)
		library.take_over_path(directory+"animations.tres")
		animation_nodes(scene,author,directory+"animations.tres")
		equipment(rig,scene,author)
		look_modifiers(scene,rig)
		rig.reset_bone_poses()
		save_scene(scene, OUT + "tactical_" + id + "/body.tscn")
		ragdoll(id,rig)
		await first_person(id)
		print("AUTHORED ", id, " bones ", rig.get_bone_count(), " body bounds ", rig.get_node("Body").mesh.get_aabb())
	for data in sources.values(): data.instance.queue_free()
	for data in models.values(): data.scene.queue_free()
	await migrate_journal_arms()
	await process_frame
	quit()
