extends SceneTree
## Read dependency metadata, including binary scenes, without instantiating levels.
var _graph: Dictionary = {}
var _extensions := ResourceLoader.get_recognized_extensions_for_type("")

func _initialize() -> void:
	_run.call_deferred()

func _scan(path: String) -> void:
	var directory := DirAccess.open(path)
	if directory == null:
		push_error("Cannot inspect resource directory: " + path)
		return
	for file in directory.get_files():
		var source := path.path_join(file)
		# Importers register image/model/audio extensions separately from native loaders.
		if file.get_extension() not in _extensions and not FileAccess.file_exists(source + ".import"): continue
		var dependencies: Array[String] = []
		for dependency in ResourceLoader.get_dependencies(source):
			var parts := dependency.split("::")
			dependencies.append(parts[parts.size() - 1])
		_graph[source] = dependencies
	for folder in directory.get_directories():
		if not folder.begins_with("."): _scan(path.path_join(folder))

func _run() -> void:
	for path in ["res://assets", "res://scenes", "res://scripts"]:
		_scan(path)
	DirAccess.make_dir_recursive_absolute("res://tools/.local")
	var file := FileAccess.open("res://tools/.local/runtime_resource_graph.json", FileAccess.WRITE)
	if file == null:
		push_error("Cannot write resource dependency graph")
		quit(1)
		return
	file.store_string(JSON.stringify(_graph))
	file.close()
	print("GRAPH ", _graph.size())
	quit()
