class_name PlayerLocalInput
extends RefCounted
## Local device samples and action edges. Does not simulate movement or send RPCs.

var input_move: Vector2 = Vector2.ZERO
var input_sprint: bool = false
var input_crouch: bool = false
var input_yaw: float = 0.0
var input_pitch: float = 0.0
var jump_serial: int = 0
var flashlight_serial: int = 0
var interact_serial: int = 0
var drop_item_serial: int = 0
var pad_sprint: bool = false
var pad_crouch: bool = false
var flight_vertical: float = 0.0

func _unhandled_input(player: GamePlayer, event: InputEvent) -> void:
	if player.is_debug_free_camera_active():
		return
	if player.survival.dead:
		return
	if not player.is_local_player():
		return
	if player.is_bunk_busy():
		if event.is_action_pressed("interact"):
			player.request_leave_bunk_sleep()
		return
	if player._is_journal_open():
		return

	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if event is InputEventKey and event.echo:
		return

	if event is InputEventMouseMotion:
		var sensitivity: float = (
			player.mouse_sensitivity
			* float(player.get_node("/root/GameMenu").get_mouse_sensitivity_multiplier())
		)
		input_yaw = wrapf(
			input_yaw - event.relative.x * sensitivity,
			-PI,
			PI
		)
		input_pitch = clampf(
			input_pitch - event.relative.y * sensitivity,
			deg_to_rad(-85.0),
			deg_to_rad(85.0)
		)
		player.camera.add_look_impulse(event.relative)
		player.flashlight.add_look_impulse(event.relative)
	elif event.is_action_pressed("jump"):
		jump_serial += 1
	elif player.is_climbing():
		return
	elif event.is_action_pressed("interact"):
		if player.handoff.is_offering():
			pass
		elif player.get_interaction_target() != null and player.get_interaction_target().has_method("begin_item_handoff"):
			player.get_interaction_target().begin_item_handoff()
		elif player.needs_flashlight_shake():
			player.request_inventory_action(&"shake_flashlight")
		elif player.get_interaction_target() != null and player.get_interaction_target().has_method("begin_lobby_interaction") and player.get_interaction_target().begin_lobby_interaction():
			pass
		elif player.get_interaction_target() != null and player.get_interaction_target().has_method("begin_terminal_interaction"):
			player.get_interaction_target().begin_terminal_interaction()
		elif not player.get_node("ItemDrag").begin_interaction():
			interact_serial += 1
	elif event.is_action_pressed("drop_item"):
		if not player.handoff.is_offering() and not player.get_node("ItemDrag").is_heavy_carrying(): drop_item_serial += 1
	elif event.is_action_pressed("offer_item"):
		if player.handoff.is_offering(): player.handoff.request_cancel()
		else: player.handoff.request_offer(player._held_item_type, false)
	elif event.is_action_pressed("replace_battery"):
		player.request_reload_or_battery()
	elif event.is_action_pressed("sprint") and player.get_node("/root/SteamInput").is_controller_event(event):
		pad_sprint = not pad_sprint
		pad_crouch = false
	elif event.is_action_pressed("crouch") and player.get_node("/root/SteamInput").is_controller_event(event):
		pad_crouch = not pad_crouch
		pad_sprint = false
	elif event.is_action_pressed("flashlight"):
		if player._has_flashlight:
			flashlight_serial += 1

func collect_local_input(player: GamePlayer) -> void:
	if player.is_debug_free_camera_active():
		input_move = Vector2.ZERO
		input_sprint = false
		input_crouch = player._is_crouching
		pad_sprint = false
		pad_crouch = false
		return
	if (
		Input.mouse_mode != Input.MOUSE_MODE_CAPTURED
		or player.is_bunk_busy()
		or player._is_journal_open()
	):
		input_move = Vector2.ZERO
		input_sprint = false
		input_crouch = false
		pad_sprint = false
		return

	var godot_move := Input.get_vector(
		"move_left",
		"move_right",
		"move_forward",
		"move_backward"
	)
	var steam_move := _get_steam_input_vector(player, &"get_gameplay_move")
	input_move = (
		steam_move
		if steam_move.length_squared() > godot_move.length_squared()
		else godot_move
	)
	var using_controller: bool = bool(player.get_node("/root/SteamInput").using_controller)
	if not using_controller:
		pad_sprint = false
		pad_crouch = false
	if input_move.length() < 0.1:
		pad_sprint = false
	input_crouch = pad_crouch if using_controller else Input.is_action_pressed("crouch")
	input_sprint = (pad_sprint if using_controller else Input.is_action_pressed("sprint")) and not input_crouch

func collect_local_look(player: GamePlayer, delta: float) -> void:
	if player.is_debug_free_camera_active():
		return
	if (
		Input.mouse_mode != Input.MOUSE_MODE_CAPTURED
		or player.is_bunk_busy()
		or player._is_journal_open()
	):
		return
	var sensitivity_multiplier: float = float(
		player.get_node("/root/GameMenu").get_mouse_sensitivity_multiplier()
	)
	var godot_look := Input.get_vector(
		"look_left",
		"look_right",
		"look_up",
		"look_down"
	)
	var look_radians: Vector2 = (
		godot_look
		* player.controller_look_speed
		* sensitivity_multiplier
		* delta
	)
	var steam_look := _get_steam_input_vector(player, &"get_gameplay_look")
	if not steam_look.is_zero_approx():
		# Steam may expose the same controller through the raw joypad fallback.
		# A native look sample replaces, rather than doubles, that sample.
		look_radians = steam_look * player.mouse_sensitivity * sensitivity_multiplier
	if look_radians.is_zero_approx():
		return
	input_yaw = wrapf(input_yaw - look_radians.x, -PI, PI)
	input_pitch = clampf(
		input_pitch - look_radians.y,
		deg_to_rad(-85.0),
		deg_to_rad(85.0)
	)
	var look_impulse: Vector2 = look_radians / maxf(player.mouse_sensitivity, 0.00001)
	player.camera.add_look_impulse(look_impulse)
	player.flashlight.add_look_impulse(look_impulse)

func _get_steam_input_vector(player: GamePlayer, method_name: StringName) -> Vector2:
	var steam_input := player.get_node_or_null("/root/SteamInput")
	if steam_input == null or not steam_input.has_method(method_name):
		return Vector2.ZERO
	return steam_input.call(method_name) as Vector2
