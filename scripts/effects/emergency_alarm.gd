extends AudioStreamPlayer
## Audio output is the single clock for the existing red lights and fixtures.
@export var alarm_volume_db := -15.0
@export_range(.02,2.0) var presence_fade_seconds := .35
@export_range(0.0,1.0) var intensity := 0.0
@onready var animation: AnimationPlayer = $AnimationPlayer
@onready var power: BasePowerLightingController = get_node("../../BasePowerLightingController")
@onready var presence: AudioStreamPlayer = get_node("../../BaseInteriorAmbience")
var _gain := 0.0

func _ready() -> void:
	animation.play(&"alarm")
	animation.pause()
	volume_db=-100.0

func advance_emergency(delta: float) -> float:
	var active:bool = not power.is_standard_powered and get_parent().get_node("Emergency").visible
	if not active:
		stop();_gain=0.0;volume_db=-100.0
		return 1.0
	# Muted outside, still advancing: entering the base must not reset the beat.
	if not playing: play()
	_gain=move_toward(_gain,listener_gain(),delta/presence_fade_seconds)
	volume_db=alarm_volume_db+linear_to_db(maxf(smoothstep(0.0,1.0,_gain),.00001))
	var clock:=get_playback_position()+AudioServer.get_time_since_last_mix()-AudioServer.get_output_latency()
	animation.seek(fposmod(maxf(0.0,clock),stream.get_length()),true)
	return intensity

func listener_gain() -> float:
	var gain: float = presence.listener_gain()
	var camera := get_viewport().get_camera_3d()
	if camera == null: return gain
	for portal: AcousticPortal in get_tree().get_nodes_in_group("acoustic_portals"):
		var distance := camera.global_position.distance_to(portal.wind.global_position)
		if distance < 22.0 and portal.openness() > .001 and portal.wind_path_clear(camera):
			gain = maxf(gain, portal.openness() * .8 * (1.0 - smoothstep(2.0,22.0,distance)))
	return gain
