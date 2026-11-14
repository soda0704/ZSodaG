extends SceneTree

const EQUIPMENT = preload("res://scripts/characters/components/player_equipment.gd")
var failures := 0

func check(ok: bool, label: String) -> void:
	print("PASS " if ok else "FAIL ", label)
	if not ok: failures += 1

func _initialize() -> void:
	var first = EQUIPMENT.new()
	var second = EQUIPMENT.new()
	check(first.toggle_flashlight() == EQUIPMENT.FlashlightResult.UNAVAILABLE, "missing lamp cannot be toggled")
	first.has_flashlight = true
	first.charge = .7
	check(not second.has_flashlight and second.charge == 0.0, "players own independent equipment")
	first.toggle_flashlight()
	check(first.enabled and first.is_handheld_drawn() and not first.is_offhand_drawn(), "empty hands draw the lamp")
	first.toggle_flashlight()
	check(not first.enabled and first.held_item == &"", "second toggle pockets the lamp")
	first.held_item = &"pistol"
	first.toggle_flashlight()
	check(first.enabled and first.is_offhand_drawn() and first.held_item == &"pistol", "offhand lamp preserves the pistol")
	first.toggle_flashlight()
	check(not first.enabled and not first.is_offhand_drawn(), "offhand lamp can be pocketed")
	for weapon in [&"m4a1", &"flamethrower"]:
		first.held_item = weapon
		check(first.toggle_flashlight() == EQUIPMENT.FlashlightResult.POCKETED and not first.enabled, "two handed weapon blocks handheld lamp: " + weapon)
	first.mounted = true
	first.toggle_flashlight()
	check(first.enabled and not first.is_handheld_drawn(), "mounted lamp works with two handed weapon")
	first.toggle_flashlight()
	check(not first.enabled, "mounted lamp toggles off")
	first.mounted = false
	first.held_item = &""
	first.charge = 0.0
	first.toggle_flashlight()
	check(first.is_handheld_drawn() and not first.enabled, "empty battery allows drawing without light")
	first.toggle_flashlight()
	first.charge = .7
	first.malfunctioning = true
	first.toggle_flashlight()
	check(first.is_handheld_drawn() and not first.enabled and first.malfunctioning and first.charge == .7, "toggle does not repair faults or recharge batteries")
	print("PLAYER EQUIPMENT FAILURES ", failures)
	quit(1 if failures else 0)
