class_name PlayerStateReplication
extends RefCounted
## Per-player movement snapshot state. RPC endpoints remain on GamePlayer.

var send_accumulator: float = 0.0
var correction_offset: Vector3 = Vector3.ZERO
var target_position: Vector3 = Vector3.ZERO
var target_velocity: Vector3 = Vector3.ZERO
var target_yaw: float = 0.0
var target_pitch: float = 0.0
var crouching: bool = false
var grounded: bool = true
var has_snapshot: bool = false


func send_if_due(player: GamePlayer, delta: float) -> void:
	send_accumulator += delta
	var interval := 1.0 / player.SNAPSHOT_SEND_RATE
	if send_accumulator < interval:
		return

	send_accumulator = fmod(send_accumulator, interval)
	var ladder = player.get_node("LadderClimb")
	player._receive_authoritative_state.rpc(
		player.position,
		player.velocity,
		player.rotation.y,
		player.head.rotation.x,
		player._is_crouching,
		player._held_item_type,
		player._has_flashlight,
		player._battery_charge,
		player._flashlight_enabled,
		player._flashlight_malfunctioning,
		player._server_last_sequence,
		player.get_inventory_snapshot(),
		Vector3(player._sprint_remaining, 1.0 if player._sprint_exhausted else 0.0, 1.0 if player._sprint_active else 0.0),
		{
			"grounded": player.is_on_floor(),
			"journal_phase": player._journal_phase,
			"journal_map": player._journal_map,
			"journal_loupe": player._journal_loupe,
			"variant": player.character_variant_id,
			"aiming": player._aiming,
			"ladder": str(ladder.route.get_path()) if player.is_climbing() else "",
			"ladder_revision": ladder.revision,
			"ladder_blocked": ladder.exit_blocked,
		}
	)


func receive(
	player: GamePlayer,
	server_position: Vector3,
	server_velocity: Vector3,
	server_yaw: float,
	server_pitch: float,
	server_crouching: bool,
	server_held_item_type: StringName,
	server_has_flashlight: bool,
	server_battery_charge: float,
	server_flashlight_enabled: bool,
	server_flashlight_malfunctioning: bool,
	_acknowledged_input: int,
	server_inventory: Dictionary = {},
	server_sprint_state: Vector3 = Vector3(-1.0, 0.0, 0.0),
	server_animation: Dictionary = {}
) -> void:
	grounded = bool(server_animation.get("grounded", grounded))
	var ladder = player.get_node("LadderClimb")
	ladder.exit_blocked = bool(server_animation.get("ladder_blocked", false))
	ladder.sync(str(server_animation.get("ladder", "")), int(server_animation.get("ladder_revision", 0)))
	player._journal_phase = int(server_animation.get("journal_phase", player._journal_phase))
	player._journal_map = bool(server_animation.get("journal_map", player._journal_map))
	player._journal_loupe = bool(server_animation.get("journal_loupe", player._journal_loupe))
	if not player.is_local_player():
		player._aiming = bool(server_animation.get("aiming", false))
	if server_sprint_state.x >= 0.0:
		player._sprint_remaining = clampf(server_sprint_state.x, 0.0, player.sprint_duration)
		player._sprint_exhausted = server_sprint_state.y > 0.5
		player._sprint_active = server_sprint_state.z > 0.5
	if not server_inventory.is_empty():
		player.apply_inventory_snapshot(server_inventory)
	else:
		player.apply_inventory_snapshot({
			"held_item": server_held_item_type,
			"has_flashlight": server_has_flashlight,
			"battery_charge": server_battery_charge,
			"flashlight_enabled": server_flashlight_enabled,
			"malfunctioning": server_flashlight_malfunctioning,
		})

	if player.is_local_player():
		var extrapolated_position := (
			server_position
			+ server_velocity * player.REMOTE_EXTRAPOLATION_SECONDS
		)
		var error := extrapolated_position - player.position
		if error.length() >= player.hard_reconciliation_distance:
			player.position = extrapolated_position
			correction_offset = Vector3.ZERO
		else:
			correction_offset = error
		player.velocity = player.velocity.lerp(server_velocity, 0.15)
		return

	target_position = server_position
	target_velocity = server_velocity
	target_yaw = server_yaw
	target_pitch = server_pitch
	crouching = server_crouching
	has_snapshot = true


func reconcile(player: GamePlayer, delta: float) -> void:
	if player.is_driving():
		return
	if correction_offset.is_zero_approx():
		return

	var weight := 1.0 - exp(-player.reconciliation_speed * delta)
	var correction := correction_offset * weight
	player.position += correction
	correction_offset -= correction


func interpolate(player: GamePlayer, delta: float) -> void:
	if not has_snapshot or player.is_bunk_busy() or player.is_driving():
		return

	var weight := 1.0 - exp(-player.remote_interpolation_speed * delta)
	var extrapolated_position := (
		target_position
		+ target_velocity * player.REMOTE_EXTRAPOLATION_SECONDS
	)
	player.position = player.position.lerp(extrapolated_position, weight)
	player.rotation.y = lerp_angle(player.rotation.y, target_yaw, weight)
	player.head.rotation.x = lerp_angle(
		player.head.rotation.x,
		target_pitch,
		weight
	)
