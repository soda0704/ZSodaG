extends SceneTree

const BatteryPickup := preload("res://scripts/gameplay/items/battery_pickup.gd")
var failures := 0
var checks := 0

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	print("PASS " if ok else "FAIL ",label)
	if not ok: failures += 1

func run() -> void:
	root.get_node("GameMenu").force_close_menu()
	var arena: Node3D = load("res://tools/tests/fixtures/character_test_arena.tscn").instantiate()
	root.add_child(arena)
	for kind in [&"pistol",&"m4a1"]:
		var pickup: WorldItemPickup = load("res://scenes/objects/items/%s_pickup.tscn"%kind).instantiate()
		pickup.setup_spawn({"item_type":kind,"item_state":{"rounds":7},"transform":Transform3D(Basis.IDENTITY,Vector3(0,0.7,0))})
		arena.add_child(pickup)
		var mesh: ArrayMesh = pickup.get_node("Model/Body").mesh
		var collision: CollisionShape3D = pickup.get_node("CollisionShape3D")
		var bounds := mesh.get_aabb()
		var collider := AABB(collision.position-collision.shape.size*0.5,collision.shape.size)
		check(mesh.resource_path.contains("gameplay.res") and bounds.size.z<0.9,"%s uses the normalized supplied model"%kind)
		check(collider.encloses(bounds),"%s authored collider encloses its actual model"%kind)
		check(pickup.item_state.rounds==7,"%s model replacement preserves magazine state"%kind)
		for surface in mesh.get_surface_count():
			check(mesh.surface_get_arrays(surface)[Mesh.ARRAY_BONES]==null,"%s has no redundant runtime weapon skin %d"%[kind,surface])
		pickup.queue_free()
	var tape: WorldItemPickup = load("res://scenes/objects/items/tool_pickup.tscn").instantiate()
	tape.setup_spawn({"item_type":&"tape","item_state":{},"transform":Transform3D(Basis.IDENTITY,Vector3(0,0.3,0))})
	arena.add_child(tape)
	var tape_mesh: ArrayMesh = tape.get_node("ItemModel/Body").mesh
	check(tape_mesh.resource_path.contains("duct_tape/gameplay.res"),"tape pickup uses the supplied native model")
	var tape_shape: CollisionShape3D = tape.get_node("CollisionShape3D")
	check(AABB(-tape_shape.shape.size*0.5,tape_shape.shape.size).encloses(tape_mesh.get_aabb()),"tape collider encloses the roll")
	check(tape.item_type==&"tape" and tape.get_interaction_prompt().contains("крепление"),"tape retains existing pickup and mounting identity")
	tape.queue_free()
	var variants: MeshLibrary = BatteryPickup.VARIANTS
	check(variants.get_item_list().size()==9,"all nine battery designs are available")
	seed(424242)
	var selected := {}
	var stable := true
	for i in 100:
		var state := BatteryPickup.prepare_state({"charge_amount":0.37})
		selected[state.visual_variant] = true
		stable = stable and state==BatteryPickup.prepare_state(state)
	check(stable,"persisted battery variants remain stable across repeated spawning")
	check(selected.size()==9,"fresh spawns can select every design")
	for id in variants.get_item_list():
		var pickup: WorldItemPickup = load("res://scenes/objects/items/battery_pickup.tscn").instantiate()
		pickup.setup_spawn({"pickup_name":"Battery%d"%id,"item_state":{"charge_amount":0.37,"visual_variant":id},"transform":Transform3D(Basis.IDENTITY,Vector3(id*0.1,0.2,0))})
		arena.add_child(pickup)
		check(pickup.get_node("Model/Body").mesh==variants.get_item_mesh(id) and pickup.item_state.charge_amount==0.37,"saved battery %d restores its mesh without changing charge"%id)
		var encoded := var_to_bytes(pickup.item_state)
		check(BatteryPickup.prepare_state(bytes_to_var(encoded))==pickup.item_state,"battery %d survives save serialization"%id)
		check(variants.get_item_mesh(id).get_aabb().size.y<=0.066,"battery %d keeps physical cell dimensions"%id)
		pickup.queue_free()
	check(variants.get_item_list().has(BatteryPickup.prepare_state({"visual_variant":999}).visual_variant),"unknown saved variant gets a valid replacement")
	var light: PlayerFlashlight = load("res://scenes/objects/equipment/flashlight.tscn").instantiate()
	arena.add_child(light)
	light.acquire(true,0.6)
	check(light.beam.visible and light.spill.visible and light.lens.material_override.emission_enabled,"new flashlight turns on through the existing component")
	light.set_enabled(false)
	check(not light.beam.visible and not light.lens.material_override.emission_enabled and light.battery_charge==0.6,"new flashlight turns off without losing charge")
	var orphan_count := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	for id in [0,1]:
		var actor: GamePlayer = load("res://scenes/characters/player.tscn").instantiate()
		actor.name = "1"
		actor.setup(1,"",Vector3.ZERO,Color.WHITE,0,id)
		arena.get_node("Players").add_child(actor)
		actor.set_physics_process(false)
		actor.survival.set_physics_process(false)
		var layers_valid := true
		for mesh: MeshInstance3D in actor.body_animator.first_person_model.find_children("*","MeshInstance3D",true,false):
			layers_valid = layers_valid and mesh.layers==(1<<19) and mesh.cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		check(layers_valid,"variant %d assigns every view attachment to its light layer without world shadows"%id)
		actor.pickup_world_item_authoritative(&"m4a1",{"rounds":4,"mounted_charge":0.6})
		actor._flashlight_enabled = true
		actor.weapon._physics_process(0)
		check(actor.weapon._mounted_lamp.visible and actor.weapon._mounted_beam.visible,"variant %d existing mounted flashlight toggles the new lamp"%id)
		for kind in [&"pistol",&"m4a1"]:
			actor.weapon._play_effect(false,kind)
			var marker: Marker3D = actor.weapon._models[kind].get_node("Muzzle")
			check(actor.weapon._flash.global_position.distance_to(marker.global_position)<0.001,"variant %d %s flash uses the actual muzzle marker"%[id,kind])
		actor.queue_free()
		await process_frame
	for i in 3: await physics_frame
	check(int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))<=orphan_count,"loading and freeing both character variants leaves no orphaned attachment nodes")
	var room: Node3D = load("res://scenes/art/base/technical/generator_room_art.tscn").instantiate()
	arena.add_child(room)
	var generator := room.get_node("Blockout/Generator_Room/Power_Generation/Technical_Main_Generator_Blockout")
	check(generator.get_node("Body").mesh.resource_path.contains("generator/gameplay.res"),"generator room replaces the old blockout body")
	check(generator.get_node("GeneratorAudio").bus==&"Machinery" and room.has_node("ArtCollision/GeneratorBody/CollisionShape3D"),"generator retains its powered audio and authored collision")
	arena.queue_free()
	for i in 3: await physics_frame
	print("ITEM MODEL CHECKS ",checks," FAILURES ",failures)
	quit(1 if failures else 0)
