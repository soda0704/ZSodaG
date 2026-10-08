extends Node3D

@export_range(0.1, 5.0) var breathing_fade_seconds := 0.55
@export var calm_volume_db := -30.0
@export var carrying_volume_db := -23.0
@export var recovery_volume_db := -20.0
@export var long_run_threshold := 3.0
@export var short_recovery_seconds := 6.0
@export var long_recovery_seconds := 12.0
@onready var calm: AudioStreamPlayer = $CalmBreathing
@onready var recovery: AudioStreamPlayer = $RecoveryBreathing
@export var short_breath: AudioStream
@export var long_breath: AudioStream
var _run_seconds := 0.0
var _was_running := false
var _recovery_left := 0.0

func _process(delta: float) -> void:
	var player := get_parent() as GamePlayer
	if player == null:
		return
	update_breathing(delta, player._sprint_active, player.is_local_player() and not player.survival.dead and not player.is_sleeping_in_bunk() and not player.is_driving(), player.is_carrying_corpse() and Vector2(player.velocity.x, player.velocity.z).length() > 0.5)

func update_breathing(delta: float, running: bool, audible: bool, exertion: bool = false) -> void:
	if not audible:
		_run_seconds = 0.0
		_was_running = false
		_recovery_left = 0.0
	elif exertion:
		if not recovery.playing:
			recovery.stream = long_breath
			recovery.play()
		_recovery_left = short_recovery_seconds
	elif running:
		_run_seconds += delta
		_recovery_left = 0.0
	elif _was_running:
		if _run_seconds >= 0.4:
			var long_run := _run_seconds >= long_run_threshold
			recovery.stream = long_breath if long_run else short_breath
			recovery.volume_db = -80.0
			recovery.play()
			_recovery_left = long_recovery_seconds if long_run else short_recovery_seconds
		_run_seconds = 0.0
	_was_running = running and audible
	_recovery_left = maxf(0.0, _recovery_left - delta)
	var recovery_gain := smoothstep(0.0, 2.0, _recovery_left) if audible and not running else 0.0
	AudioFade.apply(recovery, db_to_linear(carrying_volume_db if exertion else recovery_volume_db) * recovery_gain, delta, breathing_fade_seconds, false)
	AudioFade.apply(calm, db_to_linear(calm_volume_db) * (1.0 - recovery_gain) * (0.4 if running else 1.0) if audible else 0.0, delta, breathing_fade_seconds)

@rpc("authority", "call_local", "reliable", 2)
func play_cue(cue: StringName) -> void:
	var player := get_parent() as GamePlayer
	if player == null or player.survival.dead:
		return
	var names := {&"pickup": "Pickup", &"battery": "Battery", &"flashlight_on": "FlashlightOn", &"flashlight_off": "FlashlightOff"}
	if names.has(cue):
		get_node(names[cue]).play()
