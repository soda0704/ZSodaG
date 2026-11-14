extends SceneTree

const PLAYER = preload("res://scenes/characters/player.tscn")
var failures := 0
var checks := 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)

func receive(player: GamePlayer, at: Vector3, speed := Vector3.ZERO) -> void:
	player._receive_authoritative_state(at, speed, .4, -.2, true, &"", false, 0.0, false, false, 7, player.get_inventory_snapshot())

func run() -> void:
	root.get_node("GameMenu").force_close_menu()
	var arena = load("res://tools/tests/fixtures/character_test_arena.tscn").instantiate()
	root.add_child(arena)
	var actors: Array[GamePlayer] = []
	for peer in [1, 2]:
		var actor: GamePlayer = PLAYER.instantiate()
		actor.name = str(peer)
		actor.setup(peer, "Replication test", Vector3.ZERO, Color.WHITE, 0, 0)
		arena.get_node("Players").add_child(actor)
		actor.set_physics_process(false)
		actor.survival.set_physics_process(false)
		actors.append(actor)
	var local := actors[0]
	var remote := actors[1]
	check(local._replication != remote._replication, "each player owns independent replication state")
	local.position = Vector3.ZERO
	receive(local, Vector3(.5, 0, 0))
	check(local.position == Vector3.ZERO and local._reconciliation_offset == Vector3(.5, 0, 0), "small server error is buffered without snapping")
	check(remote._reconciliation_offset == Vector3.ZERO, "local correction does not leak to another player")
	local.apply_reconciliation(.05)
	check(local.position.x > 0 and local.position.x < .5 and (local.position + local._reconciliation_offset).is_equal_approx(Vector3(.5, 0, 0)), "smooth correction converges without losing the remaining offset")
	receive(local, Vector3(10, 0, 0), Vector3(2, 0, 0))
	check(local.position.is_equal_approx(Vector3(10.1, 0, 0)) and local._reconciliation_offset == Vector3.ZERO, "large error snaps to the extrapolated authoritative position")
	check(local.velocity.is_equal_approx(Vector3(.3, 0, 0)), "local velocity keeps the existing reconciliation blend")
	remote.position = Vector3.ZERO
	remote.interpolate_remote_player(.1)
	check(remote.position == Vector3.ZERO, "remote player stays still until its first snapshot")
	receive(remote, Vector3(4, 0, 0), Vector3(2, 0, 0))
	check(remote._has_remote_snapshot and remote._remote_crouching and remote.position == Vector3.ZERO, "remote snapshot updates the target before rendering movement")
	remote.interpolate_remote_player(.1)
	check(remote.position.x > 0 and remote.position.x < 4.1 and remote.rotation.y > 0 and remote.head.rotation.x < 0, "remote position and look interpolate towards the received target")
	var vehicle := Node3D.new()
	root.add_child(vehicle)
	remote.vehicle = vehicle
	var before := remote.position
	remote.interpolate_remote_player(.1)
	check(remote.position == before, "vehicle view suspends remote interpolation")
	remote.vehicle = null
	remote._is_sleeping_in_bunk = true
	remote.interpolate_remote_player(.1)
	check(remote.position == before, "sleep suspends remote interpolation")
	remote._is_sleeping_in_bunk = false
	local._reconciliation_offset = Vector3.ONE
	local.vehicle = vehicle
	before = local.position
	local.apply_reconciliation(.1)
	check(local.position == before and local._reconciliation_offset == Vector3.ONE, "driving suspends local correction without consuming it")
	local.vehicle = null
	local._receive_authoritative_teleport(Vector3(20, 0, 0), .8)
	check(local.global_position.is_equal_approx(Vector3(20, 0, 0)) and local._remote_target_position == local.position and local._reconciliation_offset == Vector3.ZERO, "teleport clears stale correction and interpolation targets")
	remote._receive_bunk_sleep_state(true, Transform3D(Basis.IDENTITY, Vector3(5, 0, 0)))
	check(remote._remote_target_velocity == Vector3.ZERO and is_equal_approx(remote._remote_target_pitch, PI * .5) and not remote._remote_crouching, "sleep resets the replicated target pose")
	remote._receive_bunk_sleep_state(false, Transform3D(Basis.IDENTITY, Vector3(6, 0, 0)))
	check(remote._remote_target_position == remote.position and remote._remote_target_pitch == 0.0, "wake resets the replicated target pose")
	vehicle.queue_free()
	arena.queue_free()
	for frame in 5:
		await process_frame
		await RenderingServer.frame_post_draw
	print("PLAYER REPLICATION CHECKS ", checks, " FAILURES ", failures)
	quit(1 if failures else 0)
