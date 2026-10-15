class_name NorthernLobbyMenu
extends VBoxContainer

var session_status_label: Label
var lobby_id_value: LineEdit
var copy_button: Button
var invite_button: Button
var ready_button: Button
var start_button: Button
var leave_button: Button
var ready_status_label: Label
var crew: VBoxContainer
var count_label: Label
var _menu: Node

func configure(menu: Node) -> void:
	_menu = menu
	session_status_label = find_child("SessionStatus", true, false)
	lobby_id_value = find_child("LobbyID", true, false)
	copy_button = find_child("CopyID", true, false)
	invite_button = find_child("Invite", true, false)
	ready_button = find_child("Ready", true, false)
	start_button = find_child("Launch", true, false)
	leave_button = find_child("Leave", true, false)
	ready_status_label = find_child("ReadyStatus", true, false)
	count_label = find_child("Count", true, false)
	crew = find_child("Crew", true, false)
	crew.add_theme_constant_override("separation", 0)
	copy_button.pressed.connect(func(): _menu._on_copy_lobby_id_pressed())
	invite_button.pressed.connect(func(): _menu._on_invite_pressed())
	ready_button.pressed.connect(func(): _menu._on_ready_pressed())
	start_button.pressed.connect(func(): _menu._on_start_game_pressed())
	leave_button.pressed.connect(func(): _menu._on_leave_lobby_pressed())

func refresh() -> void:
	if crew == null:
		return
	for child in crew.get_children():
		crew.remove_child(child)
		child.queue_free()
	var world := get_tree().get_first_node_in_group("network_gameplay_controller")
	var solo: bool = world != null and world.has_method("is_solo_arrival") and world.is_solo_arrival()
	var peers: Array = CoopLobby.ready_states.keys()
	peers.sort()
	if peers.is_empty() and solo:
		peers.append(multiplayer.get_unique_id())
	count_label.text = "%d / %d" % [peers.size(), 1 if solo else CoopLobby.MAX_PLAYERS]
	for index in (1 if solo else CoopLobby.MAX_PLAYERS):
		var row := preload("res://scenes/ui/lobby_member.tscn").instantiate()
		crew.add_child(row)
		row.get_node("Content/Order").text = "0%d" % [index + 1]
		if index < peers.size():
			var peer := int(peers[index])
			var mine := peer == multiplayer.get_unique_id()
			var nickname := "Вы" if mine else SteamNetwork.get_peer_persona_name(peer)
			row.get_node("Content/Identity/MemberName").text = nickname.to_upper()
			row.get_node("Content/Identity/Role").text = "ОДИНОЧНАЯ ЭКСПЕДИЦИЯ" if solo else ("ОРГАНИЗАТОР" if peer == 1 else "УЧАСТНИК")
			var peer_ready := bool(CoopLobby.ready_states.get(peer, false))
			row.get_node("Content/Ready").text = "ГОТОВ" if peer_ready else "НЕ ГОТОВ"
	lobby_id_value.text = str(SteamNetwork.lobby_id) if SteamNetwork.lobby_id > 0 else "Одиночная экспедиция" if solo else "Подключение…"
	copy_button.disabled = SteamNetwork.lobby_id <= 0
	invite_button.disabled = SteamNetwork.lobby_id <= 0 or not SteamNetwork.is_host
	copy_button.visible = not solo
	invite_button.visible = not solo
	start_button.visible = SteamNetwork.is_host and not solo and not CoopLobby.game_has_started
	start_button.disabled = not CoopLobby.can_host_start()
	ready_button.disabled = not solo and not CoopLobby.session_active
	ready_button.text = "ОТМЕНИТЬ ГОТОВНОСТЬ" if not solo and CoopLobby.is_local_ready() else "ГОТОВ К ВЫСАДКЕ"
	ready_status_label.text = "Подтвердите готовность к высадке." if solo else "Все готовы. Можно начинать высадку." if CoopLobby.can_host_start() else "Высадка начнётся после подтверждения готовности."
	if CoopLobby.game_has_started:
		ready_button.text = "ПРОДОЛЖИТЬ ИГРУ"
		ready_button.disabled = false
		ready_status_label.text = "Экспедиция началась."
