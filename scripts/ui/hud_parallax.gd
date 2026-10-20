extends RefCounted
## Horizontal camera inertia in the HUD's 2560×1440 design coordinates.
const LIMIT := 12.0
var offset := Vector2.ZERO
var _heading := 0.0
var _initialized := false

func reset() -> void:
	offset = Vector2.ZERO
	_initialized = false

func sample(forward: Vector3, delta: float) -> void:
	var heading := atan2(forward.x, -forward.z)
	if not _initialized or delta <= 0.0 or delta > 0.15:
		offset = Vector2.ZERO
		_initialized = true
	else:
		var turn := angle_difference(_heading, heading)
		# Camera cuts and teleports should establish a new neutral, not kick the HUD.
		if absf(turn) > PI * 0.25:
			offset = Vector2.ZERO
		else:
			var velocity := turn / delta
			var target := clampf(-velocity * 6.0, -LIMIT, LIMIT)
			if absf(velocity) < 0.015: target = 0.0
			offset = Vector2(lerpf(offset.x, target, 1.0 - exp(-14.0 * delta)), 0.0)
			if offset.length_squared() < 0.000025: offset = Vector2.ZERO
	_heading = heading
