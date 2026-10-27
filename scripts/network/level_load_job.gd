extends RefCounted
## Main-thread assembly: no node enters the tree before all scene overrides exist.
const Plan = preload("res://scripts/network/level_load_plan.gd")
var chunks: Dictionary = {}
var signatures: Dictionary = {}

var skeletons: Dictionary = {}
var staged_csg: Dictionary = {}
var collisions_ready := false
var loaded_instance: Node
var restore_started := false


static func trace(label: String) -> void:
	if ProjectSettings.get_setting("northern_lab/testing/loading_trace", false):
		print("LOAD_PHASE ", label, " ", Time.get_ticks_usec())


func instantiate(packed: PackedScene, tree: SceneTree) -> Node:
	var plan: Resource = load(Plan.PLAN_PATH) if ResourceLoader.exists(Plan.PLAN_PATH) else null
	if (
		OS.has_feature("editor")
		and FileAccess.file_exists("res://project.godot")
		and not Plan.current(plan)
	):
		plan = Plan.new().build(packed)
		if plan != null:
			ResourceSaver.save(plan, Plan.PLAN_PATH)
	if plan != null and plan.get_meta("schema", 0) == Plan.SCHEMA:
		skeletons = plan.get_meta("skeletons", {}).duplicate()
		chunks = plan.get_meta("chunks", {})
		signatures = plan.get_meta("signatures", {})
	var instance = await construct(packed, tree)
	loaded_instance = instance
	return instance


func clone_local(value: Variant, copies: Dictionary, current: Variant = null) -> Variant:
	if value is Resource:
		if not value.resource_local_to_scene:
			return value
		if copies.has(value):
			return copies[value]
		# PackedScene already initialized scene-local resources, including the
		# owning scene of nested ViewportTextures. Synchronize their authored
		# overrides without replacing that native instance with an unbound copy.
		var target: Resource = (
			current
			if (
				current is Resource
				and current != value
				and current.resource_local_to_scene
				and current.get_class() == value.get_class()
			)
			else value.duplicate()
		)
		copies[value] = target
		for property in value.get_property_list():
			if (
				not property.usage & PROPERTY_USAGE_STORAGE
				or property.name in ["resource_path", "resource_local_to_scene"]
			):
				continue
			var previous: Variant = target.get(property.name)
			var updated: Variant = clone_local(value.get(property.name), copies, previous)
			if previous != updated:
				target.set(property.name, updated)
		return target
	if value is Array:
		var result = value.duplicate()
		for i in result.size():
			result[i] = clone_local(
				result[i], copies, current[i] if current is Array and i < current.size() else null
			)
		return result
	if value is Dictionary:
		var result = value.duplicate()
		for k in result:
			result[k] = clone_local(
				result[k], copies, current.get(k) if current is Dictionary else null
			)
		return result
	return value


func assign(node: Node, key: String, value: Variant, copies: Dictionary) -> void:
	value = clone_local(value, copies, node.get(key))
	if value is NodePath:
		for info in node.get_property_list():
			if info.name == key and info.type == TYPE_OBJECT:
				value = node.get_node_or_null(value)
				break
	if key == "use_collision" and staged_csg.has(node):
		staged_csg[node] = value
		return
	node.set(key, value)


func collect_csg(instance: Node, path: String) -> void:
	for node: CSGShape3D in instance.find_children("*", "CSGShape3D", true, false):
		if staged_csg.has(node) or not node.is_root_shape() or not node.use_collision:
			continue
		var local = str(instance.get_path_to(node))
		var eligible = (
			path.begins_with("res://scenes/levels/floor_")
			or path.begins_with("res://scenes/art/base/")
			or local.begins_with("Floor_")
		)
		if not eligible or "/Doors/" in local or "/Gameplay/" in local or "/Water/" in local:
			continue
		staged_csg[node] = true
		node.use_collision = false


