extends Node
## Continuous host-authoritative jet; visuals live in an editable native scene.
@export_group("Fuel and balance")
@export_range(.1,20.0) var capacity_liters := 3.0
@export_range(.001,1.0) var consumption_per_second := .06
@export_range(.1,20.0) var reach := 6.5
@export_range(.05,2.0) var jet_radius := .34
@export_range(0.0,500.0) var damage_per_second := 40.0
@export_range(.03,.5) var damage_interval := .1
@export_range(1.0,100.0) var noise_radius := 22.0
@export_range(.2,2.0) var input_lease_seconds := .45
@onready var weapon: WeaponController = get_parent()
@onready var actor: GamePlayer = weapon.get_parent()
@onready var effect: Node3D = $FlameJet
var fuel_liters := 3.0
var emitting := false
var _requested := false
var _request_deadline := 0
var _sent_trigger := false
var _heartbeat := 0.0
var _damage_elapsed := 0.0
var _publish_elapsed := 0.0
var _noise_elapsed := 0.0
var _volume := CapsuleShape3D.new()

func can_emit() -> bool:
	if actor.handoff.is_offering() or actor.get_node("ItemDrag").is_heavy_carrying(): return false
	return actor.has_held_item(&"flamethrower") and not actor.survival.dead and not actor.is_sleeping_in_bunk() and not actor.is_driving() and not actor.is_carrying_corpse() and actor._journal_phase==0 and not actor._battery_action_busy and fuel_liters>0.00001

func _physics_process(delta: float) -> void:
	if actor.is_local_player():
		var held: bool = can_emit() and not actor.is_debug_free_camera_active() and not actor._is_journal_open() and not get_node("/root/GameMenu").is_menu_open() and Input.mouse_mode==Input.MOUSE_MODE_CAPTURED and Input.is_action_pressed(&"weapon_attack")
		_heartbeat+=delta
		if held!=_sent_trigger or (held and _heartbeat>=.12):
			_sent_trigger=held;_heartbeat=0.0
			request_trigger(held)
	if multiplayer.is_server(): step_authoritative(delta)

func request_trigger(pressed: bool) -> void:
	if not actor.is_local_player() or actor.is_debug_free_camera_active():return
	if multiplayer.is_server():set_trigger_authoritative(pressed)
	else:_request_trigger.rpc_id(1,pressed)

@rpc("any_peer","call_remote","reliable",0)
func _request_trigger(pressed: bool) -> void:
	if multiplayer.is_server() and multiplayer.get_remote_sender_id()==actor.owner_peer_id:
		set_trigger_authoritative(pressed)

func set_trigger_authoritative(pressed: bool) -> void:
	if not multiplayer.is_server(): return
	_requested=pressed and can_emit()
	_request_deadline=Time.get_ticks_msec()+roundi(input_lease_seconds*1000)

func stop_authoritative() -> void:
	if not multiplayer.is_server(): return
	_requested=false
	_set_emitting(false)

func _set_emitting(value: bool) -> void:
	if emitting==value:return
	emitting=value
	_damage_elapsed=0.0
	if value: _noise_elapsed=1.0
	weapon._notify_inventory()

func step_authoritative(delta: float) -> void:
	if not multiplayer.is_server() or not is_finite(delta) or delta<=0:return
	_set_emitting(_requested and Time.get_ticks_msec()<=_request_deadline and can_emit())
	if not emitting:return
	# Account for the exact final fraction of fuel; never grant a free last tick.
	var burn_time:=minf(delta,fuel_liters/consumption_per_second)
	fuel_liters=maxf(0.0,fuel_liters-burn_time*consumption_per_second)
	_damage_elapsed+=burn_time;_noise_elapsed+=burn_time;_publish_elapsed+=delta
	if _noise_elapsed>=.6:
		_noise_elapsed=0.0
		preload("res://scripts/gameplay/gameplay_noise.gd").emit(actor,noise_radius)
	if _damage_elapsed>=damage_interval or fuel_liters<=0.00001:
		apply_jet_damage(_damage_elapsed)
		_damage_elapsed=0.0
	if fuel_liters<=0.00001:
		fuel_liters=0;_requested=false;_set_emitting(false)
	elif _publish_elapsed>=.2:
		_publish_elapsed=0.0;weapon._notify_inventory()

func physics_jet() -> Dictionary:
	var head_origin:=actor.head.global_position
	var forward: Vector3=-actor.head.global_basis.z.normalized()
	var muzzle: Node3D=actor.body_animator.model.get_node("Skeleton3D/RightHand/Equipment/flamethrower/Muzzle")
	var origin:=muzzle.global_position
	# The view model can render in front of a wall; gameplay cannot start behind it.
	var guard:=_ray(head_origin,origin,23)
	if not guard.is_empty() and not guard.collider.has_method("apply_weapon_damage"): return {"origin":head_origin,"direction":forward,"distance":head_origin.distance_to(guard.position),"hit":true,"blocked_muzzle":true}
	var aim:=_ray(head_origin,head_origin+forward*(reach+1.0),23)
	var goal: Vector3=aim.position if not aim.is_empty() else head_origin+forward*(reach+1.0)
	if (goal-origin).dot(forward)<=.05:origin=head_origin
	var direction: Vector3=(goal-origin).normalized()
	var hit:=_ray(origin,origin+direction*reach,5)
	return {"origin":origin,"direction":direction,"distance":origin.distance_to(hit.position) if not hit.is_empty() else reach,"hit":not hit.is_empty(),"blocked_muzzle":false}

