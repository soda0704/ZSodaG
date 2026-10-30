extends Area3D
## Transient offers. Inventory remains with the giver until host acceptance.
const POCKET := 2
const HELD := 1
const TITLES := {&"battery":"Батарейка", &"tape":"Скотч", &"crowbar":"Монтировка", &"pistol_ammo":"Патроны", &"rifle_magazine":"Магазин M4A1", &"flashlight":"Фонарик", &"fuse":"Предохранитель", &"seed_packet":"Семена", &"fuel_can":"Канистра", &"pistol":"Пистолет", &"m4a1":"M4A1", &"kitchen_knife":"Нож", &"flamethrower":"Огнемёт"}
@export_range(0.5, 3.0) var reach := 2.0
@onready var actor: GamePlayer = get_parent()
var mode := 0
var item: StringName = &""
var token := 0
var _started := 0
var _lease := 0
var _heartbeat := 0.0

func _ready() -> void:
	collision_layer = 0
	if not multiplayer.is_server(): _request_state.call_deferred()

func is_offering() -> bool:
	return mode != 0

func pocket_pose() -> bool:
	return mode == POCKET

func usable(player: GamePlayer, journal_allowed := false) -> bool:
	return is_instance_valid(player) and not player.is_queued_for_deletion() and not player._handoff_transaction and not player.survival.dead and not player.is_bunk_busy() and not player.is_climbing() and not player.is_driving() and not player.is_carrying_corpse() and not player.corpse_action_busy and not player.is_debug_free_camera_active() and not player._battery_action_busy and player.weapon.reload_left <= 0 and not player.get_node("ItemDrag").dragging and not player.get_node("ItemDrag").is_heavy_carrying() and (journal_allowed or player._journal_phase == 0)

func available(type: StringName, from_pocket: bool) -> bool:
	if not from_pocket: return type != &"" and actor._held_item_type == type
	if actor.CRAFT_RECIPE.pickup_scenes.has(type): return int(actor.crafting_parts.get(type, 0)) > 0
	match type:
		&"battery": return not actor._spare_batteries.is_empty()
		&"tape": return actor.tape_count > 0
		&"crowbar": return actor.crowbar_uses > 0
		&"pistol_ammo": return actor.weapon.pistol_ammo > 0
		&"rifle_magazine": return not actor.weapon.rifle_magazines.is_empty()
		&"flashlight": return actor._has_flashlight and not actor.weapon_light_mounted and actor._held_item_type != &"flashlight"
	return false

func request_offer(type: StringName, from_pocket: bool) -> void:
	if not actor.is_local_player(): return
	if multiplayer.is_server(): start_authoritative(type, from_pocket)
	else: _submit_offer.rpc_id(1, type, from_pocket)

@rpc("any_peer", "call_remote", "reliable", 2)
func _submit_offer(type: StringName, from_pocket: bool) -> void:
	if multiplayer.is_server() and multiplayer.get_remote_sender_id() == actor.owner_peer_id:
		start_authoritative(type, from_pocket)

func start_authoritative(type: StringName, from_pocket: bool) -> bool:
	if not multiplayer.is_server() or not usable(actor, from_pocket) or not available(type, from_pocket): return false
	if from_pocket and actor._journal_phase == 1: return false
	mode = POCKET if from_pocket else HELD
	item = type
	token += 1
	_started = Time.get_ticks_msec()
	_lease = _started + 1000
	actor.weapon.flame.stop_authoritative()
	_publish()
	return true

func request_cancel() -> void:
	if not actor.is_local_player(): return
	if multiplayer.is_server(): cancel_authoritative()
	else: _cancel.rpc_id(1)

@rpc("any_peer", "call_remote", "reliable", 2)
func _cancel() -> void:
	if multiplayer.is_server() and multiplayer.get_remote_sender_id() == actor.owner_peer_id: cancel_authoritative()

func cancel_authoritative() -> void:
	if not multiplayer.is_server() or mode == 0: return
	mode = 0
	item = &""
	token += 1
	_publish()

func _publish() -> void:
	_receive_offer.rpc(mode, item, token)

