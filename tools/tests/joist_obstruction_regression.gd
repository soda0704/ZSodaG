extends SceneTree
const LEVEL = preload("res://scenes/levels/floor_minus1_control_security_blockout.tscn")
const ROUTE_LAYER := 1048576
var failures := 0
var checks := 0
func _initialize() -> void:
	ProjectSettings.set_setting(BaseGameplayController.TEST_SAVE_PATH_SETTING, "user://joist_%d.cfg" % OS.get_process_id())
	create_timer(80).timeout.connect(func(): quit(2))
	run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)
func settle(count := 5) -> void:
	for frame in count: await physics_frame
func run() -> void:
	root.get_node("GameMenu").force_close_menu()
	var state := BaseGameplayController.new()
	root.add_child(state)
	state.set_process(false)
	var level = LEVEL.instantiate()
	root.add_child(level)
	await settle(20)
	var prop: HeavyCarryProp = level.get_node("FallenCheckpointJoist")
	var gate = level.get_node("JoistRouteBlocker")
	var initial := prop.global_transform
	var triangles := 0
	var clean_bounds := true
	for mesh in prop.get_node("Visual").find_children("*", "MeshInstance3D", true, false):
		clean_bounds = clean_bounds and mesh.mesh.get_aabb().position.y >= -.02
		for surface in mesh.mesh.get_surface_count():
			var arrays: Array = mesh.mesh.surface_get_arrays(surface)
			triangles += arrays[Mesh.ARRAY_INDEX].size() / 3
	check(clean_bounds and triangles == 12239, "native imported model has no detached lower iron; concrete and useful reinforcement remain")
	var manager = level.get_node("Doors/AutomaticDoors")
	check(prop.freeze and not gate.cleared, "untouched authored placement stays fixed with route closed")
	check(manager.get_door_count() == 10 and manager.get_open_door_count() == 0, "all ten level-one doors start closed without power")
	var actor: GamePlayer = load("res://scenes/characters/player.tscn").instantiate()
	actor.setup(1, "Mover", Vector3(-14.2, .02, 0), Color.WHITE)
	level.add_child(actor)
	actor.set_physics_process(false)
	actor.survival.set_physics_process(false)
	actor.get_node("ItemDrag").set_physics_process(false)
	check((actor.collision_mask & ROUTE_LAYER) != 0 and (prop.collision_mask & ROUTE_LAYER) == 0, "clearance layer blocks players without pinning the beam")
	var snapshot := state.get_snapshot()
	snapshot.fuel_delivered = true
	snapshot.main_breaker_on = true
	state._broadcast_snapshot(snapshot)
	await settle(55)
	check(manager.is_door_open_at(level.get_node("Doors/l1_checkpoint_spine")), "restored power retains normal nearby-door automation")
	var capsule := CapsuleShape3D.new()
	capsule.radius = .32
	capsule.height = 1.0
	for z in [-1.8, -.9, 0, .9, 1.8]:
		for height in [.53, 1.3, 2.2, 3.1, 4.5]:
			var query := PhysicsShapeQueryParameters3D.new()
			query.shape = capsule
			query.collision_mask = ROUTE_LAYER
			query.transform = Transform3D(Basis.IDENTITY, Vector3(-14.3, height, z))
			query.motion = Vector3(-3, 0, 0)
			var result: PackedFloat32Array = level.get_world_3d().direct_space_state.cast_motion(query)
			check(result[0] < .9, "no crouch/jump route at z=%s y=%s even with door open" % [z, height])
	var grip := prop.grip_point(0)
	actor.teleport_authoritative(Vector3(prop.position.x + .7, .02, grip.z + .8), 0)
	var point := prop.global_transform * Vector3(-2.2, .4, 0)
	var offset := point - actor.head.global_position
	actor.rotation.y = atan2(-offset.x, -offset.z)
	actor.head.rotation.x = atan2(offset.y, Vector2(offset.x, offset.z).length())
	await settle()
	check(actor.get_interaction_target() == prop, "player-only gate does not swallow the native E interaction ray")
	var drag = actor.get_node("ItemDrag")
	drag._hold(prop.get_path())
	check(prop.grips.has(1) and not prop.freeze, "normal held E releases initial placement and claims the physical beam")
	check(not gate.cleared, "a grip alone does not clear an unmoved obstruction")
	drag.cancel()
	prop.position.z = 7
	await settle()
	check(gate.cleared and gate.shape.disabled and prop.item_state.get("obstruction_cleared", false), "moving the beam permanently releases the gate")
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.collision_mask = 1 | ROUTE_LAYER
	query.transform = Transform3D(Basis.IDENTITY, Vector3(-14.3, .53, 0))
	query.motion = Vector3(-3, 0, 0)
	check(level.get_world_3d().direct_space_state.cast_motion(query)[0] > .99, "the actual open doorway is traversable after removing the beam")
	var session = load("res://scenes/levels/base_session.tscn").instantiate()
	for child in session.get_children():
		if child.name not in ["Players", "OverviewCamera", "LobbyHud", "Gameplay"]: child.free()
	session.set_script(load("res://tools/tests/fixtures/heavy_prop_checkpoint_session.gd"))
	root.add_child(session)
	# Even returning the moved beam to its original pose must not reset the event.
	prop.global_transform = initial
	prop.linear_velocity = Vector3.ZERO
	prop.angular_velocity = Vector3.ZERO
	var saved: Dictionary = session.capture_heavy_prop_checkpoint()
	check(saved.level1_checkpoint_joist.item_state.obstruction_cleared, "native checkpoint captures clearance independently of the beam's pose")
	state.inventory_checkpoint = {"heavy_props": saved}
	state.save_progress_authoritative()
	state.inventory_checkpoint = {}
	state.load_saved_snapshot()
	saved = state.inventory_checkpoint.heavy_props
	level.queue_free()
	await settle()
	level = LEVEL.instantiate()
	root.add_child(level)
	session.restore_heavy_prop_checkpoint(saved)
	await settle()
	gate = level.get_node("JoistRouteBlocker")
	check(gate.cleared and gate.shape.disabled, "disk restore of a moved-and-returned beam does not reinstate the route barrier")
	level.queue_free()
	session.queue_free()
	state.queue_free()
	await settle()
	print("JOIST OBSTRUCTION CHECKS ", checks, " FAILURES ", failures)
	quit(1 if failures else 0)
