class_name TesterFeedbackStore
extends RefCounted
## Local reports belong to each tester, including clients; never touch expedition saves.

const ROOT_SETTING := "northern_lab/testing/feedback_root"
const DEFAULT_ROOT := "user://feedback"
const CATEGORIES := ["Ошибка", "Идея", "Впечатления"]
const SEVERITIES := ["Не мешает играть", "Мешает играть", "Блокирует прохождение"]
const TITLE_LIMIT := 120
const TEXT_LIMIT := 8000
const MAX_IMAGE_FILE_BYTES := 20 * 1024 * 1024
const MAX_IMAGE_SIDE := 1920

static func archive_error(path: String) -> String:
	# ZIPReader allocates the whole uncompressed entry. Bound its native allocation
	# using the central directory before reading a ZIP selected from disk.
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > 16 * 1024 * 1024: return "Не удалось открыть пакет отчёта."
	var bytes := file.get_buffer(file.get_length())
	var end := -1
	for offset in range(bytes.size() - 22, maxi(-1, bytes.size() - 65558), -1):
		if bytes.decode_u32(offset) == 0x06054b50:
			end = offset
			break
	if end < 0 or bytes.decode_u16(end + 4) != 0 or bytes.decode_u16(end + 6) != 0: return "Некорректный ZIP отчёта."
	var count := bytes.decode_u16(end + 10)
	var cursor := bytes.decode_u32(end + 16)
	var size := bytes.decode_u32(end + 12)
	if count < 2 or count > 3 or cursor + size > end: return "Некорректный состав отчёта."
	var limits := {"report.json": 128 * 1024, "report.txt": 256 * 1024, "screenshot.png": 16 * 1024 * 1024}
	var names: Array[String] = []
	for index in count:
		if cursor + 46 > end or bytes.decode_u32(cursor) != 0x02014b50: return "Некорректный ZIP отчёта."
		var name_length := bytes.decode_u16(cursor + 28)
		var next := cursor + 46 + name_length + bytes.decode_u16(cursor + 30) + bytes.decode_u16(cursor + 32)
		if next > end: return "Некорректный ZIP отчёта."
		var name := bytes.slice(cursor + 46, cursor + 46 + name_length).get_string_from_utf8()
		if not limits.has(name) or name in names or bytes.decode_u32(cursor + 24) > int(limits[name]) or bytes.decode_u32(cursor + 20) > 16 * 1024 * 1024 or bytes.decode_u16(cursor + 8) & 1:
			return "Неподдерживаемый или слишком большой файл в отчёте."
		names.append(name)
		cursor = next
	return "" if "report.json" in names and "report.txt" in names else "В пакете нет отчёта NorthernLab."

static func png_dimensions(bytes: PackedByteArray) -> Vector2i:
	if bytes.size() < 24 or bytes.slice(0, 8) != PackedByteArray([137, 80, 78, 71, 13, 10, 26, 10]) or bytes.slice(12, 16).get_string_from_ascii() != "IHDR": return Vector2i.ZERO
	return Vector2i((bytes[16] << 24) | (bytes[17] << 16) | (bytes[18] << 8) | bytes[19], (bytes[20] << 24) | (bytes[21] << 16) | (bytes[22] << 8) | bytes[23])

static func directory() -> String:
	return str(ProjectSettings.get_setting(ROOT_SETTING, DEFAULT_ROOT))

static func validate(fields: Dictionary) -> String:
	var title := str(fields.get("title", "")).strip_edges()
	var description := str(fields.get("description", "")).strip_edges()
	if title.is_empty(): return "Добавьте короткий заголовок."
	if title.length() > TITLE_LIMIT: return "Заголовок слишком длинный: максимум 120 символов."
	if description.is_empty(): return "Опишите, что произошло или что вы хотите предложить."
	if description.length() > TEXT_LIMIT or str(fields.get("steps", "")).length() > TEXT_LIMIT:
		return "Текст слишком длинный: максимум 8000 символов в каждом поле."
	if str(fields.get("category", "")) not in CATEGORIES: return "Выберите тип сообщения."
	if str(fields.get("severity", "")) not in SEVERITIES: return "Выберите влияние на игру."
	return ""

static func prepare_image(source: Image) -> Image:
	if source == null or source.is_empty(): return null
	var image := source.duplicate() as Image
	if image.is_compressed() and image.decompress() != OK: return null
	if maxi(image.get_width(), image.get_height()) > MAX_IMAGE_SIDE:
		var factor := float(MAX_IMAGE_SIDE) / maxi(image.get_width(), image.get_height())
		image.resize(maxi(1, int(image.get_width() * factor)), maxi(1, int(image.get_height() * factor)), Image.INTERPOLATE_LANCZOS)
	image.convert(Image.FORMAT_RGB8)
	return image

