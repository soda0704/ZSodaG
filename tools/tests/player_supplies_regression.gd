extends SceneTree
const SUPPLIES = preload("res://scripts/characters/components/player_supplies.gd")
var failures := 0

func check(ok: bool, label: String) -> void:
	print("PASS " if ok else "FAIL ", label)
	if not ok: failures += 1

func _initialize() -> void:
	var first = SUPPLIES.new()
	var second = SUPPLIES.new()
	first.crafting_parts[&"tank"] = 2
	first.spare_batteries.append(.5)
	check(second.crafting_parts.is_empty() and second.spare_batteries.is_empty(), "players never share mutable supplies")
	var snapshot := {"held_item": &"pistol", "revision": 7}
	first.write_snapshot(snapshot)
	check(snapshot.held_item == &"pistol" and snapshot.revision == 7, "supplies leave equipment and revision ownership untouched")
	first.crafting_parts[&"tank"] = 3
	first.spare_batteries[0] = .9
	check(snapshot.crafting_parts[&"tank"] == 2 and snapshot.spare_batteries[0] == .5, "published snapshots do not change when the owner mutates supplies")
	second.apply_snapshot(snapshot, {&"tank": true}, 20)
	snapshot.crafting_parts[&"tank"] = 99
	snapshot.spare_batteries[0] = .1
	check(second.crafting_parts[&"tank"] == 2 and second.spare_batteries[0] == .5, "restored state does not retain incoming collection aliases")
	second.apply_snapshot({"crafting_parts": {&"tank": 999, &"unknown": 10}, "tape_count": -2, "crowbar_uses": 99, "spare_batteries": [-1, 0, .25, 2, .75]}, {&"tank": true}, 2)
	check(second.crafting_parts == {&"tank": 100} and second.tape_count == 0 and second.crowbar_uses == 3, "supplies preserve the existing allowed-part and count limits")
	check(second.spare_batteries == [.25, 1.0], "battery restore keeps positive charges in order and respects capacity")
	second.apply_snapshot({}, {&"tank": true}, 20)
	check(second.crafting_parts.is_empty() and second.spare_batteries.is_empty() and second.tape_count == 0 and second.crowbar_uses == 0, "missing supplies reset to the previous snapshot defaults")
	var allowed := {&"tank": true}
	check(second.add_material(&"tank", 2, allowed) and second.add_material(&"tape", 3, allowed), "materials are added through the supplies owner")
	check(not second.consume_recipe({&"tank": 3, &"tape": 2}) and second.tape_count == 3 and second.crafting_parts[&"tank"] == 2, "failed recipe leaves every balance unchanged")
	check(second.consume_recipe({&"tank": 2, &"tape": 2}) and second.tape_count == 1 and second.crafting_parts[&"tank"] == 0, "successful recipe consumes exact quantities atomically")
	check(not second.try_take(&"tank", {}, allowed), "empty part stack cannot be spent twice")
	check(second.try_add(&"crowbar", {"uses": 2}, allowed, 20) and not second.try_add(&"crowbar", {}, allowed, 20), "duplicate crowbar pickup preserves the existing tool")
	check(second.use_crowbar() and second.use_crowbar() and not second.use_crowbar(), "crowbar wear stops at zero")
	second.spare_batteries.assign([.4, .9])
	check(is_equal_approx(second.exchange_best_battery(.5), .9) and second.spare_batteries == [.4, .5], "replacement takes the fullest battery and preserves the old charged cell")
	check(is_equal_approx(second.exchange_best_battery(.95), .95) and second.spare_batteries == [.4, .5], "inferior replacement changes neither current nor spare charges")
	print("PLAYER SUPPLIES FAILURES ", failures)
	quit(1 if failures else 0)
