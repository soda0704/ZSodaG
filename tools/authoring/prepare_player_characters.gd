extends SceneTree
## Offline import repair and native asset authoring. No runtime bone animation.

const OUT := "res://scenes/characters/visuals/"
const TURN := Basis(Vector3.UP, PI)
const AnimationAuthor := preload("res://tools/authoring/presentation_animation_author.gd")
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
	var all_meshes: Array = instance.find_children("*", "MeshInstance3D", true, false)
	var meshes: Array = all_meshes.filter(func(mesh): return mesh.skin != null)
	var rigid_meshes: Array = all_meshes.filter(func(mesh): return mesh.skin == null)
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
	return {"instance": instance, "rig": rig, "meshes": meshes, "rigid_meshes": rigid_meshes, "local_scale": local_scale, "skin": skin, "normalization": normalization, "rests": rests, "names": names, "player": animation_player, "clip": animation_player.get_animation(animation_player.get_animation_list()[0])}

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

func fit_geometry(arrays: Array, size: Vector3, center: Vector3) -> void:
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var bounds := AABB(vertices[0], Vector3.ZERO)
	for vertex in vertices: bounds = bounds.expand(vertex)
	var scale := size / bounds.size
	var basis := Basis.from_scale(scale)
	var normal_basis := basis.inverse().transposed()
	for i in vertices.size(): vertices[i] = basis * (vertices[i] - bounds.get_center()) + center
	arrays[Mesh.ARRAY_VERTEX] = vertices
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	for i in normals.size(): normals[i] = (normal_basis * normals[i]).normalized()
	arrays[Mesh.ARRAY_NORMAL] = normals
	var tangents: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT]
	for i in tangents.size() / 4:
		var tangent := (basis * Vector3(tangents[i*4], tangents[i*4+1], tangents[i*4+2])).normalized()
		tangents[i*4] = tangent.x; tangents[i*4+1] = tangent.y; tangents[i*4+2] = tangent.z
	arrays[Mesh.ARRAY_TANGENT] = tangents

func attach_to_head(arrays: Array, source: Dictionary) -> void:
	# Caps, lenses and headset frames are rigid. Neck/arm/terminal weights
	# from the exports otherwise pull them away when looking or crouching.
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	for slot in bones.size():
		bones[slot] = source.names.find("Head")
		weights[slot] = 1.0 if slot % 4 == 0 else 0.0
	arrays[Mesh.ARRAY_BONES] = bones
	arrays[Mesh.ARRAY_WEIGHTS] = weights

