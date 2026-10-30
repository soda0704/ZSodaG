extends CanvasLayer
## Presentation only; the host's existing bunk/day state owns the night.
@onready var animation: AnimationPlayer = $AnimationPlayer
var _sleeping := false

func set_openness(value: float) -> void:
	animation.stop()
	$Cover.material.set_shader_parameter("openness",clampf(value,0.0,1.0))
	visible=value<0.999

func _ready() -> void:
	hide()
	animation.animation_finished.connect(func(clip: StringName):
		if clip == &"open" and not _sleeping: hide())

func set_sleeping(enabled: bool) -> void:
	if enabled == _sleeping: return
	_sleeping = enabled
	var at := animation.current_animation_length-animation.current_animation_position if animation.is_playing() else -1.0
	show()
	animation.play(&"close" if enabled else &"open")
	if at >= 0.0: animation.seek(at,true)
	animation.advance(0)
