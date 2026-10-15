extends SceneTree
## Bake a thin tape ribbon into a normal mesh resource; never runs in gameplay.
func _initialize() -> void:
	var section := PackedVector2Array([
		Vector2(-0.065,0.005), Vector2(-0.065,0.051),
		Vector2(-0.031,0.005), Vector2(-0.031,0.051),
	])
	for sample in 24:
		section.append(Vector2.from_angle(TAU * sample / 24.0) * 0.017)
	var outline := Geometry2D.convex_hull(section)
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var length := 0.0
	for index in outline.size()-1:
		var a := outline[index]
		var b := outline[index+1]
		var next_length := length + a.distance_to(b)
		var points := [Vector3(a.x,a.y,-0.006),Vector3(b.x,b.y,-0.006),Vector3(b.x,b.y,0.006),Vector3(a.x,a.y,0.006)]
		var uv := [Vector2(length,0),Vector2(next_length,0),Vector2(next_length,1),Vector2(length,1)]
		for corner in [0,1,2,0,2,3]:
			surface.set_uv(uv[corner])
			surface.add_vertex(points[corner])
		length = next_length
	surface.generate_normals()
	var mesh := surface.commit()
	var error := ResourceSaver.save(mesh,"res://assets/models/items/flashlight/mount_tape.res",ResourceSaver.FLAG_COMPRESS)
	print("TAPE MESH RESULT ", error)
	quit(0 if error == OK else 1)
