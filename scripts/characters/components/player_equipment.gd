class_name PlayerEquipment
extends RefCounted
## One per-player owner for held-item and flashlight state, independent of visuals/RPC.
var held_item: StringName = &""
var has_flashlight := false
var handheld_drawn := false
var enabled := false
var malfunctioning := false
var charge := 0.0
var mounted := false
enum FlashlightResult { UNAVAILABLE, POCKETED, CHANGED }

func toggle_flashlight() -> FlashlightResult:
	if not has_flashlight: return FlashlightResult.UNAVAILABLE
	if mounted:
		enabled = not enabled and charge > 0.0 and not malfunctioning
	elif held_item in [&"m4a1", &"flamethrower"]:
		return FlashlightResult.POCKETED
	else:
		if held_item in [&"", &"flashlight"]:
			held_item = &"" if held_item == &"flashlight" else &"flashlight"
			handheld_drawn = false
		else:
			handheld_drawn = not handheld_drawn
		enabled = is_handheld_drawn() and charge > 0.0 and not malfunctioning
	return FlashlightResult.CHANGED

func is_handheld_drawn() -> bool:
	return has_flashlight and not mounted and held_item not in [&"m4a1", &"flamethrower"] and (held_item == &"flashlight" or handheld_drawn)

func is_offhand_drawn() -> bool:
	return is_handheld_drawn() and held_item not in [&"", &"flashlight"]
