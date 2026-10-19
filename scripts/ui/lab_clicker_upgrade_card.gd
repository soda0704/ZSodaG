extends Panel
signal purchase_requested(id: StringName)
var upgrade: ClickerUpgrade
var available := false
var _busy := false
var _last_view: Array = []

func _ready() -> void:
	$Buy.pressed.connect(func(): purchase_requested.emit(upgrade.id))

func configure(entry: ClickerUpgrade) -> void:
	_last_view.clear()
	upgrade = entry
	$Icon.texture = entry.icon
	$Title.text = entry.title.to_upper()
	$Description.text = entry.description.to_upper()
	$Effect.text = "+%s / %s" % [LabClicker.format_number(entry.effect_value), "CLICK" if entry.effect_type == ClickerUpgrade.Effect.CLICK_POWER else "SEC"]

func refresh(model: LabClicker, busy: bool) -> void:
	_busy = busy
	var amount := model.count(upgrade.id)
	var price: float = ceil(upgrade.base_cost * pow(upgrade.cost_multiplier, amount)) if amount < model.config.max_owned else INF
	available = model.samples >= price
	var view := [amount, price, available, busy, model.config.max_owned]
	if view == _last_view: return
	_last_view = view
	$Owned.text = "OWNED %d" % amount
	$Buy.text = (LabClicker.format_number(price) + "\nBUY") if amount < model.config.max_owned else "MAX"
	# Insufficient funds remains focusable for a short error sound/message.
	$Buy.disabled = busy or amount >= model.config.max_owned
	var shade := Color.WHITE if available else Color(0.47, 0.58, 0.66)
	$Icon.modulate = shade
	$Title.modulate = shade
	$Buy.modulate = Color(0.66, 1.0, 0.48) if available else Color(0.52, 0.61, 0.69)

func purchase_feedback() -> void:
	$PurchaseFlash.stop()
	$PurchaseFlash.play(&"purchase")
