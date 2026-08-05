class_name InteractiveDoor
extends AnimatableBody3D

signal interaction_blocked(reason: String)
signal state_changed(state: int)

enum DoorState {
	CLOSED,
	OPENING,
	OPEN,
	CLOSING,
}

@export var opening_angle_degrees: float = 95.0
@export var animation_duration: float = 0.65
@export var starts_open: bool = false
@export var starts_locked: bool = false
@export var requires_power: bool = false
@export var starts_powered: bool = true

var state: DoorState = DoorState.CLOSED
var is_locked: bool = false
var is_powered: bool = true

var _closed_rotation_y: float
var _open_rotation_y: float
var _motion_tween: Tween


func _ready() -> void:
	_closed_rotation_y = rotation.y
	_open_rotation_y = _closed_rotation_y + deg_to_rad(opening_angle_degrees)
	is_locked = starts_locked
	is_powered = starts_powered

	if starts_open:
		rotation.y = _open_rotation_y
		state = DoorState.OPEN
	else:
		state = DoorState.CLOSED


func get_interaction_prompt() -> String:
	if is_locked:
		return "Дверь заблокирована"
	if requires_power and not is_powered:
		return "Нет питания двери"
	if state == DoorState.OPENING or state == DoorState.CLOSING:
		return "Дверь движется"
	if state == DoorState.OPEN:
		return "Закрыть дверь"
	return "Открыть дверь"


func interact(_interactor: Node) -> void:
	if is_locked:
		interaction_blocked.emit("locked")
		return

	if requires_power and not is_powered:
		interaction_blocked.emit("unpowered")
		return

	if state == DoorState.OPENING or state == DoorState.CLOSING:
		return

	set_open(state != DoorState.OPEN)


func network_interact(_peer_id: int, _interactor: Node) -> void:
	if not multiplayer.is_server():
		return
	if is_locked:
		interaction_blocked.emit("locked")
		return
	if requires_power and not is_powered:
		interaction_blocked.emit("unpowered")
		return
	if state == DoorState.OPENING or state == DoorState.CLOSING:
		return

	_apply_network_open.rpc(state != DoorState.OPEN)


func sync_network_state_to_peer(peer_id: int) -> void:
	if not multiplayer.is_server() or peer_id <= 0:
		return
	_receive_network_state.rpc_id(
		peer_id,
		state == DoorState.OPEN or state == DoorState.OPENING,
		is_locked,
		is_powered
	)


@rpc("authority", "call_local", "reliable")
func _apply_network_open(value: bool) -> void:
	set_open(value)


@rpc("authority", "call_remote", "reliable")
func _receive_network_state(
	opened: bool,
	locked: bool,
	powered: bool
) -> void:
	set_locked(locked)
	set_powered(powered)
	set_open(opened, true)


func set_open(value: bool, instant: bool = false) -> void:
	if is_instance_valid(_motion_tween):
		_motion_tween.kill()

	var target_rotation := _open_rotation_y if value else _closed_rotation_y

	if instant:
		rotation.y = target_rotation
		finish_motion(value)
		return

	state = DoorState.OPENING if value else DoorState.CLOSING
	state_changed.emit(state)

	_motion_tween = create_tween()
	_motion_tween.set_trans(Tween.TRANS_SINE)
	_motion_tween.set_ease(Tween.EASE_IN_OUT)
	_motion_tween.tween_property(
		self,
		"rotation:y",
		target_rotation,
		maxf(animation_duration, 0.01)
	)
	_motion_tween.finished.connect(finish_motion.bind(value))


func finish_motion(opened: bool) -> void:
	state = DoorState.OPEN if opened else DoorState.CLOSED
	state_changed.emit(state)


func set_locked(value: bool) -> void:
	is_locked = value


func set_powered(value: bool) -> void:
	is_powered = value
