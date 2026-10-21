class_name ExpeditionWinchController
extends FunctionalElevatorController

@export var gameplay_state_path: NodePath
@export var rope_animation_path: NodePath
@export var landing_lights_paths: Array[NodePath] = []
var gameplay_state: BaseGameplayController
var rope_animation: AnimationPlayer


func _ready() -> void:
	super._ready()
	add_to_group("expedition_winches")
	gameplay_state = get_node_or_null(gameplay_state_path) as BaseGameplayController
	rope_animation = get_node_or_null(rope_animation_path) as AnimationPlayer
	if rope_animation != null:
		rope_animation.play(&"travel")
		rope_animation.pause()
	if gameplay_state == null:
		push_error("Winch: assign the gameplay state in Inspector")
		set_powered(false)
		return
	gameplay_state.snapshot_changed.connect(_on_gameplay_state)
	_on_gameplay_state({})


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if rope_animation != null:
		var distance := _get_floor_y(0) - _get_floor_y(1)
		rope_animation.seek(clampf((_get_floor_y(0) - cabin.position.y) / maxf(distance, 0.01), 0.0, 1.0), true)


func _on_gameplay_state(_snapshot: Dictionary) -> void:
	for path in landing_lights_paths:
		var light := get_node_or_null(path) as Light3D
		if light != null: light.visible = gameplay_state.main_breaker_on
	if multiplayer.is_server():
		set_day(gameplay_state.day_index)
		# The solar fuse supplies the main elevator only.
		set_powered(gameplay_state.day_index >= gameplay_state.CAVE_DAY_INDEX and gameplay_state.main_breaker_on and gameplay_state.is_winch_prepared())


func get_button_prompt(floor_index: int, is_call_button: bool) -> String:
	if gameplay_state != null and gameplay_state.day_index < gameplay_state.CAVE_DAY_INDEX:
		return "Лебёдка будет доступна на 7-й день"
	if gameplay_state != null and not gameplay_state.is_winch_prepared():
		return "Подготовьте лебёдку: осмотрите пульт на уровне 5"
	if not is_powered:
		return "Лебёдка: нет основного питания"
	if super.get_button_prompt(floor_index, is_call_button).is_empty():
		return ""
	if is_call_button:
		return "Вызвать клеть: " + _get_floor_label(floor_index)
	return "Подняться на уровень 5" if floor_index == 0 else "Спуститься в нижнюю шахту"


func _get_state_label() -> String:
	match state:
		ElevatorState.UNPOWERED: return "НЕТ ПИТАНИЯ"
		ElevatorState.IDLE_OPEN: return "ПОСАДКА"
		ElevatorState.WAITING_FOR_PLAYERS: return "ОСВОБОДИТЕ ПРОЁМ"
		ElevatorState.CLOSING: return "ЗАКРЫТИЕ ВОРОТ"
		ElevatorState.MOVING: return "СПУСК" if _active_destination_floor_index == 1 else "ПОДЪЁМ"
		ElevatorState.ARRIVING: return "ПРИБЫТИЕ"
		ElevatorState.OPENING: return "ОТКРЫТИЕ ВОРОТ"
		_: return "НЕИСПРАВНОСТЬ"
