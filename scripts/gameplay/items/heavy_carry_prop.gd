class_name HeavyCarryProp
extends WorldItemPickup
## Scene-authored, persistent furniture. Never enters an inventory.
@export var checkpoint_key: StringName
@export_range(0.1, 2.0) var solo_speed := 0.6
@export_range(0.2, 3.0) var paired_speed := 1.25
@export_range(0.5, 3.0) var grip_reach := 2.4
@export var spring_strength := 14.0
@export var spring_damping := 5.0
@export var lift_height := 0.4
## Physical pitch/roll correction while held. Zero keeps a prop's free rotation.
@export var upright_strength := 0.0
@export var upright_damping := 8.0
var grips: Dictionary = {}
var _owners: Array[int] = []
var _slots: Dictionary = {}
@onready var carry_audio: Node3D = get_node_or_null("CarryAudio")

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if not multiplayer.is_server() or carry_audio == null: return
	var count := state.get_contact_count()
	var supported := false
	var speed := 0.0
	var impact := 0.0
	for index in count:
		var normal := state.get_contact_local_normal(index)
		if normal.y > .5: supported = true
		var relative := state.linear_velocity - state.get_contact_collider_velocity_at_position(index)
		speed = maxf(speed, Vector2(relative.x, relative.z).length() + state.angular_velocity.length() * carry_audio.rotation_radius)
		impact = maxf(impact, state.get_contact_impulse(index).length() / mass)
	carry_audio.observe_contacts(count > 0, supported, speed, impact, state.linear_velocity.y, state.step)

func hand_targets(peer_id: int) -> Dictionary:
	if not _slots.has(peer_id): return {}
	var grip := get_node("Grips").get_child(int(_slots[peer_id]))
	return {"Left": grip.get_node("LeftHand").global_transform, "Right": grip.get_node("RightHand").global_transform}

func _ready() -> void:
	pickup_enabled = false
	draggable = false
	super._ready()
	add_to_group("heavy_carry_props")
	if not multiplayer.is_server(): _request_grips.call_deferred()

func can_carry(actor: GamePlayer) -> bool:
	if is_instance_valid(actor) and actor.is_on_floor():
		for index in actor.get_slide_collision_count():
			var contact := actor.get_slide_collision(index)
			if contact.get_collider() == self and contact.get_normal().y > .5: return false
	return is_instance_valid(actor) and not actor.is_queued_for_deletion() and not actor.survival.dead and not actor.is_sleeping_in_bunk() and not actor.is_driving() and not actor.is_carrying_corpse() and not actor.corpse_action_busy and not actor._battery_action_busy and actor.weapon.reload_left <= 0 and actor._journal_phase == 0 and not actor.handoff.is_offering() and not actor._handoff_transaction

func _capture_elevator_cargo() -> void:
	# A long beam must fit inside the cabin, not merely overlap its center.
	_cargo_cooldown = .4
	_cargo_candidate = null
	for cabin in get_tree().get_nodes_in_group("elevator_cabins"):
		var fits := true
		for collision in find_children("*", "CollisionShape3D", true, false):
			if collision.disabled or collision.shape == null: continue
			var bounds: AABB = collision.shape.get_debug_mesh().get_aabb()
			for index in 8:
				if not cabin.get_parent().contains_cabin_point(collision.global_transform * bounds.get_endpoint(index), -.05): fits = false
		if fits:
			_cargo_candidate = cabin
			super._capture_elevator_cargo()
			return

func grip_point(index: int) -> Vector3:
	return get_node("Grips").get_child(index).global_position

func _nearest_grip(actor: GamePlayer) -> int:
	var nearest := -1
	var distance := grip_reach
	for index in get_node("Grips").get_child_count():
		var occupied := false
		for data: Dictionary in grips.values():
			if int(data.slot) == index: occupied = true
		if occupied: continue
		var next := actor.head.global_position.distance_to(grip_point(index))
		if next < distance:
			distance = next
			nearest = index
	return nearest

func _visible_grip(actor: GamePlayer, slot: int) -> bool:
	var query := PhysicsRayQueryParameters3D.create(actor.head.global_position, grip_point(slot), 1, [get_rid(), actor.get_rid()])
	query.hit_from_inside = true
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()

func acquire_grip(actor: GamePlayer) -> bool:
	if not multiplayer.is_server() or not can_carry(actor): return false
	var owner: int = actor.owner_peer_id
	var slot: int = int(grips[owner].slot) if grips.has(owner) else _nearest_grip(actor)
	if slot < 0 or actor.head.global_position.distance_to(grip_point(slot)) > grip_reach or not _visible_grip(actor, slot): return false
	if not grips.has(owner):
		if actor.get_interaction_target() != self or actor.get_node("ItemDrag").is_heavy_carrying(): return false
		grips[owner] = {"actor": actor, "slot": slot, "last_hold": Time.get_ticks_msec()}
		actor.weapon.flame.stop_authoritative()
		release_elevator_cargo()
		# A scene may retain an authored leaning placement until its first grip.
		# From this point the same physical body handles both drag and lift.
		freeze = false
		_publish_grips()
	else:
		grips[owner].last_hold = Time.get_ticks_msec()
	sleeping = false
	return true