@rpc("authority", "call_local", "reliable", 2)
func _receive_offer(next_mode: int, next_item: StringName, next_token: int) -> void:
	if next_token < token: return
	mode = next_mode
	item = next_item
	token = next_token
	collision_layer = 4 if mode != 0 and actor._journal_phase == 0 else 0
	actor._refresh_equipment_visuals()

func _request_state() -> void:
	_request_offer_state.rpc_id(1)

@rpc("any_peer", "call_remote", "reliable", 2)
func _request_offer_state() -> void:
	if multiplayer.is_server(): _receive_offer.rpc_id(multiplayer.get_remote_sender_id(), mode, item, token)

@rpc("any_peer", "call_remote", "reliable", 2)
func _hold() -> void:
	if multiplayer.is_server() and multiplayer.get_remote_sender_id() == actor.owner_peer_id and mode == HELD:
		_lease = Time.get_ticks_msec() + 1000

func _physics_process(delta: float) -> void:
	if actor.is_local_player() and mode != 0:
		var menu := get_node("/root/GameMenu")
		var book_closing := mode == POCKET and actor._journal_phase == 3
		if menu.is_menu_open() or (Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and not book_closing) or (mode == HELD and not Input.is_action_pressed("offer_item")):
			request_cancel()
		elif mode == HELD:
			_heartbeat += delta
			if _heartbeat > 0.2:
				_heartbeat = 0
				if multiplayer.is_server(): _lease = Time.get_ticks_msec() + 1000
				else: _hold.rpc_id(1)
	if multiplayer.is_server() and mode != 0:
		var pending := mode == POCKET and actor._journal_phase == 3 and Time.get_ticks_msec() - _started < 2000
		if not usable(actor, pending) or not available(item, mode == POCKET) or (mode == HELD and Time.get_ticks_msec() > _lease): cancel_authoritative()
	collision_layer = 4 if mode != 0 and actor._journal_phase == 0 else 0

func title() -> String:
	return str(actor.CRAFT_RECIPE.titles.get(item, TITLES.get(item, String(item))))

func payload() -> Dictionary:
	if mode == HELD: return actor.get_held_item_state().duplicate(true)
	match item:
		&"battery": return {"charge_amount": actor._spare_batteries.max()}
		&"crowbar": return {"uses": actor.crowbar_uses}
		&"pistol_ammo": return {"amount": mini(12, actor.weapon.pistol_ammo)}
		&"rifle_magazine": return {"rounds": actor.weapon.rifle_magazines[0]}
		&"flashlight": return {"battery_charge": actor._battery_charge, "malfunctioning": actor._flashlight_malfunctioning}
	return {}

func capacity_problem(receiver: GamePlayer) -> String:
	if actor.CRAFT_RECIPE.pickup_scenes.has(item) and int(receiver.crafting_parts.get(item, 0)) >= 100: return "Нет места для детали"
	if mode == HELD and item != &"flashlight" and receiver._held_item_type not in [&"", &"flashlight"]: return "Сначала освободите руки"
	if item == &"flashlight" and receiver._has_flashlight: return "Фонарик уже есть"
	if mode == HELD and actor.weapon_light_mounted and receiver._has_flashlight: return "Сначала уберите свой фонарик"
	if item == &"battery" and receiver._spare_batteries.size() >= receiver.MAX_SPARE_BATTERIES: return "Нет места для батарейки"
	if item == &"crowbar" and receiver.crowbar_uses > 0: return "Монтировка уже есть"
	if item == &"pistol_ammo" and receiver.weapon.pistol_ammo + mini(12, actor.weapon.pistol_ammo) > 240: return "Нет места для патронов"
	if item == &"rifle_magazine" and receiver.weapon.rifle_magazines.size() >= 10: return "Нет места для магазина"
	return ""

func get_interaction_hint_for(receiver: GamePlayer) -> String:
	if mode == 0 or receiver == actor: return ""
	if not hand_reachable(receiver): return "Подойдите к протянутой руке"
	var problem := capacity_problem(receiver)
	return problem if not problem.is_empty() else str(get_node("/root/SteamInput").get_action_hint(&"interact")) + " Забрать: " + title()

