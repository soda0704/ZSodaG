class_name FlashlightPickup
extends WorldItemPickup


func _init() -> void:
	item_type = &"flashlight"
	display_name = "фонарик"
	item_state = {"battery_charge": 1.0}


func setup_spawn(data: Dictionary) -> void:
	var normalized_data := data.duplicate(true)
	if not normalized_data.has("item_state"):
		normalized_data["item_state"] = {
			"battery_charge": clampf(
				float(normalized_data.get("battery_charge", 1.0)),
				0.0,
				1.0
			),
		}
	super.setup_spawn(normalized_data)
