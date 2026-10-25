extends SceneTree
## Offline authoring: one pasted paper sheet and native page-turn clips.
## The existing magnifier, hand contacts and character animations are preserved.
const OUTPUT := "res://scenes/ui/journal/book/inserts.tscn"
const DURATION := 0.44
var rig: Node3D

func _initialize() -> void: run.call_deferred()

func own(node: Node, parent: Node, label: String) -> void:
	parent.add_child(node)
	node.name = label
	node.owner = rig

func paper_mesh(size: Vector2, bent: bool, corner_radius := 0.0) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var X := 64 if corner_radius > 0.0 else 20
	var Y := 96 if corner_radius > 0.0 else 12
	for row in Y + 1:
		for column in X + 1:
			var uv := Vector2(float(column)/X, float(row)/Y)
			var point := (uv-Vector2(.5,.5))*size
			if corner_radius > 0.0:
				var corner := size*.5-Vector2.ONE*corner_radius
				var outer := point.abs()-corner
				if outer.x>0 and outer.y>0 and outer.length()>corner_radius:
					point = (corner+outer.normalized()*corner_radius)*point.sign()
					uv = point/size+Vector2(.5,.5)
			# The left edge is glued down; the free edge lifts only a few mm.
			var lift := (0.0014 * uv.x * uv.x + 0.0007 * pow(uv.x * uv.y, 3)) if bent else 0.0
			vertices.append(Vector3((uv.x-.5)*size.x, (.5-uv.y)*size.y, lift))
			normals.append(Vector3.BACK)
			uvs.append(uv)
	for row in Y:
		for column in X:
			var a := row*(X+1)+column
			indices.append_array(PackedInt32Array([a,a+1,a+X+1,a+1,a+X+2,a+X+1]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

func paper_material() -> ShaderMaterial:
	var result := ShaderMaterial.new()
	result.resource_local_to_scene = true
	result.shader = load("res://assets/shaders/journal_paper_insert.gdshader")
	result.set_shader_parameter("ink_texture",load("res://assets/ui/journal/maps/floor_0.svg"))
	result.set_shader_parameter("back_ink_texture",load("res://assets/ui/journal/maps/floor_0.svg"))
	result.set_shader_parameter("paper_texture",load("res://assets/ui/journal/journal.png"))
	return result

func track(clip: Animation, path: String, values: Array, discrete := false) -> void:
	var index := clip.add_track(Animation.TYPE_VALUE)
	clip.track_set_path(index, NodePath(path))
	if discrete: clip.value_track_set_update_mode(index,Animation.UPDATE_DISCRETE)
	for pair in values: clip.track_insert_key(index,pair[0],pair[1])

func run() -> void:
	rig = load(OUTPUT).instantiate()
	# Replace only presentation parts owned by this authoring tool.
	for label in ["MapFold", "MapSheet", "TurnPivot", "AnimationPlayer"]:
		var old := rig.get_node_or_null(NodePath(label))
		if old != null: old.free()
	var sheet := Node3D.new()
	sheet.position = Vector3(-.0915,.00799,.0010)
	sheet.visible = false
	own(sheet,rig,"MapSheet")
	var shadow := MeshInstance3D.new()
	var shadow_quad := QuadMesh.new()
	shadow_quad.size = Vector2(.164,.1785)
	shadow.mesh = shadow_quad
	shadow.position = Vector3(.0035,-.0030,-.0007)
	var shade := ShaderMaterial.new()
	shade.shader = load("res://assets/shaders/journal_paper_shadow.gdshader")
	shadow.material_override = shade
	shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	shadow.layers = 1 | (1<<18)
	own(shadow,sheet,"ContactShadow")
	var paper := MeshInstance3D.new()
	paper.mesh = paper_mesh(Vector2(.153,.166519),true)
	paper.material_override = paper_material()
	paper.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	paper.layers = 1 | (1<<18)
	own(paper,sheet,"Paper")
	var turn := Node3D.new()
	turn.visible = false
	own(turn,rig,"TurnPivot")
	var page := MeshInstance3D.new()
	# Match the original book's paper, not the larger UI projection rectangle.
	page.mesh = paper_mesh(Vector2(.186,.278),false,.006)
	page.position = Vector3(-.102,0,0)
	page.material_override = paper_material()
	page.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	page.layers = 1 | (1<<18)
	own(page,turn,"Page")
	var library := AnimationLibrary.new()
	for backwards in [false,true]:
		var clip := Animation.new()
		clip.length = DURATION
		track(clip,"TurnPivot:visible",[[0,true],[DURATION,false]],true)
		# The insert stays below the turning leaf. Its raised edge is revealed
		# only after the leaf lifts, and covered before that leaf settles back.
		track(clip,"MapSheet:visible",[[0,backwards],[.10,true],[.34,not backwards],[DURATION,not backwards]],true)
		var angles := []
		var curls := []
		var heights := []
		for sample in 25:
			var t := sample/24.0
			var eased := t*t*(3.0-2.0*t)
			angles.append([t*DURATION,PI*(1.0-eased if backwards else eased)])
			var lift := pow(sin(t*PI),2)
			curls.append([t*DURATION,lift*.012])
			heights.append([t*DURATION,lerpf(-.0040,-.0020,eased) + lift*.008 if backwards else lerpf(-.0020,-.0040,eased) + lift*.008])
		track(clip,"TurnPivot:rotation:y",angles)
		track(clip,"TurnPivot:position:z",heights)
		track(clip,"TurnPivot/Page:material_override:shader_parameter/curl_amount",curls)
		library.add_animation("page_to_notes" if backwards else "page_to_map",clip)
	var reset := Animation.new()
	track(reset,"TurnPivot:visible",[[0,false]],true)
	track(reset,"MapSheet:visible",[[0,false]],true)
	track(reset,"TurnPivot:rotation:y",[[0,0.0]])
	track(reset,"TurnPivot:position:z",[[0,-.0020]])
	track(reset,"TurnPivot/Page:material_override:shader_parameter/curl_amount",[[0,0.0]])
	library.add_animation("RESET",reset)
	var player := AnimationPlayer.new()
	player.add_animation_library("",library)
	own(player,rig,"AnimationPlayer")
	var packed := PackedScene.new()
	assert(packed.pack(rig)==OK)
	assert(ResourceSaver.save(packed,OUTPUT)==OK)
	rig.free()
	print("AUTHORED pasted curved map, contact shadow and two 0.44-second page turns")
	quit()
