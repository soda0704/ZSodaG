extends AudioStreamPlayer

@export var background_volume_db := -20.0
@export_range(0.1, 10.0) var fade_in_seconds := 4.0

func _ready() -> void:
	volume_linear = 0.0
	_start.call_deferred()

func _start() -> void:
	if not is_inside_tree():
		return
	bus = &"Music"
	volume_linear = 0.0
	play()
	create_tween().tween_property(self, "volume_linear", db_to_linear(background_volume_db), fade_in_seconds).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func _exit_tree() -> void:
	# Release the active decoder before the audio server shuts down, including
	# immediate exits while the menu's fade-in is still running.
	stop()
	stream = null
