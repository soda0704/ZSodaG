extends Node3D

@export_range(0.1, 5.0) var breathing_fade_seconds := 0.55
@export var recovery_volume_db := -20.0
@export var recovery_seconds := 12.0
@onready var recovery: AudioStreamPlayer = $RecoveryBreathing
@export var long_breath: AudioStream
var _was_exhausted := false
var _recovery_left := 0.0

func _process(delta: float) -> void:
	var player := get_parent() as GamePlayer
	if player == null:
		return
	update_breathing(delta, player._sprint_active, player.is_local_player() and not player.survival.dead and not player.is_sleeping_in_bunk() and not player.is_driving(), player._sprint_exhausted)

func update_breathing(delta: float, running: bool, audible: bool, exhausted: bool = false) -> void:
	if not audible:
		_recovery_left = 0.0
	elif exhausted and not _was_exhausted:
		recovery.stream = long_breath
		recovery.volume_db = -80.0
		recovery.play()
		_recovery_left = recovery_seconds
	elif running:
		_recovery_left = 0.0
	# Track the edge even while inaudible so waking/returning does not replay it.
	_was_exhausted = exhausted
	_recovery_left = maxf(0.0, _recovery_left - delta)
	var recovery_gain := smoothstep(0.0, 2.0, _recovery_left) if audible and not running else 0.0
	AudioFade.apply(recovery, db_to_linear(recovery_volume_db) * recovery_gain, delta, breathing_fade_seconds, false)

@rpc("authority", "call_local", "reliable", 2)
func play_cue(cue: StringName) -> void:
	var player := get_parent() as GamePlayer
	if player == null or player.survival.dead:
		return
	var names := {&"pickup": "Pickup", &"battery": "Battery", &"flashlight_on": "FlashlightOn", &"flashlight_off": "FlashlightOff"}
	if names.has(cue):
		get_node(names[cue]).play()
