class_name NorthernTesterFeedback
extends PanelContainer

signal back_requested

@export var delivery_config: TesterFeedbackConfig

@onready var title_input: LineEdit = %TitleInput
@onready var category: OptionButton = %Category
@onready var severity: OptionButton = %Severity
@onready var description: TextEdit = %Description
@onready var steps: TextEdit = %Steps
@onready var preview: TextureRect = %Preview
@onready var empty_preview: Label = %EmptyPreview
@onready var status: Label = %Status
@onready var save_button: Button = %Save
@onready var file_dialog: FileDialog = $FileDialog
var context: Dictionary = {}
var screenshot: Image
var saved_path := ""
var _busy := false
var _attachment_dirty := false
var _delivery_pending := false
var _saved_report_id := ""
var _sending := false

func _ready() -> void:
	%Back.pressed.connect(func(): back_requested.emit())
	%Save.pressed.connect(save)
	%ChooseImage.pressed.connect(func(): file_dialog.popup_centered_ratio(0.8))
	file_dialog.file_selected.connect(attach_file)
	%RemoveImage.pressed.connect(func(): set_screenshot(null, true))
	%Capture.pressed.connect(func(): get_node("/root/GameMenu").capture_feedback_screenshot())
	%Folder.pressed.connect(open_folder)
	%Retry.pressed.connect(send_saved_report)
	%LoadReport.pressed.connect(func():
		if has_draft():
			get_node("/root/GameMenu").confirm("Загрузить сохранённый отчёт?", "Текущий черновик будет заменён выбранным отчётом.", [{"label": "Выбрать отчёт", "action": choose_saved_report}])
		else:
			choose_saved_report())
	$ReportDialog.file_selected.connect(load_saved_report)
	%CopyPath.pressed.connect(func(): DisplayServer.clipboard_set(saved_path))
	title_input.text_changed.connect(func(_text): _edited())
	description.text_changed.connect(_edited)
	steps.text_changed.connect(_edited)
	category.item_selected.connect(func(_index):
		severity.disabled = category.selected != 0
		_edited())
	severity.item_selected.connect(func(_index): _edited())
	_update_preview()
	_edited()
	if delivery_config != null and not delivery_config.endpoint.is_empty():
		save_button.text = "ОТПРАВИТЬ ОТЧЁТ"
		%Delivery.text = "Отчёт отправится команде автоматически.\nGitHub и вход в аккаунт не нужны. Игра продолжает идти."
	else:
		%Delivery.text = "Автоотправка ещё не подключена. Сохраните отчёт и передайте ZIP команде. Игра продолжает идти."

func has_draft() -> bool:
	return _busy or _delivery_pending or (saved_path.is_empty() and (not title_input.text.is_empty() or not description.text.is_empty() or not steps.text.is_empty() or _attachment_dirty))

func begin(new_context: Dictionary, image: Image) -> void:
	context = new_context.duplicate(true)
	set_screenshot(image)
	var base: Dictionary = context.get("base", {})
	var session: Dictionary = context.get("session", {})
	%Context.text = "%s%s\n%s\nПозиция и состояние игры будут приложены автоматически." % ["День %d" % int(base.day) if base.has("day") else "Главное меню", " · " + ("Хост" if session.get("role", "host") == "host" else "Участник") if session.get("mode", "solo") == "coop" else "", "Кооператив" if session.get("mode", "solo") == "coop" else "Одиночная игра"]

func fields() -> Dictionary:
	return {"title": title_input.text, "category": category.get_item_text(category.selected), "severity": severity.get_item_text(severity.selected) if category.selected == 0 else TesterFeedbackStore.SEVERITIES[0], "description": description.text, "steps": steps.text}

func _edited() -> void:
	saved_path = ""
	_delivery_pending = false
	%Retry.hide()
	status.text = ""
	%CopyPath.disabled = true
	save_button.disabled = _busy or not TesterFeedbackStore.validate(fields()).is_empty()
	%Counter.text = "%d / %d" % [description.text.length(), TesterFeedbackStore.TEXT_LIMIT]

func set_screenshot(image: Image, edited: bool = false) -> void:
	screenshot = TesterFeedbackStore.prepare_image(image)
	_update_preview()
	if edited:
		_attachment_dirty = true
		_edited()

