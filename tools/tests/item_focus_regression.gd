extends SceneTree
var checks := 0
var failures := 0
var player: GamePlayer
var focus: PlayerItemFocus
var room: Node3D
func _initialize() -> void:
	ProjectSettings.set_setting("northern_lab/testing/settings_path", "user://item_focus_settings.json")
	run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)
func settle() -> void:
	for frame in 4: await physics_frame
	await process_frame
func aim(point: Vector3) -> void:
	player.head.look_at(point, Vector3.UP)
	player.reset_physics_interpolation()
func meshes_have(item: Node, material: Material) -> bool:
	var found := false
	for mesh: MeshInstance3D in item.find_children("*", "MeshInstance3D", true, false):
		if mesh.mesh == null: continue
		found = true
		if mesh.material_overlay != material: return false
	return found
func spawn_item(kind: StringName, path: String) -> WorldItemPickup:
	var item := load(path).instantiate() as WorldItemPickup
	item.setup_spawn({"item_type": kind, "transform": Transform3D(Basis.IDENTITY, Vector3(0, 1.3, -1.4))})
	if kind in [&"m4a1", &"pistol"]: item.rotate_y(PI * 0.5)
	item.freeze = true
	room.add_child(item)
	item.set_physics_process(false)
	return item
func capture(label: String) -> Image:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png("res://tools/.local/item-focus-%s.png" % label)
	return img
