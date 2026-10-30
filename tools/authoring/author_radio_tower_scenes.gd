extends SceneTree
const META := "res://assets/models/radio_tower/authoring.json"
func _initialize() -> void: run.call_deferred()
func own(root_node: Node, node: Node) -> void:
	node.owner=root_node
	if not node.scene_file_path.is_empty(): return
	for child in node.get_children(): own(root_node,child)
func save_scene(node: Node,path: String) -> void:
	for child in node.get_children(): own(node,child)
	var scene := PackedScene.new(); assert(scene.pack(node)==OK)
	assert(ResourceSaver.save(scene,path)==OK)
func box(parent: Node3D, size: Vector3, at:=Vector3.ZERO) -> CollisionShape3D:
	var collision := CollisionShape3D.new(); collision.name="CollisionShape3D"
	var shape := BoxShape3D.new(); shape.size=size; collision.shape=shape
	parent.add_child(collision); collision.position=at
	return collision
func marker(parent: Node3D,label: String,at: Vector3) -> void:
	var node := Marker3D.new(); node.name=label; parent.add_child(node); node.position=at
func replacement(parent: Node3D) -> void:
	var presentation := Node3D.new();presentation.name="Replacement";parent.add_child(presentation)
	for info in [["Extract","res://assets/audio/gameplay/metal_0.ogg",-19.0],["Insert","res://assets/audio/gameplay/battery_insert.ogg",-16.0]]:
		var audio := AudioStreamPlayer3D.new();audio.name=info[0];audio.stream=load(info[1]);audio.volume_db=info[2];audio.bus=&"Effects";audio.max_distance=9;audio.unit_size=3
		presentation.add_child(audio)
	var indicator := MeshInstance3D.new();indicator.name="Indicator"
	var lens := BoxMesh.new();lens.size=Vector3(.015,.045,.14);indicator.mesh=lens
	var material := StandardMaterial3D.new();material.resource_local_to_scene=true;material.emission_enabled=true;material.emission_energy_multiplier=1.5
	material.albedo_color=Color(.6,.025,.01);material.emission=material.albedo_color;indicator.material_override=material
	presentation.add_child(indicator);indicator.position=Vector3(.04,.12,0)
	var animation := Animation.new();animation.length=1.4
	var motion := animation.add_track(Animation.TYPE_VALUE);animation.track_set_path(motion,NodePath("../../Visual/module_mount:position"))
	for key in [[0.,Vector3.ZERO],[.42,Vector3(-.3,0,0)],[.72,Vector3(-.3,0,0)],[1.15,Vector3.ZERO],[1.4,Vector3.ZERO]]:animation.track_insert_key(motion,key[0],key[1])
	var visibility := animation.add_track(Animation.TYPE_VALUE);animation.track_set_path(visibility,NodePath("../../Visual/module_mount:visible"));animation.value_track_set_update_mode(visibility,Animation.UPDATE_DISCRETE)
	for key in [[0.,true],[.48,false],[.72,true],[1.4,true]]:animation.track_insert_key(visibility,key[0],key[1])
	for path in ["Indicator:material_override:albedo_color","Indicator:material_override:emission","../Status:modulate"]:
		var track := animation.add_track(Animation.TYPE_VALUE);animation.track_set_path(track,NodePath(path))
		animation.track_insert_key(track,0.,Color(.6,.025,.01));animation.track_insert_key(track,1.15,Color(.6,.025,.01));animation.track_insert_key(track,1.4,Color(.12,.85,.35))
	var text := animation.add_track(Animation.TYPE_VALUE);animation.track_set_path(text,NodePath("../Status:text"));animation.value_track_set_update_mode(text,Animation.UPDATE_DISCRETE)
	animation.track_insert_key(text,0.,"СБОЙ МОДУЛЯ");animation.track_insert_key(text,.01,"ЗАМЕНА МОДУЛЯ");animation.track_insert_key(text,1.4,"СВЯЗЬ АКТИВНА")
	for key in [["Extract",.12],["Insert",1.05]]:
		var track := animation.add_track(Animation.TYPE_AUDIO);animation.track_set_path(track,NodePath(key[0]))
		animation.track_insert_key(track,key[1],{"stream":presentation.get_node(key[0]).stream,"start_offset":0.,"end_offset":0.})
	var ap := AnimationPlayer.new();ap.name="AnimationPlayer";presentation.add_child(ap)
	var library := AnimationLibrary.new();library.add_animation(&"replace",animation);ap.add_animation_library(&"",library)
