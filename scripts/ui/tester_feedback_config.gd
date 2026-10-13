class_name TesterFeedbackConfig
extends Resource
## Only the public receiver URL belongs in a game build. GitHub credentials stay server-side.
@export var endpoint := ""
@export_range(5.0, 90.0, 1.0) var timeout_seconds := 45.0

func endpoint_error() -> String:
	if endpoint.is_empty(): return "Автоматическая отправка ещё не подключена. Отчёт сохранён локально."
	if endpoint.begins_with("https://"): return ""
	if OS.has_feature("editor") and (endpoint.begins_with("http://127.0.0.1:") or endpoint.begins_with("http://localhost:")): return ""
	return "Для отправки нужен HTTPS-адрес сервиса приёма. Отчёт сохранён локально."
