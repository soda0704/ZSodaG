class_name GamePlayer
extends CharacterBody3D

signal inventory_changed

const LOCAL_INPUT_SCRIPT = preload("res://scripts/characters/components/player_local_input.gd")
const LOCOMOTION_SCRIPT = preload("res://scripts/characters/components/player_locomotion.gd")
const INVENTORY_ACTIONS = preload("res://scripts/characters/components/player_inventory_actions.gd")
var _local_input: LOCAL_INPUT_SCRIPT = LOCAL_INPUT_SCRIPT.new()
var _locomotion: LOCOMOTION_SCRIPT = LOCOMOTION_SCRIPT.new()


var survival: PlayerSurvival
var debug_fly := false
var debug_across := false
var debug_speed_multiplier := 1.0
var _flight_vertical: float:
	get: return _local_input.flight_vertical
	set(value): _local_input.flight_vertical = value
var weapon: WeaponController
var vehicle: Node3D
var debug_free_camera

func is_debug_free_camera_active() -> bool:
	return is_instance_valid(debug_free_camera) and debug_free_camera.enabled

func is_climbing() -> bool:
	return has_node("LadderClimb") and is_instance_valid($LadderClimb.route)


func is_driving() -> bool:
	return is_instance_valid(vehicle)

const NO_ITEM := &""
const FLASHLIGHT_ITEM := &"flashlight"
const FUSE_ITEM := &"fuse"
const SEED_ITEM := &"seed_packet"
const SEED_PICKUP_SCENE := preload("res://scenes/objects/items/seed_packet_pickup.tscn")
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
@export_range(0, 1) var character_variant_id := 0

@export_group("Movement")
@export var walk_speed: float = 4.0
@export var sprint_speed: float = 6.8
@export_range(0.5, 30.0) var sprint_duration: float = 10.0
## Seconds of sprint restored per second of walking or resting.
@export_range(0.1, 5.0) var sprint_recovery_per_second: float = 1.0
## Small reserve needed only after complete exhaustion, to avoid tick-by-tick toggling.
@export_range(0.1, 5.0) var sprint_restart_reserve: float = 1.0
var _sprint_remaining: float:
	get: return _locomotion.sprint_remaining
	set(value): _locomotion.sprint_remaining = value
var _sprint_exhausted: bool:
	get: return _locomotion.sprint_exhausted
	set(value): _locomotion.sprint_exhausted = value
var _sprint_active: bool:
	get: return _locomotion.sprint_active
	set(value): _locomotion.sprint_active = value
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

@export_group("Loose item contact")
@export_range(0.0, 30.0) var item_push_acceleration := 12.0

@export_group("Flashlight")
@export_range(5.0, 1800.0, 1.0) var battery_duration_seconds: float = 120.0

@export_group("Networking")
@export var remote_interpolation_speed: float = 14.0
@export var reconciliation_speed: float = 8.0
@export var hard_reconciliation_distance: float = 1.5

@onready var head: Node3D = %Head
@onready var camera: FirstPersonCameraMotion = %Camera3D
@onready var collision_shape: CollisionShape3D = %CollisionShape3D
@onready var body_animator: GameCharacterPresentation = %BodyVisual
@onready var name_label: Label3D = %NameLabel
@onready var flashlight: PlayerFlashlight = %Flashlight
@onready var handoff = $ItemHandoff
@onready var held_seed_packet: Node3D = %HeldSeedPacket
@onready var held_fuse: Node3D = %HeldFuse
@onready var held_fuel_can: Node3D = %HeldFuelCan
@export_range(0.5, 10.0) var interaction_reach := 3.0
@onready var interaction_ray: RayCast3D = %InteractionRay
@onready var item_focus: PlayerItemFocus = %ItemFocus
@onready var interaction_prompt_label: Label = %InteractionPromptLabel
@onready var battery_label: Label = %BatteryLabel
@onready var player_audio: Node = $PlayerAudio
@onready var crosshair: Control = %Crosshair

var gravity: float = float(
	ProjectSettings.get_setting("physics/3d/default_gravity")
)

var _input_move: Vector2:
	get: return _local_input.input_move
	set(value): _local_input.input_move = value
var _input_sprint: bool:
	get: return _local_input.input_sprint
	set(value): _local_input.input_sprint = value
var _input_crouch: bool:
	get: return _local_input.input_crouch
	set(value): _local_input.input_crouch = value
var _input_yaw: float:
	get: return _local_input.input_yaw
	set(value): _local_input.input_yaw = value
var _input_pitch: float:
	get: return _local_input.input_pitch
	set(value): _local_input.input_pitch = value
var _jump_serial: int:
	get: return _local_input.jump_serial
	set(value): _local_input.jump_serial = value
var _flashlight_serial: int:
	get: return _local_input.flashlight_serial
	set(value): _local_input.flashlight_serial = value
var _interact_serial: int:
	get: return _local_input.interact_serial
	set(value): _local_input.interact_serial = value
var _drop_item_serial: int:
	get: return _local_input.drop_item_serial
	set(value): _local_input.drop_item_serial = value
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
const REPLICATION_SCRIPT = preload("res://scripts/characters/components/player_state_replication.gd")
var _replication: REPLICATION_SCRIPT = REPLICATION_SCRIPT.new()
var _snapshot_send_accumulator: float:
	get: return _replication.send_accumulator
	set(value): _replication.send_accumulator = value

var _client_consumed_jump_serial: int = 0
var _reconciliation_offset: Vector3:
	get: return _replication.correction_offset
	set(value): _replication.correction_offset = value
var _remote_target_position: Vector3:
	get: return _replication.target_position
	set(value): _replication.target_position = value
var _remote_target_velocity: Vector3:
	get: return _replication.target_velocity
	set(value): _replication.target_velocity = value
