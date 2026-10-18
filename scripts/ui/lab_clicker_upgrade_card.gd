extends Panel
signal purchase_requested(id: StringName)
var upgrade: ClickerUpgrade
var available := false
var _busy := false

func _ready() -> void:
	$Buy.pressed.connect(func(): purchase_requested.emit(upgrade.id))

func configure(entry: ClickerUpgrade) -> void:
	upgrade = entry
	$Icon.texture = entry.icon
	$Title.text = entry.title.to_upper()
	$Description.text = entry.description.to_upper()
	$Effect.text = "+%s / %s" % [LabClicker.format_number(entry.effect_value), "CLICK" if entry.effect_type == ClickerUpgrade.Effect.CLICK_POWER else "SEC"]

func refresh(model: LabClicker, busy: bool) -> void:
	_busy = busy
	available = model.samples >= model.cost(upgrade.id)
	$Owned.text = "OWNED %d" % model.count(upgrade.id)
	$Buy.text = (LabClicker.format_number(model.cost(upgrade.id)) + "\nBUY") if model.count(upgrade.id) < model.config.max_owned else "MAX"
	# Insufficient funds remains focusable for a short error sound/message.
	$Buy.disabled = busy or model.count(upgrade.id) >= model.config.max_owned
	var shade := Color.WHITE if available else Color(0.47, 0.58, 0.66)
	$Icon.modulate = shade
	$Title.modulate = shade
	$Buy.modulate = Color(0.66, 1.0, 0.48) if available else Color(0.52, 0.61, 0.69)

func purchase_feedback() -> void:
	$PurchaseFlash.stop()
	$PurchaseFlash.play(&"purchase")
