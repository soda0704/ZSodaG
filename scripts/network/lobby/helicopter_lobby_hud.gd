class_name HelicopterLobbyHud
extends CanvasLayer
const HUD_LAYOUT := preload("res://scripts/ui/hud_layout.gd")

@onready var lobby_id_label: Label = %LobbyIdLabel
@onready var lobby_panel: Control = %LobbyPanel
@onready var flight_transition: Control = %FlightTransition
@onready var transition_label: Label = %TransitionLabel

var _transition_generation: int = 0
var _transition_tween: Tween
var _waiting_for_arrival := false
var _panel_reveal := 0.0
var _panel_base_position := Vector2.ZERO
var _motion_hud: Control


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = 10 # Follow the local player's HUD sample in this same frame.
	SteamNetwork.session_ready.connect(_on_lobby_state_changed)
	SteamNetwork.session_closed.connect(_on_session_closed)
	CoopLobby.gameplay_started.connect(_on_gameplay_started)
	get_viewport().size_changed.connect(_layout_panel)
	_layout_panel()
	refresh()

func _layout_panel() -> void:
	var factor := HUD_LAYOUT.scale_for(get_viewport()) * (2560.0 / 1920.0)
	lobby_panel.scale = Vector2.ONE * factor
	# Scale about the upper left while keeping the visible right margin consistent.
	lobby_panel.offset_left = -468.0 * factor
	lobby_panel.offset_right = lobby_panel.offset_left + 420.0
	lobby_panel.offset_top = 48.0 * factor
	lobby_panel.offset_bottom = lobby_panel.offset_top + 88.0
	_panel_base_position = lobby_panel.position


func _process(delta: float) -> void:
	if flight_transition.visible:
		var frame := int(Time.get_ticks_msec() / 170) % 4
		var cells := ""
		for i in 4: cells += ("■ " if i == frame else "□ ")
		$FlightTransition/LoadingActivity.text = cells

	lobby_panel.visible = _waiting_for_arrival and not GameMenu.is_menu_open()
	if lobby_panel.visible:
		if not is_instance_valid(_motion_hud):
			var actor := get_tree().get_first_node_in_group("local_player")
			if actor != null: _motion_hud = actor.get_node_or_null("PlayerUI/NorthernLabHUD")
		var drift := Vector2.ZERO
		if is_instance_valid(_motion_hud): drift = _motion_hud.get_parallax_offset_pixels()
		lobby_panel.position = _panel_base_position + drift
	_panel_reveal = move_toward(_panel_reveal, 1.0, delta / 0.20) if lobby_panel.visible else 0.0
	lobby_panel.modulate.a = _panel_reveal * _panel_reveal * (3.0 - 2.0 * _panel_reveal)
	var pause_hint := str(get_node("/root/SteamInput").get_action_hint(&"pause")).trim_prefix("[").trim_suffix("]").to_upper().replace("ESCAPE", "ESC")
	var hint := "%s — МЕНЮ ЛОББИ" % pause_hint
	if $LobbyPanel/Margin/Content/MenuHint.text != hint:
		$LobbyPanel/Margin/Content/MenuHint.text = hint


func refresh() -> void:
	var world := get_tree().get_first_node_in_group("network_gameplay_controller")
	var waiting: bool = world != null and world.has_method("is_waiting_for_arrival") and world.is_waiting_for_arrival()
	_waiting_for_arrival = waiting
	lobby_panel.visible = waiting and not GameMenu.is_menu_open()
	if not waiting:
		return

	if world.is_solo_arrival():
		lobby_id_label.text = "CH-47 · ПОДГОТОВКА К ВЫСАДКЕ"
	elif SteamNetwork.lobby_id > 0:
		lobby_id_label.text = "CH-47 · LOBBY ID: %s" % SteamNetwork.lobby_id
	else:
		lobby_id_label.text = "CH-47 · СОЗДАНИЕ ЛОББИ…"


func _on_lobby_state_changed(_as_host: bool) -> void:
	refresh()


func _on_session_closed(_reason: String) -> void:
	refresh()


func _on_gameplay_started() -> void:
	refresh()


func play_flight_transition() -> void:
	var transition_id := show_transition_cover("ПОДЛЁТ К БАЗЕ...")
	await get_tree().create_timer(0.45).timeout
	reveal_transition_cover(transition_id)


func show_transition_cover(message: String) -> int:
	_transition_generation += 1
	if is_instance_valid(_transition_tween):
		_transition_tween.kill()
	transition_label.text = message
	$FlightTransition/JournalHint.text = "%s · ЖУРНАЛ ЭКСПЕДИЦИИ\nЗадачи, найденные записи и инвентарь — в журнале" % get_node("/root/SteamInput").get_action_hint(&"journal")
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
