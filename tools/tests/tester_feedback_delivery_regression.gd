extends SceneTree
var failures := 0
var checks := 0
var paths: Array[String] = []
var folder: String

func _initialize() -> void:
	folder = "user://feedback_delivery_%d" % OS.get_process_id()
	ProjectSettings.set_setting(TesterFeedbackStore.ROOT_SETTING, folder)
	ProjectSettings.set_setting("northern_lab/testing/settings_path", "user://feedback_delivery_settings.json")
	ProjectSettings.set_setting("northern_lab/testing/controls_path", "user://feedback_delivery_controls.cfg")
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	print("PASS " if ok else "FAIL ", label)
	if not ok: failures += 1

func create_form(endpoint: String) -> NorthernTesterFeedback:
	var form := load("res://scenes/ui/tester_feedback.tscn").instantiate() as NorthernTesterFeedback
	form.delivery_config = TesterFeedbackConfig.new()
	form.delivery_config.endpoint = endpoint
	form.delivery_config.timeout_seconds = 5
	root.add_child(form)
	form.title_input.text = "Проверка доставки отчёта"
	form.description.text = "Клиент в кооперативной игре увидел ошибку. GitHub у тестера отсутствует."
	form.steps.text = "1. Нажать E"
	form.context = {"session": {"mode": "coop", "role": "client"}, "base": {"day": 2}}
	var image := Image.create(8, 8, false, Image.FORMAT_RGB8)
	image.fill(Color(0.3, 0.5, 0.1))
	form.set_screenshot(image, true)
	return form

func run() -> void:
	await process_frame
	var url := OS.get_environment("NORTHERNLAB_FEEDBACK_TEST_URL")
	if url.is_empty():
		push_error("Run through tools/tests/run_tester_feedback_delivery.mjs")
		quit(1)
		return
	var form := create_form(url + "/reports")
	check(form.save_button.text == "ОТПРАВИТЬ ОТЧЁТ", "configured endpoint exposes automatic send action")
	await form.save()
	paths.append(form.saved_path)
	var original_path := form.saved_path
	var original_id := form._saved_report_id
	check(form._delivery_pending and form.get_node("%Retry").visible and FileAccess.file_exists(original_path), "lost issue response retains ZIP and offers retry")
	check(form.has_draft() and not form._busy, "failed delivery remains available after form close")
	await form.send_saved_report()
	check(not form._delivery_pending and form.status.text.contains("получен командой"), "retry receives matching durable receipt")
	check(form.saved_path == original_path and form._saved_report_id == original_id, "retry keeps identical report identity and local package")
	check(not form.get_node("%Retry").visible and form.save_button.disabled, "successful receipt disables repeat submission")
	form.queue_free()
	await process_frame
	form = create_form(url + "/reports")
	form.load_saved_report(original_path)
	check(form._saved_report_id == original_id and form.screenshot != null and form.context.session.role == "client", "saved report reload restores ID, screenshot and client diagnostics")
	await form.send_saved_report()
	check(not form._delivery_pending, "report can be resent after form/game reconstruction")
	form.queue_free()
	await process_frame
	form = create_form(url + "/wrong-receipt")
	await form.save()
	paths.append(form.saved_path)
	check(form._delivery_pending and not form.status.text.contains("получен командой"), "HTTP 200 with wrong report ID is not considered delivery")
	form.queue_free()
	await process_frame
	form = create_form(url + "/broken-json")
	await form.save()
	paths.append(form.saved_path)
	check(form._delivery_pending, "HTTP 200 without JSON receipt preserves unsent report")
	form.queue_free()
	await process_frame
	form = create_form(url + "/slow")
	form.delivery_config.timeout_seconds = 0.25
	await form.save()
	paths.append(form.saved_path)
	check(form._delivery_pending and not form._busy and form.get_node("%Retry").visible, "request timeout restores UI and preserves report")
	form.queue_free()
	await process_frame
	var configuration := TesterFeedbackConfig.new()
	configuration.endpoint = "http://external.example/reports"
	check(not configuration.endpoint_error().is_empty(), "unencrypted external receiver rejected")
	for owned_path in paths: DirAccess.remove_absolute(owned_path)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(folder))
	print("FEEDBACK DELIVERY RESULT: ", checks, " checks, ", failures, " failures")
	quit(0 if failures == 0 else 1)