var _remote_target_yaw: float:
	get: return _replication.target_yaw
	set(value): _replication.target_yaw = value
var _remote_target_pitch: float:
	get: return _replication.target_pitch
	set(value): _replication.target_pitch = value
var _remote_crouching: bool:
	get: return _replication.crouching
	set(value): _replication.crouching = value
var _remote_grounded: bool:
	get: return _replication.grounded
	set(value): _replication.grounded = value
var _journal_phase := 0
@export_range(1.0, 2.5) var journal_animation_speed := 1.6
var has_journal := false
var _journal_map := false
var _journal_loupe := false
var _aiming := false
var _aim_serial_state := false
var _has_remote_snapshot: bool:
	get: return _replication.has_snapshot
	set(value): _replication.has_snapshot = value
const EQUIPMENT_SCRIPT = preload("res://scripts/characters/components/player_equipment.gd")
var _equipment: EQUIPMENT_SCRIPT = EQUIPMENT_SCRIPT.new()
var _has_flashlight: bool:
	get: return _equipment.has_flashlight
	set(value): _equipment.has_flashlight = value
@export_range(0.2, 1.0) var corpse_carry_speed_multiplier := 0.6
var carried_corpse: Node3D
var corpse_action_busy := false

func is_carrying_corpse() -> bool:
	return is_instance_valid(carried_corpse)

var _held_item_type: StringName:
	get: return _equipment.held_item
	set(value): _equipment.held_item = value
var _handheld_flashlight_drawn: bool:
	get: return _equipment.handheld_drawn
	set(value): _equipment.handheld_drawn = value
var _battery_flashlight_presentation := false
var _flashlight_enabled: bool:
	get: return _equipment.enabled
	set(value): _equipment.enabled = value
var _flashlight_malfunctioning: bool:
	get: return _equipment.malfunctioning
	set(value): _equipment.malfunctioning = value
const FLASHLIGHT_SHAKE_PRESSES := 6
var _flashlight_shake_presses := 0
var _last_flashlight_shake_msec := -1000
var _battery_charge: float:
	get: return _equipment.charge
	set(value): _equipment.charge = value
var _displayed_battery_percent: int = -1
var _is_crouching: bool:
	get: return _locomotion.is_crouching
	set(value): _locomotion.is_crouching = value
var _is_sleeping_in_bunk: bool = false
const SUPPLIES_SCRIPT = preload("res://scripts/characters/components/player_supplies.gd")
var _supplies: SUPPLIES_SCRIPT = SUPPLIES_SCRIPT.new()
# Public gameplay properties delegate to one per-player state owner.
var _spare_batteries: Array[float]:
	get: return _supplies.spare_batteries
	set(value): _supplies.spare_batteries = value
var _inventory_revision: int = 0
# Handoffs publish only after both inventories contain the final ownership.
var _handoff_transaction := false
var fuel_liters := 20.0
var _battery_action_busy: bool = false
var _pad_sprint: bool:
	get: return _local_input.pad_sprint
	set(value): _local_input.pad_sprint = value
@export_group("AI movement noise")
@export_range(0.0, 50.0) var walking_noise_radius := 6.0
@export_range(0.0, 50.0) var sprinting_noise_radius := 14.0
@export_range(0.0, 5.0) var crouching_noise_radius := 0.8
@export_range(0.2, 3.0) var noise_stride := 1.5
var _noise_step_distance: float:
	get: return _locomotion.noise_step_distance
	set(value): _locomotion.noise_step_distance = value
const CRAFT_RECIPE = preload("res://assets/config/flamethrower_recipe.tres")
var crafting_parts: Dictionary:
	get: return _supplies.crafting_parts
	set(value): _supplies.crafting_parts = value
var tape_count: int:
	get: return _supplies.tape_count
	set(value): _supplies.tape_count = value
var crowbar_uses: int:
	get: return _supplies.crowbar_uses
	set(value): _supplies.crowbar_uses = value
var weapon_light_mounted: bool:
	get: return _equipment.mounted
	set(value): _equipment.mounted = value
var _equipment_notice_until := 0
var _pad_crouch: bool:
	get: return _local_input.pad_crouch
	set(value): _local_input.pad_crouch = value


func setup(
	peer_id: int,
	display_name_value: String,
	spawn_position: Vector3,
	color: Color,
	spawn_yaw: float = 0.0,
	visual_variant: int = 0
) -> void:
	owner_peer_id = peer_id
	player_display_name = display_name_value.left(32)
	position = spawn_position
	avatar_color = color
	character_variant_id = clampi(visual_variant,0,1)
	rotation.y = spawn_yaw
	_input_yaw = spawn_yaw
	_server_yaw = spawn_yaw


func _ready() -> void:
	_sprint_remaining = sprint_duration
	add_to_group("network_players")
	survival = preload("res://scripts/characters/components/player_survival.gd").new()
	survival.name = "Survival"
	add_child(survival)
	weapon = preload("res://scenes/characters/weapon_controller.tscn").instantiate()
	weapon.name = "Weapon"
	add_child(weapon)
	name_label.text = player_display_name
	name_label.modulate = avatar_color
	flashlight.reparent(body_animator.flashlight_socket(), false)
	flashlight.transform = Transform3D.IDENTITY
	flashlight.rig_attached = true
	flashlight.rig_animator = body_animator
	held_fuse.reparent(body_animator.equipment_socket("FuseGrip"), false)
	held_fuse.transform = Transform3D.IDENTITY
	held_seed_packet.reparent(body_animator.equipment_socket("FuseGrip"), false)
	held_seed_packet.transform = Transform3D.IDENTITY
	held_fuel_can.reparent(body_animator.equipment_socket("FuelGrip"), false)
	held_fuel_can.transform = Transform3D.IDENTITY

	var local_player := is_local_player()
	camera.current = local_player
	body_animator.visible = true
	for mesh in body_animator.find_children("*", "MeshInstance3D", true, false):
		mesh.layers |= 1 << 18 # Receive outdoor sunlight and cast a body shadow on snow.
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY if local_player else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	if local_player:
		for mesh: MeshInstance3D in body_animator.first_person_model.find_children("*","MeshInstance3D",true,false):
			mesh.layers = 1 << 19
			mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	name_label.visible = not local_player
	call_deferred("restore_journal_ownership")
	refresh_crosshair_visibility()
	get_node("/root/GameMenu").menu_root.visibility_changed.connect(refresh_crosshair_visibility)
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
	if local_player:
		debug_free_camera = preload("res://scripts/characters/components/debug_free_camera.gd").new()
		debug_free_camera.name = "DebugFreeCamera"
		add_child(debug_free_camera)


