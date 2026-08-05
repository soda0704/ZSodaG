class_name LobbyStartConsole
extends StaticBody3D

@onready var action_button: MeshInstance3D = %ActionButton
@onready var status_label: Label3D = %StatusLabel

var _button_material: StandardMaterial3D


func _ready() -> void:
	_button_material = (
		action_button.get_active_material(0).duplicate()
		as StandardMaterial3D
	)
	action_button.material_override = _button_material
	SteamNetwork.session_ready.connect(_on_session_ready)
	SteamNetwork.session_closed.connect(_on_session_closed)
	CoopLobby.gameplay_started.connect(_on_gameplay_started)
	refresh_visual()


func get_interaction_prompt() -> String:
	if CoopLobby.game_has_started:
		return "Вылет уже начат"
	if multiplayer.is_server():
		return "Начать вылет на базу"
	return "Только хост может начать вылет"


func interact(_interactor: Node) -> void:
	if multiplayer.is_server():
		CoopLobby.start_game()


func network_interact(peer_id: int, _interactor: Node) -> void:
	if not multiplayer.is_server() or peer_id != 1:
		return
	CoopLobby.start_game()


func _on_gameplay_started() -> void:
	refresh_visual()


func _on_session_ready(_as_host: bool) -> void:
	refresh_visual()


func _on_session_closed(_reason: String) -> void:
	refresh_visual()


func refresh_visual() -> void:
	var started := CoopLobby.game_has_started
	var color := (
		Color(0.04, 0.95, 0.12, 1.0)
		if started
		else Color(1.0, 0.01, 0.002, 1.0)
	)
	_button_material.albedo_color = color.darkened(0.35)
	_button_material.emission_enabled = true
	_button_material.emission = color
	_button_material.emission_energy_multiplier = 3.0
	status_label.visible = not started
	status_label.text = "ВЫЛЕТ НАЧАТ" if started else "ВЫЛЕТ НА БАЗУ"
