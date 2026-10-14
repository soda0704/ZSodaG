extends SceneTree
## Modal layout must remain centered across deferred container sorts and resizing.
var failures: Array[String] = []
var surface: SubViewport
var host: Control

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	print("PASS " if ok else "FAIL ", label)
	if not ok:
		failures.append(label)

func center_error(dialog: NorthernMenuDialog) -> Vector2:
	return dialog.panel.get_global_rect().get_center() - Vector2(surface.size) * 0.5

func run() -> void:
	surface = SubViewport.new()
	surface.size = Vector2i(1920, 1080)
	root.add_child(surface)
	host = Control.new()
	surface.add_child(host)
	NorthernMenuStyle.fill(host)
	await process_frame
	for dimensions in [Vector2i(1920, 1080), Vector2i(1280, 720), Vector2i(2560, 1440)]:
		surface.size = dimensions
		var dialog := preload("res://scenes/ui/menu_dialog.tscn").instantiate()
		host.hide()
		host.add_child(dialog)
		host.show()
		var choices: Array[Dictionary] = [{"label": "Продолжить"}]
		dialog.present("Применение настроек", "Параметры сохранены. ".repeat(12), choices)
		await create_timer(0.05).timeout
		var entering_offset := center_error(dialog)
		check(absf(entering_offset.x) < 2.0 and absf(entering_offset.y) <= 22.0, "entrance starts near the center instead of the top-left corner")
		await create_timer(0.60).timeout
		check(center_error(dialog).length() < 2.0, "notification centers after its first layout at %s" % dimensions)
		check(dialog.actions.get_child(dialog.actions.get_child_count() - 1).text == "НАЗАД", "Back remains the rightmost action")
		dialog.dismiss()
		await create_timer(0.25).timeout
	var moving := preload("res://scenes/ui/menu_dialog.tscn").instantiate()
	host.add_child(moving)
	var save_choices: Array[Dictionary] = [{"label": "Сохранить"}]
	moving.present("Сохранение экспедиции", "Подтвердите действие.", save_choices)
	await create_timer(0.10).timeout
	surface.size = Vector2i(1600, 900)
	moving.get_node("Center/Panel/Content/Message").text = "Уведомление с дополнительными подробностями. ".repeat(30)
	await create_timer(0.60).timeout
	check(center_error(moving).length() < 2.0, "resizing and content growth during entrance preserve centering")
	check(moving.panel.scale.is_equal_approx(Vector2.ONE) and moving.get_node("Center").scale.is_equal_approx(Vector2.ONE), "settled text uses its native scale")
	surface.size = Vector2i(1920, 1080)
	await create_timer(0.10).timeout
	check(center_error(moving).length() < 2.0, "an open notification recenters after another resize")
	moving.dismiss()
	await create_timer(0.25).timeout
	var interrupted := preload("res://scenes/ui/menu_dialog.tscn").instantiate()
	host.add_child(interrupted)
	var invoked := [false]
	var no_choices: Array[Dictionary] = []
	interrupted.present("Выход", "Проверка закрытия.", no_choices)
	interrupted.dismiss(func(): invoked[0] = true)
	await create_timer(0.25).timeout
	check(not is_instance_valid(interrupted) and invoked[0], "immediate dismissal frees the notification and runs its action")
	surface.queue_free()
	await process_frame
	print("MENU DIALOG LAYOUT RESULT ", failures)
	quit(0 if failures.is_empty() else 1)
