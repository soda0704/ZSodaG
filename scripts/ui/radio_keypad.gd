extends CanvasLayer
var target: RadioTowerInteraction
var _previous_mouse := Input.MOUSE_MODE_CAPTURED
@onready var field: LineEdit = $Shade/Center/Panel/Content/Code
@onready var status: Label = $Shade/Center/Panel/Content/Status

func _ready() -> void:
	hide(); set_process(false); set_process_input(false)
	$Shade/Center/Panel/Content/Confirm.pressed.connect(submit)
	$Shade/Center/Panel/Content/Close.pressed.connect(close)
	field.text_submitted.connect(func(_text): submit())
	for button in $Shade/Center/Panel/Content/Digits.get_children():
		button.pressed.connect(func():
			if button.text == "⌫": field.text=field.text.left(-1)
			elif field.text.length()<4: field.text+=button.text
		)

func open(interaction: RadioTowerInteraction) -> void:
	if visible or get_tree().get_first_node_in_group("terminal_ui") != null: return
	target=interaction
	_previous_mouse=Input.mouse_mode
	add_to_group("terminal_ui"); show(); set_process(true); set_process_input(true)
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	field.clear(); status.text="Четырёхзначный код"; field.grab_focus()

func submit() -> void:
	if field.text.length()!=4 or not field.text.is_valid_int():
		status.text="Введите четыре цифры"; return
	target.request_action(field.text)
	status.text="Проверка кода…"

func result(accepted: bool) -> void:
	if not visible: return
	if accepted: close()
	else: status.text="Неверный код"; field.clear(); field.grab_focus()

func close() -> void:
	if not visible: return
	hide(); remove_from_group("terminal_ui"); set_process(false); set_process_input(false)
	var menu := get_node_or_null("/root/GameMenu")
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE if menu != null and menu.is_menu_open() else _previous_mouse

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		close(); get_viewport().set_input_as_handled()

func _process(_delta: float) -> void:
	var player := get_tree().get_first_node_in_group("local_player") as GamePlayer
	var menu := get_node_or_null("/root/GameMenu")
	if not is_instance_valid(target) or player == null or player.survival.dead or player.is_climbing() or player.global_position.distance_to(target.global_position)>target.interaction_distance or (menu != null and menu.is_menu_open()): close()

func _exit_tree() -> void:
	if visible: Input.mouse_mode=_previous_mouse
