class_name GamePlayer
extends CharacterBody3D

signal inventory_changed

var survival: PlayerSurvival
var debug_fly := false
var debug_across := false
var _flight_vertical := 0.0
var weapon: WeaponController
var vehicle: Node3D

func is_driving() -> bool:
	return is_instance_valid(vehicle)

const NO_ITEM := &""
const FLASHLIGHT_ITEM := &"flashlight"
const FUSE_ITEM := &"fuse"
const BATTERY_ITEM := &"battery"
const FUEL_ITEM := &"fuel_can"
const MAX_SPARE_BATTERIES := 20
const BATTERY_PICKUP_SCENE := preload("res://scenes/objects/items/battery_pickup.tscn")
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
var _spare_batteries: Array[float] = []
var _inventory_revision: int = 0
var fuel_liters := 20.0
var _battery_action_busy: bool = false
var _pad_sprint: bool = false
var _noise_step_left := 0.0
var tape_count := 0
var crowbar_uses := 0
var weapon_light_mounted := false
var _equipment_notice_until := 0
var _pad_crouch: bool = false


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
	add_to_group("network_players")
	survival = preload("res://scripts/characters/components/player_survival.gd").new()
	survival.name = "Survival"
	add_child(survival)
	weapon = preload("res://scripts/gameplay/weapon_controller.gd").new()
	weapon.name = "Weapon"
	add_child(weapon)
	name_label.text = player_display_name
	name_label.modulate = avatar_color
	body_animator.set_avatar_color(avatar_color)

	var local_player := is_local_player()
	camera.current = local_player
	body_animator.visible = true
	for mesh in body_animator.find_children("*", "MeshInstance3D", true, false):
		mesh.layers |= 1 << 18 # Receive outdoor sunlight and cast a body shadow on snow.
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY if local_player else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	name_label.visible = not local_player
	crosshair.visible = local_player
	interaction_prompt_label.visible = false
	battery_label.visible = false

	if not multiplayer.is_server() and not local_player:
		collision_shape.set_deferred("disabled", true)

	if local_player:
		add_to_group("local_player")
		if not get_node("/root/GameMenu").is_menu_open():
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
	if survival.dead:
		return
	if not is_local_player():
		return
	if _is_sleeping_in_bunk:
		if event.is_action_pressed("interact"):
			request_leave_bunk_sleep()
		return
	if _is_journal_open():
		return

	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if event is InputEventKey and event.echo:
		return

	if event is InputEventMouseMotion:
		var sensitivity: float = (
			mouse_sensitivity
			* float(get_node("/root/GameMenu").get_mouse_sensitivity_multiplier())
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
		if not $ItemDrag.begin_interaction():
			_interact_serial += 1
	elif event.is_action_pressed("drop_item"):
		_drop_item_serial += 1
	elif event.is_action_pressed("replace_battery"):
		request_reload_or_battery()
	elif event.is_action_pressed("sprint") and get_node("/root/SteamInput").is_controller_event(event):
		_pad_sprint = not _pad_sprint
		_pad_crouch = false
	elif event.is_action_pressed("crouch") and get_node("/root/SteamInput").is_controller_event(event):
		_pad_crouch = not _pad_crouch
		_pad_sprint = false
	elif event.is_action_pressed("flashlight"):
		if _has_flashlight:
			_flashlight_serial += 1


func _physics_process(delta: float) -> void:
	if survival.dead:
		velocity = Vector3.ZERO
		interaction_prompt_label.hide()
		battery_label.hide()
		if multiplayer.is_server():
			send_snapshot_if_due(delta)
		return
	if is_local_player():
		collect_local_input()
		_flight_vertical = (float(Input.is_action_pressed("jump")) - float(Input.is_action_pressed("crouch"))) if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else 0.0
		collect_local_look(delta)
		refresh_interaction_prompt()
		update_battery_ui()

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
		_pad_sprint = false
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
	var using_controller: bool = bool(get_node("/root/SteamInput").using_controller)
	if not using_controller:
		_pad_sprint = false
		_pad_crouch = false
	if _input_move.length() < 0.1:
		_pad_sprint = false
	_input_crouch = _pad_crouch if using_controller else Input.is_action_pressed("crouch")
	_input_sprint = (_pad_sprint if using_controller else Input.is_action_pressed("sprint")) and not _input_crouch


func collect_local_look(delta: float) -> void:
	if (
		Input.mouse_mode != Input.MOUSE_MODE_CAPTURED
		or _is_sleeping_in_bunk
		or _is_journal_open()
	):
		return
	var sensitivity_multiplier: float = float(
		get_node("/root/GameMenu").get_mouse_sensitivity_multiplier()
	)
	var godot_look := Input.get_vector(
		"look_left",
		"look_right",
		"look_up",
		"look_down"
	)
	var look_radians: Vector2 = (
		godot_look
		* controller_look_speed
		* sensitivity_multiplier
		* delta
	)
	var steam_look := _get_steam_input_vector(&"get_gameplay_look")
	if not steam_look.is_zero_approx():
		# Steam may expose the same controller through the raw joypad fallback.
		# A native look sample replaces, rather than doubles, that sample.
		look_radians = steam_look * mouse_sensitivity * sensitivity_multiplier
	if look_radians.is_zero_approx():
		return
	_input_yaw = wrapf(_input_yaw - look_radians.x, -PI, PI)
	_input_pitch = clampf(
		_input_pitch - look_radians.y,
		deg_to_rad(-85.0),
		deg_to_rad(85.0)
	)
	var look_impulse: Vector2 = look_radians / maxf(mouse_sensitivity, 0.00001)
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
		_input_pitch,
		_flight_vertical
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
	pitch: float,
	flight_vertical: float = 0.0
) -> void:
	if not multiplayer.is_server():
		return
	if multiplayer.get_remote_sender_id() != owner_peer_id:
		return
	if sequence <= _server_last_sequence:
		return

	_server_last_sequence = sequence
	_flight_vertical = clampf(flight_vertical, -1.0, 1.0)
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
	if is_driving():
		update_vehicle_look(_server_yaw, _server_pitch)
		vehicle.set_driver_input(owner_peer_id, _server_move)
		_server_consumed_jump_serial = _server_jump_serial
		_server_consumed_drop_item_serial = _server_drop_item_serial
		_server_consumed_flashlight_serial = _server_flashlight_serial
		if _server_interact_serial != _server_consumed_interact_serial:
			_server_consumed_interact_serial = _server_interact_serial
			vehicle.exit_driver()
		return
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
	):
		_server_consumed_flashlight_serial = _server_flashlight_serial
		toggle_flashlight_authoritative()
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
	if is_driving():
		update_vehicle_look(_input_yaw, _input_pitch)
		return
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


