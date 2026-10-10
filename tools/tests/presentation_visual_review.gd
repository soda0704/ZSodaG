extends SceneTree
## Rendered production Player review, with animation trees and IK left enabled.
const OUT:="res://tools/.local/presentation-review/"
var actor: GamePlayer
var arena: Node3D
var failures:=0

func _initialize() -> void: run.call_deferred()

func wait_frames(count: int) -> void:
	for i in count: await process_frame

func capture(label: String) -> void:
	await wait_frames(8)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT+label+".png")
	print("CAPTURE ",label)

func run() -> void:
	Engine.max_fps=60; root.size=Vector2i(1280,720); root.position=Vector2i(100,100)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	root.get_node("GameMenu").force_close_menu()
	var input_service=root.get_node("SteamInput"); input_service.set_process(false); input_service.set_process_input(false); input_service.native_input_available=false
	for action in InputMap.get_actions(): InputMap.action_erase_events(action)
	arena=load("res://tools/tests/fixtures/character_test_arena.tscn").instantiate(); root.add_child(arena)
	arena.get_node("Environment").environment.adjustment_enabled=false
	for id in [0,1]:
		actor=load("res://scenes/characters/player.tscn").instantiate()
		actor.name="1"; actor.setup(1,"",Vector3(0,0.02,0),Color.WHITE,0,id); arena.get_node("Players").add_child(actor)
		actor.set_physics_process(false); actor.survival.set_physics_process(false); actor.weapon.set_physics_process(false)
		actor.set_process_unhandled_input(false); actor.camera.current=true
		for kind in [&"",&"pistol",&"m4a1",&"flashlight",&"kitchen_knife",&"fuse",&"fuel_can"]:
			actor._held_item_type=kind; actor.weapon.apply_state(kind,12,0)
			actor._has_flashlight=true; actor._battery_charge=1; actor._flashlight_enabled=kind==&"flashlight"; actor._refresh_equipment_visuals()
			var context:={"held_item":kind,"grounded":true,"velocity":Vector3.ZERO,"pitch":0.0,"yaw":0.0}
			for i in 30: actor.body_animator.update_context(1.0/60,context); await process_frame
			await capture("fp-%d-%s"%[id,"empty" if kind==&"" else kind])
			if kind in [&"pistol",&"m4a1"]:
				context.aiming=true
				for i in 30: actor.body_animator.update_context(1.0/60,context); await process_frame
				await capture("fp-%d-%s-ads"%[id,kind]); context.aiming=false
				actor.body_animator.weapon_effect(kind,true)
				await wait_frames(38); await capture("fp-%d-%s-reload"%[id,kind])
				actor.body_animator.cancel_weapon_action()
		var journal: QuestJournalUI=root.get_node("QuestJournal")
		journal.open_journal()
		for i in 70:
			actor.body_animator.update_context(1.0/60,{"held_item":actor._held_item_type,"grounded":true,"journal_phase":actor._journal_phase})
			if i==18: await capture("fp-%d-journal-opening"%id)
			await process_frame
		await capture("fp-%d-journal-reading"%id)
		journal.close_journal()
		for i in 55: actor.body_animator.update_context(1.0/60,{"grounded":true,"journal_phase":actor._journal_phase}); await process_frame
		await capture("fp-%d-journal-closed"%id)
		actor.camera.current=false; arena.get_node("ReviewCamera").current=true
		actor.body_animator.set_external_view(true)
		var camera: Camera3D=arena.get_node("ReviewCamera"); camera.position=Vector3(0.65,1.4,-2.1); camera.look_at(Vector3(0,1.2,0)); camera.cull_mask=1|(1<<18)
		for pose in ["empty","rifle","pistol","rifle-up","rifle-down","journal","crouch","air"]:
			var kind:=&"m4a1" if pose.begins_with("rifle") else &"pistol" if pose=="pistol" else &""
			actor.weapon.apply_state(kind,12,0)
			var context:={"held_item":kind,"grounded":pose!="air","crouching":pose=="crouch","velocity":Vector3.ZERO,"pitch":1.48 if pose=="rifle-up" else -1.48 if pose=="rifle-down" else 0.0,"yaw":0.0,"journal_phase":2 if pose=="journal" else 0}
			for i in 55: actor.body_animator.update_context(1.0/60,context); await process_frame
			# Owner TP equipment is a distinct visual instance, driven by shared state.
			actor.body_animator._sync_world_items(kind,int(context.journal_phase))
			await capture("tp-%d-%s"%[id,pose])
		journal.force_close(); actor.queue_free(); await process_frame
	print("PRESENTATION VISUAL REVIEW COMPLETE")
	quit(failures)