func _unhandled_input(event: InputEvent) -> void:
	_local_input._unhandled_input(self, event)


func _physics_process(delta: float) -> void:
	refresh_crosshair_visibility()
	if survival.dead:
		if multiplayer.is_server() and is_climbing(): $LadderClimb._set_route.rpc(NodePath(),$LadderClimb.revision+1,global_position)
		if multiplayer.is_server() or is_local_player():
			_update_sprint(delta)
		velocity = Vector3.ZERO
		interaction_prompt_label.hide()
		battery_label.hide()
		if multiplayer.is_server():
			send_snapshot_if_due(delta)
		return
	if is_local_player():
		collect_local_input()
		_update_aim_intent()
		_flight_vertical = (float(Input.is_action_pressed("jump")) - float(Input.is_action_pressed("crouch"))) if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not is_debug_free_camera_active() else 0.0
		collect_local_look(delta)
		refresh_interaction_prompt()
		update_battery_ui()

	if multiplayer.is_server():
		if is_local_player():
			copy_local_input_to_server()
		_update_sprint(delta)
		simulate_authoritative_movement(delta)
		update_authoritative_flashlight_battery(delta)
		send_snapshot_if_due(delta)
	elif is_local_player():
		_update_sprint(delta)
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


func refresh_crosshair_visibility() -> void:
	crosshair.visible = is_local_player() and not survival.dead and not is_bunk_busy() and not is_debug_free_camera_active() and not _is_journal_open() and not get_node("/root/GameMenu").is_menu_open()


func _update_sprint(delta: float) -> void:
	_locomotion._update_sprint(self, delta)


func collect_local_input() -> void:
	_local_input.collect_local_input(self)


func collect_local_look(delta: float) -> void:
	_local_input.collect_local_look(self, delta)


func _get_steam_input_vector(method_name: StringName) -> Vector2:
	return _local_input._get_steam_input_vector(self, method_name)


func update_local_view_motion(delta: float) -> void:
	var horizontal_speed := Vector2(velocity.x, velocity.z).length()
	var reference_speed := (
		crouch_speed
		if _is_crouching
		else sprint_speed if _sprint_active else walk_speed
	)
	var movement_ratio := horizontal_speed / maxf(reference_speed, 0.001)
	camera.update_motion(
		delta,
		movement_ratio,
		is_on_floor(),
		_sprint_active,
		_is_crouching,
		_aiming
	)
	flashlight.update_motion(
		delta,
		movement_ratio,
		is_on_floor(),
		_sprint_active
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
		else _sprint_active
	)
	var grounded := _remote_grounded if is_remote_client_player else is_on_floor()
	body_animator.update_context(delta,{
		"velocity": animation_velocity,
		"grounded": grounded,
		"sprinting": sprinting and not crouching,
		"crouching": crouching,
		"yaw": rotation.y,
		"pitch": head.rotation.x,
		"held_item": NO_ITEM if is_climbing() or handoff.pocket_pose() or $ItemDrag.is_heavy_carrying() else FLASHLIGHT_ITEM if _battery_flashlight_presentation else _held_item_type,
		"offering": handoff.is_offering() or $ItemDrag.is_heavy_carrying(),
		"heavy_carry": $ItemDrag.is_heavy_carrying(),
		"heavy_targets": $ItemDrag.heavy_body.hand_targets(owner_peer_id) if $ItemDrag.is_heavy_carrying() else {},
		"body_transform": get_global_transform_interpolated(),
		"offer_pocket": handoff.pocket_pose() or $ItemDrag.is_heavy_carrying(),
		"offhand_flashlight": is_offhand_flashlight_drawn() and not _battery_flashlight_presentation and not $ItemDrag.is_heavy_carrying() and not handoff.pocket_pose(),
		"journal_phase": _journal_phase,
		"journal_map": _journal_map,
		"journal_loupe": _journal_loupe,
		"journal_animation_speed": journal_animation_speed,
		"carrying": is_carrying_corpse(),
		"driving": is_driving(),
		"bunk_busy": is_bunk_busy(),
		"climbing": is_climbing(),
		"climb_phase": $LadderClimb.phase(),
		"reloading": weapon != null and weapon.reload_left>0.0,
		"aiming": _aiming and not handoff.is_offering() and not $ItemDrag.is_heavy_carrying()
	})
	name_label.visible = not is_local_player() and not is_bunk_busy()
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
		vehicle.set_driver_input(owner_peer_id, _server_move, _server_sprint)
		_server_consumed_jump_serial = _server_jump_serial
		_server_consumed_drop_item_serial = _server_drop_item_serial
		_server_consumed_flashlight_serial = _server_flashlight_serial
		if _server_interact_serial != _server_consumed_interact_serial:
			_server_consumed_interact_serial = _server_interact_serial
			vehicle.exit_driver()
		return
	if is_bunk_busy():
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
	if is_bunk_busy():
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
	_locomotion.simulate_movement(self, delta, move_input, sprinting, crouching, should_jump, yaw, pitch)


