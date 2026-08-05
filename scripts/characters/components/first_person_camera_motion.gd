class_name FirstPersonCameraMotion
extends Camera3D

@export_group("Head Bob")
@export var walk_frequency: float = 1.75
@export var sprint_frequency: float = 2.35
@export var walk_horizontal_amplitude: float = 0.012
@export var walk_vertical_amplitude: float = 0.022
@export var sprint_horizontal_amplitude: float = 0.02
@export var sprint_vertical_amplitude: float = 0.038
@export var walk_roll_degrees: float = 0.35
@export var sprint_roll_degrees: float = 0.7

@export_group("Turn Inertia")
@export var turn_tilt_strength: float = 0.00012
@export var max_turn_tilt_degrees: float = 0.8
@export var turn_return_speed: float = 10.0
@export var motion_smoothing: float = 14.0

var _rest_position: Vector3
var _rest_rotation: Vector3
var _bob_phase: float = 0.0
var _turn_rotation: Vector3 = Vector3.ZERO


func _ready() -> void:
	_rest_position = position
	_rest_rotation = rotation


func add_look_impulse(mouse_delta: Vector2) -> void:
	var max_tilt := deg_to_rad(max_turn_tilt_degrees)
	_turn_rotation.x = clamp(
		_turn_rotation.x - mouse_delta.y * turn_tilt_strength * 0.35,
		-max_tilt * 0.5,
		max_tilt * 0.5
	)
	_turn_rotation.z = clamp(
		_turn_rotation.z - mouse_delta.x * turn_tilt_strength,
		-max_tilt,
		max_tilt
	)


func update_motion(
	delta: float,
	movement_ratio: float,
	is_grounded: bool,
	is_sprinting: bool
) -> void:
	var clamped_ratio := clampf(movement_ratio, 0.0, 1.0)
	var bob_position := Vector3.ZERO
	var bob_rotation := Vector3.ZERO

	if is_grounded and clamped_ratio > 0.05:
		var frequency := sprint_frequency if is_sprinting else walk_frequency
		var horizontal_amplitude := (
			sprint_horizontal_amplitude
			if is_sprinting
			else walk_horizontal_amplitude
		)
		var vertical_amplitude := (
			sprint_vertical_amplitude
			if is_sprinting
			else walk_vertical_amplitude
		)
		var roll_degrees := (
			sprint_roll_degrees if is_sprinting else walk_roll_degrees
		)

		_bob_phase = fmod(
			_bob_phase + delta * frequency * TAU * maxf(clamped_ratio, 0.35),
			TAU
		)
		bob_position.x = sin(_bob_phase) * horizontal_amplitude
		bob_position.y = cos(_bob_phase * 2.0) * vertical_amplitude
		bob_position *= clamped_ratio
		bob_rotation.z = sin(_bob_phase) * deg_to_rad(roll_degrees)
		bob_rotation *= clamped_ratio

	var return_weight := 1.0 - exp(-turn_return_speed * delta)
	_turn_rotation = _turn_rotation.lerp(Vector3.ZERO, return_weight)

	var target_position := _rest_position + bob_position
	var target_rotation := _rest_rotation + bob_rotation + _turn_rotation
	var smoothing_weight := 1.0 - exp(-motion_smoothing * delta)

	position = position.lerp(target_position, smoothing_weight)
	rotation = rotation.lerp(target_rotation, smoothing_weight)
