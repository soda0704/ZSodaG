extends SceneTree
var failures := 0
var checks := 0
const TEST_ROOT := "user://expedition_save_slots_regression"
func _initialize() -> void:
	ProjectSettings.set_setting(ExpeditionSaveStore.ROOT_SETTING, TEST_ROOT)
	run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	print("PASS " if ok else "FAIL ", label)
	if not ok: failures += 1
func config(day: int, fuel: float) -> ConfigFile:
	var result := ConfigFile.new()
	result.set_value("save", "version", 1)
	result.set_value("base", "day_index", day)
	result.set_value("base", "fuel_liters", fuel)
	result.set_value("inventory", "checkpoint", {"players": {"steam:123": {"held_item": &"fuse"}}})
	return result
func run() -> void:
	for scope in ["solo", "coop"]:
		for number in range(1, 4):
			ExpeditionSaveStore.select(scope, number)
			check(ExpeditionSaveStore.clear(scope), "clear isolated %s slot %d" % [scope, number])
			check(ExpeditionSaveStore.rename_slot(scope, "Компания %d" % number), "name slot %s/%d" % [scope, number])
			check(ExpeditionSaveStore.write(config(number, number * 5.0), scope, "start"), "write independent %s/%d" % [scope, number])
	for scope in ["solo", "coop"]:
		for number in range(1, 4):
			ExpeditionSaveStore.select(scope, number)
			check(ExpeditionSaveStore.summary(scope).day_index == number, "independent progress %s/%d" % [scope, number])
			check(ExpeditionSaveStore.slot_name(scope) == "Компания %d" % number, "independent name %s/%d" % [scope, number])
	ExpeditionSaveStore.select("coop", 2)
	check(ExpeditionSaveStore.write(config(2, 20), "coop", "sleep"), "sleep publishes checkpoint")
	check(ExpeditionSaveStore.write(config(2, 19), "coop", "manual"), "manual updates current")
	var data := ExpeditionSaveStore.read("coop")
	check(is_equal_approx(data.config.get_value("base", "fuel_liters"), 19.0), "manual current contains current fuel")
	var points := ExpeditionSaveStore.history("coop")
	check(points.size() == 2 and points[0].kind == "sleep", "current morning and previous boundary available for rollback")
	var morning := str(points[0].name)
	for value in 12:
		ExpeditionSaveStore.write(config(2, 18.0 - value), "coop", "manual")
	check(ExpeditionSaveStore.history("coop")[0].name == morning, "manual spam cannot create rewind points")
	check(ExpeditionSaveStore.write(config(3, 12), "coop", "sleep"), "second morning")
	check(ExpeditionSaveStore.write(config(4, 11), "coop", "sleep"), "third morning")
	check(ExpeditionSaveStore.write(config(4, 10), "coop", "progress"), "periodic progress keeps checkpoints")
	points = ExpeditionSaveStore.history("coop")
	check(points.size() == 2 and points[0].day_index == 4 and points[1].day_index == 3, "history limited to latest two boundaries")
	var older := str(points[1].name)
	check(ExpeditionSaveStore.rollback("coop", older), "rollback commits selected snapshot")
	check(ExpeditionSaveStore.summary("coop").day_index == 3, "rollback replaced expedition progress")
	check(ExpeditionSaveStore.history("coop").is_empty(), "rollback discards future points")
	check(not ExpeditionSaveStore.rollback("coop", morning), "discarded branch cannot be loaded")
	check(not ExpeditionSaveStore.rollback("coop", "../solo_1/name.cfg"), "reject traversal and foreign checkpoint")
	ExpeditionSaveStore.write(config(3, 8), "coop", "manual")
	var current := ExpeditionSaveStore.read("coop")
	var file := FileAccess.open(current.path, FileAccess.WRITE)
	file.store_string("broken file")
	file.close()
	data = ExpeditionSaveStore.read("coop")
	check(not data.is_empty() and data.recovered, "corrupt latest file recovers verified previous commit")
	check(data.config.get_value("base", "fuel_liters") == 12, "recovery restores complete rollback state")
	var partial := FileAccess.open(ExpeditionSaveStore.directory("coop").path_join("commit_999999999999.cfg.tmp"), FileAccess.WRITE)
	partial.store_string("unfinished")
	partial.close()
	check(ExpeditionSaveStore.summary("coop").day_index == 3, "interrupted staging write never becomes current")
	check(ExpeditionSaveStore.write(config(3, 7), "coop", "event"), "future event checkpoint API")
	check(ExpeditionSaveStore.write(config(3, 6), "coop", "manual"), "event choice records ordinary progress")
	check(ExpeditionSaveStore.history("coop")[0].kind == "event", "before-event snapshot available")
	var previous := ExpeditionSaveStore.read("coop")
	var names := ExpeditionSaveStore._files("coop")
	var next_number := int(names[0].trim_prefix("commit_").trim_suffix(".cfg")) + 1
	var blocked := ExpeditionSaveStore.directory("coop").path_join("commit_%012d.cfg.tmp" % next_number)
	DirAccess.make_dir_absolute(ProjectSettings.globalize_path(blocked))
	check(not ExpeditionSaveStore.write(config(5, 5), "coop", "manual"), "failed staging write reports failure")
	check(ExpeditionSaveStore.read("coop").path == previous.path, "failed write preserves current and history atomically")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(blocked))
	check(ExpeditionSaveStore.clear("coop") and ExpeditionSaveStore.summary("coop").is_empty(), "clear removes current and histories")
	ExpeditionSaveStore.select("coop", 1)
	check(ExpeditionSaveStore.summary("coop").day_index == 1, "clearing second slot preserves first company")
	ExpeditionSaveStore.select("solo", 2)
	check(ExpeditionSaveStore.summary("solo").day_index == 2, "coop clearing preserves solo")
	var legacy_path := "user://expedition_slot_legacy_regression.cfg"
	config(4, 23).save(legacy_path)
	var original := FileAccess.get_file_as_string(legacy_path)
	ProjectSettings.set_setting(ExpeditionSaveStore.LEGACY_PATHS_SETTING, {"coop": legacy_path})
	ExpeditionSaveStore.select("coop", 1)
	ExpeditionSaveStore.clear("coop")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(ExpeditionSaveStore.directory("coop").path_join("migration_done.cfg")))
	check(ExpeditionSaveStore.summary("coop").day_index == 4, "legacy coop imported into first slot")
	check(FileAccess.get_file_as_string(legacy_path) == original, "migration preserves original legacy file")
	ExpeditionSaveStore.clear("coop")
	check(ExpeditionSaveStore.summary("coop").is_empty(), "cleared slot cannot resurrect from legacy")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(legacy_path))
	print("SAVE SLOT CHECKS ", checks, " FAILURES ", failures)
	quit(1 if failures else 0)
