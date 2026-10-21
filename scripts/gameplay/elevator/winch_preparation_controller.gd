class_name WinchPreparationController
extends Node3D
## The shared base snapshot owns progress; native scene clips own presentation.
@export var gameplay_state_path: NodePath
@export var winch_path: NodePath
@export_range(1.0, 10.0) var test_duration := 3.0
@onready var pin_animation: AnimationPlayer = $PinAnimation
@onready var brake_animation: AnimationPlayer = $BrakeAnimation
@onready var test_animation: AnimationPlayer = $TestAnimation
@onready var status_animation: AnimationPlayer = $StatusAnimation
@onready var service_light: OmniLight3D = $ServiceLight
var gameplay_state: BaseGameplayController
var winch: FunctionalElevatorController
var _initialized := false
var _previous: Dictionary = {}
var _test_left := 0.0
var _busy_left := 0.0


func _ready() -> void:
	add_to_group("winch_preparations")
	gameplay_state = get_node_or_null(gameplay_state_path) as BaseGameplayController
	winch = get_node_or_null(winch_path) as FunctionalElevatorController
	if gameplay_state == null or winch == null:
		push_error("Winch preparation: assign gameplay state and winch in Inspector")
		set_process(false)
		return
	gameplay_state.snapshot_changed.connect(_on_snapshot)
	_on_snapshot({})


func _process(delta: float) -> void:
	if not multiplayer.is_server() or gameplay_state == null: return
	_busy_left = maxf(0.0, _busy_left - delta)
	if _test_left <= 0.0: return
	if not _can_test():
		_test_left = 0.0
		_commit({"testing": false})
		return
	_test_left = maxf(0.0, _test_left - delta)
	if _test_left <= 0.0: _commit({"testing": false, "tested": true})


func _can_test() -> bool:
	return gameplay_state.main_breaker_on and gameplay_state.day_index >= gameplay_state.EXPEDITION_DAY_INDEX and winch.current_floor_index == 0 and winch.state in [winch.ElevatorState.UNPOWERED, winch.ElevatorState.IDLE_OPEN] and winch.door_safety_area.get_overlapping_bodies().filter(func(body): return winch._get_body_peer_id(body) > 0).is_empty()


func get_prompt(action: WinchPreparationControl.Action) -> String:
	if gameplay_state == null or gameplay_state.day_index < gameplay_state.EXPEDITION_DAY_INDEX: return ""
	var data := gameplay_state.get_winch_preparation()
	if data.get("tested", false): return ""
	if data.get("testing", false): return ""
	if action == WinchPreparationControl.Action.CONSOLE:
		if not gameplay_state.main_breaker_on: return "Нет основного питания"
		if not data.get("inspected", false): return "Осмотреть пульт лебёдки"
		if not data.get("brake_armed", false): return ""
		return "Запустить проверку" if _can_test() else ""
	if not data.get("inspected", false): return ""
	if action == WinchPreparationControl.Action.PIN:
		return "" if data.get("pin_removed", false) else "Вытянуть стопорный штифт"
	if not data.get("pin_removed", false): return ""
	return "" if data.get("brake_armed", false) else "Перевести рычаг"


func use_control(control: WinchPreparationControl, peer_id: int, interactor: Node) -> bool:
	if not multiplayer.is_server() or not is_ancestor_of(control) or not control.can_use(peer_id, interactor): return false
	if gameplay_state.day_index < gameplay_state.EXPEDITION_DAY_INDEX or _busy_left > 0.0: return false
	var data := gameplay_state.get_winch_preparation()
	if data.get("tested", false) or data.get("testing", false): return false
	match control.action:
		WinchPreparationControl.Action.CONSOLE:
			if not gameplay_state.main_breaker_on: return false
			if not data.get("inspected", false):
				_commit({"inspected": true})
			elif data.get("brake_armed", false) and _can_test():
				_test_left = test_duration
				_commit({"testing": true})
			else: return false
		WinchPreparationControl.Action.PIN:
			if not data.get("inspected", false) or data.get("pin_removed", false): return false
			_busy_left = pin_animation.get_animation(&"release").length
			_commit({"pin_removed": true})
		WinchPreparationControl.Action.BRAKE:
			if not data.get("pin_removed", false) or data.get("brake_armed", false): return false
			_busy_left = brake_animation.get_animation(&"arm").length
			_commit({"brake_armed": true})
	return true


func _commit(changes: Dictionary) -> void:
	var snapshot := gameplay_state.get_snapshot()
	var data := gameplay_state.get_winch_preparation().duplicate(true)
	data.merge(changes, true)
	snapshot.maintenance["winch_preparation"] = data
	gameplay_state._broadcast_snapshot(snapshot)


func _pose(animation: AnimationPlayer, clip: StringName, enabled: bool, previous: bool, initial: bool) -> void:
	if enabled and not previous and not initial:
		animation.play(clip)
		if animation == brake_animation: $BrakeAssembly/LeverAudio.play()
		else: $BrakeAssembly/MechanicalAudio.play()
	elif initial or enabled != previous:
		animation.play(clip)
		animation.seek(animation.get_animation(clip).length if enabled else 0.0, true)
		animation.pause()


func _on_snapshot(_snapshot: Dictionary) -> void:
	var data := gameplay_state.get_winch_preparation()
	var initial := not _initialized or gameplay_state.applying_initial_snapshot
	_pose(pin_animation, &"release", bool(data.get("pin_removed", false)), bool(_previous.get("pin_removed", false)), initial)
	_pose(brake_animation, &"arm", bool(data.get("brake_armed", false)), bool(_previous.get("brake_armed", false)), initial)
	var testing := bool(data.get("testing", false))
	if testing and not _previous.get("testing", false):
		test_animation.speed_scale = test_animation.get_animation(&"test").length / test_duration
		test_animation.play(&"test")
		$Console/TestAudio.play()
	elif not testing:
		$Console/TestAudio.stop()
		test_animation.play(&"test")
		test_animation.seek(0.0, true)
		test_animation.pause()
		_test_left = 0.0
	var powered := gameplay_state.main_breaker_on
	var status: StringName = &"off" if not powered else &"ready" if data.get("tested", false) else &"service" if data.get("brake_armed", false) or testing else &"locked"
	status_animation.play(status)
	status_animation.advance(0.0)
	status_animation.pause()
	service_light.visible = powered
	_previous = data.duplicate(true)
	_initialized = true
