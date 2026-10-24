class_name JournalReadingStore
extends RefCounted
## Personal reading state, isolated by the host's persistent expedition identity.
const ROOT_SETTING := "northern_lab/testing/journal_reading_root"
var entries: Array = []
var read_fingerprint := ""
var _path := ""

func bind_campaign(identity: String) -> void:
	var directory := str(ProjectSettings.get_setting(ROOT_SETTING, "user://journal_reading"))
	_path = directory.path_join(identity.sha256_text() + ".cfg")
	entries = []
	read_fingerprint = ""
	var file := ConfigFile.new()
	if file.load(_path) != OK: return
	var saved: Variant = file.get_value("journal", "entries", [])
	if saved is Array:
		for record in saved:
			if record is Dictionary and record.has_all(["day", "objective", "tasks"]): entries.append(record)
	read_fingerprint = str(file.get_value("journal", "read", ""))

func fingerprint(record: Dictionary) -> String:
	return ("%d|%s|%s" % [int(record.get("day",1)), record.get("objective",""), record.get("tasks", "")]).sha256_text()

func capture(record: Dictionary) -> bool:
	if not entries.is_empty() and fingerprint(entries.back()) == fingerprint(record): return false
	# Keep the last actually observed state of each day, rather than inventing history.
	entries = entries.filter(func(item): return int(item.day) <= int(record.day))
	if not entries.is_empty() and int(entries.back().day) == int(record.day): entries[-1] = record.duplicate(true)
	else: entries.append(record.duplicate(true))
	_save()
	return true

func unread(record: Dictionary) -> bool:
	return not record.is_empty() and fingerprint(record) != read_fingerprint

func mark_read(record: Dictionary) -> void:
	var next := fingerprint(record)
	if read_fingerprint == next: return
	read_fingerprint = next
	_save()

func _save() -> void:
	if _path.is_empty(): return
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_path.get_base_dir())) != OK: return
	var file := ConfigFile.new()
	file.set_value("journal", "entries", entries)
	file.set_value("journal", "read", read_fingerprint)
	var error := file.save(_path)
	if error != OK: push_warning("Cannot save personal journal reading state: " + error_string(error))
