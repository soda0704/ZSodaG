extends SceneTree
## Offline geometry, hinge hierarchy and native animation authoring.
const OUTPUT := "res://scenes/ui/journal/book/inserts.tscn"
const W := .051
const H := .057976
var rig: Node3D
var library := AnimationLibrary.new()
var hinges: Array[String] = []
func _initialize() -> void: run.call_deferred()
func own(node: Node, parent: Node, label: String) -> void:
	parent.add_child(node)
	node.name = label
	node.owner = rig
func material(column: int, row: int) -> ShaderMaterial:
	var result := ShaderMaterial.new()
	result.resource_local_to_scene = true
	result.shader = load("res://assets/shaders/journal_paper_insert.gdshader")
	result.set_shader_parameter("ink_texture", load("res://assets/ui/journal/maps/floor_0.svg"))
	result.set_shader_parameter("panel_rect", Vector4(column/3.0,row/3.0,1.0/3,1.0/3))
	result.set_shader_parameter("source_rect",Vector4(0,0,1,1))
	result.set_shader_parameter("paper_texture",load("res://assets/ui/journal/journal.png"))
	return result
func tile(parent: Node3D, label: String, column: int, row: int, at: Vector3) -> void:
	var mesh := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(W,H)
	mesh.mesh = quad
	mesh.material_override = material(column,row)
	mesh.position = at
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh.layers = 1 | (1<<18)
	own(mesh,parent,label)
func track(clip: Animation, path: String, values: Array, discrete := false) -> void:
	var index := clip.add_track(Animation.TYPE_VALUE)
	clip.track_set_path(index, NodePath(path))
	if discrete: clip.value_track_set_update_mode(index,Animation.UPDATE_DISCRETE)
	for pair in values: clip.track_insert_key(index,pair[0],pair[1])
func run() -> void:
	rig = Node3D.new()
	rig.name = "Inserts"
	rig.set_script(load("res://scripts/ui/journal_inserts.gd"))
	var map := Node3D.new()
	map.position = Vector3(-.0915,.00799,.0005)
	map.visible = false
	own(map,rig,"MapFold")
	for column in 3:
		var segment := Node3D.new()
		segment.position = Vector3((-W/2 if column==0 else W/2 if column==2 else 0),0,.0002*column)
		own(segment,map,"Column%d" % column)
		var center := Node3D.new()
		center.position.x = -W/2 if column==0 else W/2 if column==2 else 0
		own(center,segment,"Center")
		tile(center,"Middle",column,1,Vector3.ZERO)
		for row in [0,2]:
			var hinge := Node3D.new()
			hinge.position = Vector3(0,H/2 if row==0 else -H/2,.00035 if row==0 else .0007)
			own(hinge,center,"Top" if row==0 else "Bottom")
			tile(hinge,"Panel",column,row,Vector3(0,H/2 if row==0 else -H/2,0))
	var turn := Node3D.new()
	turn.visible = false
	own(turn,rig,"TurnPivot")
	var page := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(.21,.303)
	page.mesh = quad
	page.position = Vector3(.105,0,.002)
	page.material_override = material(0,0)
	page.material_override.set_shader_parameter("panel_rect",Vector4(0,0,1,1))
	page.material_override.set_shader_parameter("paper_back",Color(0.89,0.88,0.84,0))
	page.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	page.layers = 1|(1<<18)
	own(page,turn,"Page")
	var unfolded := Animation.new()
	unfolded.length = 1.35
	track(unfolded,"MapFold:visible",[[0,true]],true)
	track(unfolded,"TurnPivot:visible",[[0,false]],true)
	track(unfolded,"MapFold/Column0:rotation:y",[[0,PI],[.08,PI],[.48,0],[1.35,0]])
	track(unfolded,"MapFold/Column2:rotation:y",[[0,-PI],[.4,-PI],[.8,0],[1.35,0]])
	for column in 3:
		track(unfolded,"MapFold/Column%d/Center/Top:rotation:x" % column,[[0,PI],[.75,PI],[1.08,0],[1.35,0]])
		track(unfolded,"MapFold/Column%d/Center/Bottom:rotation:x" % column,[[0,-PI],[1.0,-PI],[1.35,0]])
	library.add_animation("unfold",unfolded)
	var folded: Animation = unfolded.duplicate(true)
	for index in folded.get_track_count():
		var keys: Array = []
		for key in folded.track_get_key_count(index): keys.append([folded.length-folded.track_get_key_time(index,key),folded.track_get_key_value(index,key)])
		for key in range(folded.track_get_key_count(index)-1,-1,-1): folded.track_remove_key(index,key)
		for key in keys: folded.track_insert_key(index,key[0],key[1])
	library.add_animation("fold",folded)
	for backwards in [false,true]:
		var clip := Animation.new()
		clip.length = .72
		track(clip,"TurnPivot:visible",[[0,true],[.71,false]],true)
		track(clip,"MapFold:visible",[[0,false]],true)
		track(clip,"TurnPivot:rotation:y",[[0,-PI if backwards else 0],[.08,-PI if backwards else 0],[.64,0 if backwards else -PI],[.72,0 if backwards else -PI]])
		library.add_animation("page_to_notes" if backwards else "page_to_map",clip)
	var reset := Animation.new()
	track(reset,"TurnPivot:visible",[[0,false]],true)
	track(reset,"MapFold:visible",[[0,false]],true)
	track(reset,"TurnPivot:rotation:y",[[0,0]])
	for path in ["MapFold/Column0:rotation:y","MapFold/Column2:rotation:y"]: track(reset,path,[[0,0]])
	for column in 3:
		for side in ["Top","Bottom"]: track(reset,"MapFold/Column%d/Center/%s:rotation:x" % [column,side],[[0,0]])
	library.add_animation("RESET",reset)
	var player := AnimationPlayer.new()
	player.speed_scale = 2.0
	player.add_animation_library("",library)
	own(player,rig,"AnimationPlayer")
	author_loupe()
	var scene := PackedScene.new()
	scene.pack(rig)
	assert(ResourceSaver.save(scene,OUTPUT)==OK)
	print("AUTHORED fixed-center nine-panel fold and page-turn animations")
	rig.free()
	quit()