func _update_preview() -> void:
	preview.texture = ImageTexture.create_from_image(screenshot) if screenshot != null else null
	empty_preview.visible = screenshot == null
	%RemoveImage.disabled = screenshot == null or _busy
	%Attachment.text = "СКРИНШОТ · %d × %d" % [screenshot.get_width(), screenshot.get_height()] if screenshot != null else "СКРИНШОТ · НЕОБЯЗАТЕЛЬНО"

func attach_file(path: String) -> void:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		status.text = "Не удалось открыть изображение."
		return
	if file.get_length() > TesterFeedbackStore.MAX_IMAGE_FILE_BYTES:
		status.text = "Выберите изображение размером до 20 МБ."
		return
	var bytes := file.get_buffer(file.get_length())
	var image := Image.new()
	var extension := path.get_extension().to_lower()
	if extension == "png":
		var dimensions := TesterFeedbackStore.png_dimensions(bytes)
		if dimensions.x <= 0 or dimensions.y <= 0 or dimensions.x > 8192 or dimensions.y > 8192 or dimensions.x * dimensions.y > 32 * 1024 * 1024:
			status.text = "Не удалось прочитать изображение. Выберите PNG до 8192 пикселей по стороне."
			return
	var error := image.load_png_from_buffer(bytes) if extension == "png" else image.load_jpg_from_buffer(bytes) if extension in ["jpg", "jpeg"] else ERR_FILE_UNRECOGNIZED
	if error != OK or image.is_empty():
		status.text = "Не удалось прочитать изображение. Нужен PNG или JPG."
		return
	set_screenshot(image, true)

func set_busy(value: bool) -> void:
	_busy = value
	for button in [%Back, %Capture, %ChooseImage, %Retry, %LoadReport]: button.disabled = value
	title_input.editable = not value
	description.editable = not value
	steps.editable = not value
	category.disabled = value
	severity.disabled = value or category.selected != 0
	save_button.disabled = value or not saved_path.is_empty() or not TesterFeedbackStore.validate(fields()).is_empty()
	%RemoveImage.disabled = value or screenshot == null

func save() -> void:
	if _busy or not saved_path.is_empty(): return
	var issue := TesterFeedbackStore.validate(fields())
	if not issue.is_empty():
		status.text = issue
		return
	set_busy(true)
	status.text = "Сохраняем отчёт…"
	await get_tree().process_frame
	var result := TesterFeedbackStore.save_report(fields(), context, screenshot)
	if result.ok:
		saved_path = str(result.path)
		_saved_report_id = str(result.report_id)
		_attachment_dirty = false
		status.text = "Отчёт сохранён. Передайте ZIP команде проекта."
		%CopyPath.disabled = false
	else:
		status.text = str(result.message)
	set_busy(false)
	if result.ok and delivery_config != null and not delivery_config.endpoint.is_empty():
		await send_saved_report()