static func collect_context(tree: SceneTree) -> Dictionary:
	var base := tree.get_first_node_in_group("base_gameplay_controller") as BaseGameplayController
	var player := tree.get_first_node_in_group("local_player") as GamePlayer
	var network := tree.root.get_node_or_null("SteamNetwork")
	var active: bool = network != null and network.has_active_session()
	var context := {
		"captured_at_utc": Time.get_datetime_string_from_system(true) + "Z",
		"game_version": str(ProjectSettings.get_setting("application/config/version", "")),
		"build_identity": network.get_build_identity() if network != null else "",
		"engine": Engine.get_version_info().string,
		"scene": tree.current_scene.scene_file_path if tree.current_scene != null else "",
		"session": {"mode": "coop" if active else "solo", "role": "host" if tree.get_multiplayer().is_server() else "client", "participants": tree.get_multiplayer().get_peers().size() + 1},
		"system": {"os": OS.get_name(), "os_version": OS.get_version(), "renderer": RenderingServer.get_current_rendering_method(), "gpu": RenderingServer.get_video_adapter_name(), "fps": Engine.get_frames_per_second(), "viewport": [tree.root.size.x, tree.root.size.y]},
	}
	if base != null:
		# Deliberately collect gameplay diagnostics, not the full save or account identifiers.
		context["base"] = {"day": base.day_index, "phase": int(base.phase), "quest_stage": int(base.quest_stage), "main_power": base.main_breaker_on, "reserve_installed": base.elevator_backup_installed, "fuel_liters": base.fuel_liters, "wiring_required": bool(base.maintenance.get("wires_required", false)), "wire_links": base.maintenance.get("wire_links", [])}
		if tree.get_multiplayer().is_server():
			context["expedition"] = {"scope": BaseGameplayController.save_scope, "slot": ExpeditionSaveStore.slot(BaseGameplayController.save_scope)}
	if player != null:
		var at := player.global_position
		context["player"] = {"position": [at.x, at.y, at.z], "character_variant": player.character_variant_id, "held_item": str(player.get("_held_item_type")), "driving": player.is_driving(), "sleeping": player.is_sleeping_in_bunk()}
		if player.survival != null:
			context.player["health"] = player.survival.health
			context.player["dead"] = player.survival.dead
	return context

static func save_report(fields: Dictionary, context: Dictionary, screenshot: Image = null) -> Dictionary:
	var issue := validate(fields)
	if not issue.is_empty(): return {"ok": false, "message": issue}
	var folder := ProjectSettings.globalize_path(directory())
	var error := DirAccess.make_dir_recursive_absolute(folder)
	if error != OK: return {"ok": false, "message": "Не удалось создать папку отчётов: " + error_string(error)}
	var stamp := Time.get_datetime_string_from_system(true).replace(":", "-")
	var id := stamp + "_" + Crypto.new().generate_random_bytes(8).hex_encode()
	var path := folder.path_join("NorthernLab_" + id + ".zip")
	var temporary := path + ".tmp"
	var report := fields.duplicate(true)
	report.title = str(report.title).strip_edges()
	report.description = str(report.description).strip_edges()
	report["schema_version"] = 1
	report["report_id"] = id
	report["saved_at_utc"] = Time.get_datetime_string_from_system(true) + "Z"
	report["context"] = context.duplicate(true)
	report["attachment"] = ""
	var image := prepare_image(screenshot)
	var png := PackedByteArray()
	if screenshot != null:
		if image == null: return {"ok": false, "message": "Не удалось подготовить скриншот. Уберите его или сделайте новый."}
		png = image.save_png_to_buffer()
		if png.is_empty(): return {"ok": false, "message": "Не удалось записать скриншот."}
		report.attachment = "screenshot.png"
	var readable := "%s\n%s · %s\n\nОписание\n%s\n\nКак повторить\n%s\n\nКонтекст игры\n%s\n\nЭто локальный отчёт. Передайте этот ZIP команде проекта.\n" % [report.title, report.category, report.severity, report.description, report.get("steps", ""), JSON.stringify(context, "\t")]
	var entries := {"report.json": JSON.stringify(report, "\t").to_utf8_buffer(), "report.txt": readable.to_utf8_buffer()}
	if not png.is_empty(): entries["screenshot.png"] = png
	var writer := ZIPPacker.new()
	error = writer.open(temporary)
	if error != OK: return {"ok": false, "message": "Не удалось записать отчёт: " + error_string(error)}
	for name in entries:
		error = writer.start_file(name)
		if error != OK: break
		error = writer.write_file(entries[name])
		var closed := writer.close_file()
		if error == OK: error = closed
		if error != OK: break
	var closed := writer.close()
	if error == OK: error = closed
	if error == OK:
		var reader := ZIPReader.new()
		error = reader.open(temporary)
		if error == OK:
			var decoded = JSON.parse_string(reader.read_file("report.json").get_string_from_utf8())
			if not decoded is Dictionary or str(decoded.get("report_id", "")) != id or (not png.is_empty() and reader.read_file("screenshot.png") != png): error = ERR_FILE_CORRUPT
			reader.close()
	if error == OK: error = DirAccess.rename_absolute(temporary, path)
	if error != OK:
		DirAccess.remove_absolute(temporary)
		return {"ok": false, "message": "Не удалось сохранить отчёт. Текст остался в форме. " + error_string(error)}
	return {"ok": true, "path": path, "report_id": id}
