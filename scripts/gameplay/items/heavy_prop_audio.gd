extends Node3D
## Sound state comes from host physics contacts, never from holding E alone.
@export var drag_stream: AudioStream
@export var lift_stream: AudioStream
@export var place_stream: AudioStream
@export var drag_volume_db := -17.0
@export var event_volume_db := -9.0
@export var motion_threshold := .08
@export var full_volume_speed := .65
@export var rotation_radius := .9
@export var impact_threshold := .8
@export var drag_noise_radius := 12.0
@export var impact_noise_radius := 18.0
@onready var prop: HeavyCarryProp = get_parent()
@onready var drag: AudioStreamPlayer3D = $Drag
@onready var event: AudioStreamPlayer3D = $Event
var _age := 0.0
var _supported := false
var _send_elapsed := 1.0
var _noise_elapsed := 1.0
var _impact_cooldown := 0.0
var _last_sent_speed := -1.0
var _target_speed := 0.0
var _gain := 0.0
var _last_received := 0

func _ready() -> void:
	drag.stream = drag_stream
	drag.volume_db = -80

func observe_contacts(touching: bool, supported: bool, speed: float, impact: float, rising: float, delta: float) -> void:
	if not multiplayer.is_server(): return
	_age += delta
	_impact_cooldown = maxf(0, _impact_cooldown - delta)
	var was_supported := _supported
	_supported = supported
	if _age < .5: return # Fresh/restored props settle silently.
	var moving := speed if touching and speed >= motion_threshold else 0.0
	_send_elapsed += delta
	if _send_elapsed >= .1 and (absf(moving - _last_sent_speed) > .025 or _send_elapsed >= .3):
		_send_elapsed = 0
		_last_sent_speed = moving
		_receive_motion.rpc(moving)
	_noise_elapsed += delta
	if moving > 0 and _noise_elapsed >= .7:
		_noise_elapsed = 0
		preload("res://scripts/gameplay/gameplay_noise.gd").emit(prop, drag_noise_radius * lerpf(.4, 1, clampf(moving / full_volume_speed, 0, 1)))
	if was_supported and not supported and prop.grips.size() >= 2 and rising > .12:
		_receive_event.rpc(false, .45, randf_range(.96, 1.04))
	if touching and impact >= impact_threshold and _impact_cooldown <= 0:
		_impact_cooldown = .4
		var strength := clampf(impact / 3, .3, 1)
		_receive_event.rpc(true, strength, randf_range(.94, 1.03))
		preload("res://scripts/gameplay/gameplay_noise.gd").emit(prop, impact_noise_radius * strength)

@rpc("authority", "call_local", "unreliable_ordered", 2)
func _receive_motion(speed: float) -> void:
	_target_speed = clampf(speed, 0, 5)
	_last_received = Time.get_ticks_msec()

@rpc("authority", "call_local", "reliable", 2)
func _receive_event(placing: bool, strength: float, pitch: float) -> void:
	event.stream = place_stream if placing else lift_stream
	event.volume_db = event_volume_db + linear_to_db(clampf(strength, .05, 1))
	event.pitch_scale = clampf(pitch, .9, 1.1)
	event.play()

func _process(delta: float) -> void:
	# A lost stop packet or disconnected host must not leave a scraping loop.
	var speed := _target_speed if Time.get_ticks_msec() - _last_received < 600 else 0.0
	var desired := clampf(speed / full_volume_speed, 0, 1)
	_gain = move_toward(_gain, desired, delta * 8)
	if _gain > .005:
		if not drag.playing: drag.play()
		drag.volume_db = drag_volume_db + linear_to_db(_gain)
		drag.pitch_scale = lerpf(.85, 1.12, _gain)
	elif drag.playing:
		drag.stop()
