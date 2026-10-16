extends SceneTree
## Keep the distant visual floor OUTSIDE native Terrain3D. Its coarse triangles
## were intersecting the cave lip and making a flat wall beside the exit.
const OUT := "res://assets/environments/cave/valley_backdrop.res"
const BACKUP := "res://tools/.local/cave-reference/valley_backdrop_before_trim.res"
func _initialize():run.call_deferred()
func clip(poly:Array[Vector3],axis:int,limit:float,keep_above:bool)->Array[Vector3]:
	var result:Array[Vector3]=[]
	for i in poly.size():
		var a:=poly[i];var b:=poly[(i+1)%poly.size()]
		var ain:bool=a[axis]>=limit if keep_above else a[axis]<=limit
		var bin:bool=b[axis]>=limit if keep_above else b[axis]<=limit
		if ain:result.append(a)
		if ain!=bin:result.append(a.lerp(b,(limit-a[axis])/(b[axis]-a[axis])))
	return result
func run():
	if not FileAccess.file_exists(BACKUP):assert(DirAccess.copy_absolute(OUT,BACKUP)==OK)
	var source:Mesh=ResourceLoader.load(BACKUP,"",ResourceLoader.CACHE_MODE_IGNORE)
	var mesh:=ArrayMesh.new();var count:=0
	for surface in source.get_surface_count():
		var faces:=source.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX] as PackedVector3Array
		var indexed:PackedInt32Array=source.surface_get_arrays(surface)[Mesh.ARRAY_INDEX]
		if not indexed.is_empty():
			var expanded:=PackedVector3Array()
			for index in indexed:expanded.append(faces[index])
			faces=expanded
		var result:=SurfaceTool.new();result.begin(Mesh.PRIMITIVE_TRIANGLES)
		for i in range(0,faces.size(),3):
			var polygon:Array[Vector3]=[faces[i],faces[i+1],faces[i+2]]
			for plane in [[0,-510.0,true],[0,1534.0,false],[2,-766.0,true],[2,766.0,false]]:
				if polygon.is_empty():break
				var outside:=clip(polygon,plane[0],plane[1],not plane[2])
				for j in range(1,outside.size()-1):
					for p in [outside[0],outside[j],outside[j+1]]:result.add_vertex(p)
					count+=1
				polygon=clip(polygon,plane[0],plane[1],plane[2])
		result.generate_normals();result.set_material(source.surface_get_material(surface));result.commit(mesh)
	assert(ResourceSaver.save(mesh,OUT,ResourceSaver.FLAG_COMPRESS)==OK)
	print("DISTANT_BACKDROP_TRIMMED ",count," triangles outside playable terrain")
	quit()
