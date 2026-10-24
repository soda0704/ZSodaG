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
	player.add_animation_library("",library)
	own(player,rig,"AnimationPlayer")
	var scene := PackedScene.new()
	scene.pack(rig)
	assert(ResourceSaver.save(scene,OUTPUT)==OK)
	print("AUTHORED fixed-center nine-panel fold and page-turn animations")
	rig.free()
	quit()
