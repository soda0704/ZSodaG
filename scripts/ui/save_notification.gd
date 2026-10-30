extends CanvasLayer
## Readable feedback for explicit saves only; background commits stay silent.
const MIN_SAVING_TIME := 0.7
const RESULT_TIME := 4.0
@onready var icon: AnimatedSprite2D = $Notice/Row/Icon/Animation
@onready var title: Label = $Notice/Row/Text/Title
@onready var detail: Label = $Notice/Row/Text/Detail
var _state: BaseGameplayController
var _elapsed := 0.0
var _finished := false
var _succeeded := false
var _result_visible := false
var _bind_elapsed := 0.0

func _process(delta: float) -> void:
	_bind_elapsed += delta
	if _bind_elapsed >= 0.25:
		_bind_elapsed = 0.0
		_bind_controller()
	if not visible: return
	_elapsed += delta
	if not _result_visible and _finished and _elapsed >= MIN_SAVING_TIME:
		_result_visible = true
		_elapsed = 0.0
		icon.stop()
		icon.visible = false
		title.text = "Игра сохранена" if _succeeded else "Не удалось сохранить игру"
		detail.text = "Можно продолжать экспедицию." if _succeeded else "Предыдущая запись сохранена. Повторите попытку."
	elif _result_visible and _elapsed >= RESULT_TIME:
		hide()

func _bind_controller() -> void:
	var next := get_tree().get_first_node_in_group("base_gameplay_controller") as BaseGameplayController
	if next == _state: return
	if is_instance_valid(_state):
		_state.save_notice_started.disconnect(_on_save_started)
		_state.save_notice_finished.disconnect(_on_save_finished)
	_state = next
	hide()
	icon.stop()
	if _state != null:
		_state.save_notice_started.connect(_on_save_started)
		_state.save_notice_finished.connect(_on_save_finished)

func _on_save_started(_kind: String) -> void:
	_elapsed = 0.0
	_finished = false
	_result_visible = false
	title.text = "Сохранение…"
	detail.text = "Не закрывайте игру."
	icon.show()
	icon.play(&"save")
	icon.frame = 0
	show()

func _on_save_finished(_kind: String, succeeded: bool) -> void:
	_finished = true
	_succeeded = succeeded
