extends SceneTree
## Read-only integrity audit. Dynamic resource names are covered by gameplay tests.
var failures := 0
var resources := 0
var seen: Dictionary = {}

func _initialize() -> void:
	run.call_deferred()

func inspect(path: String) -> void:
	if seen.has(path):
		return
	seen[path] = true
	if not ResourceLoader.exists(path):
		print("FAIL missing resource: ", path)
		failures += 1
		return
	resources += 1
	for dependency in ResourceLoader.get_dependencies(path):
		var parts := dependency.split("::")
		var target: String = parts[parts.size() - 1]
		if target.begins_with("res://"):
			inspect(target)

func scan(path: String) -> void:
	var directory := DirAccess.open(path)
	if directory == null:
		failures += 1
		return
	for file in directory.get_files():
		if file.get_extension() in ["tscn", "tres", "res"]:
			inspect(path.path_join(file))
	for folder in directory.get_directories():
		scan(path.path_join(folder))

func run() -> void:
	scan("res://scenes")
	scan("res://assets")
	print("AUDITED RESOURCES ", resources)
	print("RESULT FAILURES ", failures)
	quit(0 if failures == 0 else 1)
