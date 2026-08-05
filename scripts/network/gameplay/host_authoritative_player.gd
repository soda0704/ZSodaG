class_name HostAuthoritativeNetworkPlayer
extends CharacterBody3D

const INPUT_SEND_RATE := 30.0
const SNAPSHOT_SEND_RATE := 20.0
const REMOTE_EXTRAPOLATION_SECONDS := 0.05

@export var owner_peer_id: int = 1
@export var player_display_name: String = "Player"
@export var avatar_color: Color = Color(0.25, 0.75, 1.0)

@export_group("Movement")
@export var walk_speed: float = 4.0
@export var sprint_speed: float = 6.5
@export var acceleration: float = 14.0
@export var jump_velocity: float = 5.0
@export var mouse_sensitivity: float = 0.002

@export_group("Flashlight")
@export_range(5.0, 1800.0, 1.0) var battery_duration_seconds: float = 120.0

@export_group("Networking")
@export var remote_interpolation_speed: float = 14.0
@export var reconciliation_speed: float = 8.0
@export var hard_reconciliation_distance: float = 1.5

@onready var head: Node3D = %Head
@onready var camera: FirstPersonCameraMotion = %Camera3D
@onready var collision_shape: CollisionShape3D = %CollisionShape3D
@onready var body_mesh: MeshInstance3D = %BodyMesh
@onready var name_label: Label3D = %NameLabel
@onready var flashlight: PlayerFlashlight = %Flashlight
@onready var interaction_ray: RayCast3D = %InteractionRay
@onready var interaction_prompt_label: Label = %InteractionPromptLabel
@onready var battery_label: Label = %BatteryLabel
@onready var crosshair: Control = %Crosshair

var gravity: float = float(
	ProjectSettings.get_setting("physics/3d/default_gravity")
)

var _input_move: Vector2 = Vector2.ZERO
var _input_sprint: bool = false
var _input_yaw: float = 0.0
var _input_pitch: float = 0.0
var _jump_serial: int = 0
var _flashlight_serial: int = 0
var _interact_serial: int = 0
var _input_sequence: int = 0
var _input_send_accumulator: float = 0.0

var _server_move: Vector2 = Vector2.ZERO
var _server_sprint: bool = false
var _server_yaw: float = 0.0
var _server_pitch: float = 0.0
var _server_jump_serial: int = 0
var _server_flashlight_serial: int = 0
var _server_interact_serial: int = 0
var _server_last_sequence: int = -1
var _server_consumed_jump_serial: int = 0
var _server_consumed_flashlight_serial: int = 0
var _server_consumed_interact_serial: int = 0
var _snapshot_send_accumulator: float = 0.0

var _client_consumed_jump_serial: int = 0
var _reconciliation_offset: Vector3 = Vector3.ZERO
var _remote_target_position: Vector3 = Vector3.ZERO
var _remote_target_velocity: Vector3 = Vector3.ZERO
var _remote_target_yaw: float = 0.0
var _remote_target_pitch: float = 0.0
var _has_remote_snapshot: bool = false
var _has_flashlight: bool = false
var _flashlight_enabled: bool = false
var _flashlight_malfunctioning: bool = false
var _battery_charge: float = 0.0
var _displayed_battery_percent: int = -1


func setup(
	peer_id: int,
	display_name_value: String,
	spawn_position: Vector3,
	color: Color
) -> void:
	owner_peer_id = peer_id
	player_display_name = display_name_value.left(32)
	position = spawn_position
	avatar_color = color
	_input_yaw = rotation.y
	_server_yaw = rotation.y


func _ready() -> void:
	name_label.text = player_display_name
	name_label.modulate = avatar_color
	var body_material := body_mesh.get_active_material(0).duplicate()
	if body_material is StandardMaterial3D:
		(body_material as StandardMaterial3D).albedo_color = avatar_color
	body_mesh.material_override = body_material

	var local_player := is_local_player()
	camera.current = local_player
	body_mesh.visible = not local_player
	name_label.visible = not local_player
	crosshair.visible = local_player
	interaction_prompt_label.visible = false
	battery_label.visible = false

	if not multiplayer.is_server() and not local_player:
		collision_shape.set_deferred("disabled", true)

	if local_player:
		add_to_group("local_player")
		if not get_tree().paused:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	flashlight.drain_battery_locally = false
	flashlight.malfunction_enabled = multiplayer.is_server()
	if multiplayer.is_server():
		flashlight.malfunction_started.connect(
			_on_authoritative_flashlight_malfunction_started
		)
	apply_flashlight_inventory(false, 0.0, false)


