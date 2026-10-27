extends RefCounted
const ROOT_PATH := "res://scenes/levels/base_blockout_v03.tscn"
var skeletons: Dictionary = {}
var seen: Dictionary = {}
var chunks: Dictionary = {}
var signatures: Dictionary = {}
var failed := false
const PLAN_PATH := "res://assets/config/level_loading_plan.res"
const SCHEMA := 3


func allowed(path: String) -> bool:
	return path.begins_with("res://scenes/levels/") or path.begins_with("res://scenes/art/base/")


func weight(scene: PackedScene, visited: Dictionary) -> int:
	if visited.has(scene):
		return 0
	visited[scene] = true
	var state = scene.get_state()
	var total = state.get_node_count()
	for i in state.get_node_count():
		var child = state.get_node_instance(i)
		if child != null:
			total += weight(child, visited)
	return total


static func under(path: String, selected) -> bool:
	for chunk in selected:
		if path == chunk or path.begins_with(chunk + "/"):
			return true
	return false


func prepare(scene: PackedScene):
	var path = scene.resource_path
	if seen.has(path):
		return
	seen[path] = FileAccess.get_sha256(path)
	if not path.ends_with(".tscn") or not allowed(path):
		return
	var state = scene.get_state()
	var selected: Array[String] = []
	for i in state.get_node_count():
		var child = state.get_node_instance(i)
		if child == null or not allowed(child.resource_path) or weight(child, {}) < 128:
			continue
		var node_path = str(state.get_node_path(i)).trim_prefix("./")
		if under(node_path, selected):
			continue
		selected.append(node_path)
		prepare(child)

	if selected.is_empty():
		return
	chunks[path] = PackedStringArray(selected)
	signatures[path] = signature(scene, PackedStringArray(selected))
	var text = FileAccess.get_file_as_string(path)
	var lines = text.split("\n")
	var output: PackedStringArray = []
	var skip = false
	var node_regex = RegEx.new()
	node_regex.compile('^\\[node name="([^"]+)"[^\\n]*parent="([^"]*)"')
	var edit_regex = RegEx.new()
	edit_regex.compile('^\\[editable path="([^"]+)"')
	var uid_regex = RegEx.new()
	uid_regex.compile(' uid="[^"]+"')
	var instance_regex = RegEx.new()
	instance_regex.compile('instance=ExtResource\\("[^"]+"\\)')
	for line in lines:
		if line.begins_with("[gd_scene"):
			line = uid_regex.sub(line, "")
		if line.begins_with("["):
			skip = false
		var found = node_regex.search(line)
		if found:
			var parent = found.get_string(2)
			var current = (
				found.get_string(1) if parent == "." else parent + "/" + found.get_string(1)
			)
			if selected.has(current):
				output.append(instance_regex.sub(line, 'type="Node3D"'))
				skip = true
				continue
			if under(current, selected):
				skip = true
		var edit = edit_regex.search(line)
		if edit != null and under(edit.get_string(1), selected):
			skip = true
		if not skip:
			output.append(line)
	var directory = "user://level_load_build"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var temp = directory.path_join("skeleton_" + path.md5_text() + ".tscn")
	var f = FileAccess.open(temp, FileAccess.WRITE)
	if f == null:
		push_error("Cannot write loading plan staging scene: " + temp)
		failed = true
		return
	f.store_string("\n".join(output))
	f.close()
	var skeleton = ResourceLoader.load(temp, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(temp))
	if skeleton == null:
		push_error("Cannot build skeleton " + path)
		failed = true
		return
	skeleton.take_over_path("")
	skeletons[path] = skeleton


func build(root_scene: PackedScene) -> Resource:
	prepare(root_scene)
	if failed:
		return null
	var plan = Resource.new()
	plan.set_meta("schema", SCHEMA)
	plan.set_meta("skeletons", skeletons)
	plan.set_meta("chunks", chunks)
	plan.set_meta("source_hashes", seen)
	plan.set_meta("signatures", signatures)
	return plan


static func current(plan: Resource) -> bool:
	if plan == null or plan.get_meta("schema", 0) != SCHEMA:
		return false
	for path in plan.get_meta("source_hashes", {}):
		if FileAccess.get_sha256(path) != plan.get_meta("source_hashes")[path]:
			return false
	return true


# Guard only the cached portion. Chunk subtrees and their overrides are read
# from the current PackedScene on every load, not from the cache. Export may
# expand their redundant material overrides or discard empty editable entries.
static func signature(scene: PackedScene, selected: PackedStringArray) -> String:
	var state = scene.get_state()
	var rows: Array = []
	var resources: Dictionary = {}
	for i in state.get_node_count():
		var child = state.get_node_instance(i)
		var node_path := str(state.get_node_path(i)).trim_prefix("./")
		if under(node_path, selected):
			if selected.has(node_path):
				rows.append(["chunk", node_path, "" if child == null else child.resource_path])
			continue
		var row: Array = [
			node_path,
			state.get_node_type(i),
			str(state.get_node_owner_path(i)).trim_prefix("./"),
			state.get_node_index(i),
			state.get_node_groups(i),
			"" if child == null else child.resource_path
		]
		for j in state.get_node_property_count(i):
			row.append(
				[
					state.get_node_property_name(i, j),
					stable_value(state.get_node_property_value(i, j), resources)
				]
			)
		rows.append(row)
	for i in state.get_connection_count():
		rows.append(
			[
				str(state.get_connection_source(i)).trim_prefix("./"),
				str(state.get_connection_target(i)).trim_prefix("./"),
				state.get_connection_signal(i),
				state.get_connection_method(i),
				state.get_connection_flags(i),
				state.get_connection_unbinds(i),
				stable_value(state.get_connection_binds(i), resources)
			]
		)
	return var_to_str(rows).sha256_text()


static func stable_value(value: Variant, resources: Dictionary) -> Variant:
	if value is Resource:
		if not value.resource_path.is_empty() and "::" not in value.resource_path:
			return value.resource_path
		if resources.has(value):
			return resources[value]
		resources[value] = "cycle"
		var fields: Dictionary = {"class": value.get_class()}
		for info in value.get_property_list():
			if info.usage & PROPERTY_USAGE_STORAGE and info.name != "resource_path":
				fields[info.name] = stable_value(value.get(info.name), resources)
		var hash = var_to_str(fields).sha256_text()
		resources[value] = hash
		return hash
	if value is Array:
		var output: Array = []
		for item in value:
			output.append(stable_value(item, resources))
		return output
	if value is Dictionary:
		var output: Dictionary = {}
		for key in value:
			output[key] = stable_value(value[key], resources)
		return output
	return value
