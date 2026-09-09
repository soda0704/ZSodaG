class_name PlayerFlashlight
extends Node3D

signal availability_changed(is_available: bool)
signal battery_changed(charge_normalized: float)
signal battery_depleted
signal malfunction_started
signal repaired
signal state_changed(is_enabled: bool)

const FLICKER_DURATIONS = [0.08, 0.06, 0.14, 0.05, 0.22]
const FLICKER_VISIBILITY = [false, true, false, true, false]

@export var starts_available: bool = false
@export var starts_enabled: bool = false

@export_group("Battery")
@export_range(1.0, 1800.0, 1.0) var battery_duration_seconds: float = 180.0
@export_range(0.0, 1.0, 0.01) var starts_battery_charge: float = 1.0
@export var drain_battery_locally: bool = true

@export_group("Malfunction")
@export var malfunction_interval_seconds: float = 60.0
@export var malfunction_enabled: bool = true

@export_group("Walk Sway")
@export var walk_bob_frequency: float = 1.7
@export var sprint_bob_frequency: float = 2.35
@export var horizontal_bob: float = 0.012
@export var vertical_bob: float = 0.016
@export var roll_bob_degrees: float = 0.65

@export_group("Look Sway")
@export var look_sway_strength: float = 0.00045
@export var max_look_sway_degrees: float = 2.2
@export var motion_smoothing: float = 12.0
@export var look_return_speed: float = 9.0

@onready var beam: SpotLight3D = %Beam
@onready var spill: SpotLight3D = %Spill
@onready var lens: MeshInstance3D = $Model/Lens
@onready var malfunction_timer: Timer = %MalfunctionTimer
@onready var flicker_timer: Timer = %FlickerTimer

var is_available: bool = false
var is_enabled: bool = false
var is_malfunctioning: bool = false
var battery_charge: float = 1.0

var _rest_position: Vector3
var _rest_rotation: Vector3
var _bob_phase: float = 0.0
var _look_rotation: Vector3 = Vector3.ZERO
var _lens_material: StandardMaterial3D
var _flicker_step: int = 0
var _equip_tween: Tween
var _equipped: bool = false
var _equip_offset: float = 0.0
var _battery_tween: Tween
var _battery_pose: float = 0.0
var _replacement_cell: MeshInstance3D


func _ready() -> void:
	_rest_position = position
	_rest_rotation = rotation
	prepare_lens_material()
	_replacement_cell = MeshInstance3D.new()
	var cell_mesh := CylinderMesh.new()
	cell_mesh.top_radius = 0.012
	cell_mesh.bottom_radius = 0.012
	cell_mesh.height = 0.065
	_replacement_cell.mesh = cell_mesh
	var cell_material := StandardMaterial3D.new()
	cell_material.albedo_color = Color("456e48")
	cell_material.metallic = 0.4
	_replacement_cell.material_override = cell_material
	add_child(_replacement_cell)
	_replacement_cell.hide()
	malfunction_timer.timeout.connect(begin_malfunction)
	flicker_timer.timeout.connect(play_next_flicker_step)
	battery_charge = clampf(starts_battery_charge, 0.0, 1.0)
	set_available(starts_available, false)
	set_enabled(starts_available and starts_enabled, false)


func _process(delta: float) -> void:
	if drain_battery_locally and is_available and is_enabled:
		drain_battery(delta)


func prepare_lens_material() -> void:
	_lens_material = lens.get_active_material(0).duplicate() as StandardMaterial3D
	lens.material_override = _lens_material


func acquire(turn_on: bool = true, charge: float = 1.0) -> bool:
	if is_available:
		return false

	set_battery_charge(charge)
	set_available(true)
	set_enabled(turn_on)
	return true


func replace(charge: float, turn_on: bool = true) -> float:
	var previous_charge := battery_charge if is_available else -1.0
	cancel_malfunction()
	set_battery_charge(charge)
	set_available(true)
	set_enabled(turn_on)
	return previous_charge


func unequip() -> float:
	if not is_available:
		return -1.0
	var remaining_charge := battery_charge
	set_available(false)
	return remaining_charge


