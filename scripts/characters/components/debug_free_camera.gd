extends Camera3D
## Local inspection camera. The player keeps its own gameplay camera and position.

const DEFAULT_SPEED := 5.0
var enabled := false
var speed := DEFAULT_SPEED
var player: GamePlayer


func _ready() -> void:
	player = get_parent() as GamePlayer
	top_level = true
	current = false
	# Exclude the owner-only hands, but include the full world character and lights.
	cull_mask = player.camera.cull_mask & ~(1 << 19)
	near = 0.03
	set_process(false)
	set_process_unhandled_input(false)


func set_enabled(value: bool) -> void:
	if enabled == value:
		return
	enabled = value
	set_process(value)
	set_process_unhandled_input(value)
	player.body_animator.set_external_view(value)
	if value:
		global_transform = player.camera.global_transform
		rotation.z = 0.0
		fov = player.camera.fov
		far = player.camera.far
		attributes = player.camera.attributes
		environment = player.camera.environment
		make_current()
		player.body_animator.first_person.overlay.hide()
		player.get_node("ItemDrag").cancel()
		player.velocity.x = 0.0
		player.velocity.z = 0.0
		player.collect_local_input()
		if multiplayer.is_server():
			player.copy_local_input_to_server()
		player.interaction_prompt_label.hide()
		player.battery_label.hide()
	else:
		player.camera.make_current()
	player.crosshair.visible = not value and not player.survival.dead


func _can_control() -> bool:
	return enabled and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not get_node("/root/GameMenu").is_menu_open() and not get_node("/root/DeveloperConsole").opened


func _unhandled_input(event: InputEvent) -> void:
	if not _can_control():
		return
	if event is InputEventMouseMotion:
		var sensitivity := player.mouse_sensitivity * float(get_node("/root/GameMenu").get_mouse_sensitivity_multiplier())
		_look(event.relative * sensitivity)
		get_viewport().set_input_as_handled()


func _look(amount: Vector2) -> void:
	rotation.y = wrapf(rotation.y - amount.x, -PI, PI)
	rotation.x = clampf(rotation.x - amount.y, deg_to_rad(-85.0), deg_to_rad(85.0))


func _process(delta: float) -> void:
	if player.survival.dead or player.is_sleeping_in_bunk():
		set_enabled(false)
		return
	player.crosshair.hide()
	if not _can_control():
		return
	var sensitivity := float(get_node("/root/GameMenu").get_mouse_sensitivity_multiplier())
	var look := Input.get_vector("look_left", "look_right", "look_up", "look_down") * player.controller_look_speed * sensitivity * delta
	var steam_look := player._get_steam_input_vector(&"get_gameplay_look")
	if not steam_look.is_zero_approx():
		look = steam_look * player.mouse_sensitivity * sensitivity
	_look(look)
	var move := Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	var steam_move := player._get_steam_input_vector(&"get_gameplay_move")
	if steam_move.length_squared() > move.length_squared():
		move = steam_move
	var vertical := float(Input.is_action_pressed("jump")) - float(Input.is_action_pressed("crouch"))
	move_camera(delta, move, vertical, Input.is_action_pressed("sprint"))


func move_camera(delta: float, move: Vector2, vertical: float, fast: bool) -> void:
	var direction := global_basis * Vector3(move.x, 0.0, move.y) + Vector3.UP * vertical
	global_position += direction.limit_length() * speed * (3.0 if fast else 1.0) * delta
