extends RefCounted
## Inertia in HUD design units, driven by aim yaw and pitch.
const LIMIT := 32.0
const PITCH_LIMIT := 24.0
const SHIFT_LIMIT := 44.0
var offset := Vector2.ZERO
var pitch_offset := 0.0
var _turn_target := Vector2.ZERO

var _heading := 0.0
var _pitch := 0.0
var _initialized := false

func screen_shift() -> Vector2:
	return (Vector2(offset.x, pitch_offset)).limit_length(SHIFT_LIMIT)

func reset() -> void:
	offset = Vector2.ZERO
	pitch_offset = 0.0

	_turn_target = Vector2.ZERO

	_initialized = false

func sample(forward: Vector3, delta: float) -> void:
	var heading := atan2(forward.x, -forward.z)
	var pitch := asin(clampf(forward.y, -1.0, 1.0))
	var turn := angle_difference(_heading, heading)
	var tilt := pitch - _pitch
	if not _initialized or delta <= 0.0 or delta > 0.15 or maxf(absf(turn), absf(tilt)) > PI * 0.25:
		reset()

		_initialized = true
	else:
		var velocity := turn / delta
		var target := clampf(-velocity * 19.0, -LIMIT, LIMIT)
		if absf(velocity) < 0.015: target = 0.0
		# Filter the input first, then let the panels catch up to the filtered target.
		var pitch_target := clampf(tilt / delta * 16.0, -PITCH_LIMIT, PITCH_LIMIT)
		var requested := Vector2(target, pitch_target)
		var input_decay := exp(-3.2 * delta)
		var panel_decay := exp(-2.3 * delta)
		# Integrate both filters over the frame so a low frame rate does not shorten the lag.
		var previous_panel := Vector2(offset.x, pitch_offset)
		var integrated_input := (_turn_target - requested) * (2.3 / (2.3 - 3.2)) * (input_decay - panel_decay)
		var panel := requested + (previous_panel - requested) * panel_decay + integrated_input
		_turn_target = requested + (_turn_target - requested) * input_decay
		offset.x = panel.x
		pitch_offset = panel.y
		if offset.length_squared() < 0.000025: offset = Vector2.ZERO
		if absf(pitch_offset) < 0.005: pitch_offset = 0.0

	_heading = heading
	_pitch = pitch
