extends SceneTree
## Camera switching must never expose the owner view rig to an external view.

const OUT := "res://tools/.local/view-isolation/"
var checks := 0
var failures := 0

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	print("PASS " if ok else "FAIL ", label)
	if not ok: failures += 1

func frames(count: int) -> void:
	for frame in count: await process_frame

func view_hidden(fp: GameFirstPersonPresentation) -> bool:
	var hidden := true
	for geometry: GeometryInstance3D in fp.model.find_children("*", "GeometryInstance3D", true, false): hidden = hidden and not geometry.is_visible_in_tree()
	return hidden and not fp.overlay.visible and fp.viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED

func run() -> void:
	Engine.max_fps = 60
	root.get_node("GameMenu").force_close_menu(); root.set_meta("ui_presentation", true)
	var graphical := DisplayServer.get_name() != "headless"
	if graphical:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(Vector2i(1200, 1000)); root.size = Vector2i(1200, 1000)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var world = load("res://tools/tests/fixtures/character_test_arena.tscn").instantiate(); root.add_child(world)
	var review: Camera3D = world.get_node("ReviewCamera")
	review.fov = 36; review.position = Vector3(0.65, 1.25, -2.0); review.look_at(Vector3(0, 1.15, 0))
	# Leave the default mask, including the FP layer: visibility must be safe
	# even if a review camera has not been manually configured for the project.
	for variant in [0, 1]:
		var actor: GamePlayer = load("res://scenes/characters/player.tscn").instantiate()
		actor.setup(1, "View isolation", Vector3.ZERO, Color.WHITE, 0, variant)
		world.get_node("Players").add_child(actor)
		actor.set_physics_process(false); actor.survival.set_physics_process(false); actor.weapon.set_physics_process(false)
		actor.get_node("PlayerRagdoll").set_physics_process(false)
		var presentation := actor.body_animator
		var fp := presentation.first_person
		var lamp := OmniLight3D.new(); lamp.light_energy = 0.0; fp.model.add_child(lamp)
		var context := {"held_item": &"m4a1", "grounded": true, "velocity": Vector3.ZERO, "yaw": 0.0, "pitch": 0.0, "journal_phase": 0}
		actor.camera.make_current()
		actor._held_item_type = &"m4a1"; actor.weapon.apply_state(&"m4a1", 12, 0)
		for frame in 35: presentation.update_context(1.0/60, context); await process_frame
		check(fp.model.is_visible_in_tree() and fp.overlay.visible and not view_hidden(fp), "variant %d owner view still draws first-person arms" % variant)
		presentation.set_external_view(true)
		check(view_hidden(fp), "variant %d inspection immediately hides FP meshes, composite and viewport" % variant)
		check(lamp.is_visible_in_tree(), "variant %d hiding view geometry preserves gameplay light children" % variant)
		review.make_current()
		for state in ["rifle", "pistol", "journal"]:
			context.held_item = &"pistol" if state == "pistol" else &"m4a1"
			context.journal_phase = 2 if state == "journal" else 0
			for frame in 40: presentation.update_context(1.0/60, context); await process_frame
			check(view_hidden(fp), "variant %d %s external view cannot reactivate the second pair of arms" % [variant, state])
			check(presentation.model.get_node("Skeleton3D/Body").is_visible_in_tree(), "variant %d %s retains the complete world character" % [variant, state])
			if graphical:
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png(OUT + "%d-%s.png" % [variant, state])
		context.journal_phase = 0; context.held_item = &"m4a1"
		actor.camera.make_current(); presentation.set_external_view(false)
		for frame in 5: presentation.update_context(1.0/60, context); await process_frame
		check(fp.model.is_visible_in_tree() and fp.overlay.visible, "variant %d return to owner view restores FP presentation" % variant)
		review.make_current(); await frames(3)
		check(view_hidden(fp), "variant %d another active camera hides FP even without an inspection flag" % variant)
		actor.camera.make_current()
		actor.debug_free_camera.set_enabled(true)
		await frames(5)
		check(view_hidden(fp), "variant %d real freecam keeps the entire FP rig hidden" % variant)
		actor.debug_free_camera.set_enabled(false)
		await frames(5)
		check(fp.model.is_visible_in_tree() and fp.overlay.visible, "variant %d real freecam return restores hands" % variant)
		presentation.set_external_view(true); fp.set_dead(true); fp.set_dead(false)
		check(view_hidden(fp), "variant %d respawn cannot expose FP while inspecting" % variant)
		actor.queue_free(); await frames(1)
	print("VIEW ISOLATION CHECKS ", checks, " FAILURES ", failures)
	quit(0 if failures == 0 else 1)
