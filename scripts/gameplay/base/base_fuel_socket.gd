class_name BaseFuelSocket
extends StaticBody3D

const FUEL_ITEM := &"fuel_can"

@onready var indicator: MeshInstance3D = %Indicator
@onready var status_label: Label3D = %StatusLabel
@onready var cap_pivot: Node3D = %CapPivot

var _controller: BaseGameplayController
var _indicator_material: StandardMaterial3D
var _cap_tween: Tween


func _ready() -> void:
	_indicator_material = (
		indicator.get_active_material(0).duplicate() as StandardMaterial3D
	)
	indicator.material_override = _indicator_material
	call_deferred("_bind_controller")


func get_interaction_prompt() -> String:
	var controller := _get_controller()
	if controller == null:
		return "Топливная система недоступна"
	return "Долить топливо · %.1f / 60 л" % controller.fuel_liters


func interact(interactor: Node) -> void:
	network_interact(multiplayer.get_unique_id(), interactor)


func network_interact(peer_id: int, interactor: Node) -> void:
	if (
		not multiplayer.is_server()
		or interactor == null
		or int(interactor.get("owner_peer_id")) != peer_id
		or not interactor.has_method("has_held_item")
		or not interactor.has_method("consume_held_item_authoritative")
		or not bool(interactor.call("has_held_item", FUEL_ITEM))
	):
		return

	var controller := _get_controller()
	if controller == null:
		return
	var remaining := float(interactor.get("fuel_liters"))
	var added := controller.refill_authoritative(peer_id, remaining)
	if added > 0.0:
		interactor.set("fuel_liters", remaining - added)
		interactor.call("_publish_inventory")


func _process(_delta: float) -> void:
	if is_instance_valid(_controller):
		status_label.text = "БАК: %.1f / 60 Л" % _controller.fuel_liters


func _bind_controller() -> void:
	_controller = _get_controller()
	if _controller == null:
		push_warning("BaseFuelSocket could not find BaseGameplayController")
		_apply_fuel_state(false, true)
		return
	if not _controller.fuel_state_changed.is_connected(_on_fuel_state_changed):
		_controller.fuel_state_changed.connect(_on_fuel_state_changed)
	_apply_fuel_state(_controller.fuel_delivered, true)


func _get_controller() -> BaseGameplayController:
	if is_instance_valid(_controller):
		return _controller
	_controller = get_tree().get_first_node_in_group(
		"base_gameplay_controller"
	) as BaseGameplayController
	return _controller


func _on_fuel_state_changed(is_fueled: bool) -> void:
	_apply_fuel_state(is_fueled)


func _apply_fuel_state(is_fueled: bool, instant: bool = false) -> void:
	var color := (
		Color(0.08, 0.95, 0.24, 1.0)
		if is_fueled
		else Color(0.95, 0.12, 0.035, 1.0)
	)
	_indicator_material.albedo_color = color.darkened(0.45)
	_indicator_material.emission_enabled = true
	_indicator_material.emission = color
	_indicator_material.emission_energy_multiplier = 3.5
	status_label.text = "БАК: ПОЛОН" if is_fueled else "БАК: ПУСТ"

	if is_instance_valid(_cap_tween):
		_cap_tween.kill()
	var target_rotation := deg_to_rad(-95.0 if is_fueled else 0.0)
	if instant:
		cap_pivot.rotation.x = target_rotation
		return
	_cap_tween = create_tween()
	_cap_tween.set_trans(Tween.TRANS_BACK)
	_cap_tween.set_ease(Tween.EASE_OUT)
	_cap_tween.tween_property(cap_pivot, "rotation:x", target_rotation, 0.3)