@export_range(0.05, 0.8, 0.01) var max_step_height := 0.42

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
	head.rotation.y = 0
	head.rotation.x = pitch
	update_crouch_state(delta, crouching)
	if debug_fly and not survival.dead:
		var flight_direction := head.global_basis * Vector3(move_input.x, 0, move_input.y)
		flight_direction.y += _flight_vertical
		velocity = flight_direction.limit_length() * (18.0 if sprinting else 7.0)
		if debug_across:
			global_position += velocity * delta
		else:
			move_and_slide()
		survival.reset_fall()
		return

	if not is_on_floor():
		var gravity_scale := fall_gravity_multiplier if velocity.y < 0.0 else 1.0
		velocity.y -= gravity * gravity_scale * delta
	elif velocity.y < 0.0:
		velocity.y = 0.0

	if should_jump and is_on_floor() and not _is_crouching:
		velocity.y = jump_velocity

	var input_direction := Vector3(move_input.x, 0.0, move_input.y)
	var world_direction := transform.basis * input_direction.limit_length(1.0)
	var speed := (
		crouch_speed
		if _is_crouching
		else sprint_speed if sprinting else walk_speed
	)
	var carried_weight := 0.0
	for item in get_tree().get_nodes_in_group("world_items"):
		if item is WorldItemPickup and not item._collected and item.global_position.distance_to(global_position) < 0.75:
			item.linear_velocity += (item.global_position - global_position).normalized() * 1.5
			carried_weight = maxf(carried_weight, item.get_push_resistance())
	var target_velocity := world_direction * speed / (1.0 + carried_weight * 0.06)
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
	var incoming_y := velocity.y
	if not preload("res://scripts/characters/components/step_motion.gd").try_step(self, delta, max_step_height):
		move_and_slide()
	survival.observe_motion(incoming_y, is_on_floor(), get_platform_velocity().y)
	if multiplayer.is_server():
		_noise_step_left = maxf(0.0, _noise_step_left - delta)
		if is_on_floor() and not survival.dead and not _is_crouching and sprinting and Vector2(velocity.x, velocity.z).length() > 3.0 and _noise_step_left <= 0.0:
			_noise_step_left = 0.5
			preload("res://scripts/gameplay/gameplay_noise.gd").emit(self, 12.0)


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
	if survival.dead:
		return
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

	if is_driving():
		interaction_prompt_label.visible = true
		interaction_prompt_label.text = "Бензин: %.0f%%" % (vehicle.fuel_liters / vehicle.tank_capacity * 100.0)
		return

	if $ItemDrag.dragging:
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
	if prompt.strip_edges().is_empty():
		interaction_prompt_label.visible = false
		return
	interaction_prompt_label.text = "%s %s" % [get_node("/root/SteamInput").get_action_hint(&"interact"), prompt]
	interaction_prompt_label.visible = true