func toggle() -> bool:
	if not is_available:
		return false

	if is_malfunctioning:
		return hit_to_repair()
	if battery_charge <= 0.0:
		return false

	set_enabled(not is_enabled)
	return true


func set_available(value: bool, emit_signal: bool = true) -> void:
	if is_available == value and visible == value:
		return

	is_available = value
	visible = value

	if not is_available:
		cancel_malfunction()
		set_enabled(false, emit_signal)
		reset_motion()

	if emit_signal:
		availability_changed.emit(is_available)


func set_equipped(value: bool) -> void:
	if value == _equipped:
		return
	_equipped = value
	if _battery_tween != null and _battery_tween.is_valid():
		_battery_tween.kill()
	_battery_pose = 0.0
	_replacement_cell.hide()
	if _equip_tween != null and _equip_tween.is_valid():
		_equip_tween.kill()
	var was_visible := visible
	set_available(true, false)
	if value:
		if not was_visible:
			_equip_offset = 0.38
	else:
		set_enabled(false, false)
	_equip_tween = create_tween()
	_equip_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_equip_tween.tween_method(_set_equip_offset, _equip_offset, 0.0 if value else 0.38, 0.32 if value else 0.26)
	if not value:
		_equip_tween.tween_callback(func(): set_available(false, false))


func _set_equip_offset(value: float) -> void:
	_equip_offset = value
	position.y = _rest_position.y - value
	rotation.x = _rest_rotation.x - value * 1.2


func play_battery_action() -> void:
	if not _equipped:
		return
	if _battery_tween != null and _battery_tween.is_valid():
		_battery_tween.kill()
	_battery_tween = create_tween()
	_battery_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_battery_tween.tween_property(self, "_battery_pose", 1.0, 0.32)
	_battery_tween.tween_property(self, "_battery_pose", 0.85, 0.22)
	_battery_tween.tween_property(self, "_battery_pose", 1.1, 0.18)
	_battery_tween.tween_property(self, "_battery_pose", 0.0, 0.38)


func set_enabled(value: bool, emit_signal: bool = true) -> void:
	var next_state := value and is_available and battery_charge > 0.0
	if is_malfunctioning and next_state:
		return

	if (
		is_enabled == next_state
		and beam.visible == next_state
		and spill.visible == next_state
	):
		return

	is_enabled = next_state
	apply_light_output(is_enabled)

	if is_enabled and malfunction_enabled:
		malfunction_timer.start(maxf(malfunction_interval_seconds, 0.1))
	else:
		malfunction_timer.stop()

	if emit_signal:
		state_changed.emit(is_enabled)


func set_battery_charge(value: float, emit_signal: bool = true) -> void:
	var next_charge := clampf(value, 0.0, 1.0)
	if is_equal_approx(battery_charge, next_charge):
		return

	var was_charged := battery_charge > 0.0
	battery_charge = next_charge
	if battery_charge <= 0.0 and is_enabled:
		set_enabled(false)
	if emit_signal:
		battery_changed.emit(battery_charge)
	if was_charged and battery_charge <= 0.0:
		battery_depleted.emit()


func drain_battery(delta: float) -> void:
	if battery_charge <= 0.0:
		return
	var duration := maxf(battery_duration_seconds, 1.0)
	set_battery_charge(battery_charge - delta / duration)


func begin_malfunction(force: bool = false) -> void:
	if (
		(not malfunction_enabled and not force)
		or not is_available
		or not is_enabled
		or is_malfunctioning
	):
		return

	is_malfunctioning = true
	is_enabled = false
	malfunction_timer.stop()
	_flicker_step = 0
	state_changed.emit(false)
	malfunction_started.emit()
	play_next_flicker_step()


func play_next_flicker_step() -> void:
	if not is_malfunctioning:
		return

	if _flicker_step >= FLICKER_DURATIONS.size():
		apply_light_output(false)
		flicker_timer.stop()
		return

	apply_light_output(bool(FLICKER_VISIBILITY[_flicker_step]))
	flicker_timer.start(float(FLICKER_DURATIONS[_flicker_step]))
	_flicker_step += 1


