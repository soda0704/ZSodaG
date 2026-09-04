class_name GamePlayer
extends CharacterBody3D

const NO_ITEM := &""
const FLASHLIGHT_ITEM := &"flashlight"
const FUSE_ITEM := &"fuse"
const BATTERY_ITEM := &"battery"
const FUEL_ITEM := &"fuel_can"
const FLASHLIGHT_PICKUP_SCENE := preload(
	"res://scenes/objects/equipment/flashlight_pickup.tscn"
)
const FUSE_PICKUP_SCENE := preload(
	"res://scenes/objects/items/fuse_pickup.tscn"
)
const FUEL_PICKUP_SCENE := preload(
	"res://scenes/objects/items/fuel_can_pickup.tscn"
)
const INPUT_SEND_RATE := 30.0
const SNAPSHOT_SEND_RATE := 20.0
const REMOTE_EXTRAPOLATION_SECONDS := 0.05

@export var owner_peer_id: int = 1
@export var player_display_name: String = "Player"
@export var avatar_color: Color = Color(0.25, 0.75, 1.0)

@export_group("Movement")
@export var walk_speed: float = 4.0
@export var sprint_speed: float = 6.5
@export var crouch_speed: float = 2.2
@export var acceleration: float = 14.0
@export var air_control_multiplier: float = 0.28
@export var jump_velocity: float = 4.0
@export var fall_gravity_multiplier: float = 1.25
@export var standing_height: float = 1.8
@export var crouching_height: float = 1.15
@export var standing_head_height: float = 1.65
@export var crouching_head_height: float = 1.02
@export var crouch_transition_speed: float = 10.0
@export var mouse_sensitivity: float = 0.002
@export var controller_look_speed: float = 2.4

@export_group("Flashlight")
@export_range(5.0, 1800.0, 1.0) var battery_duration_seconds: float = 120.0

@export_group("Networking")
@export var remote_interpolation_speed: float = 14.0
@export var reconciliation_speed: float = 8.0
@export var hard_reconciliation_distance: float = 1.5

@onready var head: Node3D = %Head
@onready var camera: FirstPersonCameraMotion = %Camera3D
@onready var collision_shape: CollisionShape3D = %CollisionShape3D
@onready var body_animator: PrototypeCharacterAnimator = %BodyVisual
@onready var name_label: Label3D = %NameLabel
@onready var flashlight: PlayerFlashlight = %Flashlight
@onready var held_fuse: Node3D = %HeldFuse
@onready var held_fuel_can: Node3D = %HeldFuelCan
@onready var interaction_ray: RayCast3D = %InteractionRay
@onready var interaction_prompt_label: Label = %InteractionPromptLabel
@onready var battery_label: Label = %BatteryLabel
@onready var crosshair: Control = %Crosshair

var gravity: float = float(
	ProjectSettings.get_setting("physics/3d/default_gravity")
)

var _input_move: Vector2 = Vector2.ZERO
var _input_sprint: bool = false
var _input_crouch: bool = false
var _input_yaw: float = 0.0
var _input_pitch: float = 0.0
var _jump_serial: int = 0
var _flashlight_serial: int = 0
var _interact_serial: int = 0
var _drop_item_serial: int = 0
var _input_sequence: int = 0
var _input_send_accumulator: float = 0.0

var _server_move: Vector2 = Vector2.ZERO
var _server_sprint: bool = false
var _server_crouch: bool = false
var _server_yaw: float = 0.0
var _server_pitch: float = 0.0
var _server_jump_serial: int = 0
var _server_flashlight_serial: int = 0
var _server_interact_serial: int = 0
var _server_drop_item_serial: int = 0
var _server_last_sequence: int = -1
var _server_consumed_jump_serial: int = 0
var _server_consumed_flashlight_serial: int = 0
var _server_consumed_interact_serial: int = 0
var _server_consumed_drop_item_serial: int = 0
var _snapshot_send_accumulator: float = 0.0