func run() -> void:
	var data: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(META))
	var deck: float=data.deck_height
	var rig := Node3D.new(); rig.name="RadioTower"; root.add_child(rig)
	var model: Node3D=load("res://assets/models/radio_tower/radio_tower.glb").instantiate()
	model.name="Visual"; rig.add_child(model)
	var geometry := StaticBody3D.new(); geometry.name="StructureCollision"; rig.add_child(geometry)
	var faces := PackedVector3Array()
	var gate_faces := PackedVector3Array()
	for mesh: MeshInstance3D in model.find_children("*","MeshInstance3D",true,false):
		var gate := str(mesh.get_path()).contains("gate_hinge")
		if str(mesh.get_path()).contains("ladder_visual"): continue
		var vertices := mesh.mesh.get_faces()
		for vertex in vertices:
			var point: Vector3=rig.to_local(mesh.to_global(vertex))
			if gate: gate_faces.append(point)
			else: faces.append(point)
	var shape := ConcavePolygonShape3D.new(); shape.backface_collision=true; shape.set_faces(faces)
	var collision := CollisionShape3D.new(); collision.shape=shape; geometry.add_child(collision)
	var gate_body := StaticBody3D.new(); gate_body.name="GateCollision"; rig.add_child(gate_body)
	var gate_shape := ConcavePolygonShape3D.new(); gate_shape.backface_collision=true; gate_shape.set_faces(gate_faces)
	var gate_collision := CollisionShape3D.new(); gate_collision.name="CollisionShape3D"; gate_collision.shape=gate_shape; gate_body.add_child(gate_collision)
	var keypad := RadioTowerInteraction.new(); keypad.name="Keypad"; keypad.role="gate"; keypad.collision_layer=5
	rig.add_child(keypad); keypad.position=Vector3(-4.35,1.45,-.96)
	keypad.gate_collision_path=NodePath("../GateCollision/CollisionShape3D")
	box(keypad,Vector3(.4,.45,.32))
	keypad.add_child(load("res://scenes/ui/radio_keypad.tscn").instantiate())
	var ap := AnimationPlayer.new(); ap.name="AnimationPlayer"; keypad.add_child(ap)
	var animation := Animation.new(); animation.length=1
	var track := animation.add_track(Animation.TYPE_VALUE)
	animation.track_set_path(track,NodePath("../Visual/gate_hinge:rotation:y"))
	animation.track_insert_key(track,0,0.0); animation.track_insert_key(track,1,deg_to_rad(105))
	var library := AnimationLibrary.new(); library.add_animation(&"open",animation); ap.add_animation_library(&"",library)
	var route := LadderRoute.new(); route.name="Ladder"
	marker(route,"Bottom",Vector3(0,.15,.05)); marker(route,"Top",Vector3(0,deck+.15,.05))
	marker(route,"BottomExit",Vector3(0,.12,1.3)); marker(route,"TopExit",Vector3(0,deck+.08,1.25))
	rig.add_child(route)
	for pair in [["LowerAccess",Vector3(0,1.2,.05)],["UpperAccess",Vector3(0,deck+1,1.2)]]:
		var access := StaticBody3D.new(); access.name=pair[0]; access.set_script(load("res://scripts/gameplay/ladder_interaction.gd")); access.collision_layer=4
		rig.add_child(access); access.position=pair[1]; access.route_path=NodePath("../Ladder")
		box(access,Vector3(.8,1.8,.4))
	var socket := RadioTowerInteraction.new(); socket.name="ServiceSocket"; socket.role="socket"; socket.collision_layer=5
	rig.add_child(socket); socket.position=Vector3(1.04,deck+.85,1.1)
	box(socket,Vector3(.45,.5,.5))
	var status := Label3D.new(); status.name="Status"; status.font_size=20; status.pixel_size=.0015; status.outline_size=0
	socket.add_child(status); status.position=Vector3(.04,.25,0); status.rotation.y=-PI/2
	replacement(socket)
	save_scene(rig,"res://scenes/objects/base/radio_tower.tscn")
	var module := RadioTowerInteraction.new(); module.name="RadioModule"; module.role="module"; module.collision_layer=5
	box(module,Vector3(.16,.3,.4))
	module.add_child(load("res://assets/models/radio_tower/radio_module.glb").instantiate())
	save_scene(module,"res://scenes/objects/items/radio_module.tscn")
	var note := RadioTowerInteraction.new(); note.name="RadioAccessNote"; note.role="note"; note.collision_layer=5
	box(note,Vector3(.52,.36,.025))
	var visual := MeshInstance3D.new(); visual.name="Paper"; var plane := BoxMesh.new(); plane.size=Vector3(.52,.36,.012)
	var paper := StandardMaterial3D.new(); paper.albedo_color=Color(.72,.72,.6); paper.roughness=1
	plane.material=paper; visual.mesh=plane; note.add_child(visual)
	var text := Label3D.new(); text.name="Text"; text.font_size=30; text.pixel_size=.00085; text.modulate=Color(.08,.1,.1); text.outline_size=0
	note.add_child(text); text.position.z=.009
	save_scene(note,"res://scenes/objects/base/radio_access_note.tscn")
	rig.queue_free(); module.free(); note.free()
	await process_frame
	print("RADIO TOWER SCENES AUTHORED"); quit()
