extends WorldItemPickup

const VARIANTS := preload("res://assets/models/items/battery_set/variants.tres")

static func prepare_state(state: Dictionary) -> Dictionary:
	var result := state.duplicate(true)
	var choices := VARIANTS.get_item_list()
	var variant := int(result.get("visual_variant",-1))
	if not choices.has(variant): result["visual_variant"] = choices[randi_range(0,choices.size()-1)]
	return result

func _ready() -> void:
	# Network spawning chooses on the host before distributing spawn data.
	# Direct scene instances and old saves use the same selection rule.
	if multiplayer.is_server(): item_state = prepare_state(item_state)
	super._ready()
	$Model.variant_id = int(item_state.get("visual_variant",0))
