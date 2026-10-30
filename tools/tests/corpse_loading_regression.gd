extends SceneTree
## Reproduce the production loader's disabled scene and deferred collision assembly.
var failures := 0
func _initialize() -> void:
	ProjectSettings.set_setting(BaseGameplayController.TEST_SAVE_PATH_SETTING,"user://corpse_loading_%d.cfg" % OS.get_process_id())
	create_timer(45).timeout.connect(func(): quit(2))
	run.call_deferred()
func check(ok: bool, label: String) -> void:
	print("PASS " if ok else "FAIL ",label)
	if not ok: failures += 1
func run() -> void:
	var base = load("res://scenes/levels/base_blockout_v03.tscn").instantiate()
	var geometry := []
	for csg in base.find_children("*","CSGShape3D",true,false):
		if csg.use_collision:
			geometry.append(csg); csg.use_collision = false
	var objects := []
	for object in base.find_children("*","CollisionObject3D",true,false):
		objects.append([object, object.disable_mode])
		object.disable_mode = CollisionObject3D.DISABLE_MODE_REMOVE if object is StaticBody3D else CollisionObject3D.DISABLE_MODE_KEEP_ACTIVE
	base.process_mode = Node.PROCESS_MODE_DISABLED
	root.add_child(base); current_scene = base
	var bodies := []
	for body in base.find_children("*","RigidBody3D",true,false):
		bodies.append([body,body.freeze]); body.freeze = true
	await create_timer(2.5).timeout
	var corpses := get_nodes_in_group("medical_corpses")
	check(corpses.size() == 2,"production level owns two corpses during staged loading")
	for corpse in corpses:
		check(not corpse.initialized,"corpse %d cannot start simulation while level is disabled" % corpse.corpse_id)
		var frozen := true
		for body in corpse.ragdoll.get_children():
			if body is RigidBody3D: frozen = frozen and body.freeze
		check(frozen,"corpse %d keeps loader freeze while collision is unavailable" % corpse.corpse_id)
	for csg in geometry: csg.use_collision = true
	for i in 3: await physics_frame
	base.process_mode = Node.PROCESS_MODE_INHERIT
	for entry in objects: entry[0].disable_mode = entry[1]
	for entry in bodies: entry[0].freeze = entry[1]
	for i in 120: await physics_frame
	for corpse in corpses:
		check(corpse.initialized,"corpse %d initializes after collision assembly" % corpse.corpse_id)
		print("LOADED CORPSE ",corpse.corpse_id," ",corpse.ragdoll.root_body.global_position)
		check(corpse.ragdoll.root_body.global_position.y > -39,"corpse %d remains on level two after delayed loading" % corpse.corpse_id)
	current_scene = null; base.queue_free(); await process_frame
	print("CORPSE LOADING CHECKS 9 FAILURES ",failures); quit(0 if failures == 0 else 1)
