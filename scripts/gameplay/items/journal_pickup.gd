extends WorldItemPickup
## Two editor-placed personal journals. The existing shared snapshot owns claims.
@export var claim_key := "journal_1"
var _state: BaseGameplayController

func _ready() -> void:
	super._ready()
	_bind_state.call_deferred()

func _bind_state() -> void:
	_state = get_tree().get_first_node_in_group("base_gameplay_controller") as BaseGameplayController
	if _state == null: return
	_state.snapshot_changed.connect(_sync_claim)
	_sync_claim(_state.get_snapshot())

func _sync_claim(snapshot: Dictionary) -> void:
	_collected = (snapshot.get("maintenance", {}).get("journal_claims", {}) as Dictionary).has(claim_key)
	visible = not _collected
	collision_layer = 0 if _collected else 4
	$CollisionShape3D.set_deferred("disabled", _collected)

func get_interaction_hint_for(actor: Node) -> String:
	return "Журнал уже есть" if actor is GamePlayer and actor.has_journal else "Взять журнал"

func network_interact(peer_id: int, interactor: Node) -> void:
	if not multiplayer.is_server() or _collected or _state == null or not pickup_enabled: return
	if not interactor is GamePlayer or interactor.owner_peer_id != peer_id or not _state._can_mutate_for_peer(peer_id): return
	if interactor.global_position.distance_to(get_interaction_position()) > interaction_distance: return
	if interactor.has_journal or interactor.survival.dead: return
	if not interactor.pickup_world_item_authoritative(&"journal", {}): return
	var snapshot := _state.get_snapshot()
	var claims: Dictionary = snapshot.maintenance.get("journal_claims", {}).duplicate()
	claims[claim_key] = interactor.journal_owner_key()
	snapshot.maintenance["journal_claims"] = claims
	_state._broadcast_snapshot(snapshot)
	interactor.player_audio.play_cue.rpc(&"pickup")
