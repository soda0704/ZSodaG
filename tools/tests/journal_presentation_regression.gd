extends SceneTree

const SAVE := "user://journal_presentation_regression.cfg"
var failures := 0

func _initialize(): run.call_deferred()

func check(ok: bool, label: String):
	print("PASS " if ok else "FAIL ", label)
	if not ok: failures += 1

func settle():
	for i in 5: await process_frame

func mesh_bounds(mesh_node: MeshInstance3D, frame: Node3D) -> AABB:
	var xf := frame.global_transform.affine_inverse() * mesh_node.global_transform
	var vertices: PackedVector3Array = mesh_node.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var bounds := AABB(xf * vertices[0], Vector3.ZERO)
	for vertex in vertices:
		bounds = bounds.expand(xf * vertex)
	return bounds

func front_surface_depth(mesh_node: MeshInstance3D, frame: Node3D) -> float:
	var xf := frame.global_transform.affine_inverse() * mesh_node.global_transform
	var data := mesh_node.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = data[Mesh.ARRAY_VERTEX]
	var indices := PackedInt32Array()
	if data[Mesh.ARRAY_INDEX] != null:
		indices = data[Mesh.ARRAY_INDEX]
	if indices.is_empty():
		for i in vertices.size(): indices.append(i)
	var depth := -INF
	for i in range(0, indices.size(), 3):
		var hit = Geometry3D.segment_intersects_triangle(Vector3(0,0,0.1), Vector3(0,0,-0.1), xf * vertices[indices[i]], xf * vertices[indices[i+1]], xf * vertices[indices[i+2]])
		if hit != null: depth = maxf(depth, hit.z)
	return depth

func skinned_point(mesh_node: MeshInstance3D, rig: Skeleton3D, vertex: int, frame: Node3D) -> Vector3:
	var data := mesh_node.mesh.surface_get_arrays(0)
	var point := Vector3.ZERO
	for slot in 4:
		var bind_id: int = data[Mesh.ARRAY_BONES][vertex*4+slot]
		var weight: float = data[Mesh.ARRAY_WEIGHTS][vertex*4+slot]
		var bone := mesh_node.skin.get_bind_bone(bind_id)
		point += (rig.get_bone_global_pose(bone) * mesh_node.skin.get_bind_pose(bind_id) * data[Mesh.ARRAY_VERTEX][vertex]) * weight
	return frame.global_transform.affine_inverse() * rig.global_transform * point

