extends CanvasLayer

const COLORS := [Color("ff805f"), Color("69d5ec"), Color("f5ce6c"), Color("b4a0f5")]
const SYMBOLS := ["I", "II", "III", "IV"]
var controller: Node
var board: Control
var status: Label
var selected := -1
var left_buttons: Array[Button] = []
var right_buttons: Array[Button] = []
var _closing := false
var close_button: Button
var _opening_grace := 0.4

func _ready() -> void:
	add_to_group("wiring_ui")
	layer = 110
	var journal := get_node_or_null("/root/QuestJournal")
	if journal != null:
		journal.force_close()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var shade := ColorRect.new()
	shade.color = Color(0.015, 0.025, 0.035, 0.93)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	board = Control.new()
	board.size = Vector2(900, 620)
	add_child(board)
	board.draw.connect(_draw_board)
	_label("NORTH / ELECTRICAL SYSTEMS", Vector2(40, 28), 17, Color("72b8c5"))
	_label("ВОССТАНОВЛЕНИЕ ЦЕПЕЙ", Vector2(40, 65), 30, Color("e8f0ec"))
	_label("Выберите провод слева, затем клемму с тем же номером справа.", Vector2(40, 112), 18, Color("a5b8c2"))
	_label("ИСТОЧНИК", Vector2(55, 167), 15, Color("829da8"))
	_label("РАСПРЕДЕЛИТЕЛЬ", Vector2(655, 167), 15, Color("829da8"))
	var order: Array = controller.maintenance.get("wire_order", [2, 0, 3, 1])
	for i in 4:
		var left := _terminal(i, i, false)
		left.pressed.connect(_select.bind(i))
		left_buttons.append(left)
		var identity := order.find(i)
		var right := _terminal(i, identity, true)
		right.pressed.connect(_connect.bind(i))
		right_buttons.append(right)
	status = _label("Питание отключено · 0 / 4 цепи", Vector2(40, 515), 20, Color("f5ce6c"))
	var close := Button.new()
	close_button = close
	close.text = "Закрыть · Esc / ○"
	close.position = Vector2(640, 557)
	close.size = Vector2(220, 42)
	board.add_child(close)
	close.pressed.connect(_close)
	controller.snapshot_changed.connect(_refresh)
	_refresh({})
	left_buttons[0].grab_focus()

func _label(text: String, at: Vector2, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.position = at
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	board.add_child(label)
	return label

func _terminal(row: int, identity: int, right: bool) -> Button:
	var button := Button.new()
	button.text = "%s    %s" % ["OUT" if right else "IN", SYMBOLS[identity]]
	button.position = Vector2(665 if right else 45, 205 + row * 70)
	button.size = Vector2(190, 48)
	button.add_theme_font_size_override("font_size", 21)
	button.add_theme_color_override("font_color", COLORS[identity])
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color("182932")
	normal.border_color = COLORS[identity].darkened(0.4)
	normal.set_border_width_all(2)
	normal.set_corner_radius_all(6)
	button.add_theme_stylebox_override("normal", normal)
	var focus := normal.duplicate() as StyleBoxFlat
	focus.border_color = Color.WHITE
	button.add_theme_stylebox_override("focus", focus)
	board.add_child(button)
	return button

func _process(delta: float) -> void:
	_opening_grace = maxf(0.0, _opening_grace - delta)
	var viewport := get_viewport().get_visible_rect().size
	var scale_value := minf(1.0, minf((viewport.x - 32) / 900.0, (viewport.y - 32) / 620.0))
	board.scale = Vector2.ONE * scale_value
	board.position = (viewport - board.size * scale_value) * 0.5
	if selected >= 0:
		board.queue_redraw()
	var player := get_tree().get_first_node_in_group("local_player")
	var breaker := get_tree().get_first_node_in_group("main_breaker") as Node3D
	if player == null or player.survival.dead or breaker == null or (_opening_grace <= 0.0 and player.global_position.distance_to(breaker.global_position) > 4.5):
		_close()

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		_close()

func _select(index: int) -> void:
	selected = index
	status.text = "Цепь %s · выберите соответствующую клемму" % SYMBOLS[index]
	board.queue_redraw()

func _connect(index: int) -> void:
	if selected < 0:
		status.text = "Сначала выберите провод слева."
		return
	var order: Array = controller.maintenance.get("wire_order", [])
	if order[selected] != index:
		status.text = "Контакты не совпадают · проверьте номер цепи"
		return
	if multiplayer.is_server():
		controller.connect_wire_authoritative(multiplayer.get_unique_id(), selected, index)
	else:
		controller.request_wire.rpc_id(1, selected, index)
	selected = -1
	board.queue_redraw()

func _refresh(_snapshot: Dictionary) -> void:
	var links: Array = controller.maintenance.get("wire_links", [])
	var order: Array = controller.maintenance.get("wire_order", [])
	for i in 4:
		left_buttons[i].disabled = links.has(i)
		right_buttons[i].disabled = links.has(order.find(i))
	status.text = "Питание отключено · %d / 4 цепи" % links.size()
	if links.size() == 4:
		status.text = "ЦЕПИ ВОССТАНОВЛЕНЫ · закройте панель и включите щит"
		close_button.grab_focus()
	var focused := get_viewport().gui_get_focus_owner()
	if focused is Button and focused.disabled:
		for button in left_buttons:
			if not button.disabled:
				button.grab_focus()
				break
	board.queue_redraw()

func _draw_board() -> void:
	board.draw_style_box(_background(), Rect2(Vector2.ZERO, board.size))
	for x in range(265, 650, 28):
		for y in range(204, 477, 28):
			board.draw_circle(Vector2(x, y), 1.2, Color("273c46"))
	var order: Array = controller.maintenance.get("wire_order", [])
	var links: Array = controller.maintenance.get("wire_links", [])
	for i in 4:
		var start := Vector2(237, 229 + i * 70)
		var end := Vector2(663, 229 + int(order[i]) * 70) if links.has(i) else start + Vector2(65, 0)
		if selected == i and not links.has(i):
			end = board.get_local_mouse_position().clamp(Vector2(260, 205), Vector2(640, 485))
		var curve := Curve2D.new()
		curve.add_point(start, Vector2.ZERO, Vector2(110, 0))
		curve.add_point(end, Vector2(-110, 0), Vector2.ZERO)
		var points := curve.get_baked_points()
		board.draw_polyline(points, Color(0, 0, 0, 0.7), 11, true)
		board.draw_polyline(points, COLORS[i].darkened(0.3), 7, true)
		board.draw_polyline(points, COLORS[i], 3, true)
		board.draw_circle(end, 5, COLORS[i])
	for at in [Vector2(17, 17), Vector2(883, 17), Vector2(17, 603), Vector2(883, 603)]:
		board.draw_circle(at, 4, Color("617580"))

func _background() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color("101b23")
	box.border_color = Color("435962")
	box.set_border_width_all(2)
	box.set_corner_radius_all(14)
	return box

func _close() -> void:
	if _closing:
		return
	_closing = true
	remove_from_group("wiring_ui")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	queue_free()