func fit_shoulder_straps(arrays: Array, source: Dictionary) -> void:
	# Seat the upper straps on the actual jacket/pads and borrow the supporting
	# triangle's skin weights. Matching only rest-space height clips during crouch.
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var supports: Array = []
	for mesh: MeshInstance3D in source.meshes:
		if mesh.get_active_material(0).resource_name not in ["jumpsuit", "ShoulderPads"]: continue
		var data := mesh.mesh.surface_get_arrays(0)
		var points: PackedVector3Array = data[Mesh.ARRAY_VERTEX]
		for i in points.size(): points[i] = source.normalization * points[i]
		data[Mesh.ARRAY_VERTEX] = points
		supports.append({"mesh": mesh, "arrays": data})
	for vertex in vertices.size():
		var point := vertices[vertex]
		if point.y < 1.46: continue
		var top := -INF
		var support: Dictionary = {}
		var triangle := Vector3i.ZERO
		var hit_point := Vector3.ZERO
		for entry in supports:
			var data: Array = entry.arrays
			var points: PackedVector3Array = data[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = data[Mesh.ARRAY_INDEX]
			for face in range(0, indices.size(), 3):
				var ids := Vector3i(indices[face], indices[face+1], indices[face+2])
				var hit: Variant = Geometry3D.segment_intersects_triangle(Vector3(point.x, 1.8, point.z), Vector3(point.x, 1.3, point.z), points[ids.x], points[ids.y], points[ids.z])
				if hit != null and hit.y > top:
					top = hit.y; hit_point = hit; support = entry; triangle = ids
		if support.is_empty() or point.y > top + 0.025: continue
		vertices[vertex].y = maxf(point.y, top + 0.006)
		var data: Array = support.arrays
		var p: PackedVector3Array = data[Mesh.ARRAY_VERTEX]
		var edge0 := p[triangle.y] - p[triangle.x]
		var edge1 := p[triangle.z] - p[triangle.x]
		var delta := hit_point - p[triangle.x]
		var denominator := edge0.length_squared() * edge1.length_squared() - pow(edge0.dot(edge1), 2)
		var v := (edge1.length_squared() * delta.dot(edge0) - edge0.dot(edge1) * delta.dot(edge1)) / denominator
		var w := (edge0.length_squared() * delta.dot(edge1) - edge0.dot(edge1) * delta.dot(edge0)) / denominator
		var barycentric := Vector3(1.0 - v - w, v, w)
		var blended := {}
		for corner in 3:
			for slot in 4:
				var at := triangle[corner] * 4 + slot
				var bone: int = source.rig.find_bone(support.mesh.skin.get_bind_name(data[Mesh.ARRAY_BONES][at]))
				blended[bone] = blended.get(bone, 0.0) + maxf(0.0, barycentric[corner]) * data[Mesh.ARRAY_WEIGHTS][at]
		var strongest := blended.keys()
		strongest.sort_custom(func(a, b): return blended[a] > blended[b])
		var total := 0.0
		for slot in mini(4, strongest.size()): total += blended[strongest[slot]]
		for slot in 4:
			bones[vertex*4+slot] = strongest[slot] if slot < strongest.size() else 0
			weights[vertex*4+slot] = blended[strongest[slot]] / total if slot < strongest.size() else 0.0
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_BONES] = bones
	arrays[Mesh.ARRAY_WEIGHTS] = weights

func repair_accessory(arrays: Array, label: String, part_name: String, source: Dictionary) -> void:
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var bounds := AABB(vertices[0], Vector3.ZERO)
	for vertex in vertices: bounds = bounds.expand(vertex)
	if source == sources.a:
		if label == "Head":
			fit_geometry(arrays, bounds.size * (0.235 / bounds.size.y), Vector3(0, 1.67, -0.015))
			attach_to_head(arrays, source)
		elif label == "Material.001":
			# These are red goggle lenses, not the cap. Use the exact same
			# transform as their frame, which is part of the Head surface.
			var head_mesh: MeshInstance3D = source.meshes.filter(func(mesh): return mesh.get_active_material(0).resource_name == "Head")[0]
			var head_bounds: AABB = source.normalization * head_mesh.mesh.get_aabb()
			var scale := 0.235 / head_bounds.size.y
			fit_geometry(arrays, bounds.size * scale, (bounds.get_center() - head_bounds.get_center()) * scale + Vector3(0, 1.67, -0.015))
			attach_to_head(arrays, source)
		elif label == "material":
			# A's exported cap is flattened on Y and Z. Restore its crown and
			# brim proportions around the fitted head, retaining authored UVs.
			fit_geometry(arrays, Vector3(0.19, 0.115, 0.27), Vector3(0, 1.76, -0.025))
			attach_to_head(arrays, source)
		elif label == "Headphones":
			fit_geometry(arrays, Vector3(0.21, 0.195, bounds.size.z), Vector3(0, 1.718, -0.0305))
			attach_to_head(arrays, source)
		elif part_name == "Object_98":
			# Align shoulder straps with the suit rather than the base of the
			# head, and bring the front/back plates onto the torso.
			fit_geometry(arrays, bounds.size * Vector3(1, 1, 0.9), Vector3(bounds.get_center().x, bounds.get_center().y - 0.09, 0.016))
			fit_shoulder_straps(arrays, source)
		elif part_name == "Object_96":
			fit_geometry(arrays, bounds.size, Vector3(bounds.get_center().x, 1.135, 0.180))
	else:
		if label == "GreenCap":
			# Its authored location already fits B. Recentring it raised the
			# cap above the skull and displaced the brim behind the forehead.
			attach_to_head(arrays, source)
		elif label == "HeadphonesT":
			fit_geometry(arrays, Vector3(0.22, 0.22, bounds.size.z), Vector3(0, 1.712, -0.045))
			attach_to_head(arrays, source)
		elif part_name == "Object_101":
			# The hard knee shells must follow their pad bones as a whole.
			# The export also blends them with the thigh, stretching the shell
			# open when the knee bends deeply during crouch.
			var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			for vertex in vertices.size():
				var bone: int = source.names.find(("Left" if vertices[vertex].x < 0 else "Right") + "_Knee_Pads")
				for slot in 4:
					bones[vertex*4+slot] = bone
					weights[vertex*4+slot] = 1.0 if slot == 0 else 0.0
			arrays[Mesh.ARRAY_BONES] = bones; arrays[Mesh.ARRAY_WEIGHTS] = weights

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
		repair_accessory(arrays, mesh.get_active_material(surface).resource_name, String(mesh.name), source)
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

