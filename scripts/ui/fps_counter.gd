extends CanvasLayer

const UPDATE_INTERVAL := 0.25
@onready var value_label: Label = $Panel/Value
var _elapsed := 0.0

func _ready() -> void:
	set_enabled(false)

func set_enabled(enabled: bool) -> void:
	visible = enabled
	set_process(enabled)
	_elapsed = 0.0
	if enabled: _update_value()

func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed < UPDATE_INTERVAL: return
	_elapsed = fmod(_elapsed, UPDATE_INTERVAL)
	_update_value()

func _update_value() -> void:
	value_label.text = "FPS: %d" % Engine.get_frames_per_second()