func _is_journal_open() -> bool:
	if get_tree().get_first_node_in_group("wiring_ui") != null:
		return true
	var journal := get_node_or_null("/root/QuestJournal")
	return journal != null and bool(journal.call("is_journal_open"))


func teleport_authoritative(
	next_global_position: Vector3,
	next_yaw: float = 0.0
) -> void:
	if not multiplayer.is_server():
		return
	survival.reset_fall()
	_receive_authoritative_teleport.rpc(next_global_position, next_yaw)


func enter_bunk_sleep_authoritative(sleep_transform: Transform3D) -> void:
	if survival.dead:
		return
	if multiplayer.is_server():
		_receive_bunk_sleep_state.rpc(true, sleep_transform)


func leave_bunk_sleep_authoritative(wake_transform: Transform3D) -> void:
	if multiplayer.is_server():
		_receive_bunk_sleep_state.rpc(false, wake_transform)


func request_leave_bunk_sleep() -> void:
	if not is_local_player() or not _is_sleeping_in_bunk:
		return
	if multiplayer.is_server():
		_server_request_leave_bunk(owner_peer_id)
	else:
		_request_leave_bunk_sleep.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable", 0)
func _request_leave_bunk_sleep() -> void:
	if multiplayer.is_server():
		_server_request_leave_bunk(multiplayer.get_remote_sender_id())


func _server_request_leave_bunk(peer_id: int) -> void:
	if not multiplayer.is_server() or peer_id != owner_peer_id:
		return
	for bunk in get_tree().get_nodes_in_group("end_day_bunks"):
		if bunk.has_method("cancel_sleep_authoritative"):
			if bool(bunk.call("cancel_sleep_authoritative", peer_id, self)):
				return