func run() -> void:
	if DisplayServer.get_name() == "headless": push_error("Graphical renderer required"); quit(1); return
	Engine.max_fps = 60
	root.size = Vector2i(960, 540)
	root.get_node("GameMenu").force_close_menu()
	var input := root.get_node("SteamInput"); input.set_process(false); input.set_process_input(false)
	room = load("res://tools/tests/fixtures/item_focus_room.tscn").instantiate()
	root.add_child(room); current_scene = room
	player = load("res://scenes/characters/player.tscn").instantiate()
	player.name = "1"; player.setup(1,"",Vector3.ZERO,Color.WHITE,0)
	room.get_node("Arena/Players").add_child(player)
	player.set_physics_process(false); player.survival.set_physics_process(false)
	focus = player.item_focus
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var cases := {
		&"flashlight": "res://scenes/objects/equipment/flashlight_pickup.tscn",
		&"battery": "res://scenes/objects/items/battery_pickup.tscn",
		&"fuel_can": "res://scenes/objects/items/fuel_can_pickup.tscn",
		&"fuse": "res://scenes/objects/items/fuse_pickup.tscn",
		&"tape": "res://scenes/objects/items/tool_pickup.tscn",
		&"crowbar": "res://scenes/objects/items/tool_pickup.tscn",
		&"pistol": "res://scenes/objects/items/pistol_pickup.tscn",
		&"m4a1": "res://scenes/objects/items/m4a1_pickup.tscn",
		&"kitchen_knife": "res://scenes/objects/items/weapon_pickup.tscn",
		&"pistol_ammo": "res://scenes/objects/items/weapon_pickup.tscn",
		&"rifle_magazine": "res://scenes/objects/items/weapon_pickup.tscn",
	}
	for kind: StringName in cases:
		var item := spawn_item(kind, cases[kind])
		aim(item.global_position)
		await settle()
		check(focus.focused_item == item and PlayerItemFocus.pickup_from(player.get_interaction_target()) == item, "aim highlights and selects %s" % kind)
		check(meshes_have(item, focus.story_material if kind == &"fuse" else focus.common_material), "all model meshes use correct category: %s" % kind)
		if kind in [&"fuel_can", &"m4a1", &"fuse"]: await capture(String(kind))
		aim(Vector3(2.0, 1.3, -1.4)); await settle()
		check(focus.focused_item == null and meshes_have(item, null), "looking away restores original overlays: %s" % kind)
		item.queue_free(); await process_frame; await physics_frame
	var small := spawn_item(&"fuse", cases[&"fuse"])
	aim(small.global_position + Vector3(0.10, 0, 0)); await settle()
	check(PlayerItemFocus.pickup_from(player.interaction_ray.get_collider() as Node) == null and focus.focused_item == small, "small tolerance catches item just beside center ray")
	check(PlayerItemFocus.pickup_from(player.get_interaction_target()) == small, "E uses the same tolerant target as the outline")
	var wall := room.get_node("Occluder") as StaticBody3D
	wall.visible = true; wall.collision_layer = 1
	aim(small.global_position); await settle()
	check(focus.focused_item == null and PlayerItemFocus.pickup_from(player.get_interaction_target()) == null, "wall blocks both highlight and selection")
	await capture("behind-wall")
	wall.visible = false; wall.collision_layer = 0
	aim(small.global_position); await settle()
	small.pickup_enabled = false; await settle()
	check(focus.focused_item == null and meshes_have(small, null), "disabled pickup loses outline")
	small.pickup_enabled = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE; await settle()
	check(focus.focused_item == null, "menu mouse releases outline")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED; await settle()
	small.queue_free(); await process_frame; await settle()
	check(focus.focused_item == null and focus._overlays.is_empty(), "deleted pickup clears highlight safely")
	var can := spawn_item(&"fuel_can", cases[&"fuel_can"])
	aim(can.global_position); await settle()
	# Render proof: one static object, same camera and lighting, on/off overlay.
	focus.set_physics_process(false); focus.set_focus(null)
	var plain := await capture("can-plain")
	focus.set_focus(can)
	var outlined := await capture("can-common")
	var changed := 0
	for y in plain.get_height():
		for x in plain.get_width():
			var a := plain.get_pixel(x,y); var b := outlined.get_pixel(x,y)
			if absf(a.r-b.r)+absf(a.g-b.g)+absf(a.b-b.b) > 0.025: changed += 1
	check(changed > 30 and changed < 14000, "rendered subtle outline changes a narrow set of pixels: %d" % changed)
	for category in [WorldItemPickup.HighlightCategory.STORY, WorldItemPickup.HighlightCategory.SPECIAL]:
		focus.set_focus(null); can.highlight_category = category; focus.set_focus(can)
		check(meshes_have(can, focus.story_material if category == WorldItemPickup.HighlightCategory.STORY else focus.special_material), "story/special colors use authored materials")
		await capture("can-category-%d" % category)
	# Darkness does not suppress the unshaded outline, and depth testing still
	# prevents a forced overlay from exposing an item behind a wall.
	focus.set_focus(null); can.highlight_category = WorldItemPickup.HighlightCategory.COMMON
	room.get_node("Arena/Key").hide(); room.get_node("Arena/Fill").hide()
	var env: Environment = room.get_node("Arena/Environment").environment
	env.background_color = Color(0.01, 0.01, 0.01)
	env.ambient_light_energy = 0.005
	var dark_plain := await capture("dark-plain")
	focus.set_focus(can)
	var dark_outline := await capture("dark-outline")
	var dark_changes := 0
	for y in dark_plain.get_height():
		for x in dark_plain.get_width():
			var a := dark_plain.get_pixel(x,y); var b := dark_outline.get_pixel(x,y)
			if absf(a.r-b.r)+absf(a.g-b.g)+absf(a.b-b.b) > 0.025: dark_changes += 1
	check(dark_changes > 30, "white outline remains visible in darkness: %d pixels" % dark_changes)
	wall.visible = true; wall.collision_layer = 1
	await settle()
	var hidden_outline := await capture("forced-behind-wall")
	focus.set_focus(null)
	var hidden_plain := await capture("wall-plain")
	var hidden_changes := 0
	for y in hidden_plain.get_height():
		for x in hidden_plain.get_width():
			var a := hidden_plain.get_pixel(x,y); var b := hidden_outline.get_pixel(x,y)
			if absf(a.r-b.r)+absf(a.g-b.g)+absf(a.b-b.b) > 0.025: hidden_changes += 1
	check(hidden_changes == 0, "shader depth rejects even a forced outline behind a wall")
	focus.set_focus(null)
	room.queue_free(); await process_frame
	print("ITEM FOCUS CHECKS ", checks, " FAILURES ", failures)
	quit(0 if failures == 0 else 1)
