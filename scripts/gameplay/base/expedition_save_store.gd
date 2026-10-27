class_name ExpeditionSaveStore
extends RefCounted
## One daily manual save and the mornings of the current and previous day.
const MAX_DAY_INDEX := 999
const SLOT_COUNT := 3
const HISTORY_LIMIT := 2
const ROOT_SETTING := "northern_lab/testing/save_slots_root"
const DEFAULT_ROOT := "saves/expeditions"
const TEST_PATH_SETTING := "northern_lab/testing/base_save_path"
const LEGACY_PATHS_SETTING := "northern_lab/testing/legacy_save_paths"
static var selected_slots: Dictionary = {"solo": 1, "coop": 1}

static func slot(scope: String) -> int:
	return clampi(int(selected_slots.get(scope, 1)), 1, SLOT_COUNT)

static func select(scope: String, number: int) -> void:
	selected_slots[scope] = clampi(number, 1, SLOT_COUNT)

static func default_root() -> String:
	# In the editor the executable belongs to Godot, not to this project.
	var base_dir := ProjectSettings.globalize_path("res://") if OS.has_feature("editor") \
		else OS.get_executable_path().get_base_dir()
	return base_dir.path_join(DEFAULT_ROOT)

static func directory(scope: String) -> String:
	return str(ProjectSettings.get_setting(ROOT_SETTING, default_root())).path_join(
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
		and int(config.get_value("base", "day_index", 0)) in range(1, MAX_DAY_INDEX + 1) \
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

static func write(config: ConfigFile, scope: String, kind: String = "manual", debug_replace_future: bool = false) -> bool:
	if not _valid(config) or kind not in ["manual", "start", "sleep"]:
		return false
	if debug_replace_future and kind != "sleep": return false
	if not test_path().is_empty():
		var previous := read(scope)
		if not _prepare_write(config, previous, kind, debug_replace_future): return false
		return _publish(config.encode_to_text(), test_path())
	return _commit(config, scope, read(scope), kind, debug_replace_future)

static func _prepare_write(config: ConfigFile, previous: Dictionary, kind: String, debug_replace_future: bool = false) -> bool:
	var day := int(config.get_value("base", "day_index", 1))
	if config.has_section_key("save", "discard_future"): config.erase_section_key("save", "discard_future")
	if kind == "manual":
		if not previous.is_empty() and int(previous.config.get_value("base", "manual_save_day", 0)) == day:
			return false
		config.set_value("base", "manual_save_day", day)
	elif kind in ["start", "sleep", "migration"]:
		if not previous.is_empty():
			if kind == "start": return false
			if int(previous.config.get_value("base", "day_index", 1)) >= day:
				if not debug_replace_future or kind != "sleep": return false
				config.set_value("save", "discard_future", true)
		config.set_value("base", "manual_save_day", 0)
	config.set_value("save", "saved_at", int(Time.get_unix_time_from_system()))
	config.set_value("save", "kind", kind)
	return true

static func _morning_names(scope: String, data: Dictionary, day: int) -> Array[String]:
	var result: Array[String] = []
	var days: Array[int] = []
	var candidates: Array = [data.get("anchor", "")] + data.get("history", [])
	if not data.is_empty() and str(data.config.get_value("save", "kind", "")) in ["start", "sleep", "migration"]:
		candidates.push_front(str(data.get("path", "")).get_file())
	for candidate in candidates:
		var name := str(candidate)
		if name.is_empty() or name.get_file() != name: continue
		var point := _read_file(directory(scope).path_join(name))
		if point.is_empty(): continue
		if str(point.config.get_value("save", "kind", "")) not in ["sleep", "start", "migration"]: continue
		var point_day := int(point.config.get_value("base", "day_index", 0))
		if point_day in [day, day - 1] and not days.has(point_day):
			result.append(name)
			days.append(point_day)
	return result

static func _commit(config: ConfigFile, scope: String, previous: Dictionary, kind: String, debug_replace_future: bool = false) -> bool:
	if not _prepare_write(config, previous, kind, debug_replace_future): return false
	var dir := directory(scope)
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir)) != OK:
		return false
	var files := _files(scope)
	var serial := int(files[0].trim_prefix("commit_").trim_suffix(".cfg")) + 1 if not files.is_empty() else 1
	var name := "commit_%012d.cfg" % serial
	var day := int(config.get_value("base", "day_index", 1))
	var history := _morning_names(scope, previous, day)
	if kind in ["sleep", "start", "migration"]:
		history = history.filter(func(morning): return int(_read_file(dir.path_join(morning)).config.get_value("base", "day_index", 0)) == day - 1)
		history.push_front(name)
	while history.size() > HISTORY_LIMIT: history.pop_back()
	var anchor := ""
	for morning in history:
		if morning == name or int(_read_file(dir.path_join(morning)).config.get_value("base", "day_index", 0)) == day:
			anchor = morning
			break
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
	var latest := _read_file(directory(scope).path_join(files[0])) if not files.is_empty() else {}
	var restoring := not latest.is_empty() and (str(latest.config.get_value("save", "kind", "")) == "restore" or bool(latest.config.get_value("save", "discard_future", false)))
	# An abandoned future must not become the recovery fallback after a rollback.
	if restoring:
		keep.append(files[0])
	# Otherwise retain two valid commits for recovery, plus their bounded histories.
	for name in files:
		if restoring: break
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
	if current.is_empty(): return result
	var day := int(current.config.get_value("base", "day_index", 1))
	for name in _morning_names(scope, current, day):
		if str(name).get_file() != str(name):
			continue
		var data := _read_file(directory(scope).path_join(str(name)))
		if not data.is_empty():
			var item := summary(scope, data)
			item["name"] = str(name)
			result.append(item)
	return result

