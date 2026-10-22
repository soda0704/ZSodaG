extends SceneTree
## Load every gameplay script and inspect saved scene connections without _ready.
## Detached scene instances cannot alter saves or start network/gameplay actions.
var failures := 0
var scripts_checked := 0
var scenes_checked := 0
var connections_checked := 0
var bindings_checked := 0

func _initialize() -> void: run.call_deferred()

func scan_scripts(path: String) -> void:
	var directory := DirAccess.open(path)
	for file in directory.get_files():
		if file.get_extension() != "gd": continue
		var resource := load(path.path_join(file)) as GDScript
		scripts_checked += 1
		if resource == null or not resource.can_instantiate():
			failures += 1
			print("FAIL script cannot compile: ", path.path_join(file))
	for folder in directory.get_directories(): scan_scripts(path.path_join(folder))

func scan_scenes(path: String) -> void:
	var directory := DirAccess.open(path)
	for file in directory.get_files():
		if file.get_extension() != "tscn": continue
		var scene_path := path.path_join(file)
		var scene := load(scene_path) as PackedScene
		if scene == null:
			failures += 1
			print("FAIL scene cannot load: ", scene_path)
			continue
		scenes_checked += 1
		var state := scene.get_state()
		var bindings: Array[NodePath] = []
		for node_index in state.get_node_count():
			for property_index in state.get_node_property_count(node_index):
				if state.get_node_property_name(node_index, property_index) == &"script" and state.get_node_property_value(node_index, property_index) is GDScript:
					bindings.append(state.get_node_path(node_index))
		if state.get_connection_count() == 0 and bindings.is_empty(): continue
		var instance := scene.instantiate()
		for binding in bindings:
			bindings_checked += 1
			var node := instance.get_node_or_null(binding)
			if node == null or node.get_script() == null:
				failures += 1
				print("FAIL orphan script binding: ", scene_path, " ", binding)
		for index in state.get_connection_count():
			connections_checked += 1
			var source := instance.get_node_or_null(state.get_connection_source(index))
			var target := instance.get_node_or_null(state.get_connection_target(index))
			var signal_name := state.get_connection_signal(index)
			var method_name := state.get_connection_method(index)
			if source == null or target == null or not source.has_signal(signal_name) or not target.has_method(method_name):
				failures += 1
				print("FAIL saved connection: ", scene_path, " ", state.get_connection_source(index), ":", signal_name, " -> ", state.get_connection_target(index), ":", method_name)
		instance.free()
	for folder in directory.get_directories(): scan_scenes(path.path_join(folder))

func run() -> void:
	scan_scripts("res://scripts")
	scan_scenes("res://scenes")
	print("SCRIPT INTEGRITY scripts=", scripts_checked, " scenes=", scenes_checked, " bindings=", bindings_checked, " connections=", connections_checked, " failures=", failures)
	quit(0 if failures == 0 else 1)
