extends StaticBody3D
const RECIPE = preload("res://assets/config/flamethrower_recipe.tres")
@export var state_path := NodePath("../BaseGameplayController")
@export_range(0.5, 5.0) var interaction_distance := 3.0
var state: BaseGameplayController

func _ready() -> void:
	add_to_group("flamethrower_workbenches")
	state = get_node(state_path)

func crafted_count() -> int:
	return int(state.maintenance.get("flamethrower_crafting", {}).get("crafted",0))

func get_interaction_prompt() -> String:
	if not state.containment.get("cave_hives_found",false) or crafted_count() >= RECIPE.craft_limit: return ""
	var player := get_tree().get_first_node_in_group("local_player")
	return "Собрать огнемёт" if player != null and RECIPE.can_craft(player) else "Осмотреть схему сборки"

func network_interact(peer_id: int, actor: Node) -> void:
	if not multiplayer.is_server() or not actor is GamePlayer: return
	if actor.owner_peer_id != peer_id or not state._can_mutate_for_peer(peer_id): return
	if actor.survival.dead or actor.is_sleeping_in_bunk() or actor.is_driving() or actor.is_carrying_corpse(): return
	if actor.global_position.distance_to(global_position) > interaction_distance or actor.get_interaction_target() != self: return
	if not state.containment.get("cave_hives_found",false) or crafted_count() >= RECIPE.craft_limit: return
	if not RECIPE.can_craft(actor):
		_show_recipe.rpc_id(peer_id)
		return
	craft_authoritative(actor)

func craft_authoritative(actor: GamePlayer) -> bool:
	if not multiplayer.is_server() or actor.survival.dead or actor.is_sleeping_in_bunk() or actor.is_driving() or actor.is_carrying_corpse(): return false
	if not state._can_mutate_for_peer(actor.owner_peer_id) or not state.containment.get("cave_hives_found",false): return false
	if actor.global_position.distance_to(global_position) > interaction_distance or actor.get_interaction_target() != self: return false
	if crafted_count() >= RECIPE.craft_limit or not RECIPE.can_craft(actor): return false
	# No await between validation, consumption and award: concurrent E requests serialize on the host.
	for type in RECIPE.requirements:
		if type == &"tape": actor.tape_count -= int(RECIPE.requirements[type])
		else: actor.crafting_parts[type] = int(actor.crafting_parts.get(type,0)) - int(RECIPE.requirements[type])
	var snapshot := state.get_snapshot()
	snapshot.maintenance["flamethrower_crafting"] = {"crafted": crafted_count()+1}
	state._broadcast_snapshot(snapshot,false)
	actor.pickup_world_item_authoritative(&"flamethrower",{})
	state.save_progress_authoritative()
	return true

@rpc("authority","call_local","reliable")
func _show_recipe() -> void:
	var journal := get_node_or_null("/root/QuestJournal")
	if journal != null:
		journal.open_journal()
		journal._select_item(&"flame_recipe")