var _client_consumed_jump_serial: int = 0
var _reconciliation_offset: Vector3 = Vector3.ZERO
var _remote_target_position: Vector3 = Vector3.ZERO
var _remote_target_velocity: Vector3 = Vector3.ZERO
var _remote_target_yaw: float = 0.0
var _remote_target_pitch: float = 0.0
var _remote_crouching: bool = false
var _has_remote_snapshot: bool = false
var _has_flashlight: bool = false
var _held_item_type: StringName = NO_ITEM
var _flashlight_enabled: bool = false
var _flashlight_malfunctioning: bool = false
var _battery_charge: float = 0.0
var _displayed_battery_percent: int = -1
var _is_crouching: bool = false
var _is_sleeping_in_bunk: bool = false


func setup(
	peer_id: int,
	display_name_value: String,
	spawn_position: Vector3,
	color: Color,
	spawn_yaw: float = 0.0
) -> void:
	owner_peer_id = peer_id
	player_display_name = display_name_value.left(32)
	position = spawn_position
	avatar_color = color
	rotation.y = spawn_yaw
	_input_yaw = spawn_yaw
	_server_yaw = spawn_yaw


func _ready() -> void:
	name_label.text = player_display_name
	name_label.modulate = avatar_color
	body_animator.set_avatar_color(avatar_color)

	var local_player := is_local_player()
	camera.current = local_player
	body_animator.visible = not local_player
	name_label.visible = not local_player
	crosshair.visible = local_player
	interaction_prompt_label.visible = false
	battery_label.visible = false

	if not multiplayer.is_server() and not local_player:
		collision_shape.set_deferred("disabled", true)

	if local_player:
		add_to_group("local_player")
		if not GameMenu.is_menu_open():
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	flashlight.drain_battery_locally = false
	flashlight.set_process(false)
	flashlight.malfunction_enabled = multiplayer.is_server()
	if multiplayer.is_server():
		flashlight.malfunction_started.connect(
			_on_authoritative_flashlight_malfunction_started
		)
	apply_held_item_inventory(NO_ITEM, {})


func _unhandled_input(event: InputEvent) -> void:
	if not is_local_player():
		return
	if _is_sleeping_in_bunk or _is_journal_open():
		return

	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if event is InputEventKey and event.echo:
		return

	if event is InputEventMouseMotion:
		var sensitivity: float = (
			mouse_sensitivity
			* GameMenu.get_mouse_sensitivity_multiplier()
		)
		_input_yaw = wrapf(
			_input_yaw - event.relative.x * sensitivity,
			-PI,
			PI
		)
		_input_pitch = clampf(
			_input_pitch - event.relative.y * sensitivity,
			deg_to_rad(-85.0),
			deg_to_rad(85.0)
		)
		camera.add_look_impulse(event.relative)
		flashlight.add_look_impulse(event.relative)
	elif event.is_action_pressed("jump"):
		_jump_serial += 1
	elif event.is_action_pressed("interact"):
		_interact_serial += 1
	elif event.is_action_pressed("drop_item"):
		_drop_item_serial += 1
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
		collect_local_look(delta)
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
	update_character_animation(delta)


func is_local_player() -> bool:
	return owner_peer_id == multiplayer.get_unique_id()


func collect_local_input() -> void:
	if (
		Input.mouse_mode != Input.MOUSE_MODE_CAPTURED
		or _is_sleeping_in_bunk
		or _is_journal_open()
	):
		_input_move = Vector2.ZERO
		_input_sprint = false
		_input_crouch = false
		return

	var godot_move := Input.get_vector(
		"move_left",
		"move_right",
		"move_forward",
		"move_backward"
	)
	var steam_move := _get_steam_input_vector(&"get_gameplay_move")
	_input_move = (
		steam_move
		if steam_move.length_squared() > godot_move.length_squared()
		else godot_move
	)
	_input_crouch = Input.is_action_pressed("crouch")
	_input_sprint = Input.is_action_pressed("sprint") and not _input_crouch


