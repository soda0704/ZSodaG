class_name BaseMainBreaker
extends StaticBody3D

@onready var indicator: MeshInstance3D = %Indicator
@onready var status_label: Label3D = %StatusLabel
@onready var lever_pivot: Node3D = %LeverPivot

var _controller: BaseGameplayController
var _indicator_material: StandardMaterial3D
var _lever_tween: Tween


func _ready() -> void:
	add_to_group("main_breaker")
	_indicator_material = (
		indicator.get_active_material(0).duplicate() as StandardMaterial3D
	)
	indicator.material_override = _indicator_material
	call_deferred("_bind_controller")


func get_interaction_prompt() -> String:
	var controller := _get_controller()
	if controller == null:
		return "Главный щит недоступен"
	if controller.maintenance.get("wires_required", false):
		return "Открыть щит · восстановить проводку"
	if controller.containment.get("fault", false):
		return "Выключить щит для сброса сбоя" if controller.main_breaker_on else "Включить щит — восстановить освещение"
	if controller.main_breaker_on:
		return "Главный щит включён"
	if not controller.fuel_delivered:
		return "Нет топлива для запуска"
	return "Включить главный щит"


func interact(interactor: Node) -> void:
	network_interact(multiplayer.get_unique_id(), interactor)


func network_interact(peer_id: int, interactor: Node) -> void:
	if (
		not multiplayer.is_server()
		or interactor == null
		or int(interactor.get("owner_peer_id")) != peer_id
	):
		return
	var controller := _get_controller()
	if controller != null:
		if controller.maintenance.get("wires_required", false):
			if (interactor as Node3D).global_position.distance_to(global_position) <= 4.0:
				controller.open_wiring_ui.rpc_id(peer_id)
			return
		if controller.containment.get("fault", false):
			var encounter := get_tree().get_first_node_in_group("containment_encounter")
			if encounter != null:
				encounter.cycle_breaker(peer_id)
			return
		controller.activate_main_breaker_authoritative(peer_id)


func _bind_controller() -> void:
	_controller = _get_controller()
	if _controller == null:
		push_warning("BaseMainBreaker could not find BaseGameplayController")
		_apply_power_state(false, true)
		return
	if not _controller.power_state_changed.is_connected(_on_power_state_changed):
		_controller.power_state_changed.connect(_on_power_state_changed)
	_apply_power_state(_controller.main_breaker_on, true)


func _get_controller() -> BaseGameplayController:
	if is_instance_valid(_controller):
		return _controller
	_controller = get_tree().get_first_node_in_group(
		"base_gameplay_controller"
	) as BaseGameplayController
	return _controller


func _on_power_state_changed(is_powered: bool) -> void:
	if is_powered:
		$PowerAudio.play()
	_apply_power_state(is_powered)


func _apply_power_state(is_powered: bool, instant: bool = false) -> void:
	var color := (
		Color(0.08, 0.95, 0.24, 1.0)
		if is_powered
		else Color(0.95, 0.12, 0.035, 1.0)
	)
	_indicator_material.albedo_color = color.darkened(0.45)
	_indicator_material.emission_enabled = true
	_indicator_material.emission = color
	_indicator_material.emission_energy_multiplier = 4.0
	status_label.text = "ГЛАВНЫЙ ЩИТ: ВКЛ" if is_powered else "ГЛАВНЫЙ ЩИТ: ВЫКЛ"

	if is_instance_valid(_lever_tween):
		_lever_tween.kill()
	var target_rotation := deg_to_rad(38.0 if is_powered else -38.0)
	if instant:
		lever_pivot.rotation.x = target_rotation
		return
	_lever_tween = create_tween()
	_lever_tween.set_trans(Tween.TRANS_BACK)
	_lever_tween.set_ease(Tween.EASE_OUT)
	_lever_tween.tween_property(lever_pivot, "rotation:x", target_rotation, 0.3)