func hit_to_repair() -> bool:
	if not is_malfunctioning:
		return false

	is_malfunctioning = false
	flicker_timer.stop()
	_flicker_step = 0

	var kick_limit := deg_to_rad(max_look_sway_degrees)
	_look_rotation.x = clamp(
		_look_rotation.x - deg_to_rad(1.8),
		-kick_limit,
		kick_limit
	)
	_look_rotation.z = clamp(
		_look_rotation.z + deg_to_rad(2.2),
		-kick_limit,
		kick_limit
	)
	position += Vector3(0.012, -0.018, 0.02)

	set_enabled(true)
	repaired.emit()
	return true


func cancel_malfunction() -> void:
	is_malfunctioning = false
	malfunction_timer.stop()
	flicker_timer.stop()
	_flicker_step = 0
	apply_light_output(false)


func apply_light_output(value: bool) -> void:
	beam.visible = value
	spill.visible = value
	_lens_material.emission_enabled = value

	if value:
		_lens_material.emission = beam.light_color
		_lens_material.emission_energy_multiplier = 2.0


func add_look_impulse(mouse_delta: Vector2) -> void:
	if not is_available:
		return

	var limit := deg_to_rad(max_look_sway_degrees)
	_look_rotation.x = clamp(
		_look_rotation.x - mouse_delta.y * look_sway_strength,
		-limit,
		limit
	)
	_look_rotation.y = clamp(
		_look_rotation.y - mouse_delta.x * look_sway_strength,
		-limit,
		limit
	)
	_look_rotation.z = clamp(
		_look_rotation.z + mouse_delta.x * look_sway_strength * 0.65,
		-limit,
		limit
	)


func update_motion(
	delta: float,
	movement_ratio: float,
	is_grounded: bool,
	is_sprinting: bool
) -> void:
	if not is_available:
		return

	var clamped_ratio := clampf(movement_ratio, 0.0, 1.0)
	var bob_position := Vector3.ZERO
	var bob_rotation := Vector3.ZERO

	if is_grounded and clamped_ratio > 0.05:
		var frequency := (
			sprint_bob_frequency if is_sprinting else walk_bob_frequency
		)
		var sprint_multiplier := 1.35 if is_sprinting else 1.0
		_bob_phase = fmod(
			_bob_phase + delta * frequency * TAU * maxf(clamped_ratio, 0.35),
			TAU
		)

		bob_position.x = sin(_bob_phase) * horizontal_bob
		bob_position.y = cos(_bob_phase * 2.0) * vertical_bob
		bob_position *= clamped_ratio * sprint_multiplier

		bob_rotation.x = cos(_bob_phase * 2.0) * deg_to_rad(0.3)
		bob_rotation.z = sin(_bob_phase) * deg_to_rad(roll_bob_degrees)
		bob_rotation *= clamped_ratio * sprint_multiplier

	var look_return_weight := 1.0 - exp(-look_return_speed * delta)
	_look_rotation = _look_rotation.lerp(Vector3.ZERO, look_return_weight)

	var target_position := _rest_position + bob_position + Vector3.DOWN * _equip_offset + Vector3(-0.08, 0.1, -0.12) * _battery_pose
	var target_rotation := _rest_rotation + bob_rotation + _look_rotation + Vector3(-_equip_offset * 1.2, 0, 0) + Vector3(0.25, -0.3, -0.65) * _battery_pose
	var smoothing_weight := 1.0 - exp(-motion_smoothing * delta)
	_replacement_cell.visible = _battery_pose > 0.5
	_replacement_cell.position = Vector3(-0.045, 0.015, -0.18 + _battery_pose * 0.08)
	_replacement_cell.rotation.x = PI * 0.5

	position = position.lerp(target_position, smoothing_weight)
	rotation = rotation.lerp(target_rotation, smoothing_weight)


func reset_motion() -> void:
	_bob_phase = 0.0
	_look_rotation = Vector3.ZERO
	position = _rest_position
	rotation = _rest_rotation