func cache_rigid_frames(source: Dictionary) -> void:
	# BoneAttachment transforms update on a frame boundary. Cache the matching
	# source pose before animation authoring seeks either source rig repeatedly.
	source.rigid_frames = {}
	var head: int = source.names.find("Head")
	var source_head: Transform3D = source.rig.global_transform * source.rig.get_bone_global_pose(head)
	for mesh: MeshInstance3D in source.rigid_meshes:
		assert(mesh.get_parent().name == &"Mil_R5_Eye", "Unmapped rigid character part: " + String(mesh.name))
		source.rigid_frames[mesh.get_instance_id()] = source.rests[head] * Transform3D(Basis.from_scale(Vector3.ONE * source.local_scale), Vector3.ZERO) * source_head.affine_inverse() * mesh.global_transform

func rigid_arrays_for(mesh: MeshInstance3D, surface: int, source: Dictionary) -> Array:
	# Military's eyes are a rigid child of the source head, not a skinned mesh.
	var transform: Transform3D = source.rigid_frames[mesh.get_instance_id()]
	var arrays := mesh.mesh.surface_get_arrays(surface).duplicate(true)
	for channel in range(Mesh.ARRAY_CUSTOM0, Mesh.ARRAY_CUSTOM3 + 1): arrays[channel] = null
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var tangents: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT]
	for i in vertices.size():
		vertices[i] = transform * vertices[i]
		normals[i] = (transform.basis.inverse().transposed() * normals[i]).normalized()
		if tangents.size() > i * 4:
			var tangent := (transform.basis * Vector3(tangents[i*4], tangents[i*4+1], tangents[i*4+2])).normalized()
			tangents[i*4] = tangent.x; tangents[i*4+1] = tangent.y; tangents[i*4+2] = tangent.z
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TANGENT] = tangents
	var bones := PackedInt32Array(); bones.resize(vertices.size() * 4)
	var weights := PackedFloat32Array(); weights.resize(vertices.size() * 4)
	arrays[Mesh.ARRAY_BONES] = bones; arrays[Mesh.ARRAY_WEIGHTS] = weights
	attach_to_head(arrays, source)
	return arrays