func get_movement_noise_radius() -> float:
	return _locomotion.get_movement_noise_radius(self)


func _emit_movement_noise(travel: Vector3, grounded: bool) -> void:
	_locomotion._emit_movement_noise(self, travel, grounded)


func update_crouch_state(delta: float, wants_to_crouch: bool) -> void:
	_locomotion.update_crouch_state(self, delta, wants_to_crouch)


func can_stand_up() -> bool:
	return _locomotion.can_stand_up(self)


func get_interaction_target() -> Node:
	interaction_ray.target_position = Vector3(0, 0, -interaction_reach)
	interaction_ray.collision_mask = 4 if debug_across else 5
	force_update_transform()
	head.force_update_transform()
	camera.force_update_transform()
	interaction_ray.force_update_transform()
	interaction_ray.force_raycast_update()
	return item_focus.resolve_target(interaction_ray.get_collider() as Node)

func try_authoritative_interaction() -> void:
	if is_climbing(): return
	if survival.dead:
		return
	if not multiplayer.is_server():
		return
	if needs_flashlight_shake():
		shake_flashlight_authoritative()
		return
	var target := get_interaction_target()
	if target == null or not target.has_method("network_interact"):
		return
	target.call("network_interact", owner_peer_id, self)


func refresh_interaction_prompt() -> void:
	if (
		not is_local_player()
		or is_debug_free_camera_active()
		or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED
		or is_bunk_busy()
		or _is_journal_open()
	):
		interaction_prompt_label.visible = false
		return

	if is_climbing():
		interaction_prompt_label.show()
		interaction_prompt_label.text = "Выход занят" if $LadderClimb.exit_blocked else "Вверх / вниз — движение по лестнице"
		return

	if is_driving():
		interaction_prompt_label.visible = true
		interaction_prompt_label.text = "Бензин: %.0f%%" % (vehicle.fuel_liters / vehicle.tank_capacity * 100.0)
		interaction_prompt_label.text += " · S — тормоз / назад"
		if vehicle.get_driving_speed() <= vehicle.exit_max_speed:
			interaction_prompt_label.text += " · E — выйти"
		if vehicle.is_engine_starting():
			interaction_prompt_label.text = "Двигатель заводится…"
		return

	if handoff.is_offering():
		interaction_prompt_label.visible = true
		var offer_hint: String = get_node("/root/SteamInput").get_action_hint(&"offer_item")
		interaction_prompt_label.text = "%s %s · %s" % [offer_hint, handoff.title(), "Нажать — отменить" if handoff.pocket_pose() else "Отпустить — убрать"]
		return
	if needs_flashlight_shake():
		interaction_prompt_label.hide()
		return
	if $ItemDrag.is_heavy_carrying():
		interaction_prompt_label.visible = true
		interaction_prompt_label.text = $ItemDrag.heavy_body.carry_hint()
		return
	if $ItemDrag.dragging:
		interaction_prompt_label.visible = false
		return

	var target := get_interaction_target()
	if target == null or not target.has_method("network_interact"):
		interaction_prompt_label.visible = false
		return

	var prompt := "Взаимодействовать"
	if target.has_method("get_interaction_hint_for"):
		var hint := str(target.call("get_interaction_hint_for", self))
		interaction_prompt_label.text = hint
		interaction_prompt_label.visible = not hint.is_empty()
		return
	if target.has_method("get_interaction_prompt"):
		prompt = str(target.call("get_interaction_prompt"))
	if prompt.strip_edges().is_empty():
		interaction_prompt_label.visible = false
		return
	if prompt.is_empty():
		interaction_prompt_label.hide()
		return
	interaction_prompt_label.text = "%s %s" % [get_node("/root/SteamInput").get_action_hint(&"interact"), prompt]
	interaction_prompt_label.visible = true


func _is_journal_open() -> bool:
	if get_tree().get_first_node_in_group("wiring_ui") != null or get_tree().get_first_node_in_group("terminal_ui") != null:
		return true
	var journal := get_node_or_null("/root/QuestJournal")
	return journal != null and bool(journal.call("is_journal_open"))


func request_journal_phase(phase: int) -> void:
	if phase!=0 and is_climbing(): return
	if not is_local_player(): return
	if phase != 0 and not has_journal: return
	if phase == 1: handoff.request_cancel()
	_journal_phase = clampi(phase,0,3)
	if multiplayer.is_server():
		_publish_journal_phase(_journal_phase)
	else:
		_submit_journal_phase.rpc_id(1,_journal_phase)

func journal_owner_key() -> String:
	var session := get_tree().get_first_node_in_group("network_gameplay_controller")
	return str(session._inventory_id(owner_peer_id)) if session != null and session.has_method("_inventory_id") else "offline_%d" % owner_peer_id

func restore_journal_ownership(_snapshot: Dictionary = {}) -> void:
	var state := get_tree().get_first_node_in_group("base_gameplay_controller") as BaseGameplayController
	if state == null: return
	if not state.snapshot_changed.is_connected(restore_journal_ownership): state.snapshot_changed.connect(restore_journal_ownership)
	if has_journal or not state.maintenance.get("journal_claims", {}).values().has(journal_owner_key()): return
	has_journal = true
	if multiplayer.is_server(): _publish_inventory()

func request_journal_map(value: bool, loupe := false) -> void:
	if not is_local_player() or not has_journal: return
	_journal_map = value
	_journal_loupe = value and loupe
	if multiplayer.is_server(): _receive_journal_map.rpc(value,loupe)
	else: _submit_journal_map.rpc_id(1,value,loupe)

