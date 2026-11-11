extends RefCounted
## Buttons use the same executor and authority checks as typed commands.
const TOGGLES := {
	"/freecam": "Свободная камера", "/fullbright": "Светлый тестовый режим",
	"/camera_filters": "Фильтры камеры",
	"/blizzard": "Метель", "/fly": "Полёт", "/across": "Сквозь стены", "/god": "Бессмертие"
}
var host: CanvasLayer
var panel: TabContainer
var controls: Dictionary = {}
var actions: Dictionary = {}
var pages: Dictionary = {}
var _elapsed := 0.0

func _init(console: CanvasLayer) -> void:
	host = console
	panel = TabContainer.new()
	panel.name = "Controls"
	panel.custom_minimum_size.y = 220
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	host.get_node("Panel/Box").add_child(panel)
	host.get_node("Panel/Box").move_child(panel, host.get_node("Panel/Box/Commands").get_index())
	for title in ["Свет и вид", "Игрок", "Мир", "Предметы", "Существа", "Цель", "Огнемёт", "Сервис"]:
		var scroll := ScrollContainer.new()
		scroll.name = title
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		panel.add_child(scroll)
		var rows := VBoxContainer.new()
		rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.add_child(rows)
		pages[title] = rows
	for command: String in TOGGLES:
		var button := CheckButton.new()
		button.text = TOGGLES[command]
		button.tooltip_text = command
		button.focus_mode = Control.FOCUS_NONE
		pages["Игрок" if command in ["/fly", "/across", "/god"] else "Свет и вид"].add_child(button)
		button.toggled.connect(func(enabled: bool):
			var argument := "on" if enabled else "off"
			host._submit(command + " " + argument)
			sync()
		)
		controls[command] = button
	for command: String in host._all_commands():
		if TOGGLES.has(command.split(" ")[0]) and not " speed " in command: continue
		var button := Button.new()
		button.text = command + "  —  " + str(host._command_row(command)).get_slice(" — ", 1)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		button.tooltip_text = button.text
		button.custom_minimum_size.y = 36
		button.focus_mode = Control.FOCUS_NONE
		pages[_category(command)].add_child(button)
		button.pressed.connect(func(): host._submit(command); sync())
		actions[command] = button
	_add_number("Игрок", "Скорость игрока", "/speed", 0.1, 20, 0.1, 1)
	_add_number("Свет и вид", "Скорость свободной камеры", "/freecam speed", 0.1, 100, 0.1, 5)
	_add_number("Мир", "Перейти к дню", "/day", 1, 999, 1, 1)
	sync()

func _category(command: String) -> String:
	var verb := command.get_slice(" ", 0)
	if verb == "/flame" or "flamethrower" in command or "flame_" in command: return "Огнемёт"
	if verb in ["/item", "/weapon", "/ammo", "/tape", "/crowbar", "/flashlight", "/fuel"]: return "Предметы"
	if verb in ["/spawn", "/monsters", "/despawn"]: return "Существа"
	if verb in ["/target", "/open", "/close", "/kill"]: return "Цель"
	if verb in ["/help", "/clear"]: return "Сервис"
	if verb == "/freecam": return "Свет и вид"
	if verb in ["/speed", "/heal", "/where"]: return "Игрок"
	return "Мир"

func _add_number(category: String, title: String, command: String, minimum: float, maximum: float, step: float, initial: float) -> void:
	var row := HBoxContainer.new()
	pages[category].add_child(row)
	var label := Label.new()
	label.text = title
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var value := SpinBox.new()
	value.min_value = minimum; value.max_value = maximum; value.step = step; value.value = initial
	value.custom_minimum_size.x = 120
	row.add_child(value)
	var button := Button.new()
	button.text = "Применить"
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(func(): host._submit(command + " " + (str(int(value.value)) if step == 1.0 else str(value.value))); sync())
	row.add_child(button)

func update(delta: float) -> void:
	_elapsed += delta
	if _elapsed < 0.2: return
	_elapsed = 0.0
	sync()

func sync() -> void:
	var tree := host.get_tree()
	var player := tree.get_first_node_in_group("local_player") as GamePlayer
	var lighting := tree.get_first_node_in_group("world_lighting") as WorldLighting
	var weather := tree.get_first_node_in_group("local_blizzard")
	var post := player.get_node_or_null("PlayerUI/CameraPostProcess") if player != null else null
	var states := {
		"/freecam": player.is_debug_free_camera_active() if player != null else false,
		"/fullbright": lighting.debug_darkness < 1.0 if lighting != null else false,
		"/camera_filters": post.effect_enabled if post != null else false,
		"/blizzard": weather.enabled if weather != null else false,
		"/fly": player.debug_fly if player != null else false,
		"/across": player.debug_across if player != null else false,
		"/god": (player.survival.debug_invincible if host.multiplayer.is_server() else bool(host._server_toggle_states.get(player.get_instance_id(), false))) if player != null else false
	}
	for command in controls:
		var button: CheckButton = controls[command]
		button.set_pressed_no_signal(states[command])
		button.disabled = (lighting == null if command == "/fullbright" else weather == null if command == "/blizzard" else player == null)

func filter_commands(partial: String, show_all: bool) -> void:
	for command in actions: actions[command].visible = show_all or str(command).begins_with(partial)
	for command in controls: controls[command].visible = show_all or str(command).begins_with(partial) or partial.begins_with(str(command) + " ")
	# Matching actions should be reachable without manually guessing their tab.
	if not show_all and partial != "/":
		for index in panel.get_tab_count():
			var rows: VBoxContainer = pages[panel.get_tab_title(index)]
			if rows.get_children().any(func(child): return child.visible and (child is Button)):
				panel.current_tab = index
				break
