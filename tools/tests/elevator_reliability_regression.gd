extends SceneTree
## Real door animations, sensor overlaps and CharacterBody platform physics.

class Passenger extends CharacterBody3D:
	var owner_peer_id := 1
	func _physics_process(delta: float) -> void:
		velocity.y -= 9.8 * delta
		move_and_slide()

var failures := 0
var checks := 0
var elevator: FunctionalElevatorController
var replica: FunctionalElevatorController
var one: Passenger
var two: Passenger

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	print("PASS " if ok else "FAIL ", label)
	if not ok: failures += 1

func settle(frames: int = 6) -> void:
	for frame in frames: await physics_frame
	await process_frame

func until(predicate: Callable, seconds: float = 10.0) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000)
	while not predicate.call() and Time.get_ticks_msec() < deadline:
		await physics_frame
	return predicate.call()

func passenger(peer_id: int, where: Vector3) -> Passenger:
	var body := Passenger.new()
	body.owner_peer_id = peer_id
	body.collision_layer = 2
	body.collision_mask = 1
	body.floor_snap_length = 0.3
	var collision := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.height = 1.8
	shape.radius = 0.3
	collision.shape = shape
	collision.position.y = 0.9
	body.add_child(collision)
	root.add_child(body)
	body.global_position = where
	return body

func run() -> void:
	var scene := load("res://scenes/objects/elevator/elevator_functional_blockout.tscn") as PackedScene
	elevator = scene.instantiate()
	elevator.door_animation_duration = 0.3
	elevator.arrival_alignment_duration = 0.08
	elevator.travel_start_stop_time = 0.1
	root.add_child(elevator)
	replica = scene.instantiate()
	replica.position.x = 100.0
	root.add_child(replica)
	one = passenger(1, Vector3(0, 0.08, 0))
	two = passenger(2, Vector3(-6, 0.08, 0))
	await settle()
	check(elevator._passenger_peer_ids.has(1), "real passenger overlap is detected")
	check(elevator.cabin_door.is_open and elevator._get_landing_door(0).is_open and not elevator._get_landing_door(1).is_open, "only the occupied landing starts open")
	check(not elevator.request_floor(-1) and not elevator.request_floor(6) and not elevator.request_floor(0) and not elevator.request_floor(2), "invalid, current and locked destinations are rejected")
	elevator.set_powered(false)
	check(not elevator.request_call(1), "unpowered elevator rejects calls")
	elevator.set_powered(true)
	# Real overlap, not a stale dictionary entry, controls departure.
	one.global_position = Vector3(-6, 0.08, 1.5)
	await settle()
	elevator._passenger_peer_ids[1] = true
	check(not elevator.request_floor(1) and elevator.state == elevator.ElevatorState.WAITING_FOR_PLAYERS, "stale passenger entry cannot start a trip")
	one.global_position = Vector3(0, 0.08, 0)
	check(await until(func(): return elevator.state == elevator.ElevatorState.CLOSING), "pending trip begins when missing passenger enters")
	two.global_position = Vector3(-2.85, 0.08, 0)
	check(await until(func(): return elevator.state == elevator.ElevatorState.OPENING), "entering the doorway reverses closing")
	var aborted := elevator.get_network_snapshot()
	replica._receive_network_snapshot(aborted)
	await settle(2)
	check(replica.pending_floor_index == 1 and replica._active_destination_floor_index == -1, "client retains destination after aborted departure")
	check(await until(func(): return elevator.state == elevator.ElevatorState.WAITING_FOR_PLAYERS), "doors reopen and wait for obstruction to clear")
	check(is_zero_approx(elevator.cabin.position.y) and elevator.cabin_door_travel_barrier.disabled, "aborted trip keeps cabin at landing with exit open")
	await settle(25)
	check(elevator.state == elevator.ElevatorState.WAITING_FOR_PLAYERS, "obstructed trip cannot restart itself")
	two.global_position = Vector3(-6, 0.08, 0)
	check(await until(func(): return elevator.state == elevator.ElevatorState.MOVING), "clearing doorway resumes the original trip")
	check(not elevator.cabin_door_travel_barrier.disabled and not elevator._get_landing_door(0).is_open, "travel barrier and departure landing close before movement")
	check(not elevator.request_call(0), "busy elevator rejects conflicting call")
	await settle(70)
	var moving := elevator.get_network_snapshot()
	replica._receive_network_snapshot(moving)
	await settle(2)
	check(is_equal_approx(replica._cabin_motion_start_y, elevator._cabin_motion_start_y) and is_equal_approx(replica._cabin_motion_duration, elevator._cabin_motion_duration) and absf(replica._cabin_motion_elapsed - elevator._cabin_motion_elapsed) < 0.04, "late snapshot resumes original acceleration curve and elapsed time")
	var phase_matched := true
	for frame in 15:
		await physics_frame
		await process_frame
		phase_matched = phase_matched and absf(replica.cabin.position.y - elevator.cabin.position.y) < 0.25
	check(phase_matched, "late replica follows the same curve instead of restarting acceleration")
	elevator.set_powered(false)
	check(elevator.state == elevator.ElevatorState.MOVING and elevator._power_off_after_trip, "power loss lets current trip reach a safe landing")
	check(await until(func(): return elevator.state == elevator.ElevatorState.UNPOWERED), "power-loss trip completes and opens doors")
	check(elevator.current_floor_index == 1 and is_equal_approx(elevator.cabin.position.y, -elevator.floor_spacing), "cabin reaches exact requested landing")
	check(absf(one.global_position.y - elevator.cabin.global_position.y) < 0.25, "CharacterBody passenger remains on cabin floor throughout descent")
	check(elevator.cabin_door.is_open and elevator._get_landing_door(1).is_open and not elevator._get_landing_door(0).is_open and elevator.cabin_door_travel_barrier.disabled, "only arrival doors open after power-loss trip")
	replica._receive_network_snapshot(elevator.get_network_snapshot())
	await settle(2)
	check(replica.state == replica.ElevatorState.UNPOWERED and replica.current_floor_index == 1 and replica.cabin_door.is_open, "authoritative final phase corrects client and opens exit")
	elevator.set_powered(true)
	elevator.require_all_connected_players = false
	check(elevator.request_call(0), "landing call can return an empty cabin")
	check(await until(func(): return elevator.state == elevator.ElevatorState.IDLE_OPEN), "return trip completes")
	check(elevator.current_floor_index == 0 and absf(one.global_position.y) < 0.25, "passenger returns safely with cabin")
	# Repeated deferred requests and departure reversals must not create two trips.
	check(elevator.request_floor(1), "next trip accepted")
	elevator.pending_floor_index = 0
	check(not elevator._try_begin_pending_trip() and elevator._active_destination_floor_index == 1, "deferred pending retry cannot start a second trip while closing")
	elevator.pending_floor_index = -1
	elevator._abort_departure()
	elevator.set_powered(false)
	check(await until(func(): return elevator.state == elevator.ElevatorState.UNPOWERED), "power loss during reopening cancels pending departure")
	await settle(25)
	check(is_zero_approx(elevator.cabin.position.y), "cancelled coroutine never moves cabin later")
	var button := elevator.get_node("CabinMoving/InteriorPanel/FloorButton1") as ElevatorFloorButton
	button.network_interact(1, null)
	check(elevator.state == elevator.ElevatorState.UNPOWERED, "missing interactor is rejected safely")
	one.queue_free(); two.queue_free(); replica.queue_free(); elevator.queue_free()
	await settle()
	print("CHECKS ", checks, " RESULT FAILURES ", failures)
	quit(1 if failures else 0)