func release_grip(peer_id: int) -> void:
	if not multiplayer.is_server() or not grips.has(peer_id): return
	grips.erase(peer_id)
	_publish_grips()
	sync_physics_state()

func _publish_grips() -> void:
	var owners: Array[int] = []
	var slots := {}
	for owner in grips: owners.append(int(owner))
	for owner in grips: slots[owner] = int(grips[owner].slot)
	_receive_grips(owners, slots)
	for peer in get_ready_physics_peers():
		_receive_grips.rpc_id(peer, owners, slots)

@rpc("authority", "call_local", "reliable", 2)
func _receive_grips(owners: Array[int], slots: Dictionary) -> void:
	_owners = owners
	_slots = slots
	_apply_grip_owners()
	# Existing elevator cargo code treats any nonzero owner as occupied.
	drag_owner_peer = owners[0] if not owners.is_empty() else 0

func _apply_grip_owners() -> void:
	for actor in get_tree().get_nodes_in_group("network_players"):
		var drag := actor.get_node_or_null("ItemDrag")
		if drag == null or actor.is_queued_for_deletion(): continue
		if _owners.has(actor.owner_peer_id) and drag.heavy_body != self:
			drag.heavy_body = self
			actor._refresh_equipment_visuals()
		elif not _owners.has(actor.owner_peer_id) and drag.heavy_body == self:
			drag.heavy_body = null
			actor._refresh_equipment_visuals()

func _request_grips() -> void:
	_request_grip_state.rpc_id(1)

@rpc("any_peer", "call_remote", "reliable", 2)
func _request_grip_state() -> void:
	if not multiplayer.is_server(): return
	var owners: Array[int] = []
	var slots := {}
	for owner in grips: owners.append(int(owner))
	for owner in grips: slots[owner] = int(grips[owner].slot)
	_receive_grips.rpc_id(multiplayer.get_remote_sender_id(), owners, slots)
	sync_physics_state()

func _physics_process(delta: float) -> void:
	_apply_grip_owners()
	if multiplayer.is_server() and carry_audio != null and (freeze or sleeping):
		carry_audio.observe_contacts(false, false, 0, 0, 0, delta)
	if multiplayer.is_server():
		for owner in grips.keys():
			var data: Dictionary = grips[owner]
			var actor := data.actor as GamePlayer
			if not can_carry(actor) or Time.get_ticks_msec() - int(data.last_hold) > 400:
				release_grip(owner)
			elif actor.head.global_position.distance_to(grip_point(int(data.slot))) > grip_reach + 0.4 or not _visible_grip(actor, int(data.slot)):
				release_grip(owner)
		if not grips.is_empty():
			var paired := grips.size() >= 2
			if upright_strength > 0.0:
				var tilt_error := global_basis.orthonormalized().y.cross(Vector3.UP)
				var tilt_velocity := Vector3(angular_velocity.x, 0, angular_velocity.z)
				apply_torque((tilt_error * upright_strength - tilt_velocity * upright_damping) * mass)
			for data: Dictionary in grips.values():
				var actor := data.actor as GamePlayer
				var point := grip_point(int(data.slot))
				var forward := -actor.global_basis.z
				var destination := actor.global_position + forward * 0.5
				destination.y = actor.global_position.y + lift_height + get_node("Grips").get_child(int(data.slot)).position.y
				var offset := point - global_position
				var point_velocity := linear_velocity + angular_velocity.cross(offset)
				var acceleration := (destination - point) * spring_strength - point_velocity * spring_damping
				if paired: acceleration.y += float(ProjectSettings.get_setting("physics/3d/default_gravity"))
				else: acceleration.y = 0
				apply_force(acceleration.limit_length(18) * mass / grips.size(), offset)
			var limit := paired_speed if paired else solo_speed
			var horizontal := Vector3(linear_velocity.x, 0, linear_velocity.z).limit_length(limit)
			linear_velocity.x = horizontal.x
			linear_velocity.z = horizontal.z
			angular_velocity = angular_velocity.limit_length(0.8)
	super._physics_process(delta)

func carry_hint() -> String:
	return str(get_node("/root/SteamInput").get_action_hint(&"interact")) + " " + display_name + " · Отпустить — поставить"

func get_interaction_hint_for(actor: GamePlayer) -> String:
	if not can_carry(actor): return ""
	if _nearest_grip(actor) < 0: return "Подойдите к свободному краю"
	return str(get_node("/root/SteamInput").get_action_hint(&"interact")) + " Удерживать — взяться за край · " + display_name

func get_interaction_prompt() -> String:
	return display_name + " · удерживать E — взяться за край"

func network_interact(_peer_id: int, _interactor: Node) -> void:
	# Hold requests go through the existing owner-checked ItemDrag RPC.
	pass

func _exit_tree() -> void:
	for actor in get_tree().get_nodes_in_group("network_players"):
		var drag := actor.get_node_or_null("ItemDrag")
		if drag != null and drag.heavy_body == self: drag.heavy_body = null
