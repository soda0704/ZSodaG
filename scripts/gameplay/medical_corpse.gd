class_name MedicalCorpse
extends Node3D

enum Mode { GROUND, LIFTING, CARRIED, PLACING, DELIVERED }
@export_group("Recovery")
@export_range(0, 1) var corpse_id := 0
@export var recoverable := true
@export_group("Carry physics")
@export var carry_support_bones: Array[StringName] = [&"pelvis_015", &"spine_01_062", &"spine_03_064"]
@export_range(0.1, 3.14) var carry_swing_limit := 2.2
@export_range(0.1, 3.14) var carry_twist_limit := 1.0
@export_range(0.0, 10.0) var carry_linear_damp := 1.5
@export_range(0.0, 10.0) var carry_angular_damp := 4.0
@export_group("Interaction")
@export var interaction_distance := 3.0
@export var visual_cull_margin := 1.0
var mode: Mode = Mode.GROUND
var carrier_peer := 0
var bed_path := NodePath()
var action_progress := 0.0
var initialized := false
var state: BaseGameplayController
var _rest_offsets: Array[Transform3D] = []
var _joint_links: Array[Dictionary] = []
var _ground_damping: Array[Vector2] = []
var _rest_basis := Basis.IDENTITY
var _model_offset := Vector3.ZERO
var _model_basis := Basis.IDENTITY
var _action_from: Array[Transform3D] = []
var _sync_time := 0.0
var _settle_time := 0.0
var _pending_status: Dictionary = {}
@onready var ragdoll: SkeletalRagdoll = $Ragdoll
@onready var animator: AnimationPlayer = $ActionAnimation

func _ready() -> void:
 add_to_group("medical_corpses")
 process_physics_priority = 25
 state = get_tree().get_first_node_in_group("base_gameplay_controller")
 await get_tree().physics_frame
 var rig: Skeleton3D = $Model.find_children("*", "Skeleton3D", true, false)[0]
 ragdoll.initialize(rig, multiplayer.is_server())
 var root_pose := ragdoll.root_body.global_transform
 _rest_basis = global_basis.inverse() * root_pose.basis
 for body in ragdoll.bodies:
  _rest_offsets.append(root_pose.affine_inverse()*body.global_transform)
  _ground_damping.append(Vector2(body.linear_damp,body.angular_damp))
 for joint in ragdoll.get_children():
  if joint is ConeTwistJoint3D:
   var child_index := ragdoll.bodies.find(ragdoll.get_node(joint.get_meta("child_body")))
   var parent_index := ragdoll.bodies.find(ragdoll.get_node(joint.get_meta("parent_body")))
   var child_anchor := ragdoll.offsets[child_index].origin
   var parent_anchor := _rest_offsets[parent_index].affine_inverse() * (_rest_offsets[child_index] * child_anchor)
   _joint_links.append({"child":child_index,"parent":parent_index,"child_anchor":child_anchor,"parent_anchor":parent_anchor,"joint":joint,"swing":joint.swing_span,"twist":joint.twist_span})
 _model_basis = $Model.global_basis
 _model_offset = $Model.global_transform.affine_inverse()*root_pose.origin
 for mesh in $Model.find_children("*", "MeshInstance3D", true, false):
  mesh.extra_cull_margin = visual_cull_margin
 animator.animation_finished.connect(_animation_finished)
 initialized = true
 if state != null:
  var saved: Dictionary = state.maintenance.get("corpse_recovery", {}).get("bodies", {}).get(str(corpse_id), {})
  if not saved.is_empty():
   bed_path = saved.get("bed_path",NodePath())
   var level := get_tree().get_first_node_in_group("expedition_level")
   for bed in get_tree().get_nodes_in_group("medical_corpse_beds"):
    if not bed.legacy_bed_path.is_empty() and bed_path==bed.legacy_bed_path and level!=null:
     bed_path=level.get_path_to(bed)
   mode = Mode.DELIVERED if int(saved.get("mode",0))==Mode.DELIVERED else Mode.GROUND
   ragdoll.apply_poses(saved.get("poses",[]))
 if not _pending_status.is_empty():
  _apply_status(_pending_status.mode,_pending_status.peer,_pending_status.bed,_pending_status.poses,_pending_status.elapsed)
 _update_interaction()

