extends SceneTree
## Compare the actual shell before entering the tree; never rewrite the loading plan.
const Plan = preload("res://scripts/network/level_load_plan.gd")
const Job = preload("res://scripts/network/level_load_job.gd")
const LEVEL = "res://scenes/levels/base_blockout_v03.tscn"
const SHELL = "Floor_0_Base_Blockout/ArcticBase_ExteriorShell"
var checks := 0
var failures := 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ",label)

func world_pose(node: Node3D) -> Transform3D:
	var pose := node.transform
	var parent := node.get_parent()
	while parent != null:
		if parent is Node3D: pose = parent.transform * pose
		parent = parent.get_parent()
	return pose

func snapshot(level: Node) -> Dictionary:
	var data := {}
	var shell := level.get_node(SHELL)
	for node: MeshInstance3D in shell.find_children("*","MeshInstance3D",true,false):
		var materials: Array = []
		for index in node.mesh.get_surface_count():
			materials.append(Plan.stable_value(node.get_active_material(index),{}))
		data[str(shell.get_path_to(node))] = {
			"pose":world_pose(node),"visible":node.visible,"layers":node.layers,
			"bounds":node.mesh.get_aabb(),"surfaces":node.mesh.get_surface_count(),
			"faces":node.mesh.get_faces().size(),"materials":materials,
			"range_begin":node.visibility_range_begin,"range_end":node.visibility_range_end
		}
	return data

func run() -> void:
	var packed: PackedScene = load(LEVEL)
	var native := packed.instantiate()
	var before := snapshot(native)
	check(before.size()>=6,"native level contains all authored exterior mesh nodes")
	for key in before: print("EXTERIOR NATIVE ",key," ",before[key].pose," faces ",before[key].faces)
	native.free()
	var plan: Resource = load(Plan.PLAN_PATH)
	var job := Job.new()
	job.skeletons=plan.get_meta("skeletons",{}).duplicate()
	job.chunks=plan.get_meta("chunks",{})
	job.signatures=plan.get_meta("signatures",{})
	var staged: Node = await job.construct(packed,self)
	var after := snapshot(staged)
	check(before.keys()==after.keys(),"staged load preserves every exterior mesh")
	for key in before:
		check(before[key]==after.get(key),"staged exterior preserves geometry, transforms, materials and visibility: "+key)
		if before[key]!=after.get(key): print("EXTERIOR DIFF before ",before[key]," after ",after.get(key))
	staged.free()
	print("EXTERIOR LOAD CHECKS ",checks," FAILURES ",failures)
	quit(1 if failures else 0)