func _unhandled_input(event: InputEvent) -> void:
	if not is_local_player():
		return

	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if event is InputEventKey and event.echo:
		return

	if event is InputEventMouseMotion:
		_input_yaw = wrapf(
			_input_yaw - event.relative.x * mouse_sensitivity,
			-PI,
			PI
		)
		_input_pitch = clampf(
			_input_pitch - event.relative.y * mouse_sensitivity,
			deg_to_rad(-85.0),
			deg_to_rad(85.0)
		)
		camera.add_look_impulse(event.relative)
		flashlight.add_look_impulse(event.relative)
	elif event.is_action_pressed("jump"):
		_jump_serial += 1
	elif event.is_action_pressed("interact"):
		_interact_serial += 1
	elif event.is_action_pressed("flashlight"):
		if _has_flashlight and _battery_charge > 0.0:
			_flashlight_serial += 1
			if not multiplayer.is_server():
				if _flashlight_malfunctioning:
					_flashlight_malfunctioning = false
					_flashlight_enabled = true
					flashlight.hit_to_repair()
					update_battery_ui()
				else:
					apply_flashlight_inventory(
						_has_flashlight,
						_battery_charge,
						not _flashlight_enabled
					)


func _physics_process(delta: float) -> void:
	if is_local_player():
		collect_local_input()
		refresh_interaction_prompt()

	if multiplayer.is_server():
		if is_local_player():
			copy_local_input_to_server()
		simulate_authoritative_movement(delta)
		update_authoritative_flashlight_battery(delta)
		send_snapshot_if_due(delta)
	elif is_local_player():
		simulate_predicted_movement(delta)
		send_input_if_due(delta)
		apply_reconciliation(delta)
	else:
		interpolate_remote_player(delta)

	if is_local_player():
		update_local_view_motion(delta)


func is_local_player() -> bool:
	return owner_peer_id == multiplayer.get_unique_id()


func collect_local_input() -> void:
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		_input_move = Vector2.ZERO
		_input_sprint = false
		return

	_input_move = Input.get_vector(
		"move_left",
		"move_right",
		"move_forward",
		"move_backward"
	)
	_input_sprint = Input.is_action_pressed("sprint")


func update_local_view_motion(delta: float) -> void:
	var horizontal_speed := Vector2(velocity.x, velocity.z).length()
	var reference_speed := sprint_speed if _input_sprint else walk_speed
	var movement_ratio := horizontal_speed / maxf(reference_speed, 0.001)
	camera.update_motion(
		delta,
		movement_ratio,
		is_on_floor(),
		_input_sprint
	)
	flashlight.update_motion(
		delta,
		movement_ratio,
		is_on_floor(),
		_input_sprint
	)


func copy_local_input_to_server() -> void:
	_server_move = _input_move
	_server_sprint = _input_sprint
	_server_yaw = _input_yaw
	_server_pitch = _input_pitch
	_server_jump_serial = _jump_serial
	_server_flashlight_serial = _flashlight_serial
	_server_interact_serial = _interact_serial
	_server_last_sequence = _input_sequence


func send_input_if_due(delta: float) -> void:
	_input_send_accumulator += delta
	var interval := 1.0 / INPUT_SEND_RATE
	if _input_send_accumulator < interval:
		return

	_input_send_accumulator = fmod(_input_send_accumulator, interval)
	_input_sequence += 1
	_submit_input.rpc_id(
		1,
		_input_sequence,
		_input_move,
		_input_sprint,
		_jump_serial,
		_flashlight_serial,
		_interact_serial,
		_input_yaw,
		_input_pitch
	)


@rpc("any_peer", "call_remote", "unreliable_ordered", 0)
func _submit_input(
	sequence: int,
	move_input: Vector2,
	sprinting: bool,
	jump_serial: int,
	flashlight_serial: int,
	interact_serial: int,
	yaw: float,
	pitch: float
) -> void:
	if not multiplayer.is_server():
		return
	if multiplayer.get_remote_sender_id() != owner_peer_id:
		return
	if sequence <= _server_last_sequence:
		return

	_server_last_sequence = sequence
	_server_move = move_input.limit_length(1.0)
	_server_sprint = sprinting
	_server_jump_serial = maxi(jump_serial, _server_jump_serial)
	_server_flashlight_serial = maxi(
		flashlight_serial,
		_server_flashlight_serial
	)
	_server_interact_serial = maxi(interact_serial, _server_interact_serial)
	_server_yaw = wrapf(yaw, -PI, PI)
	_server_pitch = clampf(
		pitch,
		deg_to_rad(-85.0),
		deg_to_rad(85.0)
	)


