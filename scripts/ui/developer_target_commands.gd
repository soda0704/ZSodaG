extends RefCounted

static func resolve(node: Node, tree: SceneTree) -> Node:
	var current := node
	while current != null:
		if current.has_method("debug_set_open") or current is InteractiveDoor or current is WorldItemPickup or current.is_in_group("hostile_monsters"):
			return current
		for manager in tree.get_nodes_in_group("base_auto_door_managers"):
			for door in manager._doors:
				# Passage bodies are siblings of their visual door, not children.
				if door.anchor == current or door.blocker.get_parent() == current:
					return door.anchor
		current = current.get_parent()
	return node

static func execute(args: PackedStringArray, player: GamePlayer, selected: NodePath, point: Vector3) -> String:
	var tree := player.get_tree()
	if args[0] == "/item":
		var world := tree.get_first_node_in_group("network_gameplay_controller")
		if world == null or args.size() < 2 or not world.ITEM_SCENES.has(StringName(args[1])):
			return "Использование: /item tape|crowbar|fuel_can|flashlight|battery|fuse|pistol|m4a1|kitchen_knife|pistol_ammo|rifle_magazine [число]"
		if args.size() > 2 and (not args[2].is_valid_int() or int(args[2]) < 1):
			return "Количество должно быть положительным целым числом."
		if not point.is_finite() or player.global_position.distance_to(point) > 65:
			return "Точка слишком далеко. Снова наведитесь и откройте консоль."
		var count := clampi(int(args[2]), 1, 100) if args.size() > 2 else 1
		for index in count:
			var position := point + Vector3((index % 5) * 0.35, 0.35 + (index / 25) * 0.3, ((index / 5) % 5) * 0.35)
			world.spawn_world_item(StringName(args[1]), world.world_items.global_transform.affine_inverse() * Transform3D(Basis.IDENTITY, position), {})
		return "Создано предметов: %d" % count
	var path := NodePath(args[1]) if args.size() > 1 else selected
	var target := player.get_node_or_null(path) if not path.is_empty() else null
	if target == null:
		return "Цель не найдена. Наведитесь на объект и снова откройте консоль."
	target = resolve(target, tree)
	if args[0] == "/target":
		return "ID: " + str(target.get_path())
	if args[0] == "/kill":
		if not target.is_in_group("hostile_monsters"):
			return "Цель не является монстром."
		target.apply_weapon_damage(100000.0)
		return "Убит: " + str(target.get_path())
	var opened := args[0] == "/open"
	if target.has_method("debug_set_open"):
		target.debug_set_open(opened)
	elif target is InteractiveDoor:
		target._apply_network_open.rpc(opened)
	else:
		var found := false
		for manager in tree.get_nodes_in_group("base_auto_door_managers"):
			if manager.debug_set_door_open(target, opened):
				found = true
				break
		if not found:
			return "Цель не является дверью или гаражом."
	return ("Открыто: " if opened else "Закрыто: ") + str(target.get_path())
