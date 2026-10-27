extends SceneTree
const PATH := "res://scenes/levels/base_blockout_v03.tscn"
var failures := 0
var resources: Dictionary = {}


func _initialize():
	run.call_deferred()


func normalize(value: Variant, root_node: Node, depth := 0) -> Variant:
	if depth > 12:
		return "depth"
	if value is Node:
		return "node:" + node_path(root_node, value)
	if value is Resource:
		if value is Script:
			return "script:" + value.resource_path
		if not value.resource_path.is_empty() and "::" not in value.resource_path:
			return "resource:" + value.resource_path
		if resources.has(value):
			return resources[value]
		var data: Dictionary = {"class": value.get_class()}
		resources[value] = "cycle"
		for prop in value.get_property_list():
			if (
				prop.usage & PROPERTY_USAGE_STORAGE
				and (
					prop.name
					not in ["resource_path", "resource_name", "resource_local_to_scene", "script"]
				)
			):
				data[prop.name] = normalize(value.get(prop.name), root_node, depth + 1)
		var result = var_to_str(data).sha256_text()
		resources[value] = result
		return result
	if value is Array:
		var result = []
		for v in value:
			result.append(normalize(v, root_node, depth + 1))
		return result
	if value is Dictionary:
		var result = {}
		for k in value:
			result[str(k)] = normalize(value[k], root_node, depth + 1)
		return result
	return value


func node_path(world: Node, node: Node) -> String:
	if node == world:
		return "."
	var segment = str(node.name)
	if segment.begins_with("@"):
		segment = node.get_class() + "#" + str(node.get_index(true))
	var parent = node.get_parent()
	return segment if parent == world else node_path(world, parent) + "/" + segment


func capture(world: Node, job = null) -> Dictionary:
	var data: Dictionary = {}
	resources.clear()
	for node in [world] + world.find_children("*", "", true, false):
		var entry = {
			"class": node.get_class(),
			"groups": Array(node.get_groups()),
			"sibling_index": node.get_index(true),
			"scene_file_path": node.scene_file_path,
			"owner": "" if node.owner == null else node_path(world, node.owner)
		}
		entry.groups.sort()
		entry["connections"] = []
		for signal_info in node.get_signal_list():
			for connection in node.get_signal_connection_list(signal_info.name):
				if not connection.flags & CONNECT_PERSIST: continue
				var callback: Callable = connection.callable
				entry.connections.append([signal_info.name, node_path(world, callback.get_object()), callback.get_method(), connection.flags, callback.get_unbound_arguments_count(), normalize(callback.get_bound_arguments(), world)])

		for prop in node.get_property_list():
			if not prop.usage & PROPERTY_USAGE_STORAGE or prop.name.begins_with("_editor"):
				continue
			var value = node.get(prop.name)
			if prop.name == "name" and str(value).begins_with("@"):
				value = node.get_class() + "#" + str(node.get_index(true))
			if prop.name == "use_collision" and job != null and job.staged_csg.has(node):
				value = job.staged_csg[node]
			entry[prop.name] = normalize(value, world)
		data[node_path(world, node)] = entry
	return data


func run():
	var packed: PackedScene = load(PATH)
	var original = packed.instantiate()
	var before = capture(original)
	original.free()
	var plan: Resource = load("res://assets/config/level_loading_plan.res")
	for dependency in ResourceLoader.get_dependencies("res://assets/config/level_loading_plan.res"):
		if "user://" in dependency or "tools/.local" in dependency:
			push_error("Nonportable plan dependency: " + dependency)
			quit(1)
			return
	var expected_signatures: Dictionary = plan.get_meta("signatures").duplicate()
	if "--stale-plan" in OS.get_cmdline_user_args():
		var stale := expected_signatures.duplicate()
		stale[PATH] = "intentionally_stale_for_regression"
		plan.set_meta("signatures", stale)
	print("PLAN scopes ", plan.get_meta("skeletons").size())
	var job = load("res://scripts/network/level_load_job.gd").new()
	var staged = await job.instantiate(packed, self)
	if staged == null:
		quit(1)
		return
	var after = capture(staged, job)
	plan.set_meta("signatures", expected_signatures)
	if "--stale-plan" in OS.get_cmdline_user_args() and job.skeletons.has(PATH):
		push_error("Stale plan was not rejected")
		staged.free()
		quit(1)
		return
	var missing = []
	var different = []
	for path in before:
		if not after.has(path):
			missing.append(path)
			continue
		if before[path] != after[path]:
			var fields = []
			for key in before[path]:
				if before[path][key] != after[path].get(key):
					fields.append(key)
			different.append({"path": path, "fields": fields})
	var extra = []
	for path in after:
		if not before.has(path):
			extra.append(path)
	var result = {
		"before_nodes": before.size(),
		"after_nodes": after.size(),
		"missing": missing,
		"extra": extra,
		"different": different
	}
	var f = FileAccess.open("user://level_load_equivalence.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(result, "\t"))
	f.close()
	print(
		"EQUIVALENCE nodes ",
		before.size(),
		" / ",
		after.size(),
		" missing ",
		missing.size(),
		" extra ",
		extra.size(),
		" different ",
		different.size()
	)
	for i in mini(12, different.size()):
		print(different[i])
	staged.free()
	quit(0 if missing.is_empty() and extra.is_empty() and different.is_empty() else 1)
