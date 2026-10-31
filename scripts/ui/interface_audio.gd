extends Node
## Local UI feedback survives scene changes; never sent through multiplayer.
signal sound_played(kind: StringName)

@onready var hover: AudioStreamPlayer = $Hover
@onready var click: AudioStreamPlayer = $Click
var _pointer_input := true
var _last_hover_id := 0
var _last_hover_frame := -1

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().node_added.connect(_node_added)
	_scan.call_deferred()

func _input(event: InputEvent) -> void:
	if event is InputEventMouse:
		_pointer_input = true
	elif (event is InputEventKey or event is InputEventJoypadButton) and event.is_pressed():
		_pointer_input = false
	elif event is InputEventJoypadMotion and absf(event.axis_value) > .5:
		_pointer_input = false
	elif event is InputEventAction and event.pressed and str(event.action).begins_with("ui_"):
		_pointer_input = false

func _scan() -> void:
	for node in get_tree().root.find_children("*", "Control", true, false): _attach(node)
	for node in get_tree().root.find_children("*", "PopupMenu", true, false): _attach(node)

func _node_added(node: Node) -> void:
	if node is Control or node is PopupMenu: _attach_id.call_deferred(node.get_instance_id())

func _attach_id(id: int) -> void:
	var node := instance_from_id(id)
	if is_instance_valid(node) and node.is_inside_tree(): _attach(node)

func _attach(node: Node) -> void:
	if node is PopupMenu:
		if node.id_focused.is_connected(_popup_hover.bind(node)): return
		node.id_focused.connect(_popup_hover.bind(node))
		node.id_pressed.connect(_popup_click.bind(node))
		node.window_input.connect(_popup_input.bind(node))
		node.popup_hide.connect(func():node.set_meta("_ui_audio_hover",-1))
		return
	if not (node is BaseButton or node is LineEdit or node is TextEdit or node is Slider): return
	if node.mouse_entered.is_connected(_hover.bind(node)): return
	node.mouse_entered.connect(_hover.bind(node))
	node.focus_entered.connect(_focus.bind(node))
	node.gui_input.connect(_gui_input.bind(node))
	if node is OptionButton or node is MenuButton: _attach(node.get_popup())

func _enabled(control: Control) -> bool:
	if not control.is_visible_in_tree() or control.is_queued_for_deletion(): return false
	if control is BaseButton: return not control.disabled
	if control is LineEdit or control is TextEdit or control is Slider: return control.editable
	return true

func _hover(control: Control) -> void:
	if not _enabled(control): return
	var frame := Engine.get_process_frames()
	if _last_hover_id == control.get_instance_id() and _last_hover_frame == frame: return
	_last_hover_id = control.get_instance_id(); _last_hover_frame = frame
	hover.play()
	sound_played.emit(&"hover")

func _focus(control: Control) -> void:
	_focus_after_input.call_deferred(control.get_instance_id())

func _focus_after_input(id: int) -> void:
	var control := instance_from_id(id) as Control
	if is_instance_valid(control) and control.has_focus() and not _pointer_input: _hover(control)

func _gui_input(event: InputEvent, control: Control) -> void:
	_input(event)
	if not _enabled(control) or event.is_echo(): return
	var pointer_press: bool = event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed
	var accept_press: bool = control is BaseButton and event.is_action_pressed("ui_accept")
	if pointer_press or accept_press: _click(control)

func _click(source: Node) -> void:
	var ancestor := source
	while ancestor != null:
		# Specialized applications may already own action/success/error sounds.
		if not bool(ancestor.get_meta("ui_click_sound", true)): return
		ancestor = ancestor.get_parent()
	hover.stop()
	click.play()
	sound_played.emit(&"click")

func _popup_hover(id: int, menu: PopupMenu) -> void:
	var index := menu.get_item_index(id)
	if index < 0 or menu.is_item_disabled(index) or menu.is_item_separator(index): return
	menu.set_meta("_ui_audio_hover",index)
	hover.play()
	sound_played.emit(&"hover")

func _popup_input(event: InputEvent, menu: PopupMenu) -> void:
	if event is InputEventMouseMotion: _popup_pointer.call_deferred(menu.get_instance_id())

func _popup_pointer(id: int) -> void:
	var menu := instance_from_id(id) as PopupMenu
	if not is_instance_valid(menu) or not menu.visible: return
	var index := menu.get_focused_item()
	if index < 0 or menu.is_item_disabled(index) or menu.is_item_separator(index):
		menu.set_meta("_ui_audio_hover",-1)
		return
	if index == int(menu.get_meta("_ui_audio_hover",-1)): return
	_popup_hover(menu.get_item_id(index),menu)

func _popup_click(id: int, menu: PopupMenu) -> void:
	var index := menu.get_item_index(id)
	if index >= 0 and not menu.is_item_disabled(index) and not menu.is_item_separator(index): _click(menu)
