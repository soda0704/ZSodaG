class_name HelicopterLobbyHud
extends CanvasLayer

@onready var lobby_id_label: Label = %LobbyIdLabel
@onready var lobby_panel: Control = %LobbyPanel
@onready var flight_transition: Control = %FlightTransition
@onready var transition_label: Label = %TransitionLabel

var _transition_generation: int = 0
var _transition_tween: Tween


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	SteamNetwork.session_ready.connect(_on_lobby_state_changed)
	SteamNetwork.session_closed.connect(_on_session_closed)
	CoopLobby.gameplay_started.connect(_on_gameplay_started)
	refresh()


func refresh() -> void:
	var session_active := SteamNetwork.has_active_session()
	lobby_panel.visible = session_active and not CoopLobby.game_has_started
	if not lobby_panel.visible:
		return

	lobby_id_label.text = "LOBBY ID: %s" % SteamNetwork.lobby_id


func _on_lobby_state_changed(_as_host: bool) -> void:
	refresh()


func _on_session_closed(_reason: String) -> void:
	refresh()


func _on_gameplay_started() -> void:
	refresh()
	play_flight_transition()


func play_flight_transition() -> void:
	var transition_id := show_transition_cover("ПОДЛЁТ К БАЗЕ...")
	await get_tree().create_timer(0.45).timeout
	reveal_transition_cover(transition_id)


func show_transition_cover(message: String) -> int:
	_transition_generation += 1
	if is_instance_valid(_transition_tween):
		_transition_tween.kill()
	transition_label.text = message
	flight_transition.visible = true
	flight_transition.modulate = Color.WHITE
	return _transition_generation


func reveal_transition_cover(transition_id: int) -> void:
	if transition_id != _transition_generation:
		return
	if is_instance_valid(_transition_tween):
		_transition_tween.kill()
	_transition_tween = create_tween()
	_transition_tween.tween_property(
		flight_transition,
		"modulate:a",
		0.0,
		0.8
	)
	await _transition_tween.finished
	if transition_id != _transition_generation:
		return
	flight_transition.visible = false
	flight_transition.modulate = Color.WHITE
