extends SceneTree
var checks := 0
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)
func delay(seconds := 0.25) -> void: await create_timer(seconds).timeout
func equip_fixture(player: GamePlayer, kind: StringName, extra := {}) -> void:
	var data := {"held_item": kind, "has_flashlight": true, "battery_charge": 0.65, "handheld_flashlight_drawn": false, "tape_count": 3, "weapon_rounds": 8, "pistol_ammo": 20}
	data.merge(extra, true)
	player.apply_inventory_snapshot(data)
func check_grip(player: GamePlayer) -> void:
	# Compare actual animated finger contacts with the original right-hand
	# grip mirrored through the native L/R rests, not a second authored guess.
	var reference := player.body_animator.variant.first_person_scene.instantiate() as Node3D
	root.add_child(reference)
	reference.hide()
	reference.get_node("AnimationTree").active = false
	var source_sk := reference.get_node("Skeleton3D") as Skeleton3D
	for modifier in source_sk.get_children():
		if modifier is SkeletonModifier3D: modifier.active = false
	var animation := reference.get_node("AnimationPlayer") as AnimationPlayer
	animation.play("FlashlightIdle"); animation.seek(0.0, true); animation.pause()
	source_sk.force_update_all_bone_transforms()
	var mirror := Transform3D(Basis.from_scale(Vector3(-1,1,1)), Vector3.ZERO)
	var sk := player.body_animator.first_person_model.get_node("Skeleton3D") as Skeleton3D
	var left := sk.find_bone("LeftHand")
	var right := source_sk.find_bone("RightHand")
	var expected_hand := mirror * source_sk.get_bone_global_pose(right) * source_sk.get_bone_global_rest(right).affine_inverse() * mirror * sk.get_bone_global_rest(left)
	var actual_hand := sk.get_bone_global_pose(left)
	var position_error := 0.0
	var angle_error := 0.0
	for finger in ["Thumb", "Index", "Middle", "Ring", "Pinky"]:
		for joint in [1,2,3]:
			var l := sk.find_bone("LeftHand" + finger + str(joint))
			var r := source_sk.find_bone("RightHand" + finger + str(joint))
			var expected := expected_hand.affine_inverse() * mirror * source_sk.get_bone_global_pose(r) * source_sk.get_bone_global_rest(r).affine_inverse() * mirror * sk.get_bone_global_rest(l)
			var actual := actual_hand.affine_inverse() * sk.get_bone_global_pose(l)
			position_error = maxf(position_error, expected.origin.distance_to(actual.origin))
			angle_error = maxf(angle_error, expected.basis.get_rotation_quaternion().angle_to(actual.basis.get_rotation_quaternion()))
	check(position_error < 0.002 and angle_error < 0.015, "actual left fingers mirror original right grip: %.5f m / %.5f rad" % [position_error, angle_error])
	var source_socket: Node3D = source_sk.get_node("RightHand/Equipment")
	var mirrored_lamp: Transform3D = mirror * source_sk.get_bone_global_pose(right) * source_socket.transform * source_socket.get_node("FlashlightGrip").transform * mirror
	var actual_direction := (sk.global_basis.inverse() * -player.flashlight.beam.global_basis.z).normalized()
	check(actual_direction.dot((-mirrored_lamp.basis.z).normalized()) > 0.999, "beam orientation preserves mirrored original grip")
	reference.queue_free()
