extends SceneTree
## Rebuild after structural edits. Run with the editor binary and Forward+.
const OUT := "res://assets/environments/base_gi/"
const ZONES := [
	["Entrance",0,Vector3(-27,3,0),Vector3(38,12,26),2],
	["Hub",0,Vector3(0,4,0),Vector3(24,12,62),3],
	["Living",0,Vector3(23,3,2),Vector3(30,12,32),2],
	["Control",1,Vector3(-30,-14,0),Vector3(88,12,60),3],
	["LifeSupport",2,Vector3(-30,-32,0),Vector3(98,16,62),3],
	["Trials",3,Vector3(-24,-50,-3),Vector3(48,14,42),3],
	["Containment",4,Vector3(-18,-68,-14),Vector3(68,14,64),3],
	["Expedition",5,Vector3(-20,-86,-17),Vector3(76,16,68),3]
]
const FLOORS := ["Floor_0_Base_Blockout","Floor_Minus1_Control_Security_Blockout","Floor_Minus2_Life_Support_Blockout","Floor_Minus3_Trials_Observation_Blockout","Floor_Minus4_Biocontainment_Blockout","Floor_Minus5_Expedition_Shaft_Blockout"]

func _initialize() -> void: run.call_deferred()

func floor_transform(floor_name:String) -> Transform3D:
	var scene:=FileAccess.get_file_as_string("res://scenes/levels/Base_Blockout_v03.tscn")
	var expression:=RegEx.new()
	expression.compile('(?m)^\\[node name="'+floor_name+'" parent="\\."[^\\n]*\\]\\r?\\ntransform = ([^\\r\\n]+)')
	var found:=expression.search(scene)
	if found!=null:
		var value:Variant=str_to_var(found.get_string(1))
		if value is Transform3D:return value
	return Transform3D.IDENTITY

func prepare(node: Node, moving := false) -> void:
	moving = moving or node is RigidBody3D or node is CharacterBody3D or node is MedicalCorpse or str(node.name) in ["ClosedPreview","OpenPreview","ClosedState","OpenState","DoorLeaves","Leaf","DoorPanel"]
	if node is GeometryInstance3D:
		node.gi_mode = GeometryInstance3D.GI_MODE_DISABLED if moving else GeometryInstance3D.GI_MODE_STATIC
	# No live scripts, door animation or gameplay state during the geometry bake.
	node.set_script(null)
	for child in node.get_children(): prepare(child,moving)

func run() -> void:
	if DisplayServer.get_name()=="headless":
		push_error("VoxelGI bake requires the Forward+ renderer");quit(1);return
	root.get_node("GameMenu").force_close_menu()
	Engine.max_fps=30
	var holder:=Node3D.new();holder.name="WorldIndirectLighting"
	holder.set_script(load("res://scripts/levels/world_indirect_lighting.gd"))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var only_zone:=""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--zone="):only_zone=argument.trim_prefix("--zone=")
	for zone in ZONES:
		if "--entrance-only" in OS.get_cmdline_user_args() and zone[0]!="Entrance":continue
		var probe:=VoxelGI.new()
		probe.name=zone[0];probe.position=zone[2];probe.size=zone[3];probe.subdiv=zone[4]
		var path:=OUT+str(probe.name).to_snake_case()+".res"
		if "--retune" in OS.get_cmdline_user_args():
			var existing:=load(path) as VoxelGIData
			existing.energy=0.7
			existing.interior=zone[1]!=0
			if ResourceSaver.save(existing,path,ResourceSaver.FLAG_COMPRESS)!=OK:quit(1);return
			print("RETUNED ",probe.name," cells=",existing.get_octree_cells().size()," interior=",existing.interior)
			probe.data=existing
			holder.add_child(probe);probe.owner=holder
			continue
		if not only_zone.is_empty() and only_zone!=zone[0]:
			probe.data=load(path)
			holder.add_child(probe);probe.owner=holder
			continue
		# Load one floor without the existing GI, terrain or gameplay. Previously
		# baked probes stay outside the tree, so baking cannot trigger GI updates.
		var floor_root:=load("res://scenes/levels/"+FLOORS[zone[1]]+".tscn").instantiate() as Node3D
		prepare(floor_root)
		floor_root.transform=floor_transform(FLOORS[zone[1]])
		root.add_child(floor_root)
		root.add_child(probe)
		for frame in 8:await process_frame
		print("BAKING ",probe.name," size=",probe.size)
		probe.bake(floor_root)
		if probe.data==null or probe.data.get_octree_cells().is_empty():
			push_error("Empty voxel data for "+str(probe.name));quit(1);return
		var data:=probe.data as VoxelGIData
		data.interior=zone[1]!=0;data.use_two_bounces=true
		data.energy=0.7;data.propagation=0.55;data.bias=0.5;data.normal_bias=0.5
		if ResourceSaver.save(data,path,ResourceSaver.FLAG_COMPRESS)!=OK:quit(1);return
		data.take_over_path(path)
		print("BAKED ",probe.name," cells=",data.get_octree_cells().size())
		root.remove_child(probe)
		holder.add_child(probe);probe.owner=holder
		floor_root.queue_free()
		for frame in 3: await process_frame
	var packed:=PackedScene.new()
	if packed.pack(holder)!=OK:quit(1);return
	var destination:="res://tools/.local/entrance_gi.tscn" if "--entrance-only" in OS.get_cmdline_user_args() else "res://scenes/levels/world_indirect_lighting.tscn"
	if ResourceSaver.save(packed,destination)!=OK:quit(1);return
	print("GI BAKE COMPLETE ",destination)
	holder.free()
	for frame in 3:await process_frame
	quit()
