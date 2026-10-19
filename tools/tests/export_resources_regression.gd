extends SceneTree
## Run against the exported EXE using --main-pack and an external audit manifest.
var failures: Array[String] = []

func _initialize() -> void:
	ProjectSettings.set_setting("northern_lab/testing/settings_path", "user://export_resources_%d.json" % OS.get_process_id())
	ProjectSettings.set_setting("northern_lab/testing/controls_path", "user://export_resources_%d.cfg" % OS.get_process_id())
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	print("PASS " if ok else "FAIL ", label)
	if not ok: failures.append(label)

func run() -> void:
	check(FileAccess.file_exists("res://project.binary"), "audit runs against the exported package")
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(OS.get_environment("NORTHERNLAB_EXPORT_MANIFEST")))
	if not manifest is Dictionary:
		check(false, "export audit manifest is readable")
		quit(1)
		return
	var missing: Array[String] = []
	for path in manifest.resources:
		if not ResourceLoader.exists(path): missing.append(path)
	check(missing.is_empty(), "all %d reachable resources are packaged: %s" % [manifest.resources.size(), missing])
	var unloadable: Array[String] = []
	for path in manifest.roots:
		if load(path) == null: unloadable.append(path)
	check(unloadable.is_empty(), "all %d export roots load with their dependencies: %s" % [manifest.roots.size(), unloadable])
	for path in ["res://assets/models/weapons/pistol.glb", "res://assets/characters/tactical_a/scene.gltf", "res://scenes/tests", "res://tools", "res://Blender", "res://assets/models/modular_scifi_megakit/models"]:
		check(not ResourceLoader.exists(path) and not DirAccess.dir_exists_absolute(path), "unused/source content is absent: " + path)
	for path in ["res://network_build.cfg", "res://game_actions_480.vdf", "res://assets/models/ITEM_MODEL_CREDITS.md"]:
		check(FileAccess.file_exists(path), "runtime configuration or attribution is packaged: " + path)
	print("EXPORT RESOURCES RESULT ", failures)
	quit(0 if failures.is_empty() else 1)
