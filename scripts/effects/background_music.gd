extends AudioStreamPlayer

@export var background_volume_db := -20.0
@export_range(0.1, 5.0) var fade_in_seconds := 2.0

func _ready() -> void:
	_start.call_deferred()

func _start() -> void:
	bus = &"Music"
	volume_db = -60.0
	play()
	create_tween().tween_property(self, "volume_db", background_volume_db, fade_in_seconds).set_trans(Tween.TRANS_SINE)
