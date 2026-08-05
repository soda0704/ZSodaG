extends CharacterBody3D

const FLASHLIGHT_PICKUP_SCENE := preload(
	"res://scenes/objects/equipment/flashlight_pickup.tscn"
)

@export var walk_speed: float = 4.0
@export var sprint_speed: float = 6.5
@export var acceleration: float = 14.0
@export var jump_velocity: float = 5.0
@export var mouse_sensitivity: float = 0.002

@onready var head: Node3D = $Head
@onready var camera_motion: FirstPersonCameraMotion = $Head/Camera3D
@onready var flashlight: PlayerFlashlight = $Head/Camera3D/Flashlight
@onready var interaction_controller: InteractionController = (
	$Head/Camera3D/InteractionRay
)
@onready var battery_label: Label = %BatteryLabel

var gravity: float = float(
	ProjectSettings.get_setting("physics/3d/default_gravity")
)
var _displayed_battery_percent: int = -1


func _ready() -> void:
	add_to_group("local_player")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	flashlight.battery_changed.connect(_on_flashlight_battery_changed)
	flashlight.availability_changed.connect(_on_flashlight_availability_changed)
	update_battery_ui()


func _unhandled_input(event: InputEvent) -> void:
	if (
		event.is_action_pressed("interact")
		and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
		and not (event is InputEventKey and event.echo)
	):
		if interaction_controller.try_interact():
			get_viewport().set_input_as_handled()

	if (
		event.is_action_pressed("flashlight")
		and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
		and not (event is InputEventKey and event.echo)
	):
		if flashlight.toggle():
			get_viewport().set_input_as_handled()

	if (
		event is InputEventMouseMotion
		and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	):
		rotate_camera(event)

func rotate_camera(event: InputEventMouseMotion) -> void:
	rotate_y(-event.relative.x * mouse_sensitivity)

	head.rotate_x(-event.relative.y * mouse_sensitivity)
	head.rotation.x = clamp(
		head.rotation.x,
		deg_to_rad(-85.0),
		deg_to_rad(85.0)
	)
	camera_motion.add_look_impulse(event.relative)
	flashlight.add_look_impulse(event.relative)


func _physics_process(delta: float) -> void:
	apply_gravity(delta)

	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		stop_horizontal_movement(delta)
		update_view_motion(delta, false)
		return

	handle_jump()
	handle_movement(delta)
	move_and_slide()
	update_view_motion(delta, Input.is_action_pressed("sprint"))


func acquire_flashlight(battery_charge: float = 1.0) -> bool:
	return flashlight.acquire(true, battery_charge)


func swap_flashlight(battery_charge: float) -> bool:
	var previous_charge := flashlight.replace(battery_charge, true)
	if previous_charge >= 0.0:
		drop_flashlight(previous_charge)
	update_battery_ui()
	return true


func drop_flashlight(battery_charge: float) -> void:
	var dropped_flashlight := (
		FLASHLIGHT_PICKUP_SCENE.instantiate() as FlashlightPickup
	)
	dropped_flashlight.battery_charge = battery_charge
	get_tree().current_scene.add_child(dropped_flashlight)

	var forward := -head.global_basis.z.normalized()
	dropped_flashlight.global_transform = Transform3D(
		head.global_basis.orthonormalized(),
		head.global_position + forward * 0.7 + Vector3.DOWN * 0.35
	)
	dropped_flashlight.linear_velocity = velocity + forward * 1.1
	dropped_flashlight.angular_velocity = Vector3(1.4, 0.8, -1.1)


func update_battery_ui() -> void:
	battery_label.visible = flashlight.is_available
	if not battery_label.visible:
		_displayed_battery_percent = -1
		return

	var battery_percent := roundi(flashlight.battery_charge * 100.0)
	if battery_percent == _displayed_battery_percent:
		return
	_displayed_battery_percent = battery_percent
	battery_label.text = "БАТАРЕЯ: %d%%" % battery_percent


func _on_flashlight_battery_changed(_charge: float) -> void:
	update_battery_ui()


func _on_flashlight_availability_changed(_is_available: bool) -> void:
	update_battery_ui()


func update_view_motion(delta: float, is_sprinting: bool) -> void:
	var horizontal_speed := Vector2(velocity.x, velocity.z).length()
	var reference_speed := sprint_speed if is_sprinting else walk_speed
	var movement_ratio := horizontal_speed / maxf(reference_speed, 0.001)

	camera_motion.update_motion(
		delta,
		movement_ratio,
		is_on_floor(),
		is_sprinting
	)
	flashlight.update_motion(
		delta,
		movement_ratio,
		is_on_floor(),
		is_sprinting
	)


func apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0.0


func handle_jump() -> void:
	if Input.is_action_just_pressed("jump"):
		try_jump()


func try_jump() -> bool:
	if not is_on_floor():
		return false

	velocity.y = jump_velocity
	return true


func stop_horizontal_movement(delta: float) -> void:
	velocity.x = move_toward(
		velocity.x,
		0.0,
		acceleration * delta
	)

	velocity.z = move_toward(
		velocity.z,
		0.0,
		acceleration * delta
	)

	move_and_slide()


func handle_movement(delta: float) -> void:
	var input_direction := Input.get_vector(
		"move_left",
		"move_right",
		"move_forward",
		"move_backward"
	)

	var direction := (
		transform.basis *
		Vector3(input_direction.x, 0.0, input_direction.y)
	).normalized()

	var current_speed := walk_speed

	if Input.is_action_pressed("sprint"):
		current_speed = sprint_speed

	var target_velocity := direction * current_speed

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
