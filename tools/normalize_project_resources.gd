extends SceneTree
## Keep native resources loaded while paths move, then preserve their IDs on save.
var plan: Dictionary
var originals: Dictionary = {}
var visited: Dictionary = {}
var remapped := 0

func _initialize() -> void:
	run.call_deferred()

func target(path: String) -> String:
	var parts := path.split("::", true, 1)
	var base := parts[0].trim_prefix("res://")
	var next: String = plan.mapping.get(base, plan.directories.get(base, base))
	return "res://" + next + ("::" + parts[1] if parts.size() > 1 else "") if path.begins_with("res://") else path

func patch_value(value: Variant) -> Variant:
	if value is Resource:
		patch_resource(value)
	elif value is Array:
		for index in value.size(): value[index] = patch_value(value[index])
	elif value is Dictionary:
		for key in value.keys(): value[key] = patch_value(value[key])
	elif value is String and value.begins_with("res://"):
		return target(value)
	return value

func patch_resource(resource: Resource) -> void:
	if visited.has(resource.get_instance_id()): return
	visited[resource.get_instance_id()] = true
	var next := target(resource.resource_path)
	if next != resource.resource_path:
		resource.take_over_path(next)
		remapped += 1
	for property in resource.get_property_list():
		if not property.usage & PROPERTY_USAGE_STORAGE or property.name in ["resource_path", "resource_name"]: continue
		var value: Variant = resource.get(property.name)
		var updated: Variant = patch_value(value)
		if value is String and value != updated: resource.set(property.name, updated)

func run() -> void:
	plan = JSON.parse_string(FileAccess.get_file_as_string("res://tools/.local/path_normalization_plan.json"))
	if OS.get_cmdline_user_args().has("--canonicalize-uids"):
		var fixed := 0
		var supported := ResourceLoader.get_recognized_extensions_for_type("")
		for old: String in plan.mapping:
			var next := "res://" + str(plan.mapping[old])
			if next.get_extension().to_lower() not in supported: continue
			var uid := ResourceLoader.get_resource_uid(next)
			if uid == ResourceUID.INVALID_ID: continue
			if not ResourceUID.has_id(uid):
				ResourceUID.add_id(uid, next)
				fixed += 1
			elif target(ResourceUID.get_id_path(uid)) == next:
				ResourceUID.set_id(uid, next)
				fixed += 1
		print("CANONICAL UIDS ", fixed)
		quit()
		return
	if not plan.collisions.is_empty(): push_error("Unresolved collisions"); quit(1); return
	for old: String in plan.native:
		var path := "res://" + old
		var resource := ResourceLoader.load(path)
		if resource == null: push_error("Cannot preload " + path); quit(1); return
		originals[old] = {"resource": resource, "uid": ResourceLoader.get_resource_uid(path)}
	print("NATIVE RESOURCES PRELOADED ", originals.size())
	if not OS.get_cmdline_user_args().has("--apply"):
		quit()
		return
	for entry: Dictionary in originals.values(): patch_resource(entry.resource)
	var output: Array = []
	var python := OS.get_environment("NORTHERNLAB_PYTHON")
	if python.is_empty(): python = "python"
	var result := OS.execute(python, [ProjectSettings.globalize_path("res://tools/normalize_project_paths.py"), "--apply-native-stage"], output, true)
	for line in output: print(line)
	if result != 0: push_error("Path application failed; use the recorded backup"); quit(1); return
	for old: String in originals:
		var entry: Dictionary = originals[old]
		var destination := "res://" + str(plan.mapping.get(old, old))
		if ResourceSaver.save(entry.resource, destination) != OK:
			push_error("Cannot save " + destination); quit(1); return
		if int(entry.uid) != ResourceUID.INVALID_ID:
			if ResourceSaver.set_uid(destination, int(entry.uid)) != OK:
				push_error("Cannot preserve UID " + destination); quit(1); return
			if ResourceUID.has_id(int(entry.uid)): ResourceUID.set_id(int(entry.uid), destination)
			else: ResourceUID.add_id(int(entry.uid), destination)
	print("NATIVE RESOURCE PATHS UPDATED ", remapped, " SAVED ", originals.size())
	var completed: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tools/.local/path_normalization_plan.json"))
	completed.native_complete = true
	var file := FileAccess.open("res://tools/.local/path_normalization_plan.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(completed, "\t"))
	file.close()
	quit()