func simulate_authoritative_movement(delta: float) -> void:
	var should_jump := _server_jump_serial != _server_consumed_jump_serial
	if should_jump:
		_server_consumed_jump_serial = _server_jump_serial

	if (
		_server_flashlight_serial != _server_consumed_flashlight_serial
		and _has_flashlight
		and _battery_charge > 0.0
	):
		_server_consumed_flashlight_serial = _server_flashlight_serial
		if _flashlight_malfunctioning:
			_flashlight_malfunctioning = false
			flashlight.hit_to_repair()
			_flashlight_enabled = flashlight.is_enabled
			update_battery_ui()
		else:
			apply_flashlight_inventory(
				_has_flashlight,
				_battery_charge,
				not _flashlight_enabled
			)
	elif _server_flashlight_serial != _server_consumed_flashlight_serial:
		_server_consumed_flashlight_serial = _server_flashlight_serial

	var should_interact := (
		_server_interact_serial != _server_consumed_interact_serial
	)
	if should_interact:
		_server_consumed_interact_serial = _server_interact_serial

	simulate_movement(
		delta,
		_server_move,
		_server_sprint,
		should_jump,
		_server_yaw,
		_server_pitch
	)
	if should_interact:
		try_authoritative_interaction()


func simulate_predicted_movement(delta: float) -> void:
	var should_jump := _jump_serial != _client_consumed_jump_serial
	if should_jump:
		_client_consumed_jump_serial = _jump_serial

	simulate_movement(
		delta,
		_input_move,
		_input_sprint,
		should_jump,
		_input_yaw,
		_input_pitch
	)


func simulate_movement(
	delta: float,
	move_input: Vector2,
	sprinting: bool,
	should_jump: bool,
	yaw: float,
	pitch: float
) -> void:
	rotation.y = yaw
	head.rotation.x = pitch

	if not is_on_floor():
		velocity.y -= gravity * delta
	elif velocity.y < 0.0:
		velocity.y = 0.0

	if should_jump and is_on_floor():
		velocity.y = jump_velocity

	var input_direction := Vector3(move_input.x, 0.0, move_input.y)
	var world_direction := (transform.basis * input_direction).normalized()
	var speed := sprint_speed if sprinting else walk_speed
	var target_velocity := world_direction * speed

	velocity.x = move_toward(
		velocity.x,
		target_velocity.x,
		acceleration * delta
	)
	velocity.z = move_toward(
		velocity.z,
		target_velocity.z,
		acceleration * delta
	)
	move_and_slide()


func try_authoritative_interaction() -> void:
	if not multiplayer.is_server():
		return
	interaction_ray.force_raycast_update()
	var target := interaction_ray.get_collider() as Node
	if target == null or not target.has_method("network_interact"):
		return
	target.call("network_interact", owner_peer_id, self)


func refresh_interaction_prompt() -> void:
	if not is_local_player() or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		interaction_prompt_label.visible = false
		return

	interaction_ray.force_raycast_update()
	var target := interaction_ray.get_collider() as Node
	if target == null or not target.has_method("network_interact"):
		interaction_prompt_label.visible = false
		return

	var prompt := "Взаимодействовать"
	if target.has_method("get_interaction_prompt"):
		prompt = str(target.call("get_interaction_prompt"))
	interaction_prompt_label.text = "[E] %s" % prompt
	interaction_prompt_label.visible = true


func teleport_authoritative(
	next_global_position: Vector3,
	next_yaw: float = 0.0
) -> void:
	if not multiplayer.is_server():
		return
	_receive_authoritative_teleport.rpc(next_global_position, next_yaw)


@rpc("authority", "call_local", "reliable", 2)
func _receive_authoritative_teleport(
	next_global_position: Vector3,
	next_yaw: float
) -> void:
	global_position = next_global_position
	velocity = Vector3.ZERO
	rotation.y = next_yaw
	head.rotation.x = 0.0
	_input_yaw = next_yaw
	_server_yaw = next_yaw
	_input_pitch = 0.0
	_server_pitch = 0.0
	_remote_target_position = position
	_remote_target_velocity = Vector3.ZERO
	_remote_target_yaw = next_yaw
	_remote_target_pitch = 0.0
	_reconciliation_offset = Vector3.ZERO


func swap_flashlight_authoritative(next_battery_charge: float) -> float:
	if not multiplayer.is_server():
		return -1.0

	var previous_charge := _battery_charge if _has_flashlight else -1.0
	var next_charge := clampf(next_battery_charge, 0.0, 1.0)
	_flashlight_malfunctioning = false
	_receive_flashlight_inventory.rpc(
		true,
		next_charge,
		next_charge > 0.0
	)
	return previous_charge


func get_flashlight_drop_transform() -> Transform3D:
	var forward := -head.global_basis.z.normalized()
	return Transform3D(
		head.global_basis.orthonormalized(),
		head.global_position + forward * 0.7 + Vector3.DOWN * 0.35
	)


func get_flashlight_drop_linear_velocity() -> Vector3:
	return velocity + -head.global_basis.z.normalized() * 1.1