@rpc("any_peer", "call_remote", "reliable", 2)
func _submit_journal_map(value: bool, loupe := false) -> void:
	if not multiplayer.is_server() or multiplayer.get_remote_sender_id() != owner_peer_id or not has_journal or _journal_phase != 2: return
	var state := get_tree().get_first_node_in_group("base_gameplay_controller") as BaseGameplayController
	if value and (state == null or not state.has_entered_base()): return
	_receive_journal_map.rpc(value,loupe)

@rpc("authority", "call_local", "reliable", 2)
func _receive_journal_map(value: bool, loupe := false) -> void:
	_journal_map = value
	_journal_loupe = value and loupe

func _push_loose_item(item: WorldItemPickup, _movement: Vector3, delta: float) -> void:
	_locomotion._push_loose_item(self, item, _movement, delta)


func _update_aim_intent() -> void:
	if is_debug_free_camera_active():
		return
	var value: bool = Input.is_action_pressed("weapon_aim") and _held_item_type in [&"pistol",&"m4a1"] and not survival.dead and not _is_journal_open() and not is_bunk_busy() and not is_driving() and not handoff.is_offering() and not $ItemDrag.is_heavy_carrying()
	_aiming=value
	if value==_aim_serial_state: return
	_aim_serial_state=value
	if multiplayer.is_server(): _receive_aim_state.rpc(value)
	else: _submit_aim_state.rpc_id(1,value)

@rpc("any_peer","call_remote","reliable",2)
func _submit_aim_state(value: bool) -> void:
	if not multiplayer.is_server() or multiplayer.get_remote_sender_id()!=owner_peer_id: return
	_receive_aim_state.rpc(value and _held_item_type in [&"pistol",&"m4a1"] and not survival.dead)

@rpc("authority","call_local","reliable",2)
func _receive_aim_state(value: bool) -> void:
	_aiming=value


@rpc("any_peer","call_remote","reliable",2)
func _submit_journal_phase(phase: int) -> void:
	if not multiplayer.is_server() or multiplayer.get_remote_sender_id()!=owner_peer_id: return
	if phase != 0 and not has_journal: return
	if survival.dead and phase!=0: return
	_publish_journal_phase(clampi(phase,0,3))


func _publish_journal_phase(phase: int) -> void:
	if phase!=0 and is_climbing(): return
	_journal_phase = phase
	if phase == 0:
		_journal_map = false
		_journal_loupe = false
	_refresh_equipment_visuals()
	_receive_journal_phase.rpc(phase)


@rpc("authority","call_remote","reliable",2)
func _receive_journal_phase(phase: int) -> void:
	_journal_phase = clampi(phase,0,3)
	if phase == 0:
		_journal_map = false
		_journal_loupe = false
	_refresh_equipment_visuals()


func teleport_authoritative(
	next_global_position: Vector3,
	next_yaw: float = 0.0
) -> void:
	if not multiplayer.is_server():
		return
	if is_climbing(): $LadderClimb._set_route.rpc(NodePath(),$LadderClimb.revision+1,next_global_position)
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


func apply_weapon_damage(amount: float, hit_impulse: Vector3 = Vector3.ZERO) -> void:
	survival.pending_hit_impulse=hit_impulse.limit_length(35.0)
	if multiplayer.is_server():
		survival.damage(amount, "Огнестрельное ранение")


func is_sleeping_in_bunk() -> bool:
	return _is_sleeping_in_bunk

func is_bunk_busy() -> bool:
	return _is_sleeping_in_bunk or $BunkSleep.waking

func clear_wake_pose(preferred: Transform3D, reserved: Array = []) -> Variant:
	var shape := CapsuleShape3D.new();shape.radius=.35;shape.height=standing_height
	var query := PhysicsShapeQueryParameters3D.new();query.shape=shape;query.collision_mask=collision_mask|2;query.exclude=[get_rid()];query.margin=.01
	var space := get_world_3d().direct_space_state
	var offsets := [Vector3.ZERO,Vector3.RIGHT*.85,Vector3.LEFT*.85,Vector3.FORWARD*.85,Vector3.BACK*.85]
	for radius in [1.4,2.0]:
		for index in 8: offsets.append(Vector3(cos(index*TAU/8),0,sin(index*TAU/8))*radius)
	for offset: Vector3 in offsets:
		var pose := preferred;pose.origin+=preferred.basis*offset
		var ray := PhysicsRayQueryParameters3D.create(pose.origin+Vector3.UP*.3,pose.origin-Vector3.UP*.65,1,[get_rid()])
		var floor_hit := space.intersect_ray(ray)
		if floor_hit.is_empty() or floor_hit.normal.y<.7: continue
		pose.origin.y=floor_hit.position.y+.06
		var occupied := false
		var points := reserved.duplicate()
		for actor in get_tree().get_nodes_in_group("network_players"):
			if actor!=self and not actor.survival.dead and not actor.is_sleeping_in_bunk(): points.append(actor.global_position)
		for point: Vector3 in points:
			var difference := pose.origin-point
			if Vector2(difference.x,difference.z).length()<.78 and absf(difference.y)<standing_height: occupied=true;break
		if occupied: continue
		query.transform=Transform3D(pose.basis,pose.origin+Vector3.UP*standing_height*.5)
		if space.intersect_shape(query,1).is_empty(): return pose
	return null


