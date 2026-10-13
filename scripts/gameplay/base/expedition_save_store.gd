class_name ExpeditionSaveStore
extends RefCounted
## Immutable commits: publishing one verified file commits both progress and history.
const SLOT_COUNT := 3
const HISTORY_LIMIT := 2
const ROOT_SETTING := "northern_lab/testing/save_slots_root"
const DEFAULT_ROOT := "user://expeditions"
const TEST_PATH_SETTING := "northern_lab/testing/base_save_path"
const LEGACY_PATHS_SETTING := "northern_lab/testing/legacy_save_paths"
static var selected_slots: Dictionary = {"solo": 1, "coop": 1}

static func slot(scope: String) -> int:
	return clampi(int(selected_slots.get(scope, 1)), 1, SLOT_COUNT)

static func select(scope: String, number: int) -> void:
	selected_slots[scope] = clampi(number, 1, SLOT_COUNT)

static func directory(scope: String) -> String:
	return str(ProjectSettings.get_setting(ROOT_SETTING, DEFAULT_ROOT)).path_join(
		"%s_%d" % ["coop" if scope == "coop" else "solo", slot(scope)])

static func test_path() -> String:
	return str(ProjectSettings.get_setting(TEST_PATH_SETTING, ""))

static func _files(scope: String) -> Array[String]:
	var files: Array[String] = []
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(directory(scope))):
		return files
	for name in DirAccess.get_files_at(directory(scope)):
		if name.begins_with("commit_") and name.ends_with(".cfg"):
			files.append(name)
	files.sort()
	files.reverse()
	return files

static func _read_file(path: String) -> Dictionary:
	var envelope := ConfigFile.new()
	if envelope.load(path) != OK or int(envelope.get_value("storage", "version", 0)) != 1:
		return {}
	var payload: String = str(envelope.get_value("storage", "payload", ""))
	var history_data: Variant = envelope.get_value("storage", "history", [])
	var anchor_data := str(envelope.get_value("storage", "anchor", ""))
	if not history_data is Array:
		return {}
	if (payload + var_to_str(history_data) + anchor_data).sha256_text() != str(envelope.get_value("storage", "checksum", "")):
		return {}
	var config := ConfigFile.new()
	if config.parse(payload) != OK or not _valid(config):
		return {}
	return {"config": config, "history": envelope.get_value("storage", "history", []),
		"anchor": str(envelope.get_value("storage", "anchor", "")), "path": path}

static func _valid(config: ConfigFile) -> bool:
	return int(config.get_value("save", "version", 0)) == 1 \
		and int(config.get_value("base", "day_index", 0)) in range(1, 6) \
		and config.get_value("inventory", "checkpoint", {}) is Dictionary \
		and config.get_value("base", "maintenance", {}) is Dictionary \
		and config.get_value("base", "containment", {}) is Dictionary

static func read(scope: String) -> Dictionary:
	if not test_path().is_empty():
		var config := ConfigFile.new()
		return {"config": config, "path": test_path(), "history": [], "anchor": ""} \
			if config.load(test_path()) == OK and _valid(config) else {}
	_migrate_legacy(scope)
	var files := _files(scope)
	for index in files.size():
		var data := _read_file(directory(scope).path_join(files[index]))
		if not data.is_empty():
			data["recovered"] = index > 0
			return data
	return {}

static func _migrate_legacy(scope: String) -> void:
	if slot(scope) != 1 or not _files(scope).is_empty() \
		or FileAccess.file_exists(directory(scope).path_join("migration_done.cfg")):
		return
	var legacy := "user://base_gameplay_state_coop.cfg" if scope == "coop" else "user://base_gameplay_state.cfg"
	# Tests of slots never read actual player saves.
	if ProjectSettings.has_setting(ROOT_SETTING) and not ProjectSettings.has_setting(LEGACY_PATHS_SETTING):
		return
	if ProjectSettings.has_setting(LEGACY_PATHS_SETTING):
		legacy = str((ProjectSettings.get_setting(LEGACY_PATHS_SETTING) as Dictionary).get(scope, ""))
		if legacy.is_empty():
			return
	var config := ConfigFile.new()
	if config.load(legacy) == OK and _valid(config):
		_commit(config, scope, {}, "migration")

static func write(config: ConfigFile, scope: String, kind: String = "progress") -> bool:
	if not _valid(config):
		return false
	if not test_path().is_empty():
		return _publish(config.encode_to_text(), test_path())
	return _commit(config, scope, read(scope), kind)

