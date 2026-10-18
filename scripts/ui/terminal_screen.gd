class_name TerminalScreenUI
extends PanelContainer

signal quest_requested
signal close_requested
@export var ready_background: StyleBox
@export var missing_background: StyleBox
@export var app_background: StyleBox
var app_open := false
var terminal: Node

func _ready() -> void:
	$Overlay/Tabs/Expedition.pressed.connect(func(): request_app(false))
	$Overlay/Tabs/Clicker.pressed.connect(func(): request_app(true))
	$Overlay/Tabs/Close.pressed.connect(func(): close_requested.emit())
	$Overlay/QuestAction.pressed.connect(func(): quest_requested.emit())

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