func apply_weapon_damage(amount: float) -> void:
	if multiplayer.is_server():
		survival.damage(amount, "Огнестрельное ранение")


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
	_remote_target_position = position
	_remote_target_velocity = Vector3.ZERO
	_remote_target_yaw = rotation.y
	_remote_target_pitch = PI * 0.5 if is_sleeping else 0.0
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
		head.rotation = Vector3(PI * 0.5, 0, 0)
		_input_pitch = PI * 0.5
		_server_pitch = PI * 0.5
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
	if not multiplayer.is_server() or survival.dead:
		return false

	if item_type == &"pistol_ammo":
		var amount := int(item_state.get("amount", 12))
		if amount <= 0 or weapon.pistol_ammo + amount > 240:
			return false
		weapon.pistol_ammo += amount
		_publish_inventory()
		return true
	if item_type == &"rifle_magazine":
		var amount := int(item_state.get("rounds", 30))
		if amount <= 0 or amount > 30 or weapon.rifle_magazines.size() >= 10:
			return false
		weapon.rifle_magazines.append(amount)
		_publish_inventory()
		return true

	if item_type == BATTERY_ITEM:
		if _spare_batteries.size() >= MAX_SPARE_BATTERIES:
			return false
		var charge_amount := clampf(float(item_state.get("charge_amount", 1.0)), 0.0, 1.0)
		if charge_amount <= 0.0:
			return false
		_spare_batteries.append(charge_amount)
		_publish_inventory()
		return true
	if item_type == &"tape":
		tape_count += 1
		_publish_inventory()
		return true
	if item_type == &"crowbar":
		if crowbar_uses > 0:
			return false
		crowbar_uses = clampi(int(item_state.get("uses", 3)), 1, 3)
		_publish_inventory()
		return true

	if item_type not in [FLASHLIGHT_ITEM, FUSE_ITEM, FUEL_ITEM] and not WeaponController.TYPES.has(item_type):
		return false
	if item_type == FLASHLIGHT_ITEM:
		if _has_flashlight:
			return false
		_has_flashlight = true
		_battery_charge = clampf(float(item_state.get("battery_charge", 1.0)), 0.0, 1.0)
		if _held_item_type == NO_ITEM:
			_held_item_type = FLASHLIGHT_ITEM
			_flashlight_enabled = _battery_charge > 0.0
	else:
		# Equipment is pocketed, only another bulky hand item is dropped.
		if _held_item_type not in [NO_ITEM, FLASHLIGHT_ITEM]:
			spawn_dropped_item_authoritative(_held_item_type, get_held_item_state())
			if weapon_light_mounted:
				_has_flashlight = false
				_battery_charge = 0.0
				weapon_light_mounted = false
		_held_item_type = item_type
		if item_type == FUEL_ITEM:
			fuel_liters = clampf(float(item_state.get("fuel_liters", 20.0)), 0.0, 20.0)
		if WeaponController.TYPES.has(item_type):
			if item_state.has("mounted_charge") and item_type != &"kitchen_knife":
				if _has_flashlight:
					spawn_dropped_item_authoritative(FLASHLIGHT_ITEM, {"battery_charge": _battery_charge})
				_has_flashlight = true
				weapon_light_mounted = true
				_battery_charge = clampf(float(item_state.mounted_charge), 0.0, 1.0)
			weapon.reload_left = 0.0
			weapon.rounds = clampi(int(item_state.get("rounds", WeaponController.CAPACITY[item_type])), 0, WeaponController.CAPACITY[item_type])
		_flashlight_enabled = false
		_flashlight_malfunctioning = false
	_publish_inventory()
	return true


func get_inventory_snapshot() -> Dictionary:
	return {
		"held_item": _held_item_type,
		"debug_fly": debug_fly,
		"debug_across": debug_across,
		"fuel_liters": fuel_liters,
		"tape_count": tape_count,
		"crowbar_uses": crowbar_uses,
		"weapon_light_mounted": weapon_light_mounted,
		"has_flashlight": _has_flashlight,
		"battery_charge": _battery_charge,
		"spare_batteries": _spare_batteries.duplicate(),
		"flashlight_enabled": _flashlight_enabled,
		"malfunctioning": _flashlight_malfunctioning,
		"revision": _inventory_revision,
		"weapon_rounds": weapon.rounds if weapon != null else 0,
		"pistol_ammo": weapon.pistol_ammo if weapon != null else 0,
		"rifle_magazines": weapon.rifle_magazines.duplicate() if weapon != null else [],
		"weapon_reload": weapon.reload_left if weapon != null else 0.0,
	}


func _publish_inventory() -> void:
	_inventory_revision += 1
	_receive_equipment.rpc(get_inventory_snapshot())
	var world := get_tree().get_first_node_in_group("network_gameplay_controller")
	if world != null and world.has_method("save_inventory_checkpoint"):
		world.call_deferred("save_inventory_checkpoint")


@rpc("authority", "call_local", "reliable", 2)
func _receive_equipment(data: Dictionary) -> void:
	apply_inventory_snapshot(data)


