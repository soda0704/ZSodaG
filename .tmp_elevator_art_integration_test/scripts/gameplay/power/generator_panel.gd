class_name GeneratorPanel
extends StaticBody3D

signal power_state_changed(is_powered: bool)

const FUSE_ITEM := &"fuse"

@export var powered_light_path: NodePath

@onready var fuse_socket: MeshInstance3D = %FuseSocket
@onready var indicator: MeshInstance3D = %Indicator
@onready var switch_pivot: Node3D = %SwitchPivot
@onready var status_label: Label3D = %StatusLabel
@onready var powered_light: Light3D = get_node_or_null(
	powered_light_path
) as Light3D

var has_fuse: bool = false
var is_powered: bool = false
var _socket_material: StandardMaterial3D
var _indicator_material: StandardMaterial3D
var _switch_tween: Tween


func _ready() -> void:
	_socket_material = (
		fuse_socket.get_active_material(0).duplicate()
		as StandardMaterial3D
	)
	_indicator_material = (
		indicator.get_active_material(0).duplicate()
		as StandardMaterial3D
	)
	fuse_socket.material_override = _socket_material
	indicator.material_override = _indicator_material
	apply_state(false, false, true)


func get_interaction_prompt() -> String:
	if not has_fuse:
		return "Вставить предохранитель из рук"
	if is_powered:
		return "Остановить генератор"
	return "Запустить генератор"


func interact(interactor: Node) -> void:
	network_interact(multiplayer.get_unique_id(), interactor)


func network_interact(peer_id: int, interactor: Node) -> void:
	if (
		not multiplayer.is_server()
		or int(interactor.get("owner_peer_id")) != peer_id
	):
		return

	if not has_fuse:
		if not interactor.has_method("consume_held_item_authoritative"):
			return
		if not bool(interactor.call(
			"consume_held_item_authoritative",
			FUSE_ITEM
		)):
			return
		_apply_network_state.rpc(true, false)
		return
	_apply_network_state.rpc(true, not is_powered)


func sync_network_state_to_peer(peer_id: int) -> void:
	if not multiplayer.is_server() or peer_id <= 0:
		return
	_receive_network_state.rpc_id(peer_id, has_fuse, is_powered)


@rpc("authority", "call_local", "reliable")
func _apply_network_state(next_has_fuse: bool, next_powered: bool) -> void:
	apply_state(next_has_fuse, next_powered)


@rpc("authority", "call_remote", "reliable")
func _receive_network_state(next_has_fuse: bool, next_powered: bool) -> void:
	apply_state(next_has_fuse, next_powered, true)


func apply_state(
	next_has_fuse: bool,
	next_powered: bool,
	instant: bool = false
) -> void:
	var power_changed := is_powered != (next_powered and next_has_fuse)
	has_fuse = next_has_fuse
	is_powered = next_powered and has_fuse
	update_visuals(instant)
	if power_changed:
		power_state_changed.emit(is_powered)


func update_visuals(instant: bool) -> void:
	var indicator_color := Color(0.95, 0.04, 0.015, 1.0)
	if has_fuse:
		indicator_color = (
			Color(0.04, 0.95, 0.18, 1.0)
			if is_powered
			else Color(1.0, 0.58, 0.035, 1.0)
		)
	_socket_material.albedo_color = (
		Color(0.72, 0.62, 0.34, 1.0)
		if has_fuse
		else Color(0.035, 0.04, 0.045, 1.0)
	)
	_indicator_material.albedo_color = indicator_color.darkened(0.35)
	_indicator_material.emission_enabled = true
	_indicator_material.emission = indicator_color
	_indicator_material.emission_energy_multiplier = 4.0
	status_label.text = (
		"ПИТАНИЕ ВКЛЮЧЕНО"
		if is_powered
		else "ГОТОВ К ЗАПУСКУ" if has_fuse else "НЕТ ПРЕДОХРАНИТЕЛЯ"
	)
	if powered_light != null:
		powered_light.visible = is_powered

	if is_instance_valid(_switch_tween):
		_switch_tween.kill()
	var target_rotation := deg_to_rad(32.0 if is_powered else -32.0)
	if instant:
		switch_pivot.rotation.x = target_rotation
		return
	_switch_tween = create_tween()
	_switch_tween.set_trans(Tween.TRANS_BACK)
	_switch_tween.set_ease(Tween.EASE_OUT)
	_switch_tween.tween_property(
		switch_pivot,
		"rotation:x",
		target_rotation,
		0.28
	)
