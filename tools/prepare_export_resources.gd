extends SceneTree
## Select the full dependency closure, including imported fonts and nested themes.
## String-built resource families must be listed here because they have no static edge.
const DYNAMIC_FAMILIES := {
	"res://assets/environments/calibration": "gamma_*.tres",
	"res://assets/environments/snow/expanded_terrain": "terrain3d*.res",
	"res://assets/ui/journal_sketches": "*.png",
}
const DYNAMIC_RESOURCES := [
	"res://scenes/characters/ragdolls/the_monster.tscn",
	"res://scenes/characters/ragdolls/slasher.tscn",
	"res://scenes/characters/ragdolls/smily.tscn",
]
var selected: Dictionary = {}
var visited: Dictionary = {}
var classes: Dictionary = {}
var failures: Array[String] = []
var resource_literal := RegEx.new()
var identifier := RegEx.new()

func _initialize() -> void:
	run.call_deferred()

func select(path: String) -> void:
	selected[path] = true
	visit(path)

func visit(path: String) -> void:
	if visited.has(path): return
	visited[path] = true
	# Windows may resolve the wrong case locally while the exported pack cannot.
	if path != path.to_lower() or path.contains(" "):
		failures.append("Export resource violates lowercase/no-space naming: " + path)
		return
	if not ResourceLoader.exists(path):
		failures.append("Missing export resource: " + path)
		return
	for dependency in ResourceLoader.get_dependencies(path):
		select(dependency.split("::")[-1])
	if path.get_extension() != "gd": return
	var source := FileAccess.get_file_as_string(path)
	# Includes load(variable), menu templates and resource paths stored in constants.
	for literal in resource_literal.search_all(source):
		var target: String = literal.get_string(1)
		if target.get_extension() in ["gd", "tscn", "tres", "res", "glb", "gltf", "gdshader", "png", "svg", "ogg", "ogv"] and FileAccess.file_exists(target):
			select(target)
	# Global script classes also create dependencies without load()/preload().
	for token in identifier.search_all(source):
		var name: String = token.get_string()
		if classes.has(name): select(classes[name])

func run() -> void:
	resource_literal.compile("[\"'](res://[^\"'\\n]+)[\"']")
	identifier.compile("\\b[A-Za-z_][A-Za-z_0-9]*\\b")
	for entry in ProjectSettings.get_global_class_list():
		classes[str(entry["class"])] = str(entry.path)
	select(str(ProjectSettings.get_setting("application/run/main_scene")))
	select("res://default_bus_layout.tres")
	select(str(ProjectSettings.get_setting("application/config/icon")))
	for property in ProjectSettings.get_property_list():
		var key: String = property.name
		if key.begins_with("autoload/"):
			select(str(ProjectSettings.get_setting(key)).trim_prefix("*"))
	for extension in ["res://addons/godotsteam/godotsteam.gdextension", "res://addons/terrain_3d/terrain.gdextension"]:
		select(extension)
	for path in DYNAMIC_RESOURCES: select(path)
	for directory in DYNAMIC_FAMILIES:
		for file in DirAccess.get_files_at(directory):
			if file.match(DYNAMIC_FAMILIES[directory]): select(directory.path_join(file))
	if not failures.is_empty():
		for failure in failures: push_error(failure)
		quit(1)
		return
	var preset := ConfigFile.new()
	if preset.load("res://export_presets.cfg") != OK:
		push_error("Could not load export_presets.cfg")
		quit(1)
		return
	var paths := PackedStringArray(selected.keys())
	paths.sort()
	var changed := false
	for section in preset.get_sections():
		if not section.begins_with("preset.") or section.ends_with(".options"): continue
		if preset.get_value(section, "platform", "") != "Windows Desktop": continue
		changed = changed or preset.get_value(section, "export_filter", "") != "resources" or preset.get_value(section, "export_files", PackedStringArray()) != paths
		preset.set_value(section, "export_filter", "resources")
		preset.set_value(section, "export_files", paths)
	# Avoid rewriting an unchanged preset while an editor/file watcher reads it.
	if changed:
		var result := preset.save("res://export_presets.cfg")
		if result != OK:
			push_error("Could not save export_presets.cfg: " + error_string(result))
			quit(1)
			return
	# External manifest lets the package audit check every dependency after export.
	DirAccess.make_dir_recursive_absolute("res://tools/.local")
	var manifest := FileAccess.open("res://tools/.local/export_resources.json", FileAccess.WRITE)
	if manifest == null:
		push_error("Could not write export audit manifest")
		quit(1)
		return
	var dependencies := PackedStringArray(visited.keys())
	dependencies.sort()
	manifest.store_string(JSON.stringify({"roots": paths, "resources": dependencies}, "  "))
	manifest.close()
	print("EXPORT RESOURCES: ", paths.size(), " selected roots, ", visited.size(), " resources with dependencies")
	quit()
