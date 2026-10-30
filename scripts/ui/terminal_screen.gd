class_name TerminalScreenUI
extends PanelContainer

signal quest_requested
signal close_requested
@export var ready_background: StyleBox
@export var missing_background: StyleBox
@export var app_background: StyleBox
var app_open := false
var _quest_hold := 0.0
var _quest_holding := false
var terminal: Node
@onready var extraction_audio: AudioStreamPlayer = $ExtractionAudio

func _ready() -> void:
	$Overlay/Tabs/Expedition.pressed.connect(func(): request_app(false))
	$Overlay/Tabs/Clicker.pressed.connect(func(): request_app(true))
	$Overlay/Tabs/Close.pressed.connect(func(): close_requested.emit())
	$Overlay/QuestAction.pressed.connect(func():
		if terminal != null and not terminal.is_key_terminal: quest_requested.emit())
	$Overlay/QuestAction.button_down.connect(func():
		if terminal != null and terminal.is_key_terminal and not $Overlay/QuestAction.disabled:
			_quest_hold = 0.0
			_quest_holding = true
			if terminal.request_clicker_action(&"quest_begin"):
				extraction_audio.play()
			else:
				_quest_holding = false)
	$Overlay/QuestAction.button_up.connect(_cancel_quest_hold)

func bind(controller: BaseGameplayController, source: Node) -> void:
	terminal = source
	$Overlay/LabClicker.bind(controller, source)

func request_app(clicker: bool) -> void:
	if terminal != null: terminal.request_app(clicker)

func select_app(clicker: bool) -> void:
	app_open = clicker
	$ShellArtwork.visible = clicker
	$Margin.visible = not clicker
	$Overlay/LabClicker.visible = clicker
	$Overlay/QuestAction.visible = not clicker
	$Overlay/Tabs/Expedition.set_pressed_no_signal(not clicker)
	$Overlay/Tabs/Clicker.set_pressed_no_signal(clicker)
	if terminal != null: terminal.refresh_app_display()

func set_key_present(present: bool) -> void:
	add_theme_stylebox_override("panel", app_background if app_open else (ready_background if present else missing_background))

func set_quest_available(available: bool) -> void:
	$Overlay/QuestAction.disabled = not available or terminal == null or not terminal.can_operate()

func refresh_access() -> void:
	var readonly: bool = terminal == null or not terminal.can_operate()
	$Overlay/Tabs/Expedition.disabled = readonly
	$Overlay/Tabs/Clicker.disabled = readonly
	$Overlay/LabClicker.refresh()

func _cancel_quest_hold() -> void:
	extraction_audio.stop()
	if _quest_holding and terminal != null: terminal.request_clicker_action(&"quest_cancel")
	_quest_holding = false
	_quest_hold = 0.0

func _process(delta: float) -> void:
	if terminal == null: return
	if _quest_holding:
		if not terminal.active or app_open or $Overlay/QuestAction.disabled:
			_cancel_quest_hold()
		else:
			_quest_hold += delta
			if _quest_hold >= 1.35:
				_quest_holding = false
				extraction_audio.stop()
				quest_requested.emit()
	$Overlay/QuestAction.text = ("УДЕРЖИВАЙТЕ / ИЗВЛЕЧЬ PASS KEY  %d%%" % mini(100, int(_quest_hold / 1.35 * 100.0))) if terminal.is_key_terminal else "PASS KEY / ВЗАИМОДЕЙСТВОВАТЬ"
