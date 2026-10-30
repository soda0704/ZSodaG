class_name LadderRoute
extends Node3D
@export var climb_speed := 1.8
@export var rung_spacing := .3
@onready var bottom: Marker3D = $Bottom
@onready var top: Marker3D = $Top
@onready var bottom_exit: Marker3D = $BottomExit
@onready var top_exit: Marker3D = $TopExit
func can_enter(p: GamePlayer) -> bool:
	if occupant()!=null or p.is_climbing() or p._battery_action_busy or p._journal_phase!=0 or p.handoff.is_offering() or p.weapon.reload_left>0: return false
	if p.survival.dead or p.is_sleeping_in_bunk() or p.is_driving() or p.is_carrying_corpse() or p.get_node("ItemDrag").is_heavy_carrying(): return false
	var near_top := p.global_position.distance_to(top_exit.global_position)<p.global_position.distance_to(bottom_exit.global_position)
	var entry := top if near_top else bottom
	return minf(p.global_position.distance_to(bottom_exit.global_position),p.global_position.distance_to(top_exit.global_position)) < 1.8 and position_clear(p,entry.global_position,false)

func occupant() -> GamePlayer:
	for actor in get_tree().get_nodes_in_group("network_players"):
		if actor is GamePlayer and not actor.is_queued_for_deletion() and not actor.survival.dead and actor.is_climbing() and actor.get_node("LadderClimb").route==self: return actor
	return null

func position_clear(player: GamePlayer, point: Vector3, geometry := true) -> bool:
	# Remote client bodies have disabled colliders, so check live players explicitly.
	for other in get_tree().get_nodes_in_group("network_players"):
		if other==player or not other is GamePlayer or other.survival.dead or other.is_queued_for_deletion(): continue
		var offset: Vector3=other.global_position-point
		if Vector2(offset.x,offset.z).length()<.78 and absf(offset.y)<player.standing_height: return false
	if not geometry: return true
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape=player.collision_shape.shape
	query.transform=Transform3D(player.global_basis,point)*player.collision_shape.transform
	query.collision_mask=player.collision_mask
	query.exclude=[player.get_rid()]
	query.margin=.01
	return get_world_3d().direct_space_state.intersect_shape(query,1).is_empty()