func collect_local_look(delta: float) -> void:
	if (
		Input.mouse_mode != Input.MOUSE_MODE_CAPTURED
		or _is_sleeping_in_bunk
		or _is_journal_open()
	):
		return
	var sensitivity_multiplier := GameMenu.get_mouse_sensitivity_multiplier()
	var godot_look := Input.get_vector(
		"look_left",
		"look_right",
		"look_up",
		"look_down"
	)
	var look_radians := (
		godot_look
		* controller_look_speed
		* sensitivity_multiplier
		* delta
	)
	var steam_look := _get_steam_input_vector(&"get_gameplay_look")
	look_radians += steam_look * mouse_sensitivity * sensitivity_multiplier
	if look_radians.is_zero_approx():
		return
	_input_yaw = wrapf(_input_yaw - look_radians.x, -PI, PI)
	_input_pitch = clampf(
		_input_pitch - look_radians.y,
		deg_to_rad(-85.0),
		deg_to_rad(85.0)
	)
	var look_impulse := look_radians / maxf(mouse_sensitivity, 0.00001)
	camera.add_look_impulse(look_impulse)
	flashlight.add_look_impulse(look_impulse)


func _get_steam_input_vector(method_name: StringName) -> Vector2:
	var steam_input := get_node_or_null("/root/SteamInput")
	if steam_input == null or not steam_input.has_method(method_name):
		return Vector2.ZERO
	return steam_input.call(method_name) as Vector2


func update_local_view_motion(delta: float) -> void:
	var horizontal_speed := Vector2(velocity.x, velocity.z).length()
	var reference_speed := (
		crouch_speed
		if _is_crouching
		else sprint_speed if _input_sprint else walk_speed
	)
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


func update_character_animation(delta: float) -> void:
	body_animator.set_sleeping(_is_sleeping_in_bunk)
	var is_remote_client_player := (
		not multiplayer.is_server() and not is_local_player()
	)
	var crouching := (
		_remote_crouching
		if is_remote_client_player
		else _is_crouching
	)
	var animation_velocity := (
		_remote_target_velocity if is_remote_client_player else velocity
	)
	var horizontal_speed := Vector2(
		animation_velocity.x,
		animation_velocity.z
	).length()
	var sprinting := (
		horizontal_speed > walk_speed + 0.45
		if is_remote_client_player
		else _server_sprint if multiplayer.is_server() else _input_sprint
	)
	var grounded := (
		absf(animation_velocity.y) < 0.12
		if is_remote_client_player
		else is_on_floor()
	)
	body_animator.update_pose(
		delta,
		horizontal_speed,
		grounded,
		sprinting and not crouching,
		crouching,
		animation_velocity.y
	)
	name_label.visible = not is_local_player() and not _is_sleeping_in_bunk
	name_label.position.y = lerpf(
		name_label.position.y,
		1.55 if crouching else 2.05,
		1.0 - exp(-10.0 * delta)
	)


func copy_local_input_to_server() -> void:
	_server_move = _input_move
	_server_sprint = _input_sprint
	_server_crouch = _input_crouch
	_server_yaw = _input_yaw
	_server_pitch = _input_pitch
	_server_jump_serial = _jump_serial
	_server_flashlight_serial = _flashlight_serial
	_server_interact_serial = _interact_serial
	_server_drop_item_serial = _drop_item_serial
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
		_input_crouch,
		_jump_serial,
		_flashlight_serial,
		_interact_serial,
		_drop_item_serial,
		_input_yaw,
		_input_pitch
	)


