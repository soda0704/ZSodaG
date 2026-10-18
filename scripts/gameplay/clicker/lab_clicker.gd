class_name LabClicker
extends RefCounted
## Pure economy; the base controller owns time, replication and persistence.
var config: LabClickerConfig
var samples := 0.0
var owned: Dictionary = {}
# These values belong to the running session, never to the durable economy save.
var activity := 0.0
var bacteria_remaining := 0.0
var bacteria_id := 0
var bacteria_slot := 0
var _bacteria_wait := 0.0
var _rng := RandomNumberGenerator.new()

func _init(settings: LabClickerConfig = null) -> void:
	config = settings if settings != null else preload("res://scenes/ui/clicker/balance.tres")
	_rng.randomize()
	_schedule_bacterium()

func upgrade(id: StringName) -> ClickerUpgrade:
	for entry in config.upgrades:
		if entry.id == id: return entry
	return null

func count(id: StringName) -> int:
	return int(owned.get(String(id), 0))

func cost(id: StringName) -> float:
	var entry := upgrade(id)
	if entry == null or count(id) >= config.max_owned: return INF
	return ceil(entry.base_cost * pow(entry.cost_multiplier, count(id)))

func income(type: ClickerUpgrade.Effect) -> float:
	var result := config.base_click_power if type == ClickerUpgrade.Effect.CLICK_POWER else 0.0
	for entry in config.upgrades:
		if entry.effect_type == type: result += count(entry.id) * entry.effect_value
	return result

func click_multiplier() -> float:
	return config.activity_multiplier if activity >= config.activity_threshold else 1.0

func click_power() -> float:
	return income(ClickerUpgrade.Effect.CLICK_POWER) * click_multiplier()

func click() -> float:
	activity = minf(1.0, activity + config.activity_per_click)
	var added := minf(click_power(), config.max_samples - samples)
	samples += added
	return added

func advance(delta: float, encounter_enabled: bool = false, powered: bool = true) -> void:
	if not is_finite(delta) or delta <= 0.0: return
	activity = maxf(0.0, activity - delta * config.activity_decay_per_second)
	if powered: samples = minf(config.max_samples, samples + delta * income(ClickerUpgrade.Effect.PASSIVE_INCOME))
	if bacteria_remaining > 0.0:
		bacteria_remaining = maxf(0.0, bacteria_remaining - delta)
		if bacteria_remaining == 0.0: _schedule_bacterium()
	elif encounter_enabled and powered:
		_bacteria_wait -= delta
		if _bacteria_wait <= 0.0:
			bacteria_id += 1
			bacteria_slot = _rng.randi_range(0, 2147483647)
			bacteria_remaining = config.bacteria_lifetime

func bacteria_reward() -> float:
	# Ignore the temporary click multiplier: this reward tracks real upgrades.
	return ceil(income(ClickerUpgrade.Effect.CLICK_POWER) * config.bacteria_clicks_reward + income(ClickerUpgrade.Effect.PASSIVE_INCOME) * config.bacteria_seconds_reward)

func collect_bacterium(ticket: int) -> float:
	if ticket != bacteria_id or ticket <= 0 or bacteria_remaining <= 0.0: return 0.0
	var reward := minf(bacteria_reward(), config.max_samples - samples)
	samples += reward
	bacteria_remaining = 0.0
	_schedule_bacterium()
	return reward

func _schedule_bacterium() -> void:
	_bacteria_wait = _rng.randf_range(minf(config.bacteria_interval_min, config.bacteria_interval_max), maxf(config.bacteria_interval_min, config.bacteria_interval_max))

func buy(id: StringName) -> bool:
	var price := cost(id)
	if not is_finite(price) or samples < price: return false
	samples = maxf(0.0, samples - price)
	owned[String(id)] = count(id) + 1
	return true

func capture() -> Dictionary:
	return {"samples": samples, "owned": owned.duplicate()}

func capture_runtime() -> Dictionary:
	var data := capture()
	data.merge({"activity": activity, "bacteria_remaining": bacteria_remaining, "bacteria_id": bacteria_id, "bacteria_slot": bacteria_slot})
	return data

func restore(data: Dictionary) -> void:
	activity = _finite_value(data.get("activity", 0.0), 1.0)
	bacteria_remaining = _finite_value(data.get("bacteria_remaining", 0.0), config.bacteria_lifetime)
	bacteria_id = maxi(0, int(data.get("bacteria_id", 0))) if data.get("bacteria_id", 0) is int else 0
	bacteria_slot = maxi(0, int(data.get("bacteria_slot", 0))) if data.get("bacteria_slot", 0) is int else 0
	if not data.has("activity"): _schedule_bacterium()
	var balance: Variant = data.get("samples", 0.0)
	samples = clampf(float(balance), 0.0, config.max_samples) if (balance is float or balance is int) and is_finite(float(balance)) else 0.0
	owned.clear()
	var values: Variant = data.get("owned", {})
	if not values is Dictionary: return
	for entry in config.upgrades:
		var value: Variant = values.get(String(entry.id), 0)
		owned[String(entry.id)] = clampi(int(value), 0, config.max_owned) if value is int else 0

static func _finite_value(value: Variant, maximum: float) -> float:
	return clampf(float(value), 0.0, maximum) if (value is float or value is int) and is_finite(float(value)) else 0.0

static func format_number(value: float) -> String:
	if not is_finite(value): return "MAX"
	var suffixes := ["", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No"]
	var index := 0
	var number := maxf(0.0, value)
	while number >= 999.95 and index < suffixes.size() - 1:
		number /= 1000.0
		index += 1
	if index == 0:
		return ("%.1f" % number).trim_suffix(".0") if absf(number - roundf(number)) > 0.00001 else str(int(roundf(number)))
	var result := "%.1f" % number
	if result.ends_with(".0"): result = result.trim_suffix(".0")
	return result + suffixes[index]