@rpc("authority", "call_local", "reliable", 2)
func _receive_bunk_sleep_state(
	is_sleeping: bool,
	target_transform: Transform3D
) -> void:
	var source_head := head.global_transform
	var source_body := body_animator.global_transform
	_is_sleeping_in_bunk = is_sleeping
	if is_sleeping:
		if is_local_player():
			var journal := get_node_or_null("/root/QuestJournal")
			if journal!=null: journal.force_close()
		_journal_phase=0
		if multiplayer.is_server() or is_local_player(): $ItemDrag.cancel()
		handoff.cancel_authoritative()
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
	_sprint_active=false;_input_sprint=false;_server_sprint=false
	_input_crouch=false;_server_crouch=false;_pad_sprint=false;_pad_crouch=false;_remote_crouching=false
	_client_consumed_jump_serial=_jump_serial;_server_consumed_jump_serial=_server_jump_serial
	_server_consumed_interact_serial=_server_interact_serial
	_server_consumed_drop_item_serial=_server_drop_item_serial
	camera.reset_motion()
	if collision_shape.shape is CapsuleShape3D:
		collision_shape.shape.height=standing_height
		collision_shape.position.y=standing_height*.5
	collision_shape.set_deferred(
		"disabled",
		survival.dead or is_sleeping or (not multiplayer.is_server() and not is_local_player())
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
	$BunkSleep.begin(is_sleeping,source_head,source_body)
	_refresh_equipment_visuals()
	reset_physics_interpolation()


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
	var screen_effect := get_node_or_null("PlayerUI/CameraPostProcess")
	if screen_effect != null: screen_effect.reset_motion_history()


func pickup_world_item_authoritative(
	item_type: StringName,
	item_state: Dictionary
) -> bool:
	return INVENTORY_ACTIONS.pickup_world_item_authoritative(self, item_type, item_state)


func take_pocket_supply(type: StringName, data: Dictionary) -> bool:
	return multiplayer.is_server() and _supplies.try_take(type, data, CRAFT_RECIPE.pickup_scenes)

func use_crowbar_authoritative() -> bool:
	return multiplayer.is_server() and _supplies.use_crowbar()

func add_crafting_supply_authoritative(type: StringName, amount: int) -> bool:
	return multiplayer.is_server() and _supplies.add_material(type, amount, CRAFT_RECIPE.pickup_scenes)

func consume_crafting_supplies(requirements: Dictionary) -> bool:
	return multiplayer.is_server() and _supplies.consume_recipe(requirements)

func is_handheld_flashlight_drawn() -> bool:
	return _equipment.is_handheld_drawn()


func is_offhand_flashlight_drawn() -> bool:
	return _equipment.is_offhand_drawn()


func get_inventory_snapshot() -> Dictionary:
	var snapshot := {
		"has_journal": has_journal,
		"held_item": _held_item_type,
		"debug_fly": debug_fly,
		"debug_across": debug_across,
		"debug_speed_multiplier": debug_speed_multiplier,
		"fuel_liters": fuel_liters,
		"weapon_light_mounted": weapon_light_mounted,
		"has_flashlight": _has_flashlight,
		"handheld_flashlight_drawn": _handheld_flashlight_drawn,
		"battery_charge": _battery_charge,
		"flashlight_enabled": _flashlight_enabled,
		"malfunctioning": _flashlight_malfunctioning,
		"revision": _inventory_revision,
		"weapon_rounds": weapon.rounds if weapon != null else 0,
		"pistol_ammo": weapon.pistol_ammo if weapon != null else 0,
		"rifle_magazines": weapon.rifle_magazines.duplicate() if weapon != null else [],
		"weapon_reload": weapon.reload_left if weapon != null else 0.0,
		"flame_fuel_liters": weapon.flame.fuel_liters if weapon != null else 3.0,
		"flame_active": weapon.flame.emitting if weapon != null else false,
	}
	_supplies.write_snapshot(snapshot)
	return snapshot


func _publish_inventory(force := false) -> void:
	if _handoff_transaction and not force: return
	_inventory_revision += 1
	_receive_equipment.rpc(get_inventory_snapshot())


@rpc("authority", "call_local", "reliable", 2)
func _receive_equipment(data: Dictionary) -> void:
	apply_inventory_snapshot(data)


func apply_inventory_snapshot(data: Dictionary) -> void:
	var revision := int(data.get("revision", _inventory_revision))
	if revision < _inventory_revision:
		return
	_inventory_revision = revision
	has_journal = bool(data.get("has_journal", has_journal))
	debug_fly = bool(data.get("debug_fly", false))
	debug_across = bool(data.get("debug_across", false))
	debug_speed_multiplier = clampf(float(data.get("debug_speed_multiplier", 1.0)), 0.1, 20.0)
	_supplies.apply_snapshot(data, CRAFT_RECIPE.pickup_scenes, MAX_SPARE_BATTERIES)
	weapon_light_mounted = bool(data.get("weapon_light_mounted", false)) and StringName(data.get("held_item", "")) == &"m4a1" and bool(data.get("has_flashlight", false))
	fuel_liters = clampf(float(data.get("fuel_liters", 20.0)), 0.0, 20.0)
	_has_flashlight = bool(data.get("has_flashlight", false))
	_battery_charge = clampf(float(data.get("battery_charge", 0.0)), 0.0, 1.0) if _has_flashlight else 0.0
	_held_item_type = StringName(data.get("held_item", NO_ITEM))
	weapon.pistol_ammo = clampi(int(data.get("pistol_ammo", 0)), 0, 240)
	weapon.rifle_magazines.clear()
	for magazine: Variant in data.get("rifle_magazines", []):
		if weapon.rifle_magazines.size() < 10 and int(magazine) > 0:
			weapon.rifle_magazines.append(clampi(int(magazine), 1, 30))
	weapon.flame.apply_inventory(data)
	weapon.apply_state(_held_item_type, int(data.get("weapon_rounds", WeaponController.CAPACITY.get(_held_item_type, 0))), float(data.get("weapon_reload", 0.0)))
	if _held_item_type == FLASHLIGHT_ITEM and not _has_flashlight:
		_held_item_type = NO_ITEM
	# Legacy pistol mounts become a handheld lamp without losing ownership/charge.
	var legacy_pistol_mount := _held_item_type == &"pistol" and bool(data.get("weapon_light_mounted", false))
	_handheld_flashlight_drawn = bool(data.get("handheld_flashlight_drawn", legacy_pistol_mount)) and _has_flashlight and not weapon_light_mounted and _held_item_type not in [&"m4a1", &"flamethrower"]
	if _held_item_type == NO_ITEM and _handheld_flashlight_drawn:
		_held_item_type = FLASHLIGHT_ITEM
		_handheld_flashlight_drawn = false
	_flashlight_malfunctioning = bool(data.get("malfunctioning", false)) and _has_flashlight
	_flashlight_enabled = bool(data.get("flashlight_enabled", false)) and (is_handheld_flashlight_drawn() or weapon_light_mounted) and _battery_charge > 0.0 and not _flashlight_malfunctioning
	_refresh_equipment_visuals()
	inventory_changed.emit()


func toggle_flashlight_authoritative() -> bool:
	return INVENTORY_ACTIONS.toggle_flashlight_authoritative(self)


func request_inventory_action(action: StringName) -> void:
	if is_climbing(): return
	if not is_local_player():
		return
	if multiplayer.is_server():
		_begin_inventory_action(action)
	else:
		_request_inventory_action.rpc_id(1, action)


func request_reload_or_battery() -> void:
	request_inventory_action(&"reload_or_battery")

func get_reload_or_battery_action() -> StringName:
	if _held_item_type == &"flamethrower":return &"refuel_flamethrower"
	var better_cell := _has_flashlight and not _spare_batteries.is_empty() and float(_spare_batteries.max()) > _battery_charge
	var battery_priority := better_cell and (_battery_charge <= 0.0 or (is_handheld_flashlight_drawn() and not weapon_light_mounted))
	return &"reload" if WeaponController.TYPES.has(_held_item_type) and not battery_priority else &"replace_battery"


@rpc("authority", "call_local", "reliable")
func _show_pocket_light_notice() -> void:
	_equipment_notice_until = Time.get_ticks_msec() + 2200
	update_battery_ui()


@rpc("any_peer", "call_remote", "reliable", 0)
func _request_inventory_action(action: StringName) -> void:
	if multiplayer.is_server() and multiplayer.get_remote_sender_id() == owner_peer_id:
		_begin_inventory_action(action)


func _begin_inventory_action(action: StringName) -> void:
	if is_climbing(): return
	if handoff.is_offering() or $ItemDrag.is_heavy_carrying(): return
	if survival.dead:
		return
	if action == &"reload_or_battery":
		if _battery_action_busy:
			return
		if get_reload_or_battery_action() == &"refuel_flamethrower":
			perform_inventory_action_authoritative(&"refuel_flamethrower")
			return
		if get_reload_or_battery_action() == &"reload":
			weapon.perform_action(&"reload")
			return
		action = &"replace_battery"
	if action != &"replace_battery":
		perform_inventory_action_authoritative(action)
		return
	if _battery_action_busy or is_bunk_busy() or weapon.reload_left > 0.0 or not _has_flashlight or _spare_batteries.is_empty():
		return
	if float(_spare_batteries.max()) <= _battery_charge:
		return
	_battery_action_busy = true
	var revision := _inventory_revision
	_play_battery_action.rpc()
	# No cell is removed before the insertion marker. Any inventory change
	# (drop, pickup, stow, load) invalidates this pending transaction.
	await get_tree().create_timer(0.72, false).timeout
	if revision == _inventory_revision and not is_bunk_busy():
		perform_inventory_action_authoritative(&"replace_battery")
	await get_tree().create_timer(0.38, false).timeout
	_battery_action_busy = false


@rpc("authority", "call_local", "reliable", 2)
func _play_battery_action() -> void:
	player_audio.play_cue(&"battery")
	if weapon_light_mounted:
		weapon.play_mounted_battery_action()
	else:
		# Reuse the authored two-hand battery clip: temporarily stow the main
		# item visually, without changing inventory or spawning another lamp.
		_battery_flashlight_presentation = _held_item_type != FLASHLIGHT_ITEM
		_refresh_equipment_visuals()
		update_character_animation(0.0)
		await get_tree().process_frame
		await get_tree().process_frame
		flashlight.play_battery_action()
		await get_tree().create_timer(1.10, false).timeout
		_battery_flashlight_presentation = false
		_refresh_equipment_visuals()


func perform_inventory_action_authoritative(action: StringName) -> bool:
	return INVENTORY_ACTIONS.perform_inventory_action_authoritative(self, action)


func get_held_item_state() -> Dictionary:
	return INVENTORY_ACTIONS.get_held_item_state(self)


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
	return INVENTORY_ACTIONS.get_held_item_drop_transform(self)


func get_held_item_drop_linear_velocity() -> Vector3:
	return INVENTORY_ACTIONS.get_held_item_drop_linear_velocity(self)


func drop_current_item_authoritative() -> bool:
	return INVENTORY_ACTIONS.drop_current_item_authoritative(self)


func drop_current_item_at_authoritative(
	drop_transform: Transform3D,
	drop_velocity: Vector3 = Vector3.ZERO
) -> bool:
	return INVENTORY_ACTIONS.drop_current_item_at_authoritative(self, drop_transform, drop_velocity)


func release_held_item_authoritative() -> Dictionary:
	return INVENTORY_ACTIONS.release_held_item_authoritative(self)


func has_held_item(item_type: StringName) -> bool:
	return _held_item_type == item_type


func drop_all_items_at_authoritative(drop_transform: Transform3D) -> void:
	INVENTORY_ACTIONS.drop_all_items_at_authoritative(self, drop_transform)


func consume_held_item_authoritative(item_type: StringName) -> bool:
	return INVENTORY_ACTIONS.consume_held_item_authoritative(self, item_type)


func get_item_pickup_scene(item_type: StringName) -> PackedScene:
	return INVENTORY_ACTIONS.get_item_pickup_scene(self, item_type)


func spawn_dropped_item_authoritative(
	item_type: StringName,
	item_state: Dictionary,
	drop_transform_override: Variant = null,
	linear_velocity_override: Variant = null
) -> void:
	INVENTORY_ACTIONS.spawn_dropped_item_authoritative(self, item_type, item_state, drop_transform_override, linear_velocity_override)


func update_authoritative_flashlight_battery(delta: float) -> void:
	INVENTORY_ACTIONS.update_authoritative_flashlight_battery(self, delta)


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
	_replication.send_if_due(self, delta)


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
	server_inventory: Dictionary = {},
	server_sprint_state: Vector3 = Vector3(-1.0, 0.0, 0.0),
	server_animation: Dictionary = {}
) -> void:
	_replication.receive(
		self,
		server_position,
		server_velocity,
		server_yaw,
		server_pitch,
		server_crouching,
		server_held_item_type,
		server_has_flashlight,
		server_battery_charge,
		server_flashlight_enabled,
		server_flashlight_malfunctioning,
		_acknowledged_input,
		server_inventory,
		server_sprint_state,
		server_animation
	)


