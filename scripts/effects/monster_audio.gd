extends AudioStreamPlayer3D
@export var voices: Array[AudioStream] = []
@export var pause_range := Vector2(1.5, 5.0)
@export var initial_delay_range := Vector2(0.15, 4.5)
@export var tail_volume_db := -7.0
var countdown := 0.0
var voice_pitch := 1.0

func _ready() -> void:
	countdown = randf_range(initial_delay_range.x, initial_delay_range.y)
	voice_pitch = randf_range(0.9, 1.1)
	if str(get_parent().get("model_id")) == "the_monster":
		volume_db = tail_volume_db

func _process(delta: float) -> void:
	var actor := get_parent()
	if float(actor.get("health")) <= 0.0:
		stop()
		return
	if playing:
		return
	countdown -= delta
	if countdown > 0.0 or playing:
		return
	countdown = randf_range(pause_range.x, pause_range.y)
	var camera := get_viewport().get_camera_3d()
	if camera == null or camera.global_position.distance_to(global_position) > max_distance:
		return
	var index := 0 if str(actor.get("model_id")) == "the_monster" else 1 if str(actor.get("model_id")) == "slasher" else 2
	if voices.size() > index:
		stream = voices[index]
		pitch_scale = voice_pitch * randf_range(0.98, 1.02)
		play()
