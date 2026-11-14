class_name PlayerSupplies
extends RefCounted
## Per-player pocket supplies. No scene nodes, rendering or multiplayer authority.
var crafting_parts: Dictionary = {}
var tape_count := 0
var crowbar_uses := 0
var spare_batteries: Array[float] = []

func add_material(type: StringName, amount: int, allowed_parts: Dictionary) -> bool:
	if amount <= 0: return false
	if type == &"tape": tape_count += amount
	elif allowed_parts.has(type): crafting_parts[type] = int(crafting_parts.get(type, 0)) + amount
	else: return false
	return true

func try_add(type: StringName, data: Dictionary, allowed_parts: Dictionary, battery_limit: int) -> bool:
	if allowed_parts.has(type):
		return add_material(type, 1, allowed_parts)
	elif type == &"battery":
		var charge := clampf(float(data.get("charge_amount", 1.0)), 0.0, 1.0)
		if spare_batteries.size() >= battery_limit or charge <= 0.0: return false
		spare_batteries.append(charge)
	elif type == &"tape":
		return add_material(type, 1, allowed_parts)
	elif type == &"crowbar":
		if crowbar_uses > 0: return false
		crowbar_uses = clampi(int(data.get("uses", 3)), 1, 3)
	else:
		return false
	return true

func try_take(type: StringName, data: Dictionary, allowed_parts: Dictionary) -> bool:
	if allowed_parts.has(type):
		if int(crafting_parts.get(type, 0)) <= 0: return false
		crafting_parts[type] = int(crafting_parts[type]) - 1
	elif type == &"battery":
		var charge := float(data.get("charge_amount", 0.0))
		if not spare_batteries.has(charge): return false
		spare_batteries.erase(charge)
	elif type == &"tape":
		if tape_count <= 0: return false
		tape_count -= 1
	elif type == &"crowbar":
		if crowbar_uses <= 0: return false
		crowbar_uses = 0
	else:
		return false
	return true

func consume_recipe(requirements: Dictionary) -> bool:
	# Validate the whole recipe before changing any balance.
	for type in requirements:
		var count := tape_count if type == &"tape" else int(crafting_parts.get(type, 0))
		if int(requirements[type]) < 0 or count < int(requirements[type]): return false
	for type in requirements:
		if type == &"tape": tape_count -= int(requirements[type])
		else: crafting_parts[type] = int(crafting_parts.get(type, 0)) - int(requirements[type])
	return true

func exchange_best_battery(current_charge: float) -> float:
	if spare_batteries.is_empty(): return current_charge
	var best: float = spare_batteries.max()
	if best <= current_charge: return current_charge
	spare_batteries.erase(best)
	if current_charge > 0.0: spare_batteries.append(current_charge)
	return best

func clear() -> void:
	crafting_parts.clear()
	tape_count = 0
	crowbar_uses = 0
	spare_batteries.clear()

func take_last_battery() -> float:
	return spare_batteries.pop_back() if not spare_batteries.is_empty() else 0.0

func use_crowbar() -> bool:
	if crowbar_uses <= 0: return false
	crowbar_uses -= 1
	return true

func write_snapshot(snapshot: Dictionary) -> void:
	# Append to the player's existing payload without allocating a second dictionary.
	snapshot["crafting_parts"] = crafting_parts.duplicate()
	snapshot["tape_count"] = tape_count
	snapshot["crowbar_uses"] = crowbar_uses
	snapshot["spare_batteries"] = spare_batteries.duplicate()

func apply_snapshot(data: Dictionary, allowed_parts: Dictionary, battery_limit: int) -> void:
	crafting_parts.clear()
	for type in allowed_parts:
		var count := clampi(int(data.get("crafting_parts", {}).get(type, 0)), 0, 100)
		if count > 0: crafting_parts[type] = count
	tape_count = maxi(0, int(data.get("tape_count", 0)))
	crowbar_uses = clampi(int(data.get("crowbar_uses", 0)), 0, 3)
	spare_batteries.clear()
	for charge: Variant in data.get("spare_batteries", []):
		if spare_batteries.size() >= battery_limit: break
		if float(charge) > 0.0:
			spare_batteries.append(clampf(float(charge), 0.0, 1.0))