func apply_reconciliation(delta: float) -> void:
	_replication.reconcile(self, delta)


func interpolate_remote_player(delta: float) -> void:
	_replication.interpolate(self, delta)


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
	_handheld_flashlight_drawn = enabled and has_flashlight and _held_item_type not in [NO_ITEM, FLASHLIGHT_ITEM, &"m4a1", &"flamethrower"]
	_flashlight_enabled = enabled and is_handheld_flashlight_drawn() and not malfunctioning
	_flashlight_malfunctioning = malfunctioning and _has_flashlight
	_refresh_equipment_visuals()
	inventory_changed.emit()


func apply_held_item_inventory(
	item_type: StringName,
	item_state: Dictionary,
	flashlight_enabled: bool = false,
	malfunctioning: bool = false
) -> void:
	var keep_handheld := is_handheld_flashlight_drawn()
	_held_item_type = item_type
	_handheld_flashlight_drawn = keep_handheld and item_type not in [NO_ITEM, FLASHLIGHT_ITEM, &"m4a1", &"flamethrower"]
	if item_type == FLASHLIGHT_ITEM:
		_has_flashlight = true
		_battery_charge = clampf(float(item_state.get("battery_charge", 1.0)), 0.0, 1.0)
	_flashlight_malfunctioning = (
		malfunctioning and _has_flashlight
	)
	_flashlight_enabled = (
		flashlight_enabled
		and item_type == FLASHLIGHT_ITEM
		and _battery_charge > 0.0
		and not _flashlight_malfunctioning
	)
	_refresh_equipment_visuals()
	inventory_changed.emit()


