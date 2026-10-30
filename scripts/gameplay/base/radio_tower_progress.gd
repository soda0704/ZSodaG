class_name RadioTowerProgress
extends RefCounted
## Shared story inventory and flags live in the existing saved/replicated maintenance snapshot.
static func ensure(state: Node) -> void:
	if state.multiplayer.is_server() and not state.maintenance.has("radio_pin"):
		state.maintenance["radio_pin"] = "%04d" % randi_range(0,9999)

static func tasks(state: Node) -> String:
	if state.day_index < 2 or not state.maintenance.get("radio_note_read", false): return ""
	var data: Dictionary = state.maintenance
	if data.get("radio_repaired",false): return "Радиовышка: электромодуль заменён."
	var text := "Радиовышка — восстановить связь\n"
	text += "Код ограждения: %s\n" % data.get("radio_pin","••••")
	if not data.get("radio_unlocked",false): text += "Открыть кодовый замок у вышки.\n"
	text += "Подняться к верхнему электрощиту и заменить модуль."
	if data.get("radio_module",false): text += "\nЗапасной электромодуль у команды."
	else: text += "\nЗапасной электромодуль — возле компьютера на этаже испытаний (−3)."
	return text

static func act(state: Node, action: StringName, peer: int, target: Node, code := "") -> bool:
	if not state.multiplayer.is_server() or state.day_index < 2: return false
	var player: Node = state.get_player_node(peer)
	if not target.can_use(peer,player): return false
	var snapshot: Dictionary = state.get_snapshot()
	var data: Dictionary = snapshot.maintenance
	match action:
		&"note": data["radio_note_read"] = true
		&"gate":
			if code.length()!=4 or code!=str(data.get("radio_pin","")): return false
			data["radio_unlocked"] = true
		&"module":
			if data.get("radio_module",false) or data.get("radio_repaired",false): return false
			data["radio_module"] = true
		&"socket":
			if not data.get("radio_module",false) or data.get("radio_repaired",false): return false
			data["radio_module"] = false
			data["radio_repaired"] = true
		_: return false
	state._broadcast_snapshot(snapshot)
	return true