static func checkpoints(scope: String) -> Array[Dictionary]:
	var current := read(scope)
	var result: Array[Dictionary] = [{}, {}, {}]
	if current.is_empty(): return result
	var day := int(current.config.get_value("base", "day_index", 1))
	if str(current.config.get_value("save", "kind", "")) == "manual":
		result[0] = summary(scope, current)
		result[0]["name"] = str(current.path).get_file()
	for point in history(scope):
		if int(point.day_index) == day: result[1] = point
		elif int(point.day_index) == day - 1: result[2] = point
	return result

static func rollback(scope: String, name: String) -> bool:
	var current := read(scope)
	var points: Array = current.get("history", [])
	if name.get_file() != name or not points.has(name):
		return false
	var point := _read_file(directory(scope).path_join(name))
	if point.is_empty():
		return false
	# Replaying this morning does not refund a manual save already used today.
	var day := int(point.config.get_value("base", "day_index", 1))
	if int(current.config.get_value("base", "manual_save_day", 0)) == day:
		point.config.set_value("base", "manual_save_day", day)
	# Only the two currently offered mornings may survive the branch change.
	# Old envelopes can reference technical backups that are no longer selectable.
	var branch := {"config": point.config, "path": point.path,
		"history": current.get("history", []), "anchor": name}
	return _commit(point.config, scope, branch, "restore")

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

static func select_existing(scope: String) -> void:
	# The simplified menu has no slot picker. Keep the active save, or find the
	# newest valid one left by the previous UI without moving/deleting any files.
	if not read(scope).is_empty(): return
	var chosen := slot(scope)
	var newest := -1
	for number in range(1, SLOT_COUNT + 1):
		select(scope, number)
		var data := summary(scope)
		if not data.is_empty() and int(data.get("saved_at", 0)) > newest:
			chosen = number
			newest = int(data.get("saved_at", 0))
	select(scope, chosen)

static func rename_slot(scope: String, label: String) -> bool:
	if label.strip_edges().is_empty() or label.length() > 48:
		return false
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory(scope))) != OK:
		return false
	var config := ConfigFile.new()
	config.set_value("slot", "name", label.strip_edges())
	return _publish(config.encode_to_text(), directory(scope).path_join("name.cfg"))
