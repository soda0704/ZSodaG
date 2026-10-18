extends Control
## Presentation only; no timers or money live in this view.
const CARD := preload("res://scenes/ui/clicker/upgrade_card.tscn")
const NUMBER := preload("res://scenes/ui/clicker/floating_number.tscn")
@export var activity_cold_style: StyleBox
@export var activity_hot_style: StyleBox
var _bacteria_pending := false
var _bacteria_request_since := 0
var state: BaseGameplayController
var terminal: Node
var _cards: Dictionary = {}
var _pending := false
var _pending_since := 0
var _effect_serial := 0
var _scroll_elapsed := 0.0
var _last_sent_scroll := -1

func _ready() -> void:
	$Tube.pressed.connect(_click)
	$Bacteria/Icon.pressed.connect(_collect_bacterium)
	set_process(false)

func bind(controller: BaseGameplayController, source: Node) -> void:
	if state == controller and terminal == source: return
	if is_instance_valid(state) and state.clicker_changed.is_connected(refresh): state.clicker_changed.disconnect(refresh)
	if is_instance_valid(terminal) and terminal.clicker_result.is_connected(_result): terminal.clicker_result.disconnect(_result)
	state = controller
	terminal = source
	for child in $Scroll/Cards.get_children(): child.free()
	_cards.clear()
	for entry in state.clicker.config.upgrades:
		var card := CARD.instantiate()
		$Scroll/Cards.add_child(card)
		card.configure(entry)
		card.purchase_requested.connect(_buy)
		_cards[entry.id] = card
	$Title.text = state.clicker.config.title
	$UpgradeHeading.text = "UPGRADES / %d TYPES" % state.clicker.config.upgrades.size()
	$CounterPanel/Resource.text = state.clicker.config.resource_name_plural + " STORED"
	$ClickAudio.stream = state.clicker.config.click_sound
	$PurchaseAudio.stream = state.clicker.config.purchase_sound
	$ErrorAudio.stream = state.clicker.config.error_sound
	state.clicker_changed.connect(refresh)
	terminal.clicker_result.connect(_result)
	refresh()
	set_process(true)

func _process(delta: float) -> void:
	if terminal != null:
		if not terminal.can_operate():
			$Scroll.scroll_vertical = terminal.app_scroll
		else:
			_scroll_elapsed += delta
			if _scroll_elapsed >= 0.1 and $Scroll.scroll_vertical != _last_sent_scroll:
				_scroll_elapsed = 0.0
				_last_sent_scroll = $Scroll.scroll_vertical
				terminal.request_scroll(_last_sent_scroll)
	if _bacteria_pending and Time.get_ticks_msec() - _bacteria_request_since > 3000:
		_bacteria_pending = false
		refresh()
	# Never leave a button locked after a disconnection/lost terminal session.
	if _pending and Time.get_ticks_msec() - _pending_since > 3000:
		_pending = false
		$Status.text = "NO REPLY / TRY AGAIN"
		refresh()

func refresh() -> void:
	if state == null: return
	$CounterPanel/Balance.text = LabClicker.format_number(state.clicker.samples)
	$Rates.text = "%s / CLICK    %s / SEC" % [LabClicker.format_number(state.clicker.click_power()), LabClicker.format_number(state.clicker.income(ClickerUpgrade.Effect.PASSIVE_INCOME))]
	$Rhythm/Meter.value = state.clicker.activity * 100.0
	$Rhythm/Multiplier.text = "x" + LabClicker.format_number(state.clicker.click_multiplier())
	var hot := state.clicker.click_multiplier() > 1.0
	$Rhythm/Meter.add_theme_stylebox_override("fill", activity_hot_style if hot else activity_cold_style)
	$Rhythm/Multiplier.modulate = Color(0.65, 1.0, 0.22) if hot else Color(0.62, 0.82, 0.87)
	$Rhythm/Threshold.position.y = $Rhythm/Meter.position.y + $Rhythm/Meter.size.y * (1.0 - state.clicker.config.activity_threshold)
	var appeared := state.clicker.bacteria_remaining > 0.0
	if appeared != $Bacteria.visible:
		$Bacteria.visible = appeared
		if appeared:
			$BacteriaAnimation.play(&"idle")
			$Status.text = "RARE MICROBE / CATCH IT!"
		else: $BacteriaAnimation.stop()
	if appeared:
		var locations := $BacteriaLocations.get_children()
		$Bacteria.position = locations[state.clicker.bacteria_slot % locations.size()].position
		$Bacteria/Life.value = 100.0 * state.clicker.bacteria_remaining / state.clicker.config.bacteria_lifetime
		$Bacteria/Icon.tooltip_text = "CAPTURE +" + LabClicker.format_number(state.clicker.bacteria_reward())
		$Bacteria/Icon.disabled = _bacteria_pending or terminal == null or not terminal.can_operate()
	for card in _cards.values(): card.refresh(state.clicker, _pending or terminal == null or not terminal.can_operate())

func _click() -> void:
	if terminal == null or not terminal.can_operate(): return
	$PressAnimation.stop()
	$PressAnimation.play(&"press")
	if $ClickAudio.stream != null: $ClickAudio.play()
	terminal.request_clicker_action(&"click")

func _collect_bacterium() -> void:
	if _bacteria_pending or terminal == null or not terminal.can_operate(): return
	_bacteria_pending = true
	_bacteria_request_since = Time.get_ticks_msec()
	if not terminal.request_clicker_action(&"bacteria", state.clicker.bacteria_id): _bacteria_pending = false
	refresh()

func _show_gain(amount: float, point: Vector2) -> void:
	if $Effects.get_child_count() >= 8 or not is_visible_in_tree(): return
	var popup := NUMBER.instantiate()
	$Effects.add_child(popup)
	popup.position = point
	popup.show_amount(amount)

func _buy(id: StringName) -> void:
	if _pending or terminal == null or not terminal.can_operate(): return
	if not _cards[id].available:
		_error("NOT ENOUGH " + state.clicker.config.resource_name_plural)
		return
	_pending = true
	_pending_since = Time.get_ticks_msec()
	refresh()
	if not terminal.request_clicker_action(id):
		_pending = false
		_error("TERMINAL OFFLINE")
		refresh()

func _result(id: StringName, success: bool, amount: float) -> void:
	if id == &"quest": return
	if id == &"bacteria": _bacteria_pending = false
	elif id != &"click": _pending = false
	if not success:
		_error("REQUEST DECLINED")
	elif id == &"click":
		if not terminal.can_operate():
			$PressAnimation.stop()
			$PressAnimation.play(&"press")
		_show_gain(amount, Vector2(48 + (_effect_serial * 67) % 176, 170 + (_effect_serial * 29) % 90))
		_effect_serial += 1
	elif id == &"bacteria":
		_show_gain(amount, $Bacteria.position + Vector2(-25, 0))
		$Status.text = "MICROBE CAPTURED / +" + LabClicker.format_number(amount)
		if terminal.active and $PurchaseAudio.stream != null: $PurchaseAudio.play()
	else:
		if _cards.has(id): _cards[id].purchase_feedback()
		$Status.text = "UPGRADE INSTALLED / NICE WORK"
		if terminal.active and $PurchaseAudio.stream != null: $PurchaseAudio.play()
	refresh()

func _error(message: String) -> void:
	$Status.text = message
	if $ErrorAudio.stream != null: $ErrorAudio.play()