static func _commit(config: ConfigFile, scope: String, previous: Dictionary, kind: String) -> bool:
	var dir := directory(scope)
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir)) != OK:
		return false
	var files := _files(scope)
	var serial := int(files[0].trim_prefix("commit_").trim_suffix(".cfg")) + 1 if not files.is_empty() else 1
	var name := "commit_%012d.cfg" % serial
	var history: Array = previous.get("history", []).duplicate()
	var anchor := str(previous.get("anchor", ""))
	if not anchor.is_empty() and not history.has(anchor):
		history.push_front(anchor)
	while history.size() > HISTORY_LIMIT:
		history.pop_back()
	if kind in ["sleep", "event", "start"]:
		anchor = name
	config.set_value("save", "saved_at", int(Time.get_unix_time_from_system()))
	config.set_value("save", "kind", kind)
	var payload := config.encode_to_text()
	var envelope := ConfigFile.new()
	envelope.set_value("storage", "version", 1)
	envelope.set_value("storage", "payload", payload)
	envelope.set_value("storage", "checksum", (payload + var_to_str(history) + anchor).sha256_text())
	envelope.set_value("storage", "history", history)
	envelope.set_value("storage", "anchor", anchor)
	if not _publish(envelope.encode_to_text(), dir.path_join(name)):
		return false
	# Marker prevents deleted/migrated slots importing legacy progress again.
	var marker := ConfigFile.new()
	marker.set_value("migration", "done", true)
	marker.save(dir.path_join("migration_done.cfg"))
	_prune(scope)
	return true

static func _publish(text: String, path: String) -> bool:
	var temporary := path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(text)
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK or FileAccess.get_file_as_string(temporary) != text:
		return false
	return DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary), ProjectSettings.globalize_path(path)) == OK

static func _prune(scope: String) -> void:
	var files := _files(scope)
	var keep: Array[String] = []
	# Retain two valid commits for recovery, plus their bounded histories.
	for name in files:
		var data := _read_file(directory(scope).path_join(name))
		if data.is_empty():
			continue
		keep.append(name)
		if keep.size() == 2:
			break
	var commits := keep.duplicate()
	for name in commits:
		var data := _read_file(directory(scope).path_join(name))
		for reference in data.history + [data.anchor]:
			if not str(reference).is_empty() and not keep.has(str(reference)):
				keep.append(str(reference))
	for name in files:
		if not keep.has(name):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(directory(scope).path_join(name)))

static func summary(scope: String, data: Dictionary = {}) -> Dictionary:
	if data.is_empty():
		data = read(scope)
	if data.is_empty():
		return {}
	var config: ConfigFile = data.config
	return {"day_index": int(config.get_value("base", "day_index", 1)),
		"phase": int(config.get_value("base", "phase", 0)),
		"fuel_delivered": bool(config.get_value("base", "fuel_delivered", false)),
		"main_breaker_on": bool(config.get_value("base", "main_breaker_on", false)),
		"saved_at": int(config.get_value("save", "saved_at", 0)),
		"kind": str(config.get_value("save", "kind", "migration")),
		"label": str(config.get_value("save", "label", "")),
		"recovered": bool(data.get("recovered", false))}

static func history(scope: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var current := read(scope)
	for name in current.get("history", []):
		if str(name).get_file() != str(name):
			continue
		var data := _read_file(directory(scope).path_join(str(name)))
		if not data.is_empty():
			var item := summary(scope, data)
			item["name"] = str(name)
			result.append(item)
	return result

static func rollback(scope: String, name: String) -> bool:
	var current := read(scope)
	var points: Array = current.get("history", [])
	if name.get_file() != name or not points.has(name):
		return false
	var point := _read_file(directory(scope).path_join(name))
	if point.is_empty():
		return false
	# Discard the future branch, preserving only older available checkpoints.
	var older := points.slice(points.find(name) + 1)
	return _commit(point.config, scope, {"history": older, "anchor": ""}, "rollback")

static func clear(scope: String) -> bool:
	if not test_path().is_empty():
		return not FileAccess.file_exists(test_path()) or DirAccess.remove_absolute(ProjectSettings.globalize_path(test_path())) == OK
	var dir := directory(scope)
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir)) != OK:
		return false
	var marker := ConfigFile.new()
	marker.set_value("migration", "done", true)
	if marker.save(dir.path_join("migration_done.cfg")) != OK:
		return false
	for name in _files(scope):
		if DirAccess.remove_absolute(ProjectSettings.globalize_path(dir.path_join(name))) != OK:
			return false
	return true

static func slot_name(scope: String) -> String:
	var config := ConfigFile.new()
	config.load(directory(scope).path_join("name.cfg"))
	return str(config.get_value("slot", "name", "Экспедиция %d" % slot(scope)))

static func has_any_save(scope: String) -> bool:
	var selected := slot(scope)
	var found := false
	for number in range(1, SLOT_COUNT + 1):
		select(scope, number)
		if not read(scope).is_empty():
			found = true
			break
	select(scope, selected)
	return found

static func rename_slot(scope: String, label: String) -> bool:
	if label.strip_edges().is_empty() or label.length() > 48:
		return false
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory(scope))) != OK:
		return false
	var config := ConfigFile.new()
	config.set_value("slot", "name", label.strip_edges())
	return _publish(config.encode_to_text(), directory(scope).path_join("name.cfg"))
