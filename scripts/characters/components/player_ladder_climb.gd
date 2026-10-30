extends Node
var route: LadderRoute
var revision := 0
var exit_blocked := false
var _pending_exit := 0
var last_contact := Vector3.ZERO
var last_collider := ""
@onready var player: GamePlayer = get_parent()
func enter(next: LadderRoute) -> void:
	if not multiplayer.is_server() or not next.can_enter(player): return
	var near_top := player.global_position.distance_to(next.top_exit.global_position) < player.global_position.distance_to(next.bottom_exit.global_position)
	_set_route.rpc(next.get_path(),revision+1,next.top.global_position if near_top else next.bottom.global_position)
@rpc("authority","call_local","reliable",2)
func _set_route(path: NodePath, next_revision: int, point: Vector3) -> void:
	if next_revision < revision: return
	revision=next_revision
	exit_blocked=false
	_pending_exit=0
	route=get_node_or_null(path) as LadderRoute if not path.is_empty() else null
	player.global_position=point; player.velocity=Vector3.ZERO
	player._reconciliation_offset=Vector3.ZERO
	player.survival.reset_fall(); player.head.rotation.y=0
	player._is_crouching=false
	player.update_crouch_state(1.0,false)
	player._refresh_equipment_visuals()
func sync(path: String, next_revision: int) -> void:
	if next_revision < revision: return
	revision=next_revision
	route=get_node_or_null(NodePath(path)) as LadderRoute if not path.is_empty() else null
func simulate(delta: float, movement: Vector2, jump: bool, yaw: float, pitch: float) -> void:
	if not is_instance_valid(route): route=null; return
	if jump:
		var release := player.global_position+route.global_basis.z*.8
		if multiplayer.is_server() and route.position_clear(player,release): _set_route.rpc(NodePath(),revision+1,release)
		return
	player.rotation.y=route.global_rotation.y
	player.head.rotation.y=clampf(angle_difference(player.rotation.y,yaw),-1.1,1.1)
	player.head.rotation.x=clampf(pitch,-1.3,1.3)
	var target := route.to_local(player.global_position)
	target.x=route.bottom.position.x; target.z=route.bottom.position.z
	var speed := -movement.y*route.climb_speed
	target.y=clampf(target.y+speed*delta,route.bottom.position.y,route.top.position.y)
	var destination := route.to_global(target)
	player.velocity=(destination-player.global_position)/maxf(delta,.001)
	var contact := player.move_and_collide(destination-player.global_position)
	if contact != null:
		last_contact=contact.get_position()
		last_collider=str(contact.get_collider().get_path())
	player.survival.reset_fall()
	exit_blocked=false
	if multiplayer.is_server():
		if speed*_pending_exit<0: _pending_exit=0
		if speed>0 and player.global_position.y>=route.top.global_position.y-.01: _pending_exit=1
		elif speed<0 and player.global_position.y<=route.bottom.global_position.y+.01: _pending_exit=-1
		if _pending_exit!=0: finish(route.top_exit.global_position if _pending_exit==1 else route.bottom_exit.global_position)

func finish(point: Vector3) -> void:
	exit_blocked=not route.position_clear(player,point)
	if exit_blocked: player.velocity=Vector3.ZERO
	else: _set_route.rpc(NodePath(),revision+1,point)
func phase() -> float:
	return fposmod(route.to_local(player.global_position).y/(route.rung_spacing*2),1.0) if is_instance_valid(route) else 0.0
