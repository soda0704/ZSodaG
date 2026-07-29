extends CharacterBody3D

@export var walk_speed: float = 4.0
@export var sprint_speed: float = 6.5
@export var acceleration: float = 14.0
@export var mouse_sensitivity: float = 0.002

@onready var head: Node3D = $Head

var gravity: float = float(
	ProjectSettings.get_setting("physics/3d/default_gravity")
)


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		toggle_mouse_mode()

	if (
		event is InputEventMouseMotion
		and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	):
		rotate_camera(event)


func toggle_mouse_mode() -> void:
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func rotate_camera(event: InputEventMouseMotion) -> void:
	rotate_y(-event.relative.x * mouse_sensitivity)

	head.rotate_x(-event.relative.y * mouse_sensitivity)
	head.rotation.x = clamp(
		head.rotation.x,
		deg_to_rad(-85.0),
		deg_to_rad(85.0)
	)


func _physics_process(delta: float) -> void:
	apply_gravity(delta)

	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		stop_horizontal_movement(delta)
		return

	handle_movement(delta)
	move_and_slide()


func apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0.0


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
