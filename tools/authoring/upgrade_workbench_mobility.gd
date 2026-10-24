extends SceneTree
## One-time upgrade of the user's edited workbench. Does not regenerate the base.
const BENCH := "res://scenes/objects/crafting/flamethrower_workbench.tscn"
const BASE := "res://scenes/levels/Base_Blockout_v03.tscn"
func _initialize() -> void: run.call_deferred()
func owned(root_node: Node, child: Node) -> void:
	child.owner = root_node
	if not child.scene_file_path.is_empty(): return
	for nested in child.get_children(): owned(root_node, nested)
func scene_transform(value: String) -> Transform3D:
	return str_to_var(value)
func scene_text(value: Transform3D) -> String:
	return var_to_str(value)
func run() -> void:
	var source_uid := ResourceLoader.get_resource_uid(BENCH)
	var table: HeavyCarryProp = load(BENCH).instantiate()
	if table.has_meta("mobility_authored"):
		print("Workbench already upgraded; keeping editor changes.")
		table.free()
		quit()
		return
	var source := FileAccess.get_file_as_string(BASE)
	var section := source.find('[node name="FlamethrowerWorkbench" parent="."')
	assert(section >= 0)
	var start := source.find("transform = ", section) + 12
	var finish := source.find("\n", start)
	var authored := scene_transform(source.substr(start, finish - start))
	var orientation := authored.basis.orthonormalized()
	var stretch := orientation.inverse() * authored.basis
	# Rigid bodies require unit scale. Keep the exact edited appearance by
	# baking stretch/shear into the native visual and collision resources.
	for child in table.get_children():
		if child is CollisionShape3D:
			var shape: BoxShape3D = child.shape
			assert(shape != null)
			var box := AABB(-shape.size * .5, shape.size)
			var points := PackedVector3Array()
			for corner in 8: points.append(stretch * (child.transform * box.get_endpoint(corner)))
			var hull := ConvexPolygonShape3D.new()
			hull.points = points
			child.shape = hull
			child.transform = Transform3D.IDENTITY
		elif child is Node3D:
			child.transform = Transform3D(stretch, Vector3.ZERO) * child.transform
	table.mass = 90
	table.freeze = true
	table.physics_material_override = PhysicsMaterial.new()
	table.physics_material_override.friction = .2
	table.pickup_enabled = false
	table.draggable = false
	table.linear_damp = 2
	table.angular_damp = 5
	table.contact_monitor = true
	table.max_contacts_reported = 8
	table.checkpoint_key = &"equipment_workbench"
	table.display_name = "Верстак"
	table.interaction_anchor_path = NodePath("AimAnchor")
	table.drag_distance = 5
	table.interaction_distance = 3
	table.push_resistance = 25
	table.upright_strength = 26
	table.upright_damping = 9
	var grips := Node3D.new()
	grips.name = "Grips"
	table.add_child(grips)
	for side in [-1, 1]:
		var grip := Marker3D.new()
		grip.name = "Left" if side < 0 else "Right"
		grips.add_child(grip)
		grip.position = stretch * Vector3(side * 1.15, .95, 0)
		for hand in [-1, 1]:
			var marker := Marker3D.new()
			marker.name = "LeftHand" if hand < 0 else "RightHand"
			grip.add_child(marker)
			marker.position = stretch * Vector3(0, -.09, hand * side * .24)
	var aim := Marker3D.new()
	aim.name = "AimAnchor"
	aim.position = stretch * Vector3(0, .8, 0)
	table.add_child(aim)
	var audio: Node3D = load("res://scenes/objects/props/heavy_prop_audio.tscn").instantiate()
	table.add_child(audio)
	for kind in ["drag", "lift", "place"]:
		audio.set(kind + "_stream", load("res://assets/audio/gameplay/heavy_props/bench_" + kind + ".wav"))
	table.set_meta("mobility_authored", 1)
	var minimum_y := INF
	for shape in table.get_children():
		if shape is CollisionShape3D:
			for point in (shape.shape as ConvexPolygonShape3D).points:
				minimum_y = minf(minimum_y, (orientation * point).y + authored.origin.y)
	# Match this floor's authored top, leaving a tiny physical clearance.
	if minimum_y < -.009: authored.origin.y += -.009 - minimum_y
	var replacement := scene_text(Transform3D(orientation, authored.origin))
	source = source.substr(0, start) + replacement + source.substr(finish)
	for child in table.get_children(): owned(table, child)
	var packed := PackedScene.new()
	assert(packed.pack(table) == OK)
	var temporary := BENCH.trim_suffix(".tscn") + ".mobility.tscn"
	var result := ResourceSaver.save(packed, temporary)
	for attempt in 4:
		if result == OK: break
		OS.delay_msec(200)
		result = ResourceSaver.save(packed, temporary)
	assert(result == OK)
	if source_uid != ResourceUID.INVALID_ID:
		assert(ResourceSaver.set_uid(temporary, source_uid) == OK)
	assert(DirAccess.rename_absolute(temporary, BENCH) == OK)
	var file := FileAccess.open(BASE, FileAccess.WRITE)
	assert(file != null)
	file.store_string(source)
	file.close()
	print("WORKBENCH MOBILITY: retained edited X/Z and exact stretch; grounded root ", replacement)
	table.free()
	quit()
