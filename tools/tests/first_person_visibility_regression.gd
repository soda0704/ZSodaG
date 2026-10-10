extends SceneTree
## Rendered shadow proof and owner body isolation, with both native characters.
var checks:=0
var failures:=0
func _initialize(): run.call_deferred()
func check(ok: bool,label: String):
	checks+=1
	if not ok: failures+=1
	print("PASS " if ok else "FAIL ",label)
func settle():
	for i in 12: await process_frame
	await RenderingServer.frame_post_draw
func run():
	if DisplayServer.get_name()=="headless": quit(1); return
	root.size=Vector2i(1280,720); Engine.max_fps=60; root.get_node("GameMenu").force_close_menu()
	var arena=load("res://tools/tests/fixtures/character_test_arena.tscn").instantiate(); root.add_child(arena)
	for light: DirectionalLight3D in arena.find_children("*","DirectionalLight3D",true,false): light.rotation_degrees=Vector3(-65,0,0); light.shadow_enabled=true
	for id in [0,1]:
		var actor: GamePlayer=load("res://scenes/characters/player.tscn").instantiate(); actor.name="1"; actor.setup(1,"",Vector3.ZERO,Color.WHITE,0,id); arena.get_node("Players").add_child(actor)
		actor.set_physics_process(false); actor.survival.set_physics_process(false); actor.weapon.set_physics_process(false); actor.head.rotation.x=-1.20; actor.camera.current=true
		for i in 20: actor.body_animator.update_context(1.0/60,{"grounded":true,"pitch":-1.20}); await process_frame
		var hidden:=true
		for mesh: MeshInstance3D in actor.body_animator.model.find_children("*","MeshInstance3D",true,false): hidden=hidden and mesh.cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		check(hidden,"variant %d complete owner body cannot draw visible head, shoulder or torso"%id)
		var actual_mask:=actor.camera.cull_mask
		check(actual_mask&(1<<19)==0 and actor.body_animator.first_person.view_camera.cull_mask==1<<19,"variant %d camera separates FP and world geometry"%id)
		actor.body_animator.first_person._disabled=true; actor.body_animator.first_person.overlay.hide(); actor.body_animator.first_person.viewport.render_target_update_mode=SubViewport.UPDATE_DISABLED
		actor.camera.cull_mask=1; await settle(); var without_shadow:=root.get_texture().get_image()
		actor.camera.cull_mask=actual_mask; await settle(); var with_shadow:=root.get_texture().get_image()
		var changed:=0
		for y in range(0,with_shadow.get_height(),4):
			for x in range(0,with_shadow.get_width(),4):
				var before:=without_shadow.get_pixel(x,y); var after:=with_shadow.get_pixel(x,y)
				if before.r-after.r>.08: changed+=1
		check(changed>200,"variant %d own body produces a real rendered ground shadow (%d samples)"%[id,changed])
		with_shadow.save_png("res://tools/.local/owner-shadow-%d.png"%id)
		actor.queue_free(); await process_frame
	print("VISIBILITY CHECKS ",checks," FAILURES ",failures); quit(1 if failures else 0)
