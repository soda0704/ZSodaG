class_name PlayerItemFocus
extends ShapeCast3D
## A small authored aim tolerance, shared by E targeting and local presentation.
## Only world pickups are outlined. No lights, duplicate meshes or global glow.
@export_node_path("CharacterBody3D") var player_path := NodePath("../../..")
@export var common_material: Material
@export var story_material: Material
@export var special_material: Material
@onready var player: GamePlayer = get_node(player_path)
var focused_item: WorldItemPickup
var _overlays: Dictionary = {}
var _category := -1

static func pickup_from(node: Node) -> WorldItemPickup:
	while node != null:
		if node is WorldItemPickup: return node
		node = node.get_parent()
	return null

func _eligible(item: WorldItemPickup) -> bool:
	return is_instance_valid(item) and not item._collected and item.pickup_enabled and item.is_visible_in_tree() and item.drag_owner_peer in [0, player.owner_peer_id]

func resolve_target(center_target: Node) -> Node:
	# Exact aim keeps priority, including doors, terminals and other interactions.
	if center_target != null and center_target.has_method("network_interact"):
		return center_target
	target_position = Vector3(0, 0, -player.interaction_reach)
	force_update_transform()
	force_shapecast_update()
	var chosen: WorldItemPickup
	var best_distance := INF
	var eye := global_position
	for index in get_collision_count():
		var item := pickup_from(get_collider(index) as Node)
		if not _eligible(item): continue
		var point := get_collision_point(index)
		if eye.distance_squared_to(point) >= best_distance: continue
		# The wider cast never grants wall vision or selection behind another prop.
		var direction := (point - eye).normalized()
		var query := PhysicsRayQueryParameters3D.create(eye, point + direction * 0.025, 5, [player.get_rid()])
		query.collide_with_areas = true
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty() and pickup_from(hit.collider as Node) == item:
			chosen = item
			best_distance = eye.distance_squared_to(point)
	return chosen if chosen != null else center_target

func _physics_process(_delta: float) -> void:
	if not player.is_local_player(): return
	if not player.camera.current or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED or player.survival == null or player.survival.dead or player.is_sleeping_in_bunk() or player.is_driving() or player.is_debug_free_camera_active() or player._is_journal_open() or player.get_node("ItemDrag").dragging:
		set_focus(null)
		return
	var item := pickup_from(player.get_interaction_target())
	set_focus(item if _eligible(item) else null)

func set_focus(item: WorldItemPickup) -> void:
	if focused_item == item:
		if is_instance_valid(item) and item.highlight_category == _category and not _overlays.is_empty(): return
		if item == null and _overlays.is_empty():
			focused_item = null
			return
	for mesh in _overlays:
		if is_instance_valid(mesh): mesh.material_overlay = _overlays[mesh]
	_overlays.clear()
	focused_item = item
	_category = -1
	if not is_instance_valid(item): return
	_category = item.highlight_category
	var material := common_material
	match item.highlight_category:
		WorldItemPickup.HighlightCategory.STORY: material = story_material
		WorldItemPickup.HighlightCategory.SPECIAL: material = special_material
	for mesh: MeshInstance3D in item.find_children("*", "MeshInstance3D", true, false):
		if mesh.mesh == null: continue
		_overlays[mesh] = mesh.material_overlay
		mesh.material_overlay = material

func _exit_tree() -> void:
	set_focus(null)