func apply_inventory_snapshot(data: Dictionary) -> void:
	var revision := int(data.get("revision", _inventory_revision))
	if revision < _inventory_revision:
		return
	_inventory_revision = revision
	debug_fly = bool(data.get("debug_fly", false))
	debug_across = bool(data.get("debug_across", false))
	tape_count = maxi(0, int(data.get("tape_count", 0)))
	crowbar_uses = clampi(int(data.get("crowbar_uses", 0)), 0, 3)
	weapon_light_mounted = bool(data.get("weapon_light_mounted", false)) and StringName(data.get("held_item", "")) in [&"pistol", &"m4a1"] and bool(data.get("has_flashlight", false))
	fuel_liters = clampf(float(data.get("fuel_liters", 20.0)), 0.0, 20.0)
	_has_flashlight = bool(data.get("has_flashlight", false))
	_battery_charge = clampf(float(data.get("battery_charge", 0.0)), 0.0, 1.0) if _has_flashlight else 0.0
	_spare_batteries.clear()
	for charge: Variant in data.get("spare_batteries", []):
		if _spare_batteries.size() >= MAX_SPARE_BATTERIES:
			break
		if float(charge) > 0.0:
			_spare_batteries.append(clampf(float(charge), 0.0, 1.0))
	_held_item_type = StringName(data.get("held_item", NO_ITEM))
	weapon.pistol_ammo = clampi(int(data.get("pistol_ammo", 0)), 0, 240)
	weapon.rifle_magazines.clear()
	for magazine: Variant in data.get("rifle_magazines", []):
		if weapon.rifle_magazines.size() < 10 and int(magazine) > 0:
			weapon.rifle_magazines.append(clampi(int(magazine), 1, 30))
	weapon.apply_state(_held_item_type, int(data.get("weapon_rounds", WeaponController.CAPACITY.get(_held_item_type, 0))), float(data.get("weapon_reload", 0.0)))
	if _held_item_type == FLASHLIGHT_ITEM and not _has_flashlight:
		_held_item_type = NO_ITEM
	_flashlight_malfunctioning = bool(data.get("malfunctioning", false)) and _held_item_type == FLASHLIGHT_ITEM and _battery_charge > 0.0
	_flashlight_enabled = bool(data.get("flashlight_enabled", false)) and (_held_item_type == FLASHLIGHT_ITEM or weapon_light_mounted) and _battery_charge > 0.0 and not _flashlight_malfunctioning
	_refresh_equipment_visuals()
	inventory_changed.emit()


func toggle_flashlight_authoritative() -> bool:
	if survival.dead:
		return false
	if not multiplayer.is_server() or not _has_flashlight or _is_sleeping_in_bunk:
		return false
	if _held_item_type not in [NO_ITEM, FLASHLIGHT_ITEM]:
		if weapon_light_mounted:
			_flashlight_enabled = not _flashlight_enabled and _battery_charge > 0.0
			_publish_inventory()
			return true
		_show_pocket_light_notice.rpc_id(owner_peer_id)
		return false
	_held_item_type = NO_ITEM if _held_item_type == FLASHLIGHT_ITEM else FLASHLIGHT_ITEM
	_flashlight_enabled = _held_item_type == FLASHLIGHT_ITEM and _battery_charge > 0.0
	_flashlight_malfunctioning = false
	_publish_inventory()
	return true


func request_inventory_action(action: StringName) -> void:
	if not is_local_player():
		return
	if multiplayer.is_server():
		_begin_inventory_action(action)
	else:
		_request_inventory_action.rpc_id(1, action)


func request_reload_or_battery() -> void:
	request_inventory_action(&"reload_or_battery")


@rpc("authority", "call_local", "reliable")
func _show_pocket_light_notice() -> void:
	_equipment_notice_until = Time.get_ticks_msec() + 2200
	update_battery_ui()


@rpc("any_peer", "call_remote", "reliable", 0)
func _request_inventory_action(action: StringName) -> void:
	if multiplayer.is_server() and multiplayer.get_remote_sender_id() == owner_peer_id:
		_begin_inventory_action(action)


func _begin_inventory_action(action: StringName) -> void:
	if survival.dead:
		return
	if action == &"reload_or_battery":
		if _battery_action_busy:
			return
		if WeaponController.TYPES.has(_held_item_type) and not (weapon_light_mounted and _battery_charge <= 0.0 and not _spare_batteries.is_empty()):
			weapon.perform_action(&"reload")
			return
		action = &"replace_battery"
	if action != &"replace_battery":
		perform_inventory_action_authoritative(action)
		return
	if _battery_action_busy or _is_sleeping_in_bunk or not _has_flashlight or _spare_batteries.is_empty():
		return
	if float(_spare_batteries.max()) <= _battery_charge:
		return
	_battery_action_busy = true
	var revision := _inventory_revision
	_play_battery_action.rpc()
	# No cell is removed before the insertion marker. Any inventory change
	# (drop, pickup, stow, load) invalidates this pending transaction.
	await get_tree().create_timer(0.72, false).timeout
	if revision == _inventory_revision and not _is_sleeping_in_bunk:
		perform_inventory_action_authoritative(&"replace_battery")
	await get_tree().create_timer(0.38, false).timeout
	_battery_action_busy = false


