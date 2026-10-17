extends "res://tools/tests/project_resource_audit.gd"
## Validate saved objects, their dependencies, animation rigs and physical surfaces.
const LIBRARY := "res://scenes/objects/base/modular_scifi/"
var checked_objects := 0
var checked_collisions := 0
var checked_animations := 0

func require(condition: bool, message: String) -> void:
	if not condition:
		print("FAIL ", message)
		failures += 1

func run() -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(LIBRARY + "library_index.json"))
	require(manifest.source_models == 191 and manifest.objects.size() == 208, "Incomplete library")
	var names: Dictionary = {}
	for entry: Dictionary in manifest.objects:
		var path := str(entry.scene)
		inspect(path)
		require(not names.has(path), "Duplicate object: " + path)
		names[path] = true
		var scene := load(path) as PackedScene
		if scene == null:
			require(false, "Cannot load scene: " + path)
			continue
		var object := scene.instantiate() as Node3D
		root.add_child(object)
		var original := load(str(object.get_meta("source_path")))
		var source: Node3D
		if original is PackedScene:
			source = original.instantiate() as Node3D
		else:
			source = MeshInstance3D.new()
			(source as MeshInstance3D).mesh = original
		var source_parts := source.find_children("*", "MeshInstance3D", true, false)
		if source is MeshInstance3D:
			source_parts.push_front(source)
		var bounds := AABB()
		var first := true
		var parts := object.find_children("*", "MeshInstance3D", true, false)
		require(not parts.is_empty(), "No visible mesh: " + path)
		require(source_parts.size() == parts.size(), "Changed mesh hierarchy: " + path)
		for part: MeshInstance3D in parts:
			require(part.mesh != null, "Null mesh: " + path)
			if part.mesh == null:
				continue
			var part_bounds := part.global_transform * part.mesh.get_aabb()
			bounds = part_bounds if first else bounds.merge(part_bounds)
			first = false
			for surface in part.mesh.get_surface_count():
				var material := part.get_active_material(surface) as StandardMaterial3D
				require(material != null, "Missing material: " + path)
				if material != null and material.albedo_texture != null:
					require(material.albedo_texture.get_width() > 0, "Empty texture: " + path)
				var original_part := source_parts[parts.find(part)] as MeshInstance3D
				var original_material := original_part.get_active_material(surface) as StandardMaterial3D
				if material != null and original_material != null:
					var texture := "" if material.albedo_texture == null else material.albedo_texture.resource_path
					var source_texture := "" if original_material.albedo_texture == null else original_material.albedo_texture.resource_path
					require(texture == source_texture, "Wrong texture variant: " + path)
					if original_material.resource_name != "M_Glass":
						require(material.transparency == original_material.transparency, "Wrong transparency variant: " + path)
		source.free()
		var p: Array = entry.bounds_position
		var s: Array = entry.bounds_size
		require(bounds.position.is_equal_approx(Vector3(p[0], p[1], p[2])) and bounds.size.is_equal_approx(Vector3(s[0], s[1], s[2])), "Changed dimensions or transform: " + path)
		var collisions := object.find_children("*", "CollisionShape3D", true, false)
		if entry.collidable:
			require(collisions.size() == parts.size(), "Collision count: " + path)
			await physics_frame
			await physics_frame
			for index in mini(collisions.size(), parts.size()):
				var part := parts[index] as MeshInstance3D
				var collision := collisions[index] as CollisionShape3D
				require(collision.global_transform.is_equal_approx(part.global_transform), "Collision offset: " + path)
				var shape := collision.shape as ConcavePolygonShape3D
				require(shape != null and not shape.get_faces().is_empty(), "Missing shape: " + path)
				if shape == null:
					continue
				var faces := shape.get_faces()
				for triangle in range(0, faces.size(), 3):
					var a := collision.global_transform * faces[triangle]
					var b := collision.global_transform * faces[triangle + 1]
					var c := collision.global_transform * faces[triangle + 2]
					var normal := (b - a).cross(c - a)
					if normal.length() < 0.0001:
						continue
					normal = normal.normalized()
					var center := (a + b + c) / 3.0
					var query := PhysicsRayQueryParameters3D.create(center + normal * 0.05, center - normal * 0.05, 1)
					query.hit_back_faces = true
					var hit := root.world_3d.direct_space_state.intersect_ray(query)
					require(not hit.is_empty() and hit.collider == collision.get_parent(), "Surface ray missed collision: " + path)
					checked_collisions += 1
					break
		else:
			require(collisions.is_empty(), "Unexpected static collision on animated model/decal: " + path)
		if entry.animated:
			require(not object.find_children("*", "Skeleton3D", true, false).is_empty(), "Lost animation skeleton: " + path)
			var players := object.find_children("*", "AnimationPlayer", true, false)
			require(not players.is_empty(), "Lost AnimationPlayer: " + path)
			var animations: Array[String] = []
			for player: AnimationPlayer in players:
				for name in player.get_animation_list():
					if name == "RESET":
						continue
					animations.append(str(name))
					player.play(name)
					player.seek(player.get_animation(name).length * 0.5, true)
					player.advance(0.0)
					player.stop()
					checked_animations += 1
			require(animations == Array(entry.animations), "Changed animation list: " + path)
		if entry.ceiling_variant:
			require(absf(bounds.position.y) < 0.0001, "Ceiling underside is not Y=0: " + path)
			var visual := object.get_node("Visual") as Node3D
			require((visual.basis * Vector3.UP).dot(Vector3.DOWN) > 0.999, "Ceiling faces upward: " + path)
		object.free()
		checked_objects += 1
	for category in ["walls", "floors", "ceilings", "doors", "columns", "props", "decals", "aliens"]:
		inspect(LIBRARY + "catalogs/" + category + ".tscn")
	print("LIBRARY AUDIT: objects=%d collision_rays=%d animations=%d resources=%d failures=%d" % [checked_objects, checked_collisions, checked_animations, resources, failures])
	for frame in 8:
		await process_frame
	for player: AudioStreamPlayer in root.find_children("*", "AudioStreamPlayer", true, false):
		player.stop()
		player.stream = null
	await create_timer(0.1).timeout
	quit(0 if failures == 0 else 1)
