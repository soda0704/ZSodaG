extends SceneTree
var checks := 0
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)
func run() -> void:
	var arena = load("res://tools/tests/fixtures/character_test_arena.tscn").instantiate()
	root.add_child(arena)
	var player := load("res://scenes/characters/player.tscn").instantiate() as GamePlayer
	player.name = "1"
	player.setup(1,"",Vector3.ZERO,Color.WHITE,0)
	arena.get_node("Players").add_child(player)
	player.set_physics_process(false)
	player.survival.set_physics_process(false)
	var item := load("res://scenes/objects/items/fuel_can_pickup.tscn").instantiate() as WorldItemPickup
	arena.add_child(item)
	item.set_physics_process(false)
	item.position = Vector3(0,0.25,-0.4)
	for rate in [30,60,144]:
		item.gravity_scale = 0.0
		item.linear_velocity = Vector3.ZERO
		for tick in rate: player._push_loose_item(item,Vector3.ZERO,1.0/rate)
		check(is_equal_approx(item.linear_velocity.length(),12.0) and is_zero_approx(item.linear_velocity.y), "original proximity nudge, consistent weaker impulse at %d Hz" % rate)
		check(item.linear_velocity.length() < 90.0 / 7.0, "impulse reduced more than sevenfold from original")
	item.linear_velocity = Vector3.ZERO
	player._push_loose_item(item,Vector3.BACK,1.0/60)
	check(item.linear_velocity.length() > 0.19, "no directional gate prevents contact pushing")
	item.linear_velocity = Vector3.ZERO
	item.drag_owner_peer = 2
	player._push_loose_item(item,Vector3.FORWARD,1.0/60)
	check(item.linear_velocity == Vector3.ZERO, "another player's drag remains protected")
	item.drag_owner_peer = 0
	item.freeze = true
	player._push_loose_item(item,Vector3.FORWARD,1.0/60)
	check(item.linear_velocity == Vector3.ZERO, "elevator cargo remains fixed")
	# Actual physics: a heavy canister must move, then stop nearby.
	item.freeze = false
	item.gravity_scale = 1.0
	item.position = Vector3(0,0.35,-0.45)
	item.linear_velocity = Vector3.ZERO
	var start := item.position
	var peak_speed := 0.0
	for frame in 120:
		player.simulate_movement(1.0/60,Vector2.ZERO,false,false,false,0,0)
		player.position = Vector3.ZERO
		peak_speed = maxf(peak_speed, Vector2(item.linear_velocity.x,item.linear_velocity.z).length())
		await physics_frame
	var distance := Vector2(item.position.x-start.x,item.position.z-start.z).length()
	print("CONTACT PHYSICS distance=",distance," peak=",peak_speed)
	check(distance > 0.15 and distance < 4.0, "real canister moves instead of remaining stuck or flying far")
	check(item.position.y < 0.8 and peak_speed < 5.0, "contact stays grounded with moderate speed")
	arena.queue_free()
	await process_frame
	print("LOOSE ITEM CONTACT CHECKS ", checks, " FAILURES ", failures)
	quit(0 if failures == 0 else 1)