func _carrier() -> GamePlayer:
 return state.get_player_node(carrier_peer) as GamePlayer if state != null and carrier_peer != 0 else null

func get_interaction_prompt() -> String:
 if not recoverable: return ""
 if mode == Mode.DELIVERED: return "Тело на медицинской койке"
 if mode != Mode.GROUND: return "Тело переносит другой игрок"
 var player := get_tree().get_first_node_in_group("local_player") as GamePlayer
 if player != null and player._held_item_type not in [player.NO_ITEM, player.FLASHLIGHT_ITEM]:
  return "Освободите руки, чтобы поднять тело"
 return "Закинуть тело на плечо"

func network_interact(peer: int, player: Node) -> void:
 if not recoverable or not initialized or not multiplayer.is_server() or mode != Mode.GROUND or not player is GamePlayer:
  return
 if player.owner_peer_id != peer or player.survival.dead or player.is_driving() or player.is_sleeping_in_bunk() or player.is_carrying_corpse(): return
 if player.global_position.distance_to(ragdoll.root_body.global_position)>interaction_distance: return
 if player._held_item_type not in [player.NO_ITEM,player.FLASHLIGHT_ITEM]: return
 player.get_node("ItemDrag")._release()
 if player._held_item_type==player.FLASHLIGHT_ITEM:
  player._held_item_type=player.NO_ITEM
  player._flashlight_enabled=false
  player._publish_inventory()
 _broadcast_status(Mode.LIFTING,peer,NodePath(),ragdoll.capture(),0.0)
 _commit_objective(true)

func place_on_bed(peer:int, bed:Node3D) -> bool:
 if not initialized or not multiplayer.is_server() or mode != Mode.CARRIED or carrier_peer!=peer: return false
 var player := _carrier()
 if player==null or player.survival.dead or player.global_position.distance_to(bed.global_position)>bed.interaction_distance: return false
 var level := get_tree().get_first_node_in_group("expedition_level")
 _broadcast_status(Mode.PLACING,peer,level.get_path_to(bed),ragdoll.capture(),0.0)
 return true

func drop_from_shoulder(peer:int) -> bool:
 if not multiplayer.is_server() or mode != Mode.CARRIED or peer!=carrier_peer: return false
 _broadcast_status(Mode.GROUND,0,NodePath(),ragdoll.capture(),0.0)
 return true

func _anchor() -> Transform3D:
 if mode==Mode.PLACING or mode==Mode.DELIVERED:
  var level := get_tree().get_first_node_in_group("expedition_level")
  var bed := level.get_node_or_null(bed_path) if level != null else null
  if bed != null: return bed.get_node("RestPose").global_transform
 var player := _carrier()
 if player != null: return player.get_node("CorpseShoulder").global_transform
 return ragdoll.root_body.global_transform

