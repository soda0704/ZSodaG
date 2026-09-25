extends AudioStreamPlayer3D
@export var voices: Array[AudioStream] = []
var countdown := 3.0
func _process(delta: float) -> void:
	var actor := get_parent()
	if float(actor.get("health")) <= 0.0:
		stop()
		return
	countdown -= delta
	if countdown > 0.0 or playing:
		return
	countdown = randf_range(8.0, 16.0)
	var camera := get_viewport().get_camera_3d()
	if camera == null or camera.global_position.distance_to(global_position) > max_distance:
		return
	var index := 0 if str(actor.get("model_id")) == "the_monster" else 1 if str(actor.get("model_id")) == "slasher" else 2
	if voices.size() > index:
		stream = voices[index]
		play()
