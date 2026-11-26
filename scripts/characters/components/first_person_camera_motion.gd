class_name FirstPersonCameraMotion
extends Camera3D

@export_group("Chest Camera")
@export var walk_frequency: float = 1.2
@export var sprint_frequency: float = 1.8
@export var walk_horizontal_amplitude: float = 0.047
@export var walk_vertical_amplitude: float = 0.045
@export var walk_depth_amplitude: float = 0.028
@export var sprint_horizontal_amplitude: float = 0.047
@export var sprint_vertical_amplitude: float = 0.081
@export var sprint_depth_amplitude: float = 0.051
@export var walk_roll_degrees: float = 1.08
@export var sprint_roll_degrees: float = 1.58
@export var crouch_frequency: float = 0.7
@export var crouch_amplitude_scale: float = 0.55
@export var aim_motion_scale: float = 0.23

@export_group("Turn Inertia")
@export var turn_tilt_strength: float = 0.00012
@export var max_turn_tilt_degrees: float = 0.8
@export var turn_return_speed: float = 10.0
@export var motion_smoothing: float = 14.0

var _rest_position: Vector3
var _rest_rotation: Vector3
var _bob_phase: float = 0.0
var _turn_rotation: Vector3 = Vector3.ZERO
var _motion_strength := 0.0
var _sprint_blend := 0.0
var _crouch_blend := 0.0
var _aim_blend := 0.0
var _body_movement := Vector2.ZERO


func _ready() -> void:
	_rest_position = position
	_rest_rotation = rotation

func get_hud_displacement() -> Vector3:
	return position - _rest_position

func get_hud_roll() -> float:
	return angle_difference(_rest_rotation.z, rotation.z)

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

func reset_motion() -> void:
	_bob_phase=0.0
	_turn_rotation=Vector3.ZERO
	_motion_strength=0.0;_sprint_blend=0.0;_crouch_blend=0.0;_aim_blend=0.0
	_body_movement = Vector2.ZERO
	position=_rest_position;rotation=_rest_rotation


func update_motion(
	delta: float,
	movement_ratio: float,
	is_grounded: bool,
	is_sprinting: bool,
	is_crouching: bool = false,
	is_aiming: bool = false,
	local_movement: Vector2 = Vector2.ZERO
) -> void:
	var clamped_ratio := clampf(movement_ratio, 0.0, 1.0)
	var bob_position := Vector3.ZERO
	var bob_rotation := Vector3.ZERO
	var gait_weight := 1.0 - exp(-8.0 * delta)
	_motion_strength = lerpf(_motion_strength, clamped_ratio if is_grounded else 0.0, gait_weight)
	_sprint_blend = lerpf(_sprint_blend, 1.0 if is_sprinting and not is_crouching else 0.0, gait_weight)
	_crouch_blend = lerpf(_crouch_blend, 1.0 if is_crouching else 0.0, gait_weight)
	_aim_blend = lerpf(_aim_blend, 1.0 if is_aiming else 0.0, gait_weight)
	var grounded_movement := local_movement.limit_length() if is_grounded else Vector2.ZERO
	_body_movement = _body_movement.lerp(grounded_movement, 1.0 - exp(-5.5 * delta))

	if is_grounded and _motion_strength > 0.001:
		var frequency := lerpf(lerpf(walk_frequency, sprint_frequency, _sprint_blend), crouch_frequency, _crouch_blend)
		var amplitude_scale := lerpf(1.0, crouch_amplitude_scale, _crouch_blend) * lerpf(1.0, aim_motion_scale, _aim_blend) * _motion_strength
		var horizontal_amplitude := lerpf(walk_horizontal_amplitude, sprint_horizontal_amplitude, _sprint_blend)
		var vertical_amplitude := lerpf(walk_vertical_amplitude, sprint_vertical_amplitude, _sprint_blend)
		var roll_degrees := lerpf(walk_roll_degrees, sprint_roll_degrees, _sprint_blend)

		_bob_phase = fmod(
			_bob_phase + delta * frequency * TAU * clamped_ratio,
			TAU
		)
		var weight_shift := 0.92 * sin(_bob_phase) + 0.08 * sin(3.0 * _bob_phase - 0.45)
		bob_position.x = weight_shift * horizontal_amplitude
		# The chest drops on contact and rises more gradually as the leg takes weight.
		var step := _bob_phase * 2.0
		var impact := lerpf(0.18, 0.27, _sprint_blend)
		var rebound := sin(step - 0.7) * lerpf(0.10, 0.16, _sprint_blend)
		bob_position.y = (-cos(step) * (1.0 - impact) - cos(2.0 * step + 0.4) * impact + rebound) * vertical_amplitude
		bob_position.z = sin(step - 0.55) * lerpf(walk_depth_amplitude, sprint_depth_amplitude, _sprint_blend)
		bob_position *= amplitude_scale
		var chest_roll := 0.90 * sin(_bob_phase - 0.48) - 0.10 * sin(3.0 * _bob_phase - 0.62)
		bob_rotation.z = chest_roll * deg_to_rad(roll_degrees)
		bob_rotation *= amplitude_scale

	var return_weight := 1.0 - exp(-turn_return_speed * delta)
	_turn_rotation = _turn_rotation.lerp(Vector3.ZERO, return_weight)

	# A short translational lag on acceleration is less disruptive than rotating the sightline.
	if is_grounded:
		var body_lag := (_body_movement - grounded_movement).limit_length(1.0)
		var lag := body_lag * lerpf(0.031, 0.057, _sprint_blend)
		lag *= lerpf(1.0, aim_motion_scale, _aim_blend)
		bob_position += Vector3(lag.x, 0.0, lag.y)
		var lean := deg_to_rad(0.65) * body_lag.x * (1.0 - _aim_blend) * (1.0 - _crouch_blend * 0.45)
		bob_rotation.z = clampf(bob_rotation.z + lean, deg_to_rad(-1.45), deg_to_rad(1.45))
	var target_position := _rest_position + bob_position
	var target_rotation := _rest_rotation + bob_rotation + _turn_rotation
	var smoothing_weight := 1.0 - exp(-motion_smoothing * delta)

	position = position.lerp(target_position, smoothing_weight)
	rotation = rotation.lerp(target_rotation, smoothing_weight)
