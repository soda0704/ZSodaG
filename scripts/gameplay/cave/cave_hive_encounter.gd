extends Node3D
## Shares the base snapshot/save path; discovery and damage are host authoritative.
@export var state_path := NodePath("../../BaseGameplayController")
@export_range(1.0, 10000.0) var starting_health := 120.0
@export var hive_paths: Array[NodePath] = [NodePath("Hive0"), NodePath("Hive1"), NodePath("Hive2")]
@onready var discovery_zone: Area3D = $DiscoveryZone
var state: BaseGameplayController
var hives: Array[StaticBody3D] = []

func _ready() -> void:
	add_to_group("cave_hive_encounters")
	state = get_node_or_null(state_path) as BaseGameplayController
	if state == null:
		push_error("CaveHiveEncounter: assign the base state in Inspector")
		return
	if hive_paths.size() != 3:
		push_error("CaveHiveEncounter: assign exactly three hive placeholders in Inspector")
		return
	for path in hive_paths:
		var hive := get_node_or_null(path) as StaticBody3D
		if hive == null:
			push_error("CaveHiveEncounter: assign three hive placeholders in Inspector")
			return
		hives.append(hive)
	state.snapshot_changed.connect(_on_snapshot)
	discovery_zone.body_entered.connect(_on_discovery_entered)
	_on_snapshot({})

func get_health(index: int) -> float:
	var health: Array = state.containment.get("cave_hive_health", [])
	if index >= health.size() or not is_finite(float(health[index])): return starting_health
	return clampf(float(health[index]), 0.0, starting_health)

func _on_discovery_entered(body: Node3D) -> void:
	if not multiplayer.is_server() or state.day_index < state.CAVE_DAY_INDEX or not body is GamePlayer: return
	if body.survival.dead or body.is_sleeping_in_bunk() or not state._can_mutate_for_peer(body.owner_peer_id): return
	if state.containment.get("cave_hives_found", false): return
	var data := state.containment.duplicate(true)
	_discover(data)
	_commit(data)

func _discover(data: Dictionary) -> void:
	if not data.get("cave_hives_found", false):
		data.cave_hives_found = true
		data.cave_visited = true
		# An exit recorded by the earlier visit-only prototype is not a new completion.
		data.cave_exited = false
	if not data.has("cave_hive_health"):
		data.cave_hive_health = [starting_health, starting_health, starting_health]

func damage_hive(index: int, amount: float) -> void:
	if not multiplayer.is_server() or state.day_index < state.CAVE_DAY_INDEX: return
	if index < 0 or index >= hives.size() or not is_finite(amount) or amount <= 0.0 or get_health(index) <= 0.0: return
	var data := state.containment.duplicate(true)
	_discover(data)
	var health: Array = []
	for hive_index in hives.size(): health.append(get_health(hive_index))
	health[index] = maxf(0.0, float(health[index]) - amount)
	data.cave_hive_health = health
	data.cave_exited = false
	_commit(data)

func _commit(data: Dictionary) -> void:
	var snapshot := state.get_snapshot()
	snapshot.containment = data
	state._broadcast_snapshot(snapshot)

func _on_snapshot(_snapshot: Dictionary) -> void:
	for index in hives.size():
		# The chamber exists before its story day; only discovery/damage are gated.
		hives[index].apply_snapshot(state.day_index >= state.CAVE_DAY_INDEX, get_health(index))
	_check_current_players.call_deferred()

func _check_current_players() -> void:
	if not is_inside_tree() or is_queued_for_deletion() or not multiplayer.is_server(): return
	for body in discovery_zone.get_overlapping_bodies(): _on_discovery_entered(body)