func _apply_status(next_mode:int,peer:int,bed:NodePath,poses:Array,elapsed:float) -> void:
 if not initialized:
  _pending_status={"mode":next_mode,"peer":peer,"bed":bed,"poses":poses,"elapsed":elapsed}
  return
 var previous := _carrier()
 if previous!=null:
  previous.carried_corpse=null
  previous.corpse_action_busy=false
  previous.body_animator.set_corpse_action("")
 mode=next_mode as Mode
 carrier_peer=peer
 bed_path=bed
 ragdoll.apply_poses(poses)
 for index in ragdoll.bodies.size():
  var body:RigidBody3D=ragdoll.bodies[index]
  body.linear_velocity=Vector3.ZERO
  body.angular_velocity=Vector3.ZERO
  body.linear_damp=carry_linear_damp if mode==Mode.CARRIED else _ground_damping[index].x
  body.angular_damp=carry_angular_damp if mode==Mode.CARRIED else _ground_damping[index].y
  body.collision_mask=1 if mode in [Mode.GROUND,Mode.DELIVERED] else 0
  body.freeze=not multiplayer.is_server() or mode in [Mode.LIFTING,Mode.PLACING]
 var player := _carrier()
 if player!=null:
  player.carried_corpse=self
  player.corpse_action_busy=mode in [Mode.LIFTING,Mode.PLACING]
  var player_clip := "pickup" if mode == Mode.LIFTING else "place" if mode == Mode.PLACING else "carry"
  player.body_animator.set_corpse_action(player_clip, elapsed)
 if mode==Mode.CARRIED:
  # The shoulder supports the trunk, not just the pelvis. The short spine
  # chain otherwise oscillates between tightly limited joints under gravity.
  for body in ragdoll.bodies:
   if StringName(body.get_meta("bone")) in carry_support_bones:
    body.freeze_mode=RigidBody3D.FREEZE_MODE_STATIC
    body.freeze=true
 for link in _joint_links:
  var joint:ConeTwistJoint3D=link.joint
  joint.swing_span=carry_swing_limit if mode==Mode.CARRIED else float(link.swing)
  joint.twist_span=carry_twist_limit if mode==Mode.CARRIED else float(link.twist)
 ragdoll.rebuild_joints_from_pose()
 if mode in [Mode.LIFTING,Mode.PLACING]:
  _action_from.assign(poses)
  action_progress=0
  animator.play("pickup" if mode==Mode.LIFTING else "place")
  animator.seek(elapsed,true)
 else:
  animator.stop()
  _settle_time=0
 _update_interaction()

func _broadcast_status(next_mode:int,peer:int,bed:NodePath,poses:Array,elapsed:float) -> void:
 _apply_status(next_mode,peer,bed,poses,elapsed)
 for target in _ready_peers(): _receive_status.rpc_id(target,next_mode,peer,bed,poses,elapsed)

@rpc("authority","call_remote","reliable")
func _receive_status(next_mode:int,peer:int,bed:NodePath,poses:Array,elapsed:float) -> void:
 _apply_status(next_mode,peer,bed,poses,elapsed)

func _ready_peers() -> Array[int]:
 var world := get_tree().get_first_node_in_group("network_gameplay_controller")
 var result:Array[int]=[]
 if world!=null:
  for peer in world.get_ready_v3_peers():
   if peer!=multiplayer.get_unique_id(): result.append(peer)
 return result

func sync_network_state_to_peer(peer:int) -> void:
 if initialized: _receive_status.rpc_id(peer,mode,carrier_peer,bed_path,ragdoll.capture(),animator.current_animation_position if animator.is_playing() else 0.0)

func _physics_process(delta:float) -> void:
 if not initialized: return
 var player := _carrier()
 if multiplayer.is_server() and carrier_peer!=0 and (player==null or player.survival.dead):
  _broadcast_status(Mode.GROUND,0,NodePath(),ragdoll.capture(),0.0)
  return
 if player!=null:
  if player.carried_corpse != self:
   var clip := "pickup" if mode == Mode.LIFTING else "place" if mode == Mode.PLACING else "carry"
   player.body_animator.set_corpse_action(clip, animator.current_animation_position if mode in [Mode.LIFTING, Mode.PLACING] else 0.0)
  player.carried_corpse=self
  player.corpse_action_busy=mode in [Mode.LIFTING,Mode.PLACING]
 if mode in [Mode.LIFTING,Mode.PLACING,Mode.CARRIED]:
  var anchor := _anchor()
  var target_root := Transform3D(anchor.basis*_rest_basis,anchor.origin)
  if mode==Mode.CARRIED:
   # Transport the complete chain every step, including turns. Moving only
   # the frozen pelvis makes the solver drag the limbs after a teleported root.
   var teleport := ragdoll.root_body.global_position.distance_to(target_root.origin) > 0.75
   var shift := target_root * ragdoll.root_body.global_transform.affine_inverse()
   var moved := not shift.is_equal_approx(Transform3D.IDENTITY)
   for body in ragdoll.bodies:
    if not moved: continue
    body.global_transform = shift * body.global_transform
    if not body.freeze: body.sleeping=false
    if teleport:
     body.linear_velocity = Vector3.ZERO
     body.angular_velocity = Vector3.ZERO
    else:
     body.linear_velocity = shift.basis * body.linear_velocity
     body.angular_velocity = shift.basis * body.angular_velocity
   if moved: ragdoll.root_body.global_transform=target_root
  elif _action_from.size()==ragdoll.bodies.size():
   _apply_action_pose(target_root)
 $Model.global_transform=Transform3D(_model_basis,ragdoll.root_body.global_position-_model_basis*_model_offset)
 _update_interaction()
 if multiplayer.is_server():
  _sync_time+=delta
  if _sync_time>=0.1:
   _sync_time=0
   for peer in _ready_peers(): _receive_poses.rpc_id(peer,ragdoll.capture())
  if mode==Mode.DELIVERED:
   _settle_time+=delta
   if _settle_time>3 and ragdoll.settled(): ragdoll.freeze_all()

