extends VBoxContainer
## Centered save selection; only the explicit Continue action can load it.
signal continue_requested(name: String)

var _points: Array[Dictionary] = []
var _latest_name := ""
var _latest_index := -1
var _selected_index := -1
var _appearance: Tween
var _action_motion: Tween
var _selected_name := ""
var _entries: Array = []
const TITLES := ["РУЧНОЕ СОХРАНЕНИЕ", "АВТОСОХРАНЕНИЕ · УТРО ТЕКУЩЕГО ДНЯ", "АВТОСОХРАНЕНИЕ · УТРО ПРЕДЫДУЩЕГО ДНЯ"]

func _ready() -> void:
	_entries = [%Manual, %Morning, %PreviousMorning]
	for index in _entries.size():
		_entries[index].pressed.connect(_select.bind(index))
	%Continue.pressed.connect(func(): continue_requested.emit(_selected_name))

func configure(scope: String, _summary: Dictionary, points: Array[Dictionary], latest_name: String, manual_used: bool) -> void:
	_points = points
	_latest_name = latest_name
	%Mode.text = "КООПЕРАТИВНАЯ ЭКСПЕДИЦИЯ · ЗАПИСИ ХОСТА" if scope == "coop" else "ОДИНОЧНАЯ ЭКСПЕДИЦИЯ"
	_latest_index = -1
	for index in 3:
		if not points[index].is_empty() and str(points[index].name) == latest_name:
			_latest_index = index
	if _latest_index < 0:
		for index in 3:
			if not points[index].is_empty():
				_latest_index = index
				break
	for index in 3:
		var point: Dictionary = points[index]
		var empty := "ИСПОЛЬЗОВАНА" if index == 0 and manual_used else "НЕТ ЗАПИСИ"
		_entries[index].configure(index, TITLES[index], point, index == _latest_index, empty)
	if _latest_index >= 0:
		_select(_latest_index, false)
	else:
		%Continue.text = "НЕТ СОХРАНЕНИЙ"
		%Continue.disabled = true
	%Delete.text = "НАЧАТЬ НОВУЮ ЭКСПЕДИЦИЮ" if scope == "coop" else "УДАЛИТЬ ЭКСПЕДИЦИЮ"
	%Delete.disabled = _latest_index < 0 and scope != "coop"

func _select(index: int, animate: bool = true) -> void:
	if _points[index].is_empty(): return
	var changed := _selected_index != index
	_selected_index = index
	var point: Dictionary = _points[index]
	var latest := index == _latest_index
	# A restored branch may wrap an immutable morning in a newer commit.
	_selected_name = _latest_name if latest else str(point.name)
	for entry_index in _entries.size(): _entries[entry_index].set_selected(entry_index == index)
	%Continue.text = "ПРОДОЛЖИТЬ ЭКСПЕДИЦИЮ" if latest else "ЗАГРУЗИТЬ УТРО ДНЯ %d" % int(point.day_index)
	%Continue.disabled = false
	if animate and changed: _animate_selection()

func animate_in() -> void:
	if _appearance != null and _appearance.is_valid(): _appearance.kill()
	_appearance = create_tween().set_parallel(true)
	for index in _entries.size():
		_entries[index].modulate.a = 0.0
		_appearance.tween_property(_entries[index], "modulate:a", 1.0, .26).set_delay(index * .045).set_custom_interpolator(NorthernMenuStyle.ease)
	%Actions.modulate.a = 0.0
	_appearance.tween_property(%Actions, "modulate:a", 1.0, .32).set_delay(.06).set_custom_interpolator(NorthernMenuStyle.ease)

func _animate_selection() -> void:
	# A quick selection during entrance must never leave other entries half hidden.
	if _appearance != null and _appearance.is_valid():
		_appearance.kill()
		for entry in _entries: entry.modulate.a = 1.0
	if _action_motion != null and _action_motion.is_valid(): _action_motion.kill()
	%Actions.modulate.a = .45
	_action_motion = create_tween()
	_action_motion.tween_property(%Actions, "modulate:a", 1.0, .18).set_custom_interpolator(NorthernMenuStyle.ease)