func run() -> void:
	Engine.max_fps = 60
	root.size = Vector2i(960, 540)
	root.get_node("GameMenu").force_close_menu()
	var input := root.get_node("SteamInput")
	input.set_process(false); input.set_process_input(false)
	var arena = load("res://tools/tests/fixtures/character_test_arena.tscn").instantiate()
	root.add_child(arena)
	current_scene = arena
	for variant in [0, 1]:
		var player := load("res://scenes/characters/player.tscn").instantiate() as GamePlayer
		player.name = "1"
		player.setup(1, "", Vector3(0, 0.1, 0), Color.WHITE, 0, variant)
		arena.get_node("Players").add_child(player)
		player.survival.set_physics_process(false)
		equip_fixture(player, &"flashlight", {"flashlight_enabled": true})
		await delay(0.55)
		check(String(player.flashlight.get_parent().get_path()).contains("/LeftHand/"), "solo torch uses left-hand socket")
		check_grip(player)
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://tools/.local/offhand-%d-solo.png" % variant)
		for kind in [&"pistol", &"fuel_can", &"fuse", &"kitchen_knife"]:
			equip_fixture(player, kind)
			check(player.toggle_flashlight_authoritative(), "F draws lamp alongside %s variant %d" % [kind, variant])
			await delay(0.55)
			check(player._held_item_type == kind and player.is_offhand_flashlight_drawn() and player.flashlight.beam.is_visible_in_tree(), "main item and working offhand light coexist")
			check(String(player.flashlight.get_parent().get_path()).contains("/LeftHand/"), "lamp uses authored left-hand socket")
			var fp := player.body_animator.first_person
			check(float(fp.tree.get("parameters/OffhandTorch/blend_amount")) > 0.99 and fp.model.get_node("Skeleton3D/SupportHandIK").influence < 0.02, "native left arm layer replaces support-hand IK")
			var beam_forward := (-player.flashlight.beam.global_basis.z).normalized().dot((-player.camera.global_basis.z).normalized())
			print("BEAM FORWARD ",variant," ",kind," dot=",beam_forward," ads=",fp._ads)
			# The original grip points about 8 degrees below the camera. Preserve
			# that authored stance, allowing its breathing and viewmodel inertia.
			check(beam_forward > cos(deg_to_rad(10.0)), "offhand beam remains in the forward cone of the original grip")
			if kind == &"fuel_can": check_grip(player)
			var snapshot := player.get_inventory_snapshot()
			player.apply_inventory_snapshot(snapshot)
			check(player.is_offhand_flashlight_drawn() and player._flashlight_enabled, "snapshot retains offhand state")
			if DisplayServer.get_name() != "headless":
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png("res://tools/.local/offhand-%d-%s.png" % [variant, kind])
			check(player.toggle_flashlight_authoritative() and player._held_item_type == kind and not player.flashlight._equipped, "F stows only lamp")
		equip_fixture(player, &"pistol", {"weapon_light_mounted": true, "flashlight_enabled": true})
		# Explicitly emulate an old snapshot that predates the new field.
		var legacy := player.get_inventory_snapshot()
		legacy.erase("handheld_flashlight_drawn"); legacy.weapon_light_mounted = true
		player.apply_inventory_snapshot(legacy)
		check(not player.weapon_light_mounted and player.is_offhand_flashlight_drawn() and is_equal_approx(player._battery_charge, 0.65), "legacy pistol tape becomes offhand, preserving charge")
		check(not player.perform_inventory_action_authoritative(&"mount_light") and player.tape_count == 3, "pistol rejects tape without spending it")
		equip_fixture(player, &"flashlight", {"flashlight_enabled": true})
		check(player.pickup_world_item_authoritative(&"fuel_can", {"fuel_liters": 7.0}) and player.is_offhand_flashlight_drawn() and player._flashlight_enabled, "pickup keeps drawn lamp on while taking canister")
		check(player.consume_held_item_authoritative(&"fuel_can") and player._held_item_type == &"flashlight" and player._flashlight_enabled, "consuming main item keeps torch in hand")
		equip_fixture(player, &"pistol", {"handheld_flashlight_drawn": true, "flashlight_enabled": true})
		Input.action_press("weapon_aim")
		await delay(0.5)
		check(player.is_offhand_flashlight_drawn() and player.flashlight.beam.is_visible_in_tree(), "pistol ADS preserves left-hand light")
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://tools/.local/offhand-%d-pistol-ads.png" % variant)
		Input.action_release("weapon_aim")
		check(player.weapon.perform_action(&"fire") and player._flashlight_enabled, "pistol shoots with offhand light")
		check(player.weapon.perform_action(&"reload"), "pistol reload starts")
		await delay(0.30)
		check(not player.flashlight._equipped and float(player.body_animator.first_person.tree.get("parameters/OffhandTorch/blend_amount")) < 0.02, "reload temporarily stows lamp and frees support hand")
		await delay(1.45)
		check(player.flashlight._equipped and player._flashlight_enabled, "reload restores offhand torch")
		player._spare_batteries.assign([1.0])
		player._begin_inventory_action(&"replace_battery")
		await delay(0.25)
		check(player._held_item_type == &"pistol" and player._battery_flashlight_presentation and not player.weapon._models[&"pistol"].visible, "native battery action temporarily stows pistol without dropping it")
		await delay(1.10)
		check(player._held_item_type == &"pistol" and player.is_offhand_flashlight_drawn() and player._battery_charge > 0.97 and not player._battery_flashlight_presentation, "battery replacement restores pistol and left-hand torch")
		var before := player._battery_charge
		check(player.drop_current_item_at_authoritative(Transform3D(Basis.IDENTITY, Vector3(2, 1, 0))) and player._held_item_type == &"flashlight" and is_equal_approx(player._battery_charge, before) and player._flashlight_enabled, "dropping pistol retains handheld torch and charge")
		equip_fixture(player, &"pistol", {"battery_charge": 0.0})
		check(player.toggle_flashlight_authoritative() and player.is_offhand_flashlight_drawn() and not player._flashlight_enabled, "empty lamp can be held but cannot emit light")
		player.perform_inventory_action_authoritative(&"drop_flashlight")
		check(player._held_item_type == &"pistol" and not player._has_flashlight and not player.is_offhand_flashlight_drawn(), "journal drop removes only lamp")
		check(player.pickup_world_item_authoritative(&"flashlight", {"battery_charge": 0.4}) and player.is_offhand_flashlight_drawn(), "torch pickup alongside pistol goes to left hand")
		player.perform_inventory_action_authoritative(&"drop_flashlight")
		check(player.pickup_world_item_authoritative(&"pistol", {"rounds": 3, "mounted_charge": 0.43}) and not player.weapon_light_mounted and player.is_offhand_flashlight_drawn() and is_equal_approx(player._battery_charge, 0.43), "legacy world pistol mount converts without losing lamp")
		equip_fixture(player, &"m4a1")
		check(not player.toggle_flashlight_authoritative() and not player.is_handheld_flashlight_drawn(), "rifle requires tape")
		check(player.perform_inventory_action_authoritative(&"mount_light") and player.weapon_light_mounted and player.tape_count == 2, "rifle still mounts torch")
		check(player.toggle_flashlight_authoritative() and not player._flashlight_enabled and player.weapon_light_mounted, "mounted rifle lamp toggles independently")
		player.queue_free()
		await process_frame; await process_frame
	arena.queue_free()
	await process_frame
	print("OFFHAND FLASHLIGHT CHECKS ", checks, " FAILURES ", failures)
	quit(0 if failures == 0 else 1)