func save_meshes(id: String, rig: Skeleton3D, scene: Node3D, body_only: bool = false) -> void:
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
			if material.resource_name in ["Head", "material"]:
				material.metallic = 0.0
				material.roughness = 0.9
			if material.resource_name == "material":
				# The cap's packed map contains polished regions; it is cloth,
				# not metal. Keep its colour/stitching without silver highlights.
				material.roughness = 0.95
				material.roughness_texture = null
				material.metallic_texture = null
				material.normal_scale = 0.4
				material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
			material.metallic_specular = 0.25
			if material.resource_name in ["jumpsuit","Mil_Suit_R5","gloves"]: material.roughness = 0.95
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
					var pad_weight := 0.0
					var body_weight := 0.0
					for slot in 4:
						var name: String = source.names[arrays[Mesh.ARRAY_BONES][v*4+slot]]
						if "Elbow_Pads" in name: pad_weight += arrays[Mesh.ARRAY_WEIGHTS][v*4+slot]
						if "Shoulder" in name or "Head" in name or "Neck" in name or "Spine" in name: body_weight += arrays[Mesh.ARRAY_WEIGHTS][v*4+slot]
						if "Arm" in name or "Hand" in name or "Shoulder" in name or "Elbow" in name:
							arm_weight += arrays[Mesh.ARRAY_WEIGHTS][v*4+slot]
							if name.begins_with("Right"): right_weight += arrays[Mesh.ARRAY_WEIGHTS][v*4+slot]
					arm_triangle = arm_triangle and arm_weight > 0.48
					# Preserve a continuous sleeve through the elbow. Its proximal
					# cut stays outside the view; shoulder/torso weights are excluded
					# separately instead of cutting a visible stump at the elbow.
					var side := "Right" if right_weight > arm_weight*0.5 else "Left"
					var shoulder: Vector3 = source.rests[source.names.find(side+"Arm")].origin
					var elbow: Vector3 = source.rests[source.names.find(side+"ForeArm")].origin
					var upper_arm := elbow-shoulder
					var along: float = (arrays[Mesh.ARRAY_VERTEX][v]-shoulder).dot(upper_arm.normalized())
					view_triangle = view_triangle and arm_triangle and pad_weight<0.05 and body_weight<=0.10 and along > upper_arm.length()*0.20
				if arm_triangle:
					for corner in 3: arm_indices.append(indices[triangle+corner])
					if view_triangle:
						for corner in 3: view_indices.append(indices[triangle+corner])
			if not arm_indices.is_empty():
				arm_arrays[Mesh.ARRAY_INDEX] = arm_indices
				arms.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arm_arrays)
				arms.surface_set_material(arms.get_surface_count()-1, material)
			if not view_indices.is_empty() and "Pads" not in material.resource_name:
				var view_arrays := arrays.duplicate(true)
				view_arrays[Mesh.ARRAY_INDEX] = view_indices
				view_arms.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,view_arrays)
				view_arms.surface_set_material(view_arms.get_surface_count()-1,material)
	for part: MeshInstance3D in source.rigid_meshes:
		for surface in part.mesh.get_surface_count():
			var material := part.get_active_material(surface).duplicate() as StandardMaterial3D
			material.resource_name = "Mil_Suit_R5_Eyes"
			material.metallic_specular = 0.25
			material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
			material_path(material, id, "Eyes_%d" % surface)
			full.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, rigid_arrays_for(part, surface, source))
			full.surface_set_material(full.get_surface_count()-1, material)
	var directory := OUT + "tactical_" + id + "/"
	var lod_mesh := ImporterMesh.new()
	for surface in full.get_surface_count():
		lod_mesh.add_surface(Mesh.PRIMITIVE_TRIANGLES,full.surface_get_arrays(surface),[],{},full.surface_get_material(surface))
	lod_mesh.generate_lods(25.0,60.0,[])
	full = lod_mesh.get_mesh()
	assert(ResourceSaver.save(full, directory + "body.res") == OK)
	if body_only:
		return
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
	# Unchanged resources do not need rewriting (Windows may hold texture/material
	# streams open while reviewing). This also avoids unrelated material diffs.
	if FileAccess.file_exists(path):
		var existing: StandardMaterial3D=load(path)
		if existing.metallic==material.metallic and existing.metallic_specular==material.metallic_specular and existing.specular_mode==material.specular_mode and existing.roughness==material.roughness and existing.roughness_texture==material.roughness_texture and existing.albedo_color==material.albedo_color:
			material.take_over_path(path)
			return
	assert(ResourceSaver.save(material, path) == OK)
	material.take_over_path(path)

