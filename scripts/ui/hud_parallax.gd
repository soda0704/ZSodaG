extends RefCounted
## Camera-space inertia. X and Y are design units, Z is relative depth.
const LIMIT := 12.0
var offset := Vector2.ZERO
var pitch_offset := 0.0
var movement := Vector3.ZERO
var roll := 0.0
var _fast_velocity := Vector3.ZERO
var _slow_velocity := Vector3.ZERO
var _heading := 0.0
var _pitch := 0.0
var _initialized := false

func reset() -> void:
	offset = Vector2.ZERO
	pitch_offset = 0.0
	movement = Vector3.ZERO
	roll = 0.0
	_fast_velocity = Vector3.ZERO
	_slow_velocity = Vector3.ZERO
	_initialized = false

func sample(forward: Vector3, delta: float, local_velocity := Vector3.ZERO,
		camera_displacement := Vector3.ZERO, camera_roll := 0.0) -> void:
	var heading := atan2(forward.x, -forward.z)
	var pitch := asin(clampf(forward.y, -1.0, 1.0))
	var turn := angle_difference(_heading, heading)
	var tilt := pitch - _pitch
	if not _initialized or delta <= 0.0 or delta > 0.15 or maxf(absf(turn), absf(tilt)) > PI * 0.25:
		reset()
		_fast_velocity = local_velocity
		_slow_velocity = local_velocity
		_initialized = true
	else:
		var velocity := turn / delta
		var target := clampf(-velocity * 7.5, -LIMIT, LIMIT)
		if absf(velocity) < 0.015: target = 0.0
		var look_response := 1.0 - exp(-14.0 * delta)
		offset = Vector2(lerpf(offset.x, target, look_response), 0.0)
		pitch_offset = lerpf(pitch_offset, clampf(tilt / delta * 6.0, -8.0, 8.0), look_response)
		if offset.length_squared() < 0.000025: offset = Vector2.ZERO
		if absf(pitch_offset) < 0.005: pitch_offset = 0.0

		# The difference between fast and slow velocity captures acceleration
		# and braking without making panels drift at constant movement speed.
		_fast_velocity = _fast_velocity.lerp(local_velocity, 1.0 - exp(-23.0 * delta))
		_slow_velocity = _slow_velocity.lerp(local_velocity, 1.0 - exp(-7.5 * delta))
		var impulse := _fast_velocity - _slow_velocity
		var translation := Vector3(
			clampf(-impulse.x * 4.0 - camera_displacement.x * 75.0, -12.0, 12.0),
			clampf(impulse.y * 2.4 + camera_displacement.y * 78.0, -9.0, 9.0),
			clampf(impulse.z * 0.008 + camera_displacement.z * 0.16, -0.028, 0.028))
		var body_response := 1.0 - exp(-18.0 * delta)
		movement = movement.lerp(translation, body_response)
		roll = lerpf(roll, clampf(-camera_roll * 0.68, -0.022, 0.022), body_response)
	_heading = heading
	_pitch = pitch
