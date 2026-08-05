class_name DoorPowerSwitch
extends StaticBody3D

signal power_state_changed(is_powered: bool)

@export var door_path: NodePath
@export var indicator_path: NodePath
@export var requires_source_power: bool = false
@export var starts_source_powered: bool = true

@onready var door: InteractiveDoor = get_node(door_path) as InteractiveDoor
@onready var indicator: DoorStatusIndicator = (
	get_node(indicator_path) as DoorStatusIndicator
)
@onready var lever_pivot: Node3D = %LeverPivot
@onready var lever: MeshInstance3D = %Lever

var is_source_powered: bool = true
var is_switch_on: bool = false
var is_powered: bool = false
var _lever_material: StandardMaterial3D
var _lever_tween: Tween


func _ready() -> void:
	_lever_material = lever.get_active_material(0).duplicate() as StandardMaterial3D
	lever.material_override = _lever_material
	is_source_powered = starts_source_powered if requires_source_power else true
	apply_switch_state(false, true)


func get_interaction_prompt() -> String:
	if is_switch_on:
		return "Отключить линию двери"
	if requires_source_power and not is_source_powered:
		return "Нет питания от генератора"
	return "Включить линию двери"


func interact(_interactor: Node) -> void:
	if not is_switch_on and requires_source_power and not is_source_powered:
		return
	apply_switch_state(not is_switch_on)


func network_interact(peer_id: int, interactor: Node) -> void:
	if (
		not multiplayer.is_server()
		or int(interactor.get("owner_peer_id")) != peer_id
		or (
			not is_switch_on
			and requires_source_power
			and not is_source_powered
		)
	):
		return
	_apply_network_power_state.rpc(not is_switch_on)


func sync_network_state_to_peer(peer_id: int) -> void:
	if not multiplayer.is_server() or peer_id <= 0:
		return
	_receive_network_power_state.rpc_id(peer_id, is_switch_on)


@rpc("authority", "call_local", "reliable")
func _apply_network_power_state(value: bool) -> void:
	apply_switch_state(value)


@rpc("authority", "call_remote", "reliable")
func _receive_network_power_state(value: bool) -> void:
	apply_switch_state(value, true)


func apply_power_state(value: bool, instant: bool = false) -> void:
	apply_switch_state(value, instant)


func apply_switch_state(value: bool, instant: bool = false) -> void:
	is_switch_on = value
	refresh_power_output(instant)


func set_source_powered(value: bool, instant: bool = false) -> void:
	is_source_powered = value if requires_source_power else true
	refresh_power_output(instant)


func refresh_power_output(instant: bool = false) -> void:
	var next_powered := is_switch_on and is_source_powered
	var state_changed := is_powered != next_powered
	is_powered = next_powered
	door.set_powered(is_powered)
	indicator.set_unlocked(is_powered)
	update_lever_visual(instant)
	if state_changed:
		power_state_changed.emit(is_powered)


func update_lever_visual(instant: bool) -> void:
	if is_instance_valid(_lever_tween):
		_lever_tween.kill()

	var target_rotation_x := deg_to_rad(38.0 if is_switch_on else -38.0)
	var target_color := (
		Color(0.12, 0.8, 0.25, 1.0)
		if is_powered
		else Color(0.9, 0.48, 0.06, 1.0)
		if is_switch_on
		else Color(0.82, 0.16, 0.07, 1.0)
	)
	_lever_material.albedo_color = target_color

	if instant:
		lever_pivot.rotation.x = target_rotation_x
		return

	_lever_tween = create_tween()
	_lever_tween.set_trans(Tween.TRANS_BACK)
	_lever_tween.set_ease(Tween.EASE_OUT)
	_lever_tween.tween_property(
		lever_pivot,
		"rotation:x",
		target_rotation_x,
		0.28
	)