func send_saved_report() -> void:
	if _busy or saved_path.is_empty() or delivery_config == null: return
	var problem := delivery_config.endpoint_error()
	if not problem.is_empty():
		_delivery_pending = true
		status.text = problem
		%Retry.show()
		return
	problem = TesterFeedbackStore.archive_error(saved_path)
	if not problem.is_empty():
		status.text = problem
		return
	var reader := ZIPReader.new()
	if reader.open(saved_path) != OK:
		status.text = "Не удалось открыть сохранённый пакет. Отчёт можно сохранить заново после изменения текста."
		return
	var boundary := "NorthernLab" + Crypto.new().generate_random_bytes(12).hex_encode()
	var body := PackedByteArray()
	for name in ["report.json", "screenshot.png"]:
		if not reader.file_exists(name): continue
		var part_name := "report" if name == "report.json" else "screenshot"
		var content_type := "application/json" if name == "report.json" else "image/png"
		body.append_array(("--%s\r\nContent-Disposition: form-data; name=\"%s\"; filename=\"%s\"\r\nContent-Type: %s\r\n\r\n" % [boundary, part_name, name, content_type]).to_utf8_buffer())
		body.append_array(reader.read_file(name))
		body.append_array("\r\n".to_utf8_buffer())
	reader.close()
	body.append_array(("--%s--\r\n" % boundary).to_utf8_buffer())
	_delivery_pending = true
	_sending = true
	set_busy(true)
	status.text = "Отправляем отчёт команде…"
	var upload: HTTPRequest = $Upload
	upload.timeout = delivery_config.timeout_seconds
	var error := upload.request_raw(delivery_config.endpoint, PackedStringArray(["Content-Type: multipart/form-data; boundary=" + boundary]), HTTPClient.METHOD_POST, body)
	if error == OK:
		var response: Array = await upload.request_completed
		var receipt = null
		var json := JSON.new()
		if int(response[0]) == HTTPRequest.RESULT_SUCCESS and int(response[1]) >= 200 and int(response[1]) < 300 and json.parse((response[3] as PackedByteArray).get_string_from_utf8()) == OK:
			receipt = json.data
		if int(response[0]) == HTTPRequest.RESULT_SUCCESS and int(response[1]) >= 200 and int(response[1]) < 300 and receipt is Dictionary and bool(receipt.get("ok", false)) and str(receipt.get("report_id", "")) == _saved_report_id:
			_delivery_pending = false
			status.text = "Отчёт получен командой. Спасибо! Копия сохранена на этом компьютере."
		else:
			status.text = "Не удалось отправить. Отчёт сохранён: повторите отправку или передайте ZIP команде."
	else:
		status.text = "Не удалось начать отправку. Отчёт сохранён на этом компьютере."
	_sending = false
	%Retry.visible = _delivery_pending
	set_busy(false)

func open_folder() -> void:
	var folder := ProjectSettings.globalize_path(TesterFeedbackStore.directory())
	var error := DirAccess.make_dir_recursive_absolute(folder)
	if error == OK: error = OS.shell_open(folder)
	if error != OK: status.text = "Не удалось открыть папку: " + error_string(error)

func request_back() -> void:
	if not _busy and not file_dialog.visible and not $ReportDialog.visible: back_requested.emit()

func choose_saved_report() -> void:
	$ReportDialog.current_dir = ProjectSettings.globalize_path(TesterFeedbackStore.directory())
	$ReportDialog.popup_centered_ratio(0.8)

func load_saved_report(path: String) -> void:
	var problem := TesterFeedbackStore.archive_error(path)
	if not problem.is_empty():
		status.text = problem
		return
	var reader := ZIPReader.new()
	if reader.open(path) != OK:
		status.text = "Не удалось открыть пакет отчёта."
		return
	# Archive metadata is local untrusted input; inspect sizes before decompression.
	# Only read the two files we own; never extract paths from an archive.
	var report_bytes := reader.read_file("report.json")
	if report_bytes.size() > 128 * 1024:
		reader.close()
		status.text = "Слишком большой JSON отчёта."
		return
	var json := JSON.new()
	var report = json.data if json.parse(report_bytes.get_string_from_utf8()) == OK else null
	if not report is Dictionary or not TesterFeedbackStore.validate(report).is_empty() or int(report.get("schema_version", 0)) != 1 or not report.get("context", null) is Dictionary or str(report.get("report_id", "")).is_empty():
		reader.close()
		status.text = "В архиве нет корректного отчёта NorthernLab."
		return
	var image: Image = null
	if report.get("attachment", "") == "screenshot.png":
		var png := reader.read_file("screenshot.png")
		var dimensions := TesterFeedbackStore.png_dimensions(png)
		if dimensions.x <= 0 or dimensions.y <= 0 or dimensions.x > 1920 or dimensions.y > 1920:
			reader.close()
			status.text = "В отчёте некорректный скриншот."
			return
		image = Image.new()
		if image.load_png_from_buffer(png) != OK:
			reader.close()
			status.text = "В сохранённом отчёте повреждён скриншот."
			return
	reader.close()
	title_input.text = report.title
	description.text = report.description
	steps.text = report.get("steps", "")
	category.select(TesterFeedbackStore.CATEGORIES.find(report.category))
	severity.select(TesterFeedbackStore.SEVERITIES.find(report.severity))
	begin(report.context, image)
	_edited()
	saved_path = path
	_saved_report_id = report.report_id
	_delivery_pending = true
	status.text = "Сохранённый отчёт загружен. Можно повторить отправку."
	%CopyPath.disabled = false
	%Retry.show()
	set_busy(false)