@rpc("authority", "call_local", "reliable", 2)
func _play_battery_action() -> void:
	if weapon_light_mounted:
		weapon.play_mounted_battery_action()
	else:
		flashlight.play_battery_action()


func perform_inventory_action_authoritative(action: StringName) -> bool:
	if is_driving():
		return false
	if survival.dead:
		return false
	if not multiplayer.is_server() or _is_sleeping_in_bunk:
		return false
	match action:
		&"mount_light":
			if tape_count <= 0 or not _has_flashlight or weapon_light_mounted or _held_item_type not in [&"pistol", &"m4a1"]:
				return false
			tape_count -= 1
			weapon_light_mounted = true
			_flashlight_enabled = _battery_charge > 0.0
		&"detach_light":
			if not weapon_light_mounted:
				return false
			weapon_light_mounted = false
			_flashlight_enabled = false
		&"drop_crowbar":
			if crowbar_uses <= 0:
				return false
			spawn_dropped_item_authoritative(&"crowbar", {"uses": crowbar_uses})
			crowbar_uses = 0
		&"drop_tape":
			if tape_count <= 0:
				return false
			spawn_dropped_item_authoritative(&"tape", {})
			tape_count -= 1
		&"drop_hand_item":
			return drop_current_item_authoritative()
		&"replace_battery":
			if not _has_flashlight or _spare_batteries.is_empty():
				return false
			# Choose the fullest cell; replacing never reduces the current charge.
			var best_charge: float = _spare_batteries.max()
			if best_charge <= _battery_charge:
				return false
			_spare_batteries.erase(best_charge)
			if _battery_charge > 0.0:
				_spare_batteries.append(_battery_charge)
			_battery_charge = best_charge
			_flashlight_malfunctioning = false
			_flashlight_enabled = _held_item_type == FLASHLIGHT_ITEM or weapon_light_mounted
		&"drop_battery":
			if _spare_batteries.is_empty():
				return false
			spawn_dropped_item_authoritative(BATTERY_ITEM, {"charge_amount": _spare_batteries.pop_back()})
		&"drop_flashlight":
			if not _has_flashlight:
				return false
			spawn_dropped_item_authoritative(FLASHLIGHT_ITEM, {"battery_charge": _battery_charge})
			_has_flashlight = false
			weapon_light_mounted = false
			_battery_charge = 0.0
			_flashlight_enabled = false
			_flashlight_malfunctioning = false
			if _held_item_type == FLASHLIGHT_ITEM:
				_held_item_type = NO_ITEM
		_:
			return false
	_publish_inventory()
	return true


func get_held_item_state() -> Dictionary:
	if _held_item_type == FUEL_ITEM:
		return {"fuel_liters": fuel_liters}
	if WeaponController.TYPES.has(_held_item_type):
		var state := {"rounds": weapon.rounds}
		if weapon_light_mounted:
			state["mounted_charge"] = _battery_charge
		return state
	if _held_item_type == FLASHLIGHT_ITEM:
		return {"battery_charge": _battery_charge}
	return {}


@rpc("authority", "call_local", "reliable")
func play_crowbar_action() -> void:
	var model := preload("res://scripts/gameplay/tool_models.gd").build(&"crowbar")
	head.add_child(model)
	model.position = Vector3(0.2, -0.1, -0.6)
	model.rotation = Vector3(-0.5, -0.25, 0.3)
	var motion := model.create_tween()
	motion.tween_property(model, "rotation:x", 0.3, 0.8).set_trans(Tween.TRANS_SINE)
	motion.tween_property(model, "position:y", -0.6, 0.4)
	motion.tween_callback(model.queue_free)


