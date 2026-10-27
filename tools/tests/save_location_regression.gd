extends SceneTree
var failures := 0
var checks := 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	print("PASS " if ok else "FAIL ", label)
	if not ok: failures += 1

func run() -> void:
	var parent := ProjectSettings.globalize_path("res://") if OS.has_feature("editor") \
		else OS.get_executable_path().get_base_dir()
	var expected := parent.path_join("saves/expeditions")
	check(ExpeditionSaveStore.default_root() == expected, "save root belongs to project/editor or exported executable")
	check(expected.is_absolute_path(), "save location is independent of launch working directory")
	check(ExpeditionSaveStore.directory("solo") == expected.path_join("solo_1"), "default solo slot uses local saves folder")
	check(ExpeditionSaveStore.directory("coop") == expected.path_join("coop_1"), "default coop slot uses local saves folder")
	# Exercise the real local filesystem without touching ordinary expedition slots.
	var isolated := expected.path_join("location_regression_%d" % OS.get_process_id())
	ProjectSettings.set_setting(ExpeditionSaveStore.ROOT_SETTING, isolated)
	ProjectSettings.set_setting(ExpeditionSaveStore.LEGACY_PATHS_SETTING, {})
	var config := ConfigFile.new()
	config.set_value("save", "version", 1)
	config.set_value("base", "day_index", 4)
	config.set_value("inventory", "checkpoint", {"test_item": "fuel"})
	for scope in ["solo", "coop"]:
		check(ExpeditionSaveStore.write(config, scope, "start"), "write local %s save" % scope)
		var saved := ExpeditionSaveStore.read(scope)
		check(not saved.is_empty() and saved.config.get_value("base", "day_index") == 4,
			"reload local %s save from disk" % scope)
		check(ExpeditionSaveStore.directory(scope).begins_with(isolated + "/"), "test override remains isolated")
		check(ExpeditionSaveStore.clear(scope), "clear isolated %s save" % scope)
		var directory := ExpeditionSaveStore.directory(scope)
		DirAccess.remove_absolute(directory.path_join("migration_done.cfg"))
		DirAccess.remove_absolute(directory)
	DirAccess.remove_absolute(isolated)
	var identity := "save_location_regression_%d" % OS.get_process_id()
	var journal := JournalReadingStore.new()
	journal.bind_campaign(identity)
	var record := {"day": 4, "objective": "Check local save", "tasks": "Read journal"}
	check(journal.capture(record), "journal entry is recorded")
	journal.mark_read(record)
	var journal_path := expected.get_base_dir().path_join("journal_reading").path_join(identity.sha256_text() + ".cfg")
	check(FileAccess.file_exists(journal_path), "journal is stored beside expedition saves")
	var reloaded := JournalReadingStore.new()
	reloaded.bind_campaign(identity)
	check(reloaded.entries == [record] and not reloaded.unread(record), "journal entries and read state survive reload")
	DirAccess.remove_absolute(journal_path)
	var override := isolated.path_join("journal")
	ProjectSettings.set_setting(JournalReadingStore.ROOT_SETTING, override)
	journal.bind_campaign(identity)
	journal.capture(record)
	var override_path := override.path_join(identity.sha256_text() + ".cfg")
	check(FileAccess.file_exists(override_path), "journal test override remains supported")
	DirAccess.remove_absolute(override_path)
	DirAccess.remove_absolute(override)
	DirAccess.remove_absolute(isolated)
	print("SAVE LOCATION CHECKS ", checks, " FAILURES ", failures)
	quit(1 if failures else 0)