func is_wiring_view_active() -> bool:
	return is_local_player() and get_tree().get_first_node_in_group("wiring_ui") != null


func _refresh_equipment_visuals() -> void:
	if not _equipment.has_flashlight: _battery_flashlight_presentation = false
	var hidden: bool = is_climbing() or _journal_phase > 0 or (is_local_player() and _is_journal_open()) or handoff.pocket_pose() or $ItemDrag.is_heavy_carrying()
	var hands_busy := survival.dead or is_bunk_busy() or is_driving() or is_carrying_corpse() or (weapon.reload_left > 0.0 and is_handheld_flashlight_drawn())
	body_animator.refresh_equipment_visuals(self, _equipment, hidden, hands_busy, _battery_flashlight_presentation, is_wiring_view_active())
	update_battery_ui()


func clear_movement_correction() -> void:
	_replication.correction_offset = Vector3.ZERO

func _on_authoritative_flashlight_malfunction_started() -> void:
	if not multiplayer.is_server():
		return
	_flashlight_malfunctioning = true
	_flashlight_enabled = false
	_flashlight_shake_presses = 0
	_last_flashlight_shake_msec = -1000
	_publish_inventory()


func needs_flashlight_shake() -> bool:
	return INVENTORY_ACTIONS.needs_flashlight_shake(self)


func shake_flashlight_authoritative() -> bool:
	return INVENTORY_ACTIONS.shake_flashlight_authoritative(self)


func update_battery_ui() -> void:
	var shake_hint := $PlayerUI/FlashlightShakeHint
	shake_hint.visible = is_local_player() and needs_flashlight_shake() and not _is_journal_open() and not get_node("/root/GameMenu").is_menu_open() and not is_debug_free_camera_active()
	if shake_hint.visible:
		shake_hint.get_node("Label").text = str(get_node("/root/SteamInput").get_action_hint(&"interact")).trim_prefix("[").trim_suffix("]").strip_edges()
	if is_debug_free_camera_active():
		battery_label.hide()
		return
	if is_local_player() and _has_flashlight and Time.get_ticks_msec() < _equipment_notice_until and not _is_journal_open() and not get_node("/root/GameMenu").is_menu_open():
		battery_label.visible = true
		battery_label.text = "Огнемёт занимает обе руки" if _held_item_type == &"flamethrower" else "Для M4A1 примотайте фонарик скотчем через журнал"
		return
	battery_label.visible = is_local_player() and _has_flashlight and not _is_journal_open() and not get_node("/root/GameMenu").is_menu_open() and (is_handheld_flashlight_drawn() or _battery_charge <= 0.0)
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
