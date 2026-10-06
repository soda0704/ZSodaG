class_name AudioFade
extends RefCounted

## Blend amplitudes rather than decibels so zero really means silence.
static func apply(player: Node, target: float, delta: float, seconds: float, restart: bool = true) -> void:
	if target > 0.0 and not player.playing and restart:
		player.volume_db = -80.0
		player.play()
	var level := lerpf(db_to_linear(player.volume_db), target, 1.0 - exp(-delta / maxf(seconds, 0.01)))
	player.volume_db = linear_to_db(maxf(level, 0.00001))
	if target <= 0.0 and level < 0.0001:
		player.stop()

