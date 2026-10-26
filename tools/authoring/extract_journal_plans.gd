extends SceneTree
## Offline survey of authored geometry. Never runs in the game.
const ROOTS := ["Floor_0_Base_Blockout", "Floor_Minus1_Control_Security_Blockout", "Floor_Minus2_Life_Support_Blockout", "Floor_Minus3_Trials_Observation_Blockout", "Floor_Minus4_Biocontainment_Blockout", "Floor_Minus5_Expedition_Shaft_Blockout"]
func _initialize() -> void:
	ProjectSettings.set_setting(BaseGameplayController.TEST_SAVE_PATH_SETTING, "user://journal_plan_authoring.cfg")
	run.call_deferred()
func run() -> void:
	var base = load("res://scenes/levels/base_blockout_v03.tscn").instantiate()
	root.add_child(base)
	for frame in 12: await physics_frame
	var plans: Array = []
	for key in ROOTS:
		var floor_root: Node3D = base.get_node(key)
		var plan := {"root": key, "elevation": floor_root.global_position.y, "lines": [], "floors": []}
		for node in floor_root.find_children("*", "GeometryInstance3D", true, false):
			if node is MeshInstance3D and node.mesh != null:
				survey_mesh(node.mesh, node.global_transform, plan)
			elif node is CSGShape3D and node.is_root_shape():
				var meshes: Array = node.get_meshes()
				if meshes.size() == 2: survey_mesh(meshes[1], node.global_transform * meshes[0], plan)
		plans.append(plan)
		print("SURVEY ", key, " floor triangles ", plan.floors.size(), " wall segments ", plan.lines.size())
	var cave = base.get_node("Cave_Day7")
	var route: Path3D = cave.get_node("AuthoredRoute")
	var points: Array = []
	for point in route.curve.get_baked_points():
		var p: Vector3 = route.to_global(point)
		points.append([p.x, p.z])
	plans.append({"root": "Cave_Day7", "elevation": -162, "route": points})
	FileAccess.open("res://tools/.local/journal_plans.json", FileAccess.WRITE).store_string(JSON.stringify(plans))
	base.queue_free()
	await process_frame
	quit()
func survey_mesh(mesh: Mesh, pose: Transform3D, plan: Dictionary) -> void:
	var bounds: AABB = pose * mesh.get_aabb()
	var level: float = plan.elevation
	if bounds.position.y > level + 1.2 or bounds.end.y < level - .5: return
	var faces: PackedVector3Array = mesh.get_faces()
	for i in range(0, faces.size(), 3):
		var p := [pose * faces[i], pose * faces[i+1], pose * faces[i+2]]
		var low: float = minf(p[0].y, minf(p[1].y, p[2].y))
		var high: float = maxf(p[0].y, maxf(p[1].y, p[2].y))
		if low > level + 1.2 or high < level - .5: continue
		if high < level + .35 and low > level - .5 and high - low < .12:
			var area: float = (p[1] - p[0]).cross(p[2] - p[0]).length()
			if area > .03: plan.floors.append([[p[0].x,p[0].z],[p[1].x,p[1].z],[p[2].x,p[2].z]])
		var cut: Array = []
		for edge in 3:
			var a: Vector3 = p[edge]
			var b: Vector3 = p[(edge+1)%3]
			var h := level + 1.1
			if (a.y < h) != (b.y < h):
				var v := a.lerp(b, (h-a.y)/(b.y-a.y))
				cut.append([v.x,v.z])
		if cut.size() == 2: plan.lines.append(cut)