func update_authoritative_flashlight_battery(delta: float) -> void:
	if (
		not multiplayer.is_server()
		or not _has_flashlight
		or not _flashlight_enabled
		or _battery_charge <= 0.0
	):
		return

	_battery_charge = maxf(
		_battery_charge - delta / maxf(battery_duration_seconds, 1.0),
		0.0
	)
	flashlight.set_battery_charge(_battery_charge, false)
	update_battery_ui()
	if _battery_charge <= 0.0:
		_receive_flashlight_inventory.rpc(true, 0.0, false)


@rpc("authority", "call_local", "reliable", 2)
func _receive_flashlight_inventory(
	has_flashlight: bool,
	battery_charge: float,
	enabled: bool
) -> void:
	apply_flashlight_inventory(has_flashlight, battery_charge, enabled)


func send_snapshot_if_due(delta: float) -> void:
	_snapshot_send_accumulator += delta
	var interval := 1.0 / SNAPSHOT_SEND_RATE
	if _snapshot_send_accumulator < interval:
		return

	_snapshot_send_accumulator = fmod(_snapshot_send_accumulator, interval)
	_receive_authoritative_state.rpc(
		position,
		velocity,
		rotation.y,
		head.rotation.x,
		_has_flashlight,
		_battery_charge,
		_flashlight_enabled,
		_flashlight_malfunctioning,
		_server_last_sequence
	)


@rpc("authority", "call_remote", "unreliable_ordered", 1)
func _receive_authoritative_state(
	server_position: Vector3,
	server_velocity: Vector3,
	server_yaw: float,
	server_pitch: float,
	server_has_flashlight: bool,
	server_battery_charge: float,
	server_flashlight_enabled: bool,
	server_flashlight_malfunctioning: bool,
	_acknowledged_input: int
) -> void:
	apply_flashlight_inventory(
		server_has_flashlight,
		server_battery_charge,
		server_flashlight_enabled,
		server_flashlight_malfunctioning
	)

	if is_local_player():
		var extrapolated_position := (
			server_position
			+ server_velocity * REMOTE_EXTRAPOLATION_SECONDS
		)
		var error := extrapolated_position - position
		if error.length() >= hard_reconciliation_distance:
			position = extrapolated_position
			_reconciliation_offset = Vector3.ZERO
		else:
			_reconciliation_offset = error
		velocity = velocity.lerp(server_velocity, 0.15)
		return

	_remote_target_position = server_position
	_remote_target_velocity = server_velocity
	_remote_target_yaw = server_yaw
	_remote_target_pitch = server_pitch
	_has_remote_snapshot = true


func apply_reconciliation(delta: float) -> void:
	if _reconciliation_offset.is_zero_approx():
		return

	var weight := 1.0 - exp(-reconciliation_speed * delta)
	var correction := _reconciliation_offset * weight
	position += correction
	_reconciliation_offset -= correction


func interpolate_remote_player(delta: float) -> void:
	if not _has_remote_snapshot:
		return

	var weight := 1.0 - exp(-remote_interpolation_speed * delta)
	var extrapolated_position := (
		_remote_target_position
		+ _remote_target_velocity * REMOTE_EXTRAPOLATION_SECONDS
	)
	position = position.lerp(extrapolated_position, weight)
	rotation.y = lerp_angle(rotation.y, _remote_target_yaw, weight)
	head.rotation.x = lerp_angle(
		head.rotation.x,
		_remote_target_pitch,
		weight
	)


func apply_flashlight_inventory(
	has_flashlight: bool,
	battery_charge: float,
	enabled: bool,
	malfunctioning: bool = false
) -> void:
	_has_flashlight = has_flashlight
	_battery_charge = clampf(battery_charge, 0.0, 1.0)
	_flashlight_malfunctioning = (
		malfunctioning and _has_flashlight and _battery_charge > 0.0
	)
	_flashlight_enabled = (
		enabled
		and _has_flashlight
		and _battery_charge > 0.0
		and not _flashlight_malfunctioning
	)
	flashlight.set_battery_charge(_battery_charge, false)
	flashlight.set_available(_has_flashlight, false)
	if _flashlight_malfunctioning:
		flashlight.set_enabled(false, false)
		flashlight.begin_malfunction(true)
	else:
		if flashlight.is_malfunctioning:
			flashlight.cancel_malfunction()
		flashlight.set_enabled(_flashlight_enabled, false)
	update_battery_ui()


func _on_authoritative_flashlight_malfunction_started() -> void:
	if not multiplayer.is_server():
		return
	_flashlight_malfunctioning = true
	_flashlight_enabled = false


func update_battery_ui() -> void:
	battery_label.visible = is_local_player() and _has_flashlight
	if not battery_label.visible:
		_displayed_battery_percent = -1
		return

	var battery_percent := roundi(_battery_charge * 100.0)
	if battery_percent == _displayed_battery_percent:
		return
	_displayed_battery_percent = battery_percent
	battery_label.text = "БАТАРЕЯ: %d%%" % battery_percent