func construct(packed: PackedScene, tree: SceneTree) -> Node:
	var path = packed.resource_path
	if (
		skeletons.has(path)
		and (
			signatures.get(path, "")
			!= Plan.signature(packed, chunks.get(path, PackedStringArray()))
		)
	):
		push_warning("Stale loading plan; using original scene: " + path)
		skeletons.erase(path)
	if not skeletons.has(path):
		var node = packed.instantiate()
		collect_csg(node, path)
		await tree.process_frame
		return node
	var skeleton: PackedScene = skeletons[path]
	var instance = skeleton.instantiate()
	instance.scene_file_path = path
	var state = packed.get_state()
	var copies: Dictionary = {}
	# Replace only the stubs actually generated in the skeleton.
	for i in state.get_node_count():
		var child_scene = state.get_node_instance(i)
		if child_scene == null:
			continue
		var node_path = state.get_node_path(i)
		var stub = instance.get_node_or_null(node_path)
		if not str(node_path).trim_prefix("./") in chunks.get(path, []):
			continue
		if stub == null:
			instance.free()
			return null
		var child = await construct(child_scene, tree)
		if child == null:
			instance.free()
			return null
		var parent = stub.get_parent()
		var index = stub.get_index()
		parent.remove_child(stub)
		stub.free()
		child.name = state.get_node_name(i)
		parent.add_child(child)
		parent.move_child(child, index)
		child.owner = instance
	# Apply the original scene's overrides and additions after the graph is whole.
	for i in state.get_node_count():
		var node_path = state.get_node_path(i)
		var node = instance if str(node_path) == "." else instance.get_node_or_null(node_path)
		if node == null:
			var parent_path = node_path.get_concatenated_names().get_base_dir()
			var parent = (
				instance
				if parent_path.is_empty() or parent_path == "."
				else instance.get_node_or_null(parent_path)
			)
			var child_scene = state.get_node_instance(i)
			if child_scene != null:
				node = await construct(child_scene, tree)
			elif not state.get_node_type(i).is_empty():
				node = ClassDB.instantiate(state.get_node_type(i))
			if node == null or parent == null:
				push_error("Missing staged node " + str(node_path))
				if node != null:
					node.free()
				instance.free()
				return null
			node.name = state.get_node_name(i)
			parent.add_child(node)
			node.owner = instance
		for property in state.get_node_property_count(i):
			assign(
				node,
				state.get_node_property_name(i, property),
				state.get_node_property_value(i, property),
				copies
			)
		for group in state.get_node_groups(i):
			node.add_to_group(group, true)
		var index = state.get_node_index(i)
		if index >= 0 and node.get_parent() != null:
			node.get_parent().move_child(node, mini(index, node.get_parent().get_child_count() - 1))
	collect_csg(instance, path)
	for i in state.get_connection_count():
		var source = instance.get_node(state.get_connection_source(i))
		var target = instance.get_node(state.get_connection_target(i))
		var signal_name = state.get_connection_signal(i)
		var callable = Callable(target, state.get_connection_method(i))
		if state.get_connection_unbinds(i) > 0:
			callable = callable.unbind(state.get_connection_unbinds(i))
		callable = callable.bindv(state.get_connection_binds(i))
		if not source.is_connected(signal_name, callable):
			source.connect(signal_name, callable, state.get_connection_flags(i))
	await tree.process_frame
	return instance


func restore_csg(tree: SceneTree, instance: Node) -> void:
	var count := 0
	for body: StaticBody3D in instance.find_children("*", "StaticBody3D", true, false):
		if not is_instance_valid(body):
			continue
		if not body.can_process():
			body.disable_mode = CollisionObject3D.DISABLE_MODE_KEEP_ACTIVE
		count += 1
		if count % 24 == 0:
			await tree.process_frame
	count = 0
	for node in staged_csg:
		if is_instance_valid(node):
			node.use_collision = staged_csg[node]
		count += 1
		if count % 24 == 0:
			await tree.process_frame
	await tree.physics_frame
	await tree.physics_frame
	collisions_ready = true


func finish_loading(tree: SceneTree) -> void:
	if not restore_started:
		restore_started = true
		await restore_csg(tree, loaded_instance)
	while not collisions_ready:
		await tree.process_frame
