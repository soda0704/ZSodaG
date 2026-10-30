extends SceneTree
## Offline visual apron: no edits to the playable height map or cave/shaft holes.
const OUT := "res://assets/environments/cave/valley_backdrop.res"
const BACKUP := "res://tools/.local/radio_tower/valley_backdrop_before_stitch.res"
var data: Terrain3DData
var space: PhysicsDirectSpaceState3D
var cache := {}
func emit(surface: SurfaceTool, points: Array) -> void:
	for point in [points[0],points[2],points[1],points[0],points[3],points[2]]:
		surface.set_uv(Vector2(point.x,point.z)/32);surface.add_vertex(point)
func _initialize() -> void: run.call_deferred()
func height_at(x: float,z: float) -> float:
	var key := Vector2(x,z)
	if cache.has(key): return cache[key]
	var ray := PhysicsRayQueryParameters3D.create(Vector3(x,2000,z),Vector3(x,-1000,z),1<<19)
	var hit := space.intersect_ray(ray)
	var original: float=hit.position.y if not hit.is_empty() else -160.0
	var edge := Vector3(clampf(x,-511,1535),0,clampf(z,-767,767))
	var native := data.get_height(edge)
	var distance := Vector2(x-edge.x,z-edge.z).length()
	var result := lerpf(native,original,smoothstep(0,384,distance)) if is_finite(native) else original
	cache[key]=result
	return result
func run() -> void:
	if not FileAccess.file_exists(BACKUP): assert(DirAccess.copy_absolute(OUT,BACKUP)==OK)
	var camera := Camera3D.new();root.add_child(camera);camera.current=true
	var source_world: Node3D=load("res://scenes/levels/snow_exterior.tscn").instantiate()
	source_world.set_script(null);root.add_child(source_world)
	var terrain: Terrain3D=source_world.get_node("Terrain3D")
	data=terrain.data
	var source: Mesh=load(BACKUP)
	var body := StaticBody3D.new();body.collision_layer=1<<19;body.collision_mask=0
	var collision := CollisionShape3D.new();collision.shape=source.create_trimesh_shape();body.add_child(collision);root.add_child(body)
	await physics_frame;await physics_frame
	space=root.get_world_3d().direct_space_state
	var bounds := source.get_aabb()
	var surface := SurfaceTool.new();surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.set_material(source.surface_get_material(0))
	var count := 0
	for x in range(floori(bounds.position.x/16)*16,ceili(bounds.end.x/16)*16,16):
		for z in range(floori(bounds.position.z/16)*16,ceili(bounds.end.z/16)*16,16):
			if x>=-512 and x<1536 and z>=-768 and z<768: continue
			if ((x==-528 or x==1536) and z>=-768 and z<768) or ((z==-784 or z==768) and x>=-512 and x<1536): continue
			for offset in [Vector2(0,0),Vector2(16,16),Vector2(0,16),Vector2(0,0),Vector2(16,0),Vector2(16,16)]:
				var px: float=x+offset.x;var pz: float=z+offset.y
				surface.set_uv(Vector2(px,pz)/32)
				surface.add_vertex(Vector3(px,height_at(px,pz),pz));count+=1
		surface.set_smooth_group(0)
	# One-metre inner edge follows native texels; the outer edge matches the
	# existing 16-metre grid exactly. Two metres overlap the native terrain.
	for side in [[0,-510.0,-528.0,-768,768],[0,1534.0,1552.0,-768,768],[2,-766.0,-784.0,-512,1536],[2,766.0,784.0,-512,1536]]:
		for along in range(side[3],side[4]):
			var quad := []
			for pair in [[side[1],along],[side[1],along+1],[side[2],along+1],[side[2],along]]:
				var point := Vector3(pair[0],0,pair[1]) if side[0]==0 else Vector3(pair[1],0,pair[0])
				if pair[0]==side[1]:
					point.y=data.get_height(Vector3(clampf(point.x,-511,1535),0,clampf(point.z,-767,767)))
				else:
					var start := floorf(pair[1]/16.0)*16
					var a := height_at(pair[0],start) if side[0]==0 else height_at(start,pair[0])
					var b := height_at(pair[0],start+16) if side[0]==0 else height_at(start+16,pair[0])
					point.y=lerpf(a,b,(pair[1]-start)/16.0)
				quad.append(point)
			if (side[0]==0 and side[1]<0) or (side[0]==2 and side[1]>0):quad.reverse()
			emit(surface,quad)
	surface.generate_normals();surface.index()
	assert(ResourceSaver.save(surface.commit(),OUT,ResourceSaver.FLAG_COMPRESS)==OK)
	print("VALLEY STITCHED vertices ",count," boundary samples ",cache.size())
	body.queue_free();source_world.queue_free();await process_frame;quit()

