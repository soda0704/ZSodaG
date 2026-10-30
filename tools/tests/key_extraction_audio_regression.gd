extends SceneTree
class TerminalStub extends Node:
	var is_key_terminal := true
	var active := true
	var accept := true
	func can_operate() -> bool: return true
	func request_clicker_action(_id: StringName) -> bool: return accept
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	print("PASS " if ok else "FAIL ", label)
	if not ok: failures += 1
func run() -> void:
	var ui = load("res://scenes/ui/terminal_screen.tscn").instantiate()
	root.add_child(ui)
	var terminal := TerminalStub.new(); root.add_child(terminal); ui.terminal = terminal
	var button: Button = ui.get_node("Overlay/QuestAction")
	button.disabled = false
	check(not ui.extraction_audio.playing, "opening/restoring terminal does not play extraction audio")
	button.button_down.emit()
	check(ui.extraction_audio.playing and ui.extraction_audio.stream.resource_path.ends_with("encryption_key_extract.wav"), "hold starts the supplied recording")
	button.button_up.emit()
	check(not ui.extraction_audio.playing and not ui._quest_holding, "release cancels sound and hold")
	button.button_down.emit(); terminal.active = false; ui._process(.1)
	check(not ui.extraction_audio.playing, "closing terminal interrupts extraction audio")
	terminal.active = true; button.button_down.emit(); ui._process(1.36)
	check(not ui.extraction_audio.playing and not ui._quest_holding, "completed extraction stops sound without looping")
	terminal.accept = false; button.button_down.emit()
	check(not ui.extraction_audio.playing and not ui._quest_holding, "rejected request cannot start sound")
	terminal.accept = true; terminal.is_key_terminal = false; button.button_down.emit()
	check(not ui.extraction_audio.playing, "hub delivery never plays extraction sound")
	ui.queue_free(); terminal.queue_free(); await process_frame
	ProjectSettings.set_setting(BaseGameplayController.TEST_SAVE_PATH_SETTING,"user://key_audio_%d.cfg" % OS.get_process_id())
	var base = load("res://scenes/levels/base_blockout_v03.tscn").instantiate()
	root.add_child(base); current_scene = base
	for i in 15: await physics_frame
	root.get_node("GameMenu").force_close_menu()
	var state: BaseGameplayController = base.get_node("BaseGameplayController")
	state.set_process(false)
	var data := state.get_snapshot(); data.day_index = 2; data.main_breaker_on = true; data.fuel_delivered = true; data.fuel_liters = 40; data.quest_stage = 1
	state._broadcast_snapshot(data)
	var player: GamePlayer = get_first_node_in_group("local_player")
	player.set_physics_process(false); player.survival.set_physics_process(false)
	var vault = base.get_node("Floor_Minus1_Control_Security_Blockout/Secure_Data_Vault/Encryption_Key_Terminal")
	var facing: Vector3 = vault.screen.global_basis.z; facing.y = 0
	player.teleport_authoritative(vault.global_position + facing.normalized() * 2, vault.global_rotation.y)
	for i in 8: await physics_frame
	vault.begin_terminal_interaction()
	check(vault.active and vault.can_operate(), "actual key terminal accepts local operator")
	var action: Button = vault.ui.get_node("Overlay/QuestAction")
	action.button_down.emit()
	check(vault.ui.extraction_audio.playing, "actual key UI starts supplied sound during hold")
	await create_timer(.3).timeout
	action.button_up.emit()
	check(not vault.ui.extraction_audio.playing and state.quest_stage == 1, "production cancellation stops sound without granting key")
	action.button_down.emit()
	await create_timer(1.5).timeout
	check(state.quest_stage == 3 and not vault.ui.extraction_audio.playing, "production full hold grants one shared key and stops sound")
	var snapshot := state.get_snapshot(); state._apply_snapshot(snapshot, true)
	check(not vault.ui.extraction_audio.playing, "snapshot restoration of collected key stays silent")
	current_scene = null; base.queue_free(); await process_frame
	print("KEY AUDIO CHECKS 12 FAILURES ", failures); quit(0 if failures == 0 else 1)
