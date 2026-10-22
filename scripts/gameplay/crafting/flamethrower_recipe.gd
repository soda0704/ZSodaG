extends Resource
@export var requirements: Dictionary = {}
@export var titles: Dictionary = {}
@export var pickup_scenes: Dictionary = {}
@export_range(1, 2) var craft_limit := 2

func available(player: Node) -> Dictionary:
	var counts: Dictionary = player.crafting_parts.duplicate()
	counts[&"tape"] = player.tape_count
	return counts

func can_craft(player: Node) -> bool:
	var counts := available(player)
	for type in requirements:
		if int(counts.get(type, 0)) < int(requirements[type]): return false
	return true
