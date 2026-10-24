extends SceneTree
const DIR := "res://scenes/objects/props/"
var failed := false
func _initialize() -> void: run.call_deferred()
func own(root_node: Node, node: Node) -> void:
	node.owner = root_node
	if not node.scene_file_path.is_empty(): return
	for child in node.get_children(): own(root_node, child)
func box(parent: Node3D, label: String, position: Vector3, size: Vector3) -> void:
	var node := CollisionShape3D.new()
	node.name = label
	var shape := BoxShape3D.new()
	shape.size = size
	node.shape = shape
	parent.add_child(node)
	node.position = position
func meshes(model: Node3D) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	for node in model.find_children("*", "MeshInstance3D", true, false): result.append(node)
	return result
func save(root_node: Node, path: String) -> void:
	for child in root_node.get_children(): own(root_node, child)
	root_node.owner = null
	var packed := PackedScene.new()
	assert(packed.pack(root_node) == OK)
	var error := ResourceSaver.save(packed,path.trim_suffix(".tscn") + ".authoring.tscn")
	for attempt in 4:
		if error == OK: break
		OS.delay_msec(200)
		error = ResourceSaver.save(packed,path.trim_suffix(".tscn") + ".authoring.tscn")
	if error == OK:
		error = DirAccess.rename_absolute(path.trim_suffix(".tscn") + ".authoring.tscn", path)
	if error != OK:
		failed = true
		push_error("Cannot save prop scene: " + path)
func make_heavy(label: String, title: String, kind: String, span: float) -> void:
	var prop := HeavyCarryProp.new()
	prop.name = label
	prop.display_name = title
	prop.checkpoint_key = StringName(kind)
	prop.pickup_enabled = false
	prop.draggable = false
	prop.mass = 160 if kind=="sofa" else 70 if kind=="bench" else 420
	prop.linear_damp = 2.0
	prop.angular_damp = 5.0
	prop.push_resistance = 25
	prop.drag_distance = 5
	prop.collision_layer = 1
	prop.collision_mask = 1
	prop.continuous_cd = true
	prop.contact_monitor = true
	prop.max_contacts_reported = 8
	prop.interaction_anchor_path = NodePath("AimAnchor")
	var visual: Node3D = load("res://assets/models/heavy_props/%s.gltf" % kind).instantiate()
	visual.name = "Visual"
	prop.add_child(visual)
	if kind.begins_with("concrete"):
		var points := PackedVector3Array()
		for mesh in meshes(visual):
			for surface in mesh.mesh.get_surface_count():
				var material := mesh.mesh.surface_get_material(surface)
				if material!=null and material.resource_name.begins_with("Volume14"):
					var arrays := mesh.mesh.surface_get_arrays(surface)
					for v: Vector3 in arrays[Mesh.ARRAY_VERTEX]: points.append(mesh.transform*v)
		assert(points.size()>0)
		var shape := ConvexPolygonShape3D.new()
		shape.points = points
		var collision := CollisionShape3D.new()
		collision.name="ConcreteCollision"
		collision.shape=shape
		prop.add_child(collision)
	elif kind=="sofa":
		box(prop,"Seat",Vector3(0,.4,0),Vector3(2.4,.7,1.04))
		box(prop,"Back",Vector3(0,.95,.43),Vector3(2.4,.55,.24))
		for x in [-1.12,1.12]:box(prop,"ArmLeft" if x<0 else "ArmRight",Vector3(x,.73,0),Vector3(.25,.6,1.04))
	else:
		box(prop,"Seat",Vector3(0,.69,0),Vector3(3.2,.17,.64))
		for x in [-1.15,1.15]:box(prop,"LegLeft" if x<0 else "LegRight",Vector3(x,.3,0),Vector3(.22,.6,.53))
	var grips := Node3D.new()
	grips.name="Grips"
	prop.add_child(grips)
	for x in [-span,span]:
		var marker := Marker3D.new()
		marker.name="Left" if x<0 else "Right"
		grips.add_child(marker)
		marker.position=Vector3(x,.75,0)
		for side in ["Left","Right"]:
			var hand:=Marker3D.new()
			hand.name=side+"Hand"
			marker.add_child(hand)
			hand.position=Vector3(0,-.16 if kind=="bench" else -.1 if kind=="sofa" else 0,(-.27 if side=="Left" else .27)*(1 if x<0 else -1))
	var anchor:=Marker3D.new()
	anchor.name="AimAnchor"
	prop.add_child(anchor)
	anchor.position.y=.6
	var sound:Node3D=load("res://scenes/objects/props/heavy_prop_audio.tscn").instantiate()
	prop.add_child(sound)
	var material:String=kind if kind in ["bench","sofa"] else "concrete"
	sound.drag_stream=load("res://assets/audio/gameplay/heavy_props/"+material+"_drag.wav")
	sound.lift_stream=load("res://assets/audio/gameplay/heavy_props/"+material+"_lift.wav")
	sound.place_stream=load("res://assets/audio/gameplay/heavy_props/"+material+"_place.wav")
	if material=="sofa":
		sound.drag_volume_db=-22
		sound.event_volume_db=-15
		sound.drag_noise_radius=7
		sound.impact_noise_radius=11
	elif material=="concrete":
		sound.drag_volume_db=-14
		sound.event_volume_db=-7
		sound.drag_noise_radius=16
		sound.impact_noise_radius=23
		sound.rotation_radius=1.7
	save(prop,DIR+kind+".tscn")
	prop.free()
func workbench() -> void:
	# The workbench now contains editor-authored dimensions, collision, native
	# crafting animation and carry grips. Keep it when rebuilding generic props.
	if not ResourceLoader.exists("res://scenes/objects/crafting/flamethrower_workbench.tscn"):
		failed = true
		push_error("Restore the authored workbench scene before preparing props")
	else:
		print("Keeping authored workbench scene")
func run() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	make_heavy("MovableSofa","Диван","sofa",1.13)
	make_heavy("MovableBench","Скамья","bench",1.55)
	make_heavy("ConcreteJoist","Железобетонная балка","concrete_joist_1",2.65)
	make_heavy("ConcreteJoistAlternate","Железобетонная балка","concrete_joist_2",2.65)
	workbench()
	if not failed: print("HEAVY PROP SCENES READY")
	quit(1 if failed else 0)
