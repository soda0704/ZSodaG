extends SceneTree
## Compile every project script without instantiating gameplay nodes or levels.
var failures: Array[String] = []
var checked := 0

func _initialize() -> void:
	_run.call_deferred()

func _scan(path: String) -> void:
	var directory := DirAccess.open(path)
	if directory == null:
		failures.append("Cannot open " + path)
		return
	for file in directory.get_files():
		if file.get_extension() != "gd": continue
		var resource := load(path.path_join(file)) as Script
		checked += 1
		if resource == null or not resource.can_instantiate():
			failures.append(path.path_join(file))
	for folder in directory.get_directories():
		if not folder.begins_with("."): _scan(path.path_join(folder))

func _run() -> void:
	_scan("res://scripts")
	print("AUDITED SCRIPTS ", checked)
	for failure in failures: print("FAIL ", failure)
	print("SCRIPT INTEGRITY FAILURES ", failures.size())
	quit(0 if failures.is_empty() else 1)
