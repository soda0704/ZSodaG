class_name ItemDropPlacement
extends RefCounted
## Reuse authored pickup colliders; this helper only chooses a clear spawn pose.
static var _bounds := {}
static func bounds_for(scene: PackedScene, kind: StringName) -> AABB:
	if _bounds.has(kind): return _bounds[kind]
	var bounds := AABB(Vector3.ONE*-.3,Vector3.ONE*.6)
	if scene != null:
		var item := scene.instantiate()
		var first := true
		for shape: CollisionShape3D in item.find_children("*","CollisionShape3D",true,false):
			if shape.disabled or shape.shape==null: continue
			var parent := shape.get_parent()
			if parent is Area3D: continue
			var pose := shape.transform
			while parent!=item and parent is Node3D:
				pose=parent.transform*pose;parent=parent.get_parent()
			var part: AABB=pose*shape.shape.get_debug_mesh().get_aabb()
			bounds=part if first else bounds.merge(part);first=false
		# Match the same fitted collider used by generic tools and weapons at runtime.
		if item.get("use_authored_collision")==false and item.has_method("fitted_collision_bounds"):
			item.item_type=kind
			bounds=item.fitted_collision_bounds()
		item.free()
	_bounds[kind]=bounds
	return bounds

static func find_pose(player: GamePlayer, scene: PackedScene, kind: StringName, desired: Transform3D) -> Variant:
	if scene==null: return null
	var bounds := bounds_for(scene,kind)
	var box := BoxShape3D.new();box.size=bounds.size+Vector3.ONE*.025
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape=box;query.collision_mask=1;query.exclude=[player.get_rid()];query.margin=.01
	var space := player.get_world_3d().direct_space_state
	var offset := desired.basis*bounds.get_center()
	var center := player.global_position+Vector3.UP*1.0
	var starts := [player.head.global_position,center-offset,center-offset+Vector3.UP*.3]
	for start: Vector3 in starts:
		query.transform=Transform3D(desired.basis,start+offset)
		query.motion=Vector3.ZERO
		if not space.intersect_shape(query,1).is_empty(): continue
		query.motion=desired.origin-start
		var fractions := space.cast_motion(query)
		var fraction := maxf(0.0,float(fractions[0])-.02) if fractions.size()>0 else 0.0
		var result := Transform3D(desired.basis,start+query.motion*fraction)
		query.motion=Vector3.ZERO;query.transform=Transform3D(result.basis,result.origin+offset)
		if not space.intersect_shape(query,1).is_empty(): continue
		var ray := PhysicsRayQueryParameters3D.create(player.head.global_position,result.origin+offset,1,[player.get_rid()])
		if space.intersect_ray(ray).is_empty(): return result
	return null