func hand_reachable(receiver: GamePlayer) -> bool:
	if receiver.camera.global_position.distance_to(global_position) > reach: return false
	var toward := receiver.global_position - actor.global_position
	toward.y = 0
	if (-actor.global_basis.z).dot(toward.normalized()) < 0.1: return false
	# An extended target must not grant access through a wall at the giver's side.
	var query := PhysicsRayQueryParameters3D.create(actor.head.global_position, global_position, 5, [actor.get_rid(), get_rid()])
	query.hit_from_inside = true
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()

func begin_item_handoff() -> bool:
	var receiver := get_tree().get_first_node_in_group("local_player") as GamePlayer
	if receiver == null or receiver == actor: return false
	if multiplayer.is_server(): accept_authoritative(receiver, token)
	else: _accept.rpc_id(1, token, receiver.rotation.y, receiver.head.rotation.x)
	return true

@rpc("any_peer", "call_remote", "reliable", 2)
func _accept(offered_token: int, yaw: float, pitch: float) -> void:
	if not multiplayer.is_server() or not is_finite(yaw) or not is_finite(pitch) or absf(pitch) > deg_to_rad(85.1): return
	for receiver in get_tree().get_nodes_in_group("network_players"):
		if receiver.owner_peer_id == multiplayer.get_remote_sender_id():
			# Keep E and its aim in one reliable request. The latest unreliable
			# movement packet may still be in flight when a client turns to a hand.
			receiver._server_yaw = wrapf(yaw, -PI, PI)
			receiver._server_pitch = clampf(pitch, deg_to_rad(-85), deg_to_rad(85))
			receiver.rotation.y = receiver._server_yaw
			receiver.head.rotation.x = receiver._server_pitch
			accept_authoritative(receiver, offered_token)
			return

func network_interact(_peer_id: int, _receiver: GamePlayer) -> void:
	# Generic movement E packets have no offer token and may be delayed.
	# Only begin_item_handoff / _accept may authorize this interaction.
	pass

func accept_authoritative(receiver: GamePlayer, offered_token: int) -> bool:
	if not multiplayer.is_server() or mode == 0 or offered_token != token or receiver == actor: return false
	if mode == HELD and Time.get_ticks_msec() > _lease: return false
	if not usable(actor) or not usable(receiver) or receiver.handoff.is_offering() or not available(item, mode == POCKET): return false
	if not hand_reachable(receiver) or receiver.get_interaction_target() != self: return false
	if not capacity_problem(receiver).is_empty(): return false
	var type := item
	var from_hand := mode == HELD
	var state := payload()
	# No inventory signals, snapshots or checkpoints may expose two owners.
	actor._handoff_transaction = true
	receiver._handoff_transaction = true
	cancel_authoritative()
	# Pickup rejects before mutation; publication is suppressed until both sides finish.
	if not receiver.pickup_world_item_authoritative(type, state):
		actor._handoff_transaction = false
		receiver._handoff_transaction = false
		return false
	if from_hand:
		actor.release_held_item_authoritative()
	elif actor.CRAFT_RECIPE.pickup_scenes.has(type): actor.crafting_parts[type] = int(actor.crafting_parts[type]) - 1
	elif type == &"battery": actor._spare_batteries.erase(float(state.charge_amount))
	elif type == &"tape": actor.tape_count -= 1
	elif type == &"crowbar": actor.crowbar_uses = 0
	elif type == &"pistol_ammo": actor.weapon.pistol_ammo -= int(state.amount)
	elif type == &"rifle_magazine": actor.weapon.rifle_magazines.remove_at(0)
	elif type == &"flashlight":
		actor._has_flashlight = false
		actor._handheld_flashlight_drawn = false
		actor._flashlight_enabled = false
		actor._battery_charge = 0
		actor._flashlight_malfunctioning = false
	# Both mutations are synchronous. Keep the reentry guard during signals.
	actor._publish_inventory(true)
	receiver._publish_inventory(true)
	actor._handoff_transaction = false
	receiver._handoff_transaction = false
	return true