func run():
	ProjectSettings.set_setting(BaseGameplayController.TEST_SAVE_PATH_SETTING, SAVE)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	var base = load("res://scenes/levels/Base_Blockout_v03.tscn").instantiate()
	root.add_child(base)
	root.get_node("GameMenu").force_close_menu()
	await settle()
	var player: GamePlayer = get_first_node_in_group("local_player")
	player.set_physics_process(false)
	player.survival.set_physics_process(false)
	player._has_flashlight = true
	player._battery_charge = 0.62
	player._spare_batteries.assign([0.75,0.25])
	player._held_item_type = player.FLASHLIGHT_ITEM
	var journal: QuestJournalUI = root.get_node("QuestJournal")
	check(not journal.is_journal_open() and journal._model_viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED, "closed journal does not render its 3D viewport")
	check(journal._cards.size() == 7 and journal._cards.has(&"kitchen_knife"), "native cards retain all existing inventory item IDs")
	var font := journal.tasks_label.get_theme_font("font")
	var glyphs_ok := true
	for character in "АБВГДЕЁЖЗИЙКЛМНОПРСТУФХЦЧШЩЪЫЬЭЮЯабвгдеёжзийклмнопрстуфхцчшщъыьэюяABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz":
		glyphs_ok = glyphs_ok and font.has_char(character.unicode_at(0))
	check(glyphs_ok and font.resource_path.ends_with("body.ttf"), "body font is scoped to journal and contains Cyrillic and Latin")
	var heading_font := journal.objective_label.get_theme_font("font")
	var heading_glyphs_ok := true
	for character in "АБВГДЕЁЖЗИЙКЛМНОПРСТУФХЦЧШЩЪЫЬЭЮЯабвгдеёжзийклмнопрстуфхцчшщъыьэюяABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz":
		heading_glyphs_ok = heading_glyphs_ok and heading_font.has_char(character.unicode_at(0))
	check(heading_glyphs_ok and heading_font.resource_path.ends_with("headings.otf"), "separate heading font contains Cyrillic and Latin")
	var book: Node3D = journal._model_viewport.get_node("World/JournalPose/ModelAlignment/Model")
	var cover: Node3D = book.get_node("FrontCoverPivot")
	check(cover.has_node("Object_2Cover") and not cover.has_node("Object_4Cover") and not book.has_node("Object_4Body"), "front leather moves while the removed metal rivet is absent")
	check(cover.has_node("InnerCover") and book.has_node("ReadingPage") and cover.has_node("Leaf2Pivot"), "left leaves belong to the front cover, with no second opening")
	var leather: MeshInstance3D = cover.get_node("Object_2Cover")
	var closed_bounds := mesh_bounds(leather, book)
	check(closed_bounds.size.x > 0.20 and closed_bounds.size.x < 0.23 and closed_bounds.size.y > 0.30 and closed_bounds.size.y < 0.32 and closed_bounds.position.z >= 0.0079, "source leather is upright and split along front depth")
	check(front_surface_depth(leather, book) > front_surface_depth(book.get_node("ReadingPage"), book), "closed front cover occludes the reading page")
	var tongues_removed := true
	for leather_node in [leather,book.get_node("Object_2Body")]:
		for uv in leather_node.mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV]:
			tongues_removed = tongues_removed and uv.x >= 0.19999
	check(tongues_removed, "both leather tongues are removed from the atlas geometry, including the stationary back")
	var reading: MeshInstance3D = book.get_node("ReadingPage")
	var reading_bounds := mesh_bounds(reading,book)
	var page_block_bounds := mesh_bounds(book.get_node("Object_3Body"),book)
	check(page_block_bounds.position.x > reading_bounds.position.x and page_block_bounds.end.x < reading_bounds.end.x and page_block_bounds.position.y > reading_bounds.position.y and page_block_bounds.end.y < reading_bounds.end.y, "original page block is fitted beneath the reading sheet without protruding edges")
	var binding: MeshInstance3D = book.get_node("PaperBinding")
	var binding_rig: Skeleton3D = book.get_node("PaperBindingRig")
	var binding_bounds := mesh_bounds(binding,book)
	check(binding.skin != null and binding_rig.get_bone_count() == 2 and binding_bounds.position.x > -0.099 and binding_bounds.end.z < 0.012, "crease folds inside the closed book instead of exposing an exterior white cylinder")
	var leaf_mesh: Mesh = cover.get_node("Leaf0Pivot/Leaf0").mesh
	check(leaf_mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size() > 6, "left leaves retain authored curved geometry")
	check(book.get_node("ReadingPage").mesh.surface_get_arrays(0)[Mesh.ARRAY_NORMAL][0].z > 0.95 and cover.get_node("InnerCover").mesh.surface_get_arrays(0)[Mesh.ARRAY_NORMAL][0].z < -0.95, "paper surfaces face the reader on the correct sides of the book")
	journal.open_journal()
	check(journal.is_journal_open() and journal._phase == journal.PresentationState.OPENING, "opening blocks gameplay from the first frame")
	check(journal._animation.is_playing() and journal._model_viewport.render_target_update_mode == SubViewport.UPDATE_ALWAYS, "opening plays native animation and renders imported 3D model")
	check(not player.crosshair.visible and not player.flashlight._equipped, "held flashlight is stowed and crosshair hidden without changing inventory")
	journal._animation.seek(0.85, true)
	var fore_edge := book.to_local(cover.to_global(Vector3(0.20,0,0)))
	check(fore_edge.z > 0.18 and cover.rotation.y < 0.0, "front cover opens towards the reader without passing through the page block")
	journal._animation.seek(1.25, true)
	check(is_equal_approx(cover.rotation.y, -PI) and mesh_bounds(leather, book).end.x < -0.09, "fully open front cover sits on the left of the stationary back")
	check((cover.basis * Vector3(0,0,-1)).z > 0.99 and journal.get_node("JournalRoot/NotebookPivot/Reveal").modulate.a < 0.01, "inner cover faces the reader before the PNG appears")
	var binding_data := binding.mesh.surface_get_arrays(0)
	var left_vertex := -1
	var right_vertex := -1
	for vertex in binding_data[Mesh.ARRAY_VERTEX].size():
		if binding_data[Mesh.ARRAY_VERTEX][vertex].y > 0.0: continue
		if binding_data[Mesh.ARRAY_WEIGHTS][vertex*4] > 0.999: left_vertex = vertex
		if binding_data[Mesh.ARRAY_WEIGHTS][vertex*4+1] > 0.999: right_vertex = vertex
	var binding_connected := left_vertex >= 0 and right_vertex >= 0
	var left_sheet: MeshInstance3D = cover.get_node("Leaf2Pivot/Leaf2")
	for time in [0.0,0.68,0.85,1.05,1.25]:
		journal._animation.seek(time,true)
		binding_rig.force_update_all_bone_transforms()
		var left_inner := book.to_local(left_sheet.to_global(left_sheet.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX][0]))
		var right_inner := book.to_local(reading.to_global(reading.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX][0]))
		binding_connected = binding_connected and skinned_point(binding,binding_rig,left_vertex,book).distance_to(left_inner) < 0.0001 and skinned_point(binding,binding_rig,right_vertex,book).distance_to(right_inner) < 0.0001
	check(binding_connected, "folded crease stays connected to both reading sheets throughout opening")
	var reveal: Control = journal.get_node("JournalRoot/NotebookPivot/Reveal")
	journal._animation.seek(1.45, true)
	check(reveal.modulate.a > 0.0 and reveal.modulate.a < 1.0 and reveal.scale.is_equal_approx(Vector2.ONE) and absf(reveal.rotation) < 0.0001, "paper blends gradually without resizing or rotating during the handoff")
	check(journal.get_node("JournalRoot/ModelViewport").modulate.a > 0.99, "3D book stays opaque behind the incoming pages")
	journal._animation.seek(1.30, true)
	var alignment: Node3D = book.get_parent()
	var pose: Node3D = alignment.get_parent()
	var settled_pose := pose.transform
	var settled_alignment := alignment.transform
	journal._animation.seek(1.62, true)
	check(pose.transform.is_equal_approx(settled_pose) and alignment.transform.is_equal_approx(settled_alignment), "3D spread remains still throughout the page crossfade")
	var motion_ok := true
	var world: Node3D = journal._model_viewport.get_node("World")
	for frame in 32:
		journal._animation.seek(frame * journal._animation.get_animation("open").length / 31.0, true)
		motion_ok = motion_ok and cover.rotation.y <= 0.0001 and cover.rotation.y >= -PI - 0.0001
		motion_ok = motion_ok and mesh_bounds(leather, world).end.z < -0.03
	check(motion_ok, "cover remains on the opening arc and clear of the camera throughout the clip")
	journal._animation.seek(0.0, true)
	await create_timer(0.35).timeout
	var before := journal._animation.current_animation_position
	journal.close_journal()
	check(journal._phase == journal.PresentationState.CLOSING and absf(before-journal._animation.current_animation_position)<0.02, "closing during lift reverses from current pose")
	await create_timer(0.12).timeout
	before = journal._animation.current_animation_position
	journal.open_journal()
	check(journal._phase == journal.PresentationState.OPENING and absf(before-journal._animation.current_animation_position)<0.02, "reopening during close preserves continuity")
	await create_timer(journal._animation.get_animation("open").length + 0.1).timeout
	check(journal._phase == journal.PresentationState.OPEN and not journal._blocker.visible, "finished opening enables page interactions")
	check(journal._model_viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED, "fully open PNG stops unnecessary 3D rendering")
	journal.set_process(false)
	for card in journal._cards.values(): card.show()
	await settle()
	var ink := journal.get_node("JournalRoot/NotebookPivot/Reveal/Ink")
	var left: Control = ink.get_node("LeftPage")
	var right: Control = ink.get_node("RightPage")
	check(left.position.x >= 145.0 and right.position.x + right.size.x <= 1255.0 and ink.get_node("Footer").position.x >= 145.0, "page text and footer retain generous outer margins")
	check(right.get_node("InventoryScroll/InventoryGrid").get_combined_minimum_size().x <= right.size.x, "all inventory cards fit the narrower right page")
	journal._refresh_inventory()
	journal.set_process(true)
	check(journal._cards[&"flashlight"].visible and journal._cards[&"battery"].visible and not journal._cards[&"pistol"].visible, "inventory visibility and battery counts remain functional")
	journal._select_item(&"battery")
	check(journal.drop_button.visible and journal.inventory_label.text.contains("75%"), "selection still exposes battery charge groups and actions")
	journal._toggle_help()
	check(journal.help_panel.visible and not journal.controls_label.text.is_empty(), "native help page retains controls")
	journal.close_journal()
	check(not journal.help_panel.visible and journal._phase == journal.PresentationState.OPEN, "first close dismisses help before stowing journal")
	journal.close_journal()
	check(journal.is_journal_open(), "closing keeps movement blocked until book is stowed")
	await create_timer(journal._animation.get_animation("open").length / journal.closing_speed + 0.1).timeout
	check(not journal.is_journal_open() and player.crosshair.visible and player.flashlight._equipped, "finished stowing restores HUD and previous held equipment")
	check(player._held_item_type == player.FLASHLIGHT_ITEM and is_equal_approx(player._battery_charge,0.62), "opening and closing do not mutate item ownership or charge")
	journal.open_journal()
	await create_timer(0.2).timeout
	player.survival.dead = true
	await settle()
	check(not journal.is_journal_open() and journal._model_viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED, "death interrupts presentation without leaving input locked")
	player.survival.dead = false
	journal.open_journal()
	journal.force_close()
	check(not journal.is_journal_open() and not journal._animation.is_playing(), "menu and scene transitions can force an immediate clean close")
	root.size = Vector2i(1280,720)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	root.content_scale_size = Vector2i(1280,720)
	await settle()
	journal._layout_book()
	print("LAYOUT 720 ",root.size," visible ",journal.get_viewport().get_visible_rect().size," book ",journal.notebook_pivot.size * journal._fit_scale)
	check(journal.notebook_pivot.size.y * journal._fit_scale.y <= 660.1, "layout fits 720p viewport")
	root.size = Vector2i(2560,1440)
	root.content_scale_size = Vector2i(2560,1440)
	await settle()
	journal._layout_book()
	check(journal._fit_scale.x > 1.0 and journal.notebook_pivot.size.y * journal._fit_scale.y <= 1380.1, "high resolution scales pages and text together")
	var viewport_env = journal._model_viewport.get_node("World/Environment").environment
	root.get_node("GameMenu/GraphicsQuality").apply({"SSR":true,"Fog":true})
	check(not viewport_env.ssr_enabled and not viewport_env.fog_enabled, "world graphics settings cannot add fog or unsupported SSR to UI presentation")
	base.queue_free()
	await settle()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	print("RESULT FAILURES ", failures)
	quit(1 if failures else 0)
