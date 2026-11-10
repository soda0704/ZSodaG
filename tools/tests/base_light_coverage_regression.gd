extends SceneTree
## Real level, independent walkable grid, both circuits and bounded residency.
var checks := 0
var failures := 0
var base: Node3D
var lighting: WorldLighting

func _initialize() -> void:
	var prefix := "user://base_light_coverage_%d" % OS.get_process_id()
	ProjectSettings.set_setting(BaseGameplayController.TEST_SAVE_PATH_SETTING, prefix + ".cfg")
	ProjectSettings.set_setting("northern_lab/testing/settings_path", prefix + ".json")
	ProjectSettings.set_setting(JournalReadingStore.ROOT_SETTING, prefix)
	create_timer(170).timeout.connect(func(): quit(2))
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)

func ray_clear(a: Vector3, b: Vector3) -> bool:
	return base.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(a, b, 1)).is_empty()

func reaches(lamp: Light3D, at: Vector3, resident := true) -> float:
	var offset := at - lamp.global_position
	var distance := offset.length()
	var radius := WorldLighting.lamp_range(lamp)
	if distance >= radius or distance < 0.05: return 0.0
	if lamp is SpotLight3D and (-lamp.global_basis.z).dot(offset / distance) < cos(deg_to_rad(lamp.spot_angle)): return 0.0
	if not ray_clear(lamp.global_position, at): return 0.0
	return float(lighting._energies[lamp]) * (float(lighting._levels[lamp]) if resident else 1.0) * pow(1.0 - distance / radius, 2.0)

func run() -> void:
	Engine.max_fps = 60
	base = load("res://scenes/levels/base_blockout_v03.tscn").instantiate()
	root.add_child(base)
	current_scene = base
	for frame in 30: await physics_frame
	root.get_node("GameMenu").force_close_menu()
	var actor: GamePlayer = get_first_node_in_group("local_player")
	actor.set_physics_process(false)
	actor.survival.set_physics_process(false)
	actor.body_animator.hide()
	actor.teleport_authoritative(Vector3(-90, 0, 45), 0)
	base.get_node("BaseGameplayController").set_process(false)
	lighting = base.get_node("WorldLighting")
	lighting.set_process(false)
	var floors: Array[float] = []
	for node in base.get_children():
		if str(node.name).begins_with("Floor_"): floors.append(node.global_position.y)
	var samples: Dictionary = {}
	for area in base.get_node("WorldIndirectLighting").get_children():
		var floor_y := 0.0
		var best := INF
		for y in floors:
			var distance := absf(y - (area.global_position.y - area.size.y * 0.5 + 2.0))
			if distance < best:
				best = distance
				floor_y = y
		var bounds := AABB(area.global_position - area.size * 0.5, area.size).grow(-0.75)
		var points: Array[Vector3] = []
		# Shifted 3 m grid differs from the grid used to place missing sources.
		for x in range(ceili(bounds.position.x) + 1, floori(bounds.end.x), 3):
			for z in range(ceili(bounds.position.z) + 1, floori(bounds.end.z), 3):
				var hit := base.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(x, floor_y + 1.6, z), Vector3(x, floor_y - 0.6, z), 1))
				if hit.is_empty() or hit.normal.y < 0.9 or absf(hit.position.y - floor_y) > 0.4: continue
				var body: Node = hit.collider
				var equipment := false
				while body != base and body != null:
					if body.name in [&"Elevator_Functional_Blockout", &"ExpeditionWinch"]: equipment = true
					body = body.get_parent()
				if equipment: continue
				var at: Vector3 = hit.position + Vector3.UP * 1.65
				var query := PhysicsPointQueryParameters3D.new()
				query.position = at
				query.collision_mask = 1
				if not base.get_world_3d().direct_space_state.intersect_point(query).is_empty(): continue
				if not ray_clear(hit.position + Vector3.UP * 0.1, hit.position + Vector3.UP * 1.9): continue
				var fits := true
				for offset in [Vector3(0.4, 0, 0), Vector3(-0.4, 0, 0), Vector3(0, 0, 0.4), Vector3(0, 0, -0.4)]:
					if not ray_clear(at, at + offset): fits = false
				if not fits: continue
				var roof := base.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(at, at + Vector3.UP * 8.0, 1))
				if roof.is_empty() or roof.normal.y > -0.7: continue
				points.append(at)
		samples[str(area.name)] = points
	for powered in [true, false]:
		base.get_node("BasePowerLightingController").apply_power_state(powered)
		for area in samples:
			var missing: Array[Vector3] = []
			var budget := true
			for at: Vector3 in samples[area]:
				lighting._update_lamps(at, 1.0)
				lighting._update_lamps(at, 1.0)
				var energy := 0.0
				var slots := 0
				for lamp: Light3D in lighting._resident_lamps:
					energy += reaches(lamp, at)
					slots += WorldLighting.shadow_slot_cost(lamp)
				budget = budget and slots <= WorldLighting.MAX_RESIDENT_SHADOW_SLOTS and lighting._resident_lamps.size() <= WorldLighting.MAX_RESIDENT_LAMPS
				if energy < 0.015:
					missing.append(at)
					var authored := 0.0
					for lamp: Light3D in lighting._lamps:
						if (lamp.get_parent().name == &"Standard") == powered: authored += reaches(lamp, at, false)
					print("MISSING ", area, " ", at, " authored=", authored, " resident=", energy)
			print("COVERAGE ", area, " powered=", powered, " samples=", samples[area].size(), " missing=", missing)
			check(samples[area].size() >= 8 and missing.is_empty(), area + " has reachable light on its independent walkable grid, powered=" + str(powered))
			check(budget, area + " respects lamp and shadow budgets, powered=" + str(powered))
			await process_frame
	current_scene = null
	base.queue_free()
	for frame in 10: await process_frame
	print("BASE LIGHT COVERAGE CHECKS ", checks, " FAILURES ", failures)
	quit(1 if failures else 0)
