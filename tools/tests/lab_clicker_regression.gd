extends SceneTree
var checks := 0
var failures := 0
func check(value: bool, label: String) -> void:
	checks += 1
	print("PASS " if value else "FAIL ", label)
	if not value: failures += 1
func _initialize() -> void:
	run.call_deferred()
func run() -> void:
	var baseline := preload("res://scenes/ui/clicker/balance.tres").duplicate() as LabClickerConfig
	baseline.activity_per_click = 0.0
	var model := LabClicker.new(baseline)
	check(model.samples == 0 and model.income(ClickerUpgrade.Effect.CLICK_POWER) == 1 and model.income(ClickerUpgrade.Effect.PASSIVE_INCOME) == 0, "fresh economy")
	check(not model.buy(&"pipette") and not model.buy(&"unknown"), "cannot buy absent or unaffordable upgrade")
	for i in 15: model.click()
	check(model.samples == 15 and model.buy(&"pipette"), "exact balance purchase")
	check(model.samples == 0 and model.count(&"pipette") == 1 and model.cost(&"pipette") == 18 and model.click() == 2, "price scales and power updates immediately")
	model.restore({"samples": 500.0, "owned": {"assistant": 4, "centrifuge": 1}})
	check(model.income(ClickerUpgrade.Effect.PASSIVE_INCOME) == 9, "effects stack")
	var saved := model.capture()
	for fps in [24, 60, 144]:
		model.restore(saved)
		for frame in fps * 10: model.advance(1.0 / fps)
		check(absf(model.samples - 590.0) < 0.00001, "delta income at %d FPS" % fps)
	var clone := LabClicker.new()
	clone.restore(model.capture())
	check(clone.capture() == model.capture() and clone.cost(&"assistant") == model.cost(&"assistant"), "roundtrip source data and prices")
	model.restore({"samples": NAN, "owned": {"assistant": -4, "pipette": 100000, "reactor": "invalid"}})
	check(model.samples == 0 and model.count(&"assistant") == 0 and model.count(&"pipette") == 999 and model.count(&"reactor") == 0, "malformed values sanitized")
	check(not model.buy(&"pipette"), "level cap")
	model.restore({"samples": 100.0})
	var purchased := 0
	for i in 200:
		if model.buy(&"pipette"): purchased += 1
	check(purchased == 4 and model.samples >= 0, "rapid buy cannot overdraw")
	check(LabClicker.format_number(950) == "950" and LabClicker.format_number(1200) == "1.2K" and LabClicker.format_number(14600) == "14.6K" and LabClicker.format_number(2300000) == "2.3M" and LabClicker.format_number(8100000000) == "8.1B", "large number formatting")
	var settings := preload("res://scenes/ui/clicker/balance.tres").duplicate() as LabClickerConfig
	settings.bacteria_interval_min = 2.0
	settings.bacteria_interval_max = 2.0
	settings.bacteria_lifetime = 1.0
	var rhythm := LabClicker.new(settings)
	for i in 7: check(rhythm.click() == 1.0, "below threshold click %d" % (i + 1))
	check(rhythm.click() == 1.5 and rhythm.click_multiplier() == 1.5, "crossing threshold activates x1.5 immediately")
	rhythm.advance(0.2)
	check(rhythm.click_multiplier() == 1.0 and rhythm.activity > 0.0, "inactivity drops below multiplier threshold")
	rhythm.advance(100.0)
	check(rhythm.activity == 0 and rhythm.bacteria_remaining == 0, "idle drains meter and closed application cannot spawn bonus")
	for fps in [24, 60, 144]:
		rhythm.activity = 1.0
		for frame in fps * 2: rhythm.advance(1.0 / fps)
		check(absf(rhythm.activity - 0.64) < 0.00001, "activity decay independent of %d FPS" % fps)
	rhythm.owned = {"pipette": 3, "assistant": 5, "centrifuge": 1}
	check(rhythm.bacteria_reward() == 82, "bonus depends on both real click and passive upgrades")
	rhythm.activity = 1.0
	check(rhythm.bacteria_reward() == 82, "temporary multiplier cannot inflate rare reward")
	rhythm.advance(2.0, true)
	var ticket := rhythm.bacteria_id
	check(ticket > 0 and rhythm.bacteria_remaining == 1.0, "active application spawns timed bacterium")
	var copy := LabClicker.new(settings)
	copy.restore(rhythm.capture_runtime())
	check(copy.activity == rhythm.activity and copy.bacteria_id == ticket and copy.bacteria_slot == rhythm.bacteria_slot and copy.bacteria_remaining == 1, "spectators receive activity and same live encounter")
	var before := rhythm.samples
	check(rhythm.collect_bacterium(ticket) == 82 and rhythm.samples == before + 82, "bonus credited once")
	check(rhythm.collect_bacterium(ticket) == 0 and rhythm.samples == before + 82, "rapid repeated capture cannot double pay")
	rhythm.advance(2.0, true)
	check(rhythm.bacteria_id != ticket and rhythm.collect_bacterium(ticket) == 0, "old encounter ticket cannot claim a new spawn")
	rhythm.advance(1.0, false)
	check(rhythm.bacteria_remaining == 0 and rhythm.collect_bacterium(rhythm.bacteria_id) == 0, "expired bacterium cannot be collected, even after closing UI")
	var persistent := rhythm.capture()
	check(not persistent.has("activity") and not persistent.has("bacteria_id"), "only economy persists, no repeatable saved encounter")
	copy.restore(persistent)
	check(copy.samples == rhythm.samples and copy.activity == 0 and copy.bacteria_remaining == 0, "reload preserves money without reviving bonus or boost")
	before = rhythm.samples
	rhythm.activity = 1
	rhythm.advance(10.0, false, false)
	check(rhythm.samples == before and rhythm.activity == 0, "power outage drains rhythm without production")
	var wait := rhythm._bacteria_wait
	rhythm.advance(60.0, false)
	check(rhythm._bacteria_wait == wait, "rare-spawn countdown pauses without an operator in app")
	check(LabClicker.format_number(1.5) == "1.5", "fractional boosted gain remains readable")
	var expanded := LabClicker.new()
	var ids: Dictionary = {}
	var previous_cost := 0.0
	var data_ok := expanded.config.upgrades.size() == 25
	for entry in expanded.config.upgrades:
		data_ok = data_ok and not ids.has(entry.id) and entry.icon != null and entry.base_cost > previous_cost
		ids[entry.id] = true
		previous_cost = entry.base_cost
		expanded.samples = expanded.cost(entry.id)
		data_ok = data_ok and expanded.buy(entry.id) and expanded.samples == 0 and expanded.count(entry.id) == 1
	check(data_ok, "25 unique increasing-price upgrades with icons and valid purchases")
	check(expanded.cost(&"microinjector") == 23000 and expanded.upgrade(&"microinjector").effect_value == 90, "new active tier increases click power and scales cost")
	var reload := LabClicker.new()
	reload.restore(expanded.capture())
	check(reload.count(&"genesis") == 1 and reload.income(ClickerUpgrade.Effect.PASSIVE_INCOME) == expanded.income(ClickerUpgrade.Effect.PASSIVE_INCOME) and reload.cost(&"genesis") == expanded.cost(&"genesis"), "late-game upgrades survive save roundtrip")
	print("CLICKER ECONOMY: %d checks, %d failures" % [checks, failures])
	quit(failures)