func get_held_item_drop_transform() -> Transform3D:
	var forward := -head.global_basis.z.normalized()
	var start := head.global_position
	var desired := start + forward * 0.7 + Vector3.DOWN * 0.35
	# Sweep a conservative item volume, not a ray: never spawn beyond a wall
	# or beneath the floor when looking down next to a surface.
	var shape := SphereShape3D.new()
	shape.radius = 0.3
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis.IDENTITY, start)
	query.motion = desired - start
	query.collision_mask = 1
	query.exclude = [get_rid()]
	var fractions := get_world_3d().direct_space_state.cast_motion(query)
	if fractions.size() > 0:
		desired = start + query.motion * maxf(fractions[0] - 0.03, 0.0)
	return Transform3D(
		head.global_basis.orthonormalized(),
		desired
	)


func get_held_item_drop_linear_velocity() -> Vector3:
	return velocity + -head.global_basis.z.normalized() * 1.1


func drop_current_item_authoritative() -> bool:
	if survival.dead:
		return false
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
	_held_item_type = NO_ITEM
	if dropped_item_type == FLASHLIGHT_ITEM or weapon_light_mounted:
		weapon_light_mounted = false
		_has_flashlight = false
		_battery_charge = 0.0
	_flashlight_enabled = false
	_flashlight_malfunctioning = false
	_publish_inventory()
	spawn_dropped_item_authoritative(
		dropped_item_type,
		dropped_item_state,
		drop_transform,
		drop_velocity
	)
	return true


func has_held_item(item_type: StringName) -> bool:
	return _held_item_type == item_type


func drop_all_items_at_authoritative(drop_transform: Transform3D) -> void:
	if not multiplayer.is_server():
		return
	drop_current_item_at_authoritative(drop_transform)
	if crowbar_uses > 0:
		spawn_dropped_item_authoritative(&"crowbar", {"uses": crowbar_uses}, drop_transform, Vector3.ZERO)
	for index in tape_count:
		spawn_dropped_item_authoritative(&"tape", {}, drop_transform, Vector3.ZERO)
	crowbar_uses = 0
	tape_count = 0
	if _has_flashlight:
		spawn_dropped_item_authoritative(FLASHLIGHT_ITEM, {"battery_charge": _battery_charge}, drop_transform, Vector3.ZERO)
	for charge in _spare_batteries:
		spawn_dropped_item_authoritative(BATTERY_ITEM, {"charge_amount": charge}, drop_transform, Vector3.ZERO)
	_has_flashlight = false
	_battery_charge = 0.0
	_spare_batteries.clear()
	_publish_inventory()
	if weapon.pistol_ammo > 0:
		spawn_dropped_item_authoritative(&"pistol_ammo", {"amount": weapon.pistol_ammo}, drop_transform, Vector3.ZERO)
	for magazine: int in weapon.rifle_magazines:
		spawn_dropped_item_authoritative(&"rifle_magazine", {"rounds": magazine}, drop_transform, Vector3.ZERO)
	weapon.pistol_ammo = 0
	weapon.rifle_magazines.clear()
	_publish_inventory()


func consume_held_item_authoritative(item_type: StringName) -> bool:
	if not multiplayer.is_server() or _held_item_type != item_type:
		return false
	_held_item_type = NO_ITEM
	_publish_inventory()
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
		else BATTERY_PICKUP_SCENE if item_type == BATTERY_ITEM
		else FUEL_PICKUP_SCENE if item_type == FUEL_ITEM
		else preload("res://scenes/objects/items/tool_pickup.tscn") if item_type in [&"tape", &"crowbar"]
		else preload("res://scenes/objects/items/weapon_pickup.tscn") if WeaponController.TYPES.has(item_type) or item_type in [&"pistol_ammo", &"rifle_magazine"] else null
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
		_flashlight_enabled = false
		_publish_inventory()


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
		_server_last_sequence,
		get_inventory_snapshot()
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
	_acknowledged_input: int,
	server_inventory: Dictionary = {}
) -> void:
	if not server_inventory.is_empty():
		apply_inventory_snapshot(server_inventory)
	else:
		apply_inventory_snapshot({
			"held_item": server_held_item_type,
			"has_flashlight": server_has_flashlight,
			"battery_charge": server_battery_charge,
			"flashlight_enabled": server_flashlight_enabled,
			"malfunctioning": server_flashlight_malfunctioning,
		})

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
	if is_driving():
		return
	if _reconciliation_offset.is_zero_approx():
		return

	var weight := 1.0 - exp(-reconciliation_speed * delta)
	var correction := _reconciliation_offset * weight
	position += correction
	_reconciliation_offset -= correction