func save_scene(scene: Node3D, path: String) -> void:
	var packed := PackedScene.new()
	assert(packed.pack(scene) == OK)
	var error:=ResourceSaver.save(packed,path)
	# Windows editor/file watchers occasionally hold a scene open for reading
	# during asset regeneration. Retry only this transient authoring write.
	for attempt in 8:
		if error==OK:break
		OS.delay_msec(100)
		error=ResourceSaver.save(packed,path)
	assert(error==OK)

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
		model.position = -author.GRIPS["Pistol" if kind=="pistol" else "Rifle"] if kind in ["pistol","m4a1"] else Vector3(0,0.045,-0.075)
		model.visible = false
		for mesh in model.find_children("*","MeshInstance3D",true,false):
			mesh.layers = (1<<19) if first_person else 1|(1<<18)
			mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if first_person else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		var support := Marker3D.new()
		support.position = author.SUPPORTS["Rifle" if kind=="m4a1" else "Pistol"] if kind in ["pistol","m4a1"] else Vector3(-0.045,-0.065,0.005)
		support.basis = author.support_basis("Rifle" if kind=="m4a1" else "Pistol")
		own(support,model,scene,"SupportHand")
		var right_grip := Marker3D.new()
		right_grip.position = author.GRIPS["Rifle" if kind=="m4a1" else "Pistol"] if kind in ["pistol","m4a1"] else Vector3.ZERO
		right_grip.basis = author.hand_basis("Right",0,true)
		own(right_grip,model,scene,"RightHandGrip")
		var left_grip := support.duplicate()
		own(left_grip,model,scene,"LeftHandGrip")
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
		marker.position = -author.GRIPS.Flashlight if label=="FlashlightGrip" else Vector3(0,-0.293,0) if label=="FuelGrip" else Vector3(0,-0.055,-0.065)
		if label=="FuseGrip": marker.rotation.z = PI*0.5
		if label=="FuelGrip":
			var compensation: Basis = author.hand_basis("Right",0,true)*author.hand_basis("Right",0,false).inverse()
			marker.basis=compensation
			marker.position=compensation*marker.position
		marker.scale = Vector3.ONE * (0.72 if label=="FuelGrip" else 1.0)
		own(marker,equipment_root,scene,label)
	var journal: Node3D = load("res://scenes/ui/journal/book/articulated_journal.tscn").instantiate()
	own(journal,scene,scene,"Journal")
	journal.scale=Vector3.ONE*(1.0 if first_person else 0.8)
	journal.visible = false
	for side in ["Left","Right"]:
		var book_grip := Marker3D.new(); book_grip.transform=author.journal_grip(side)
		own(book_grip,journal,scene,side+"Grip")
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
	left_ik.set_target_node(0,left_ik.get_path_to(equipment_root.get_node("m4a1/LeftHandGrip")))
	left_ik.set_pole_node(0,left_ik.get_path_to(pole))
	for side in ["Left","Right"]:
		var target := Marker3D.new()
		own(target,rig,scene,side+"WristTarget")
		if side=="Right":
			var ik := TwoBoneIK3D.new(); ik.set_setting_count(1)
			ik.set_root_bone_name(0,"RightArm"); ik.set_middle_bone_name(0,"RightForeArm"); ik.set_end_bone_name(0,"RightHand")
			ik.set_pole_direction_vector(0,Vector3(0.5,-0.5,0.2))
			own(ik,rig,scene,"RightGripIK")
			var right_pole := Marker3D.new(); right_pole.position=Vector3(0.48,1.02,0.08)
			own(right_pole,scene,scene,"RightElbowPole")
			ik.set_pole_node(0,ik.get_path_to(right_pole)); ik.set_target_node(0,ik.get_path_to(target)); ik.active=false

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
	var source_rests: Array[Transform3D]=[]
	for bone in rig.get_bone_count(): source_rests.append(rig.get_bone_global_rest(bone))
	# A view rig has its own sleeve proportions; fingers retain their source rest.
	for side in ["Left","Right"]:
		for label in [side+"ForeArm",side+"Hand"]:
			var bone:=rig.find_bone(label); var rest:=rig.get_bone_rest(bone)
			rest.origin*=1.26; rig.set_bone_rest(bone,rest)
	rig.reset_bone_poses()
	var view_mesh:=ArrayMesh.new()
	var source_mesh: ArrayMesh=load(directory+"view_arms.res")
	for surface in source_mesh.get_surface_count():
		var arrays:=source_mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array=arrays[Mesh.ARRAY_NORMAL]
		for vertex in vertices.size():
			var point:=Vector3.ZERO; var normal:=Vector3.ZERO
			for slot in 4:
				var at:=vertex*4+slot; var bone: int=arrays[Mesh.ARRAY_BONES][at]
				var transfer:=rig.get_bone_global_rest(bone)*source_rests[bone].affine_inverse()
				point+=transfer*vertices[vertex]*arrays[Mesh.ARRAY_WEIGHTS][at]
				normal+=transfer.basis*normals[vertex]*arrays[Mesh.ARRAY_WEIGHTS][at]
			vertices[vertex]=point; normals[vertex]=normal.normalized()
		arrays[Mesh.ARRAY_VERTEX]=vertices; arrays[Mesh.ARRAY_NORMAL]=normals
		view_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
		view_mesh.surface_set_material(surface,source_mesh.surface_get_material(surface))
	assert(ResourceSaver.save(view_mesh,directory+"view_arms.res")==OK)
	view_mesh.take_over_path(directory+"view_arms.res")
	var mesh := MeshInstance3D.new()
	mesh.mesh = view_mesh
	mesh.skin = native_skin(rig)
	mesh.skeleton = NodePath("..")
	mesh.layers = 1<<19
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh.extra_cull_margin = 0.45
	own(mesh,rig,scene,"Arms")
	var author := AnimationAuthor.new()
	author.initialize(rig,sources[id],sources)
	var library := author.build_fp()
	assert(ResourceSaver.save(library,directory+"first_person_animations.tres") == OK)
	library.take_over_path(directory+"first_person_animations.tres")
	animation_nodes(scene,author,directory+"first_person_animations.tres",true)
	scene.get_node("AnimationTree").tree_root = author.fp_graph()
	equipment(rig,scene,author,true)
	var book := scene.get_node("Journal")
	scene.set_editable_instance(book,true)
	for book_mesh in book.find_children("*","MeshInstance3D",true,false):
		book_mesh.layers=1<<19; book_mesh.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	assert(ResourceSaver.save(library,directory+"first_person_animations.tres")==OK)
	rig.reset_bone_poses()
	save_scene(scene,directory+"first_person.tscn")
	scene.queue_free()

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
		var contact_material:=PhysicsMaterial.new(); contact_material.friction=0.8; contact_material.bounce=0.0
		body.physics_material_override=contact_material
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
	for data in sources.values(): cache_rigid_frames(data)
	if "--body-only" in OS.get_cmdline_user_args() or "--world-only" in OS.get_cmdline_user_args() or "--idle-only" in OS.get_cmdline_user_args():
		for id in ["a", "b"]:
			var scene := Node3D.new()
			root.add_child(scene)
			var rig := make_rig(sources[id], scene)
			if "--idle-only" in OS.get_cmdline_user_args():
				var author := AnimationAuthor.new()
				author.initialize(rig, sources[id], sources)
				author.add_clip("Idle", 3.0, true, func(t): author.idle(t))
				var path: String = OUT + "tactical_" + id + "/animations.tres"
				var library: AnimationLibrary = load(path).duplicate(true)
				library.remove_animation("Idle")
				library.add_animation("Idle", author.library.get_animation("Idle"))
				assert(ResourceSaver.save(library, path) == OK)
				print("AUTHORED IDLE ", id)
				scene.queue_free()
				continue
			save_meshes(id, rig, scene, true)
			if "--world-only" in OS.get_cmdline_user_args():
				var author := AnimationAuthor.new()
				author.initialize(rig, sources[id], sources)
				assert(ResourceSaver.save(author.build(), OUT + "tactical_" + id + "/animations.tres") == OK)
			print("AUTHORED BODY ", id)
			scene.queue_free()
		for data in sources.values(): data.instance.queue_free()
		await process_frame
		quit()
		return
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
	await process_frame
	quit()