func author_loupe() -> void:
	var aim := Node3D.new()
	aim.visible = false
	aim.position = Vector3(-.0915,.00799,0)
	own(aim,rig,"LoupeAim")
	var lift := Node3D.new()
	lift.position.z = .07
	own(lift,aim,"Lift")
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(.17,.18,.16)
	metal.metallic = .85
	metal.roughness = .32
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(.13,.09,.055)
	wood.roughness = .8
	var visual := Node3D.new()
	visual.name = "JournalMagnifier"
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = .023
	torus.outer_radius = .0275
	torus.rings = 48
	torus.ring_segments = 8
	ring.mesh = torus
	ring.rotation.x = PI/2
	ring.material_override = metal
	own(ring,lift,"Rim")
	var handle := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = .0065
	cylinder.bottom_radius = .0075
	cylinder.height = .08
	cylinder.radial_segments = 12
	handle.mesh = cylinder
	handle.rotation.z = PI/4
	handle.position = Vector3(.041,-.051,0)
	handle.material_override = wood
	own(handle,lift,"Handle")
	var lens := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(.048,.048)
	lens.mesh = quad
	var glass := ShaderMaterial.new()
	glass.resource_local_to_scene = true
	glass.shader = load("res://assets/shaders/journal_magnifier.gdshader")
	glass.set_shader_parameter("magnification",2.0)
	glass.set_shader_parameter("ink_texture",load("res://assets/ui/journal/maps/floor_0.svg"))
	lens.material_override = glass
	own(lens,lift,"Lens")
	var grip := Marker3D.new()
	grip.transform = str_to_var("Transform3D(-0.24958633, 0.27752346, -0.9277324, 0.45061567, 0.8812877, 0.14240122, 0.85711884, -0.38250938, -0.34501353, 0.034, -0.044, 0)")
	grip.basis = Basis(Vector3(0,0,1),PI/4)*grip.basis
	grip.position = Vector3(.0658,-.0758,-.008)
	own(grip,lift,"RightGrip")
	for mesh in lift.find_children("*","MeshInstance3D",true,false):
		mesh.layers = 1|(1<<18)
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for part in [ring,handle,lens]:
		part.owner = null
		lift.remove_child(part)
		visual.add_child(part)
		part.owner = visual
	visual.visible = false
	var visual_scene := PackedScene.new()
	visual_scene.pack(visual)
	assert(ResourceSaver.save(visual_scene,"res://scenes/ui/journal/book/magnifier.tscn")==OK)
	visual.free()
	var loupe_library := AnimationLibrary.new()
	for raising in [true,false]:
		var clip := Animation.new()
		clip.length = .28
		track(clip,"LoupeAim/Lift:position",[[0,Vector3(.18,-.16,.01) if raising else Vector3(0,0,.07)],[.28,Vector3(0,0,.07) if raising else Vector3(.18,-.16,.01)]])
		loupe_library.add_animation("raise" if raising else "lower",clip)
	var animator := AnimationPlayer.new()
	animator.add_animation_library("",loupe_library)
	own(animator,rig,"LoupeAnimation")