func interpolate_remote_player(delta: float) -> void:
	if not _has_remote_snapshot or _is_sleeping_in_bunk or is_driving():
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
	_battery_charge = clampf(battery_charge, 0.0, 1.0) if has_flashlight else 0.0
	if _held_item_type in [NO_ITEM, FLASHLIGHT_ITEM]:
		_held_item_type = FLASHLIGHT_ITEM if has_flashlight and enabled else NO_ITEM
	_flashlight_enabled = enabled and _held_item_type == FLASHLIGHT_ITEM
	_flashlight_malfunctioning = malfunctioning and _held_item_type == FLASHLIGHT_ITEM
	_refresh_equipment_visuals()
	inventory_changed.emit()


func apply_held_item_inventory(
	item_type: StringName,
	item_state: Dictionary,
	flashlight_enabled: bool = false,
	malfunctioning: bool = false
) -> void:
	_held_item_type = item_type
	if item_type == FLASHLIGHT_ITEM:
		_has_flashlight = true
		_battery_charge = clampf(float(item_state.get("battery_charge", 1.0)), 0.0, 1.0)
	_flashlight_malfunctioning = (
		malfunctioning and item_type == FLASHLIGHT_ITEM and _battery_charge > 0.0
	)
	_flashlight_enabled = (
		flashlight_enabled
		and item_type == FLASHLIGHT_ITEM
		and _battery_charge > 0.0
		and not _flashlight_malfunctioning
	)
	_refresh_equipment_visuals()
	inventory_changed.emit()


func _refresh_equipment_visuals() -> void:
	flashlight.set_battery_charge(_battery_charge, false)
	flashlight.set_equipped(_held_item_type == FLASHLIGHT_ITEM)
	if _flashlight_malfunctioning:
		flashlight.set_enabled(true, false)
		flashlight.begin_malfunction(true)
	else:
		if flashlight.is_malfunctioning:
			flashlight.cancel_malfunction()
		flashlight.set_enabled(_flashlight_enabled and not weapon_light_mounted, false)
	held_fuse.visible = _held_item_type == FUSE_ITEM
	held_fuel_can.visible = _held_item_type == FUEL_ITEM
	update_battery_ui()


func _on_authoritative_flashlight_malfunction_started() -> void:
	if not multiplayer.is_server():
		return
	_flashlight_malfunctioning = true
	_flashlight_enabled = false


func update_battery_ui() -> void:
	if is_local_player() and _has_flashlight and Time.get_ticks_msec() < _equipment_notice_until and not _is_journal_open() and not get_node("/root/GameMenu").is_menu_open():
		battery_label.visible = true
		battery_label.text = "Фонарик в инвентаре · сначала освободите руки"
		return
	battery_label.visible = is_local_player() and _has_flashlight and not _is_journal_open() and not get_node("/root/GameMenu").is_menu_open() and (_held_item_type == FLASHLIGHT_ITEM or _battery_charge <= 0.0)
	if not battery_label.visible:
		_displayed_battery_percent = -1
		return

	var battery_percent := roundi(_battery_charge * 100.0)
	_displayed_battery_percent = battery_percent
	battery_label.text = "%d%%" % battery_percent
	if _battery_charge <= 0.0:
		battery_label.text = "Батарея разряжена" if not _spare_batteries.is_empty() else "Нет запасных батареек"


func begin_vehicle_view(next_vehicle: Node3D) -> void:
	vehicle = next_vehicle
	head.rotation = Vector3.ZERO
	_input_pitch = 0.0
	_server_pitch = 0.0
	_input_yaw = next_vehicle.global_rotation.y
	_server_yaw = _input_yaw

func update_vehicle_look(yaw: float, pitch: float) -> void:
	var relative := clampf(wrapf(yaw - vehicle.global_rotation.y, -PI, PI), -deg_to_rad(110), deg_to_rad(110))
	head.rotation = Vector3(clampf(pitch, -deg_to_rad(65), deg_to_rad(65)), relative, 0)
	if is_local_player():
		_input_yaw = vehicle.global_rotation.y + relative
		_input_pitch = head.rotation.x
