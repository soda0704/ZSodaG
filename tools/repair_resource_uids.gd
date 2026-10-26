extends SceneTree
## Refresh external-reference UID metadata without changing explicit paths or IDs.
var changed := 0
var references := 0
var entry := RegEx.new()
var path_pattern := RegEx.new()
var uid_pattern := RegEx.new()

func _initialize() -> void:
	entry.compile("\\[ext_resource [^\\]\\r\\n]+\\]")
	path_pattern.compile('path="([^"]+)"')
	uid_pattern.compile(' uid="([^"]+)"')
	run.call_deferred()

func scan(folder: String) -> void:
	var directory := DirAccess.open(folder)
	if directory == null: return
	for file in directory.get_files():
		if file.get_extension() not in ["tscn", "tres"]: continue
		var path := folder.path_join(file)
		var text := FileAccess.get_file_as_string(path)
		var matches := entry.search_all(text)
		var original := text
		matches.reverse()
		for match in matches:
			var block: String = match.get_string()
			var resource_path := path_pattern.search(block)
			var old_uid := uid_pattern.search(block)
			if resource_path == null or old_uid == null: continue
			var target: String = resource_path.get_string(1)
			if "::" in target or not FileAccess.file_exists(target): continue
			var uid := ResourceLoader.get_resource_uid(target)
			var replacement := "" if uid == ResourceUID.INVALID_ID else ' uid="' + ResourceUID.id_to_text(uid) + '"'
			if old_uid.get_string() == replacement: continue
			block = block.replace(old_uid.get_string(), replacement)
			text = text.substr(0, match.get_start()) + block + text.substr(match.get_end())
			references += 1
		if text != original:
			var output := FileAccess.open(path, FileAccess.WRITE)
			output.store_string(text)
			output.close()
			changed += 1
	for subfolder in directory.get_directories():
		if not FileAccess.file_exists(folder.path_join(subfolder).path_join(".gdignore")):
			scan(folder.path_join(subfolder))

func run() -> void:
	for folder in ["res://scenes", "res://assets"]: scan(folder)
	print("EXTERNAL UID METADATA UPDATED files=", changed, " references=", references)
	quit()