@rpc("authority","call_remote","unreliable_ordered",3)
func _receive_poses(poses:Array) -> void:
 if initialized: ragdoll.apply_poses(poses)

func _update_interaction() -> void:
 $InteractionArea.collision_layer=4 if recoverable and mode==Mode.GROUND else 0
 if initialized: $InteractionArea.global_position=ragdoll.root_body.global_position

func _animation_finished(_clip:StringName) -> void:
 if not multiplayer.is_server(): return
 if mode in [Mode.LIFTING,Mode.PLACING]:
  action_progress=1.0
  var anchor := _anchor()
  _apply_action_pose(Transform3D(anchor.basis*_rest_basis,anchor.origin))
 if mode==Mode.LIFTING:
  _broadcast_status(Mode.CARRIED,carrier_peer,NodePath(),ragdoll.capture(),0.0)
 elif mode==Mode.PLACING:
  _broadcast_status(Mode.DELIVERED,0,bed_path,ragdoll.capture(),0.0)
  _commit_objective(false)

func _apply_action_pose(target_root:Transform3D) -> void:
 # Interpolate rotations, then join each limb at its anatomical attachment.
 # Independent world-space position lerps shrink/stretch limbs during turns.
 for i in ragdoll.bodies.size():
  var target := target_root*_rest_offsets[i]
  target.origin += $LiftOffset.position
  ragdoll.bodies[i].global_transform=_action_from[i].interpolate_with(target,action_progress)
 _align_action_joint_anchors()

func _align_action_joint_anchors() -> void:
 # Frozen pickup/placement poses keep exact attachments. Never project
 # running physics here: that continuously injects energy into the solver.
 for link in _joint_links:
  var parent:RigidBody3D=ragdoll.bodies[link.parent]
  var child:RigidBody3D=ragdoll.bodies[link.child]
  var pose := child.global_transform
  pose.origin=parent.global_transform*Vector3(link.parent_anchor)-pose.basis*Vector3(link.child_anchor)
  child.global_transform=pose

func _commit_objective(picked:bool) -> void:
 if state==null: return
 var snapshot := state.get_snapshot()
 var data:Dictionary=snapshot.maintenance.get("corpse_recovery",{}).duplicate(true)
 if picked: data["picked_up"]=true
 if mode==Mode.DELIVERED:
  var delivered:Array=data.get("delivered",[]).duplicate()
  if not delivered.has(corpse_id): delivered.append(corpse_id)
  data["delivered"]=delivered
 snapshot.maintenance["corpse_recovery"]=data
 state._broadcast_snapshot(snapshot)

func capture_checkpoint() -> Dictionary:
 return {"mode":Mode.DELIVERED if mode==Mode.DELIVERED else Mode.GROUND,"bed_path":bed_path if mode==Mode.DELIVERED else NodePath(),"poses":ragdoll.capture() if initialized else []}