func _ray(from: Vector3,to: Vector3,mask: int) -> Dictionary:
	return actor.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from,to,mask,[actor.get_rid()]))

func apply_jet_damage(seconds: float) -> void:
	if not multiplayer.is_server() or seconds<=0:return
	var jet:=physics_jet()
	if jet.blocked_muzzle or float(jet.distance)<.03:return
	var direction: Vector3=jet.direction;var origin: Vector3=jet.origin;var length: float=jet.distance
	_volume.radius=jet_radius;_volume.height=length+2.0*jet_radius
	var query:=PhysicsShapeQueryParameters3D.new();query.shape=_volume;query.collision_mask=18;query.exclude=[actor.get_rid()]
	query.transform=Transform3D(Basis.looking_at(direction,Vector3.RIGHT if absf(direction.y)>.98 else Vector3.UP)*Basis(Vector3.RIGHT,PI*.5),origin+direction*length*.5)
	var seen: Dictionary={}
	for contact: Dictionary in actor.get_world_3d().direct_space_state.intersect_shape(query,32):
		var target: Node3D=contact.collider
		if seen.has(target) or not target.has_method("apply_weapon_damage"):continue
		seen[target]=true
		var shape_owner: int=target.shape_find_owner(int(contact.shape))
		var shape_node: Node3D=target.shape_owner_get_owner(shape_owner)
		var center:=shape_node.global_position if shape_node!=null else target.global_position+Vector3.UP
		if (center-origin).dot(direction)<0:continue
		# Every target needs its own unobstructed path, even near a doorway edge.
		var hit:=_ray(origin,center,23)
		if hit.is_empty() or hit.collider!=target:continue
		if target.has_method("apply_flame_damage"):target.apply_flame_damage(damage_per_second*seconds)
		elif target is GamePlayer:target.apply_weapon_damage(damage_per_second*seconds,Vector3.ZERO)
		else:target.apply_weapon_damage(damage_per_second*seconds)

func refuel_authoritative() -> bool:
	if not multiplayer.is_server() or not actor.has_held_item(&"flamethrower") or emitting or actor._battery_action_busy:return false
	if actor.survival.dead or actor.is_sleeping_in_bunk() or actor.is_driving() or actor.is_carrying_corpse():return false
	var can:=actor.get_interaction_target() as WorldItemPickup
	if can==null or can.item_type!=&"fuel_can" or can._collected or can.drag_owner_peer!=0 or actor.global_position.distance_to(can.global_position)>can.interaction_distance:return false
	var available: float=clampf(float(can.item_state.get("fuel_liters",20.0)),0,20)
	var transferred:=minf(available,capacity_liters-fuel_liters)
	if transferred<=.00001:return false
	fuel_liters+=transferred
	var next:=can.item_state.duplicate(true);next["fuel_liters"]=maxf(0,available-transferred)
	can._receive_item_state.rpc(next)
	actor._publish_inventory()
	return true

func apply_inventory(data: Dictionary) -> void:
	fuel_liters=clampf(float(data.get("flame_fuel_liters",capacity_liters)),0,capacity_liters)
	if not multiplayer.is_server(): emitting=bool(data.get("flame_active",false)) and actor.has_held_item(&"flamethrower")
	elif not actor.has_held_item(&"flamethrower"):
		_requested=false;emitting=false

func _process(_delta: float) -> void:
	if not is_instance_valid(actor.body_animator.model):return
	var show:=emitting and can_emit()
	var jet:=physics_jet() if show else {}
	if not show:
		if effect.active:effect.set_jet(false,Vector3.ZERO,Vector3.FORWARD,0,false)
		return
	var origin: Vector3=jet.origin;var direction: Vector3=jet.direction
	if actor.is_local_player() and not actor.body_animator._external_view:
		var fp: GameFirstPersonPresentation=actor.body_animator.first_person
		var muzzle: Node3D=fp.model.get_node("Skeleton3D/RightHand/Equipment/flamethrower/Muzzle")
		# Match the separate FP camera's screen position to the real world camera.
		var screen:=fp.view_camera.unproject_position(muzzle.global_position)
		var uv:=screen/Vector2(fp.viewport.size)
		var camera_point:=uv*actor.camera.get_viewport().get_visible_rect().size
		var from_eye:=muzzle.global_position-fp.view_camera.global_position
		origin=actor.camera.project_ray_origin(camera_point)+actor.camera.project_ray_normal(camera_point)*from_eye.length()
		var forward: Vector3=-actor.head.global_basis.z.normalized()
		var aim:=_ray(actor.head.global_position,actor.head.global_position+forward*(reach+1.0),23)
		var goal: Vector3=aim.position if not aim.is_empty() else actor.head.global_position+forward*(reach+1.0)
		if (goal-origin).dot(forward)<=.05:origin=actor.head.global_position
		direction=(goal-origin).normalized()
		var guard:=_ray(actor.head.global_position,origin,5)
		if not guard.is_empty():origin=actor.head.global_position;direction=forward
	var stop:=_ray(origin,origin+direction*reach,23)
	var length: float=origin.distance_to(stop.position) if not stop.is_empty() else reach
	effect.set_jet(true,origin,direction,length,not stop.is_empty())