@rpc("any_peer", "call_remote", "unreliable_ordered", 0)
func _submit_input(
	sequence: int,
	move_input: Vector2,
	sprinting: bool,
	crouching: bool,
	jump_serial: int,
	flashlight_serial: int,
	interact_serial: int,
	drop_item_serial: int,
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
	_server_crouch = crouching
	_server_sprint = sprinting and not crouching
	_server_jump_serial = maxi(jump_serial, _server_jump_serial)
	_server_flashlight_serial = maxi(
		flashlight_serial,
		_server_flashlight_serial
	)
	_server_interact_serial = maxi(interact_serial, _server_interact_serial)
	_server_drop_item_serial = maxi(
		drop_item_serial,
		_server_drop_item_serial
	)
	_server_yaw = wrapf(yaw, -PI, PI)
	_server_pitch = clampf(
		pitch,
		deg_to_rad(-85.0),
		deg_to_rad(85.0)
	)


func simulate_authoritative_movement(delta: float) -> void:
	if _is_sleeping_in_bunk:
		velocity = Vector3.ZERO
		_server_consumed_jump_serial = _server_jump_serial
		_server_consumed_flashlight_serial = _server_flashlight_serial
		_server_consumed_interact_serial = _server_interact_serial
		_server_consumed_drop_item_serial = _server_drop_item_serial
		return
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

	var should_drop_item := (
		_server_drop_item_serial != _server_consumed_drop_item_serial
	)
	if should_drop_item:
		_server_consumed_drop_item_serial = _server_drop_item_serial

	simulate_movement(
		delta,
		_server_move,
		_server_sprint,
		_server_crouch,
		should_jump,
		_server_yaw,
		_server_pitch
	)
	if should_interact:
		try_authoritative_interaction()
	if should_drop_item:
		drop_current_item_authoritative()


func simulate_predicted_movement(delta: float) -> void:
	if _is_sleeping_in_bunk:
		velocity = Vector3.ZERO
		_client_consumed_jump_serial = _jump_serial
		return
	var should_jump := _jump_serial != _client_consumed_jump_serial
	if should_jump:
		_client_consumed_jump_serial = _jump_serial

	simulate_movement(
		delta,
		_input_move,
		_input_sprint,
		_input_crouch,
		should_jump,
		_input_yaw,
		_input_pitch
	)


func simulate_movement(
	delta: float,
	move_input: Vector2,
	sprinting: bool,
	crouching: bool,
	should_jump: bool,
	yaw: float,
	pitch: float
) -> void:
	rotation.y = yaw
	head.rotation.x = pitch
	update_crouch_state(delta, crouching)

	if not is_on_floor():
		var gravity_scale := fall_gravity_multiplier if velocity.y < 0.0 else 1.0
		velocity.y -= gravity * gravity_scale * delta
	elif velocity.y < 0.0:
		velocity.y = 0.0

	if should_jump and is_on_floor() and not _is_crouching:
		velocity.y = jump_velocity

	var input_direction := Vector3(move_input.x, 0.0, move_input.y)
	var world_direction := (transform.basis * input_direction).normalized()
	var speed := (
		crouch_speed
		if _is_crouching
		else sprint_speed if sprinting else walk_speed
	)
	var target_velocity := world_direction * speed
	var movement_acceleration := acceleration
	if not is_on_floor():
		movement_acceleration *= air_control_multiplier

	velocity.x = move_toward(
		velocity.x,
		target_velocity.x,
		movement_acceleration * delta
	)
	velocity.z = move_toward(
		velocity.z,
		target_velocity.z,
		movement_acceleration * delta
	)
	move_and_slide()


func update_crouch_state(delta: float, wants_to_crouch: bool) -> void:
	if not wants_to_crouch and _is_crouching and not can_stand_up():
		wants_to_crouch = true
	_is_crouching = wants_to_crouch

	var target_height := crouching_height if _is_crouching else standing_height
	var target_head_height := (
		crouching_head_height if _is_crouching else standing_head_height
	)
	var capsule := collision_shape.shape as CapsuleShape3D
	if capsule != null:
		capsule.height = move_toward(
			capsule.height,
			target_height,
			crouch_transition_speed * delta
		)
		collision_shape.position.y = capsule.height * 0.5
	head.position.y = move_toward(
		head.position.y,
		target_head_height,
		crouch_transition_speed * delta
	)


func can_stand_up() -> bool:
	if get_world_3d() == null:
		return true
	var query := PhysicsRayQueryParameters3D.create(
		global_position + Vector3.UP * (crouching_height - 0.08),
		global_position + Vector3.UP * (standing_height + 0.04),
		collision_mask,
		[get_rid()]
	)
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func try_authoritative_interaction() -> void:
	if not multiplayer.is_server():
		return
	interaction_ray.force_raycast_update()
	var target := interaction_ray.get_collider() as Node
	if target == null or not target.has_method("network_interact"):
		return
	target.call("network_interact", owner_peer_id, self)


func refresh_interaction_prompt() -> void:
	if (
		not is_local_player()
		or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED
		or _is_sleeping_in_bunk
		or _is_journal_open()
	):
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


func _is_journal_open() -> bool:
	var journal := get_node_or_null("/root/QuestJournal")
	return journal != null and bool(journal.call("is_journal_open"))


func teleport_authoritative(
	next_global_position: Vector3,
	next_yaw: float = 0.0
) -> void:
	if not multiplayer.is_server():
		return
	_receive_authoritative_teleport.rpc(next_global_position, next_yaw)


func enter_bunk_sleep_authoritative(sleep_transform: Transform3D) -> void:
	if multiplayer.is_server():
		_receive_bunk_sleep_state.rpc(true, sleep_transform)


func leave_bunk_sleep_authoritative(wake_transform: Transform3D) -> void:
	if multiplayer.is_server():
		_receive_bunk_sleep_state.rpc(false, wake_transform)


func is_sleeping_in_bunk() -> bool:
	return _is_sleeping_in_bunk


@rpc("authority", "call_local", "reliable", 2)
func _receive_bunk_sleep_state(
	is_sleeping: bool,
	target_transform: Transform3D
) -> void:
	_is_sleeping_in_bunk = is_sleeping
	global_position = target_transform.origin
	rotation.y = target_transform.basis.get_euler().y
	velocity = Vector3.ZERO
	_reconciliation_offset = Vector3.ZERO
	_input_move = Vector2.ZERO
	_server_move = Vector2.ZERO
	_is_crouching = false
	collision_shape.set_deferred(
		"disabled",
		is_sleeping or (not multiplayer.is_server() and not is_local_player())
	)
	if is_sleeping:
		head.position = Vector3(0, 0.28, -1.22)
		head.rotation = Vector3(-PI * 0.5, 0, 0)
		_input_pitch = -PI * 0.5
		_server_pitch = -PI * 0.5
	else:
		head.position = Vector3(0, standing_head_height, 0)
		head.rotation = Vector3.ZERO
		_input_yaw = rotation.y
		_server_yaw = rotation.y
		_input_pitch = 0.0
		_server_pitch = 0.0


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


func pickup_world_item_authoritative(
	item_type: StringName,
	item_state: Dictionary
) -> bool:
	if not multiplayer.is_server():
		return false

	if item_type == BATTERY_ITEM:
		if _held_item_type != FLASHLIGHT_ITEM or _battery_charge >= 0.999:
			return false
		var charge_amount := clampf(
			float(item_state.get("charge_amount", 0.5)),
			0.0,
			1.0
		)
		if charge_amount <= 0.0:
			return false
		var next_charge := minf(_battery_charge + charge_amount, 1.0)
		_receive_held_item_inventory.rpc(
			FLASHLIGHT_ITEM,
			{"battery_charge": next_charge},
			_flashlight_enabled,
			_flashlight_malfunctioning
		)
		return true

	if item_type not in [FLASHLIGHT_ITEM, FUSE_ITEM, FUEL_ITEM]:
		return false
	var previous_item_type := _held_item_type
	var previous_item_state := get_held_item_state()
	var next_state := item_state.duplicate(true)
	var enable_flashlight := (
		item_type == FLASHLIGHT_ITEM
		and float(next_state.get("battery_charge", 1.0)) > 0.0
	)
	_receive_held_item_inventory.rpc(
		item_type,
		next_state,
		enable_flashlight,
		false
	)
	if previous_item_type != NO_ITEM:
		spawn_dropped_item_authoritative(
			previous_item_type,
			previous_item_state
		)
	return true


func get_held_item_state() -> Dictionary:
	if _held_item_type == FLASHLIGHT_ITEM:
		return {"battery_charge": _battery_charge}
	return {}


func get_held_item_drop_transform() -> Transform3D:
	var forward := -head.global_basis.z.normalized()
	return Transform3D(
		head.global_basis.orthonormalized(),
		head.global_position + forward * 0.7 + Vector3.DOWN * 0.35
	)


func get_held_item_drop_linear_velocity() -> Vector3:
	return velocity + -head.global_basis.z.normalized() * 1.1


func drop_current_item_authoritative() -> bool:
	return drop_current_item_at_authoritative(
		get_held_item_drop_transform(),
		get_held_item_drop_linear_velocity()
	)


func drop_current_item_at_authoritative(
	drop_transform: Transform3D,
	drop_velocity: Vector3 = Vector3.ZERO
) -> bool:
	if not multiplayer.is_server() or _held_item_type == NO_ITEM:
		return false

	var dropped_item_type := _held_item_type
	var dropped_item_state := get_held_item_state()
	_receive_held_item_inventory.rpc(NO_ITEM, {}, false, false)
	spawn_dropped_item_authoritative(
		dropped_item_type,
		dropped_item_state,
		drop_transform,
		drop_velocity
	)
	return true


func has_held_item(item_type: StringName) -> bool:
	return _held_item_type == item_type


func consume_held_item_authoritative(item_type: StringName) -> bool:
	if not multiplayer.is_server() or _held_item_type != item_type:
		return false
	_receive_held_item_inventory.rpc(NO_ITEM, {}, false, false)
	return true


func spawn_dropped_item_authoritative(
	item_type: StringName,
	item_state: Dictionary,
	drop_transform_override: Variant = null,
	linear_velocity_override: Variant = null
) -> void:
	if not multiplayer.is_server():
		return

	var drop_transform := get_held_item_drop_transform()
	if drop_transform_override is Transform3D:
		drop_transform = drop_transform_override as Transform3D
	var drop_velocity := get_held_item_drop_linear_velocity()
	if linear_velocity_override is Vector3:
		drop_velocity = linear_velocity_override as Vector3
	var controller := get_tree().get_first_node_in_group(
		"network_gameplay_controller"
	)
	if controller != null and controller.has_method("spawn_dropped_item"):
		controller.call(
			"spawn_dropped_item",
			item_type,
			{
				"item_state": item_state.duplicate(true),
				"transform": drop_transform,
				"linear_velocity": drop_velocity,
				"angular_velocity": Vector3(1.4, 0.8, -1.1),
			}
		)
		return

	var pickup_scene: PackedScene = (
		FLASHLIGHT_PICKUP_SCENE
		if item_type == FLASHLIGHT_ITEM
		else FUSE_PICKUP_SCENE
		if item_type == FUSE_ITEM
		else FUEL_PICKUP_SCENE if item_type == FUEL_ITEM else null
	)
	if pickup_scene == null or get_tree().current_scene == null:
		return
	var pickup := pickup_scene.instantiate() as WorldItemPickup
	pickup.setup_spawn({
		"item_type": item_type,
		"item_state": item_state,
		"linear_velocity": drop_velocity,
		"angular_velocity": Vector3(1.4, 0.8, -1.1),
	})
	get_tree().current_scene.add_child(pickup)
	pickup.global_transform = drop_transform


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


@rpc("authority", "call_local", "reliable", 2)
func _receive_held_item_inventory(
	item_type: StringName,
	item_state: Dictionary,
	flashlight_enabled: bool = false,
	flashlight_malfunctioning: bool = false
) -> void:
	apply_held_item_inventory(
		item_type,
		item_state,
		flashlight_enabled,
		flashlight_malfunctioning
	)


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
		_is_crouching,
		_held_item_type,
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
	server_crouching: bool,
	server_held_item_type: StringName,
	server_has_flashlight: bool,
	server_battery_charge: float,
	server_flashlight_enabled: bool,
	server_flashlight_malfunctioning: bool,
	_acknowledged_input: int
) -> void:
	var held_item_type := (
		server_held_item_type
		if server_held_item_type != NO_ITEM
		else FLASHLIGHT_ITEM if server_has_flashlight else NO_ITEM
	)
	apply_held_item_inventory(
		held_item_type,
		{"battery_charge": server_battery_charge},
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
	_remote_crouching = server_crouching
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
	apply_held_item_inventory(
		FLASHLIGHT_ITEM if has_flashlight else NO_ITEM,
		{"battery_charge": battery_charge},
		enabled,
		malfunctioning
	)


func apply_held_item_inventory(
	item_type: StringName,
	item_state: Dictionary,
	flashlight_enabled: bool = false,
	malfunctioning: bool = false
) -> void:
	_held_item_type = item_type
	_has_flashlight = _held_item_type == FLASHLIGHT_ITEM
	_battery_charge = clampf(
		float(item_state.get("battery_charge", 0.0)),
		0.0,
		1.0
	) if _has_flashlight else 0.0
	_flashlight_malfunctioning = (
		malfunctioning and _has_flashlight and _battery_charge > 0.0
	)
	_flashlight_enabled = (
		flashlight_enabled
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
	held_fuse.visible = _held_item_type == FUSE_ITEM
	held_fuel_can.visible = _held_item_type == FUEL_ITEM
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
