extends SceneTree
var failures := 0
const SAVE = "user://medical_corpse_recovery_regression.cfg"
func _initialize(): run.call_deferred()
func check(ok:bool,label:String):
 print("PASS " if ok else "FAIL ",label)
 if not ok: failures += 1
func settle(frames:int=8):
 for i in frames: await physics_frame
func joint_gap(corpse:MedicalCorpse) -> float:
 var gap:=0.0
 for link in corpse._joint_links:
  var parent:RigidBody3D=corpse.ragdoll.bodies[link.parent]
  var child:RigidBody3D=corpse.ragdoll.bodies[link.child]
  gap=maxf(gap,(parent.global_transform*Vector3(link.parent_anchor)).distance_to(child.global_transform*Vector3(link.child_anchor)))
 return gap
func aim_at_bed(player:GamePlayer,bed:Node3D) -> bool:
 var reachable:=true
 for side in [Vector3(0,0,1.5),Vector3(0,0,-1.5),Vector3(2,0,0),Vector3(-2,0,0)]:
  player.global_position=bed.global_position+side
  for height in [-0.1,0.4,0.65]:
   player.camera.look_at(bed.global_position+Vector3(0,height,0))
   await settle(2)
   var target:=player.get_interaction_target()
   reachable=reachable and (target==bed or (target!=null and target.get_parent()==bed))
 return reachable
func press_e_at_bed(player:GamePlayer,bed:Node3D):
 player.camera.rotation=Vector3.ZERO
 player.global_position.y=bed.global_position.y-0.4
 var direction:Vector3=(bed.global_position+Vector3(0,0.4,0)-player.head.global_position).normalized()
 player._input_yaw=atan2(-direction.x,-direction.z)
 player._input_pitch=asin(direction.y)
 player._server_move=Vector2.ZERO
 player._server_sprint=false
 player._pad_sprint=false
 player.velocity=Vector3.ZERO
 Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
 player.set_physics_process(true)
 await settle(8)
 print("KEYBOARD E TARGET ",player.get_interaction_target()," busy ",player.corpse_action_busy)
 print("KEYBOARD CARRY ",player.is_carrying_corpse()," dead ",player.survival.dead," position ",player.global_position," mouse ",Input.mouse_mode)
 var event:=InputEventKey.new()
 event.physical_keycode=KEY_E
 event.pressed=true
 player.set_process_unhandled_input(true)
 # Headless cannot capture the mouse; windowed run verifies full keyboard routing.
 if DisplayServer.get_name()=="headless":
  player._interact_serial+=1
 else:
  Input.parse_input_event(event)
 await settle(4)
 print("E SERIAL ",player._interact_serial," server ",player._server_interact_serial," consumed ",player._server_consumed_interact_serial)
 event=InputEventKey.new()
 event.physical_keycode=KEY_E
 event.pressed=false
 Input.parse_input_event(event)
 await settle(2)
 player.set_process_unhandled_input(false)
func run():
 ProjectSettings.set_setting(BaseGameplayController.TEST_SAVE_PATH_SETTING,SAVE)
 DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
 var base=load("res://scenes/levels/Base_Blockout_v03.tscn").instantiate()
 root.add_child(base)
 root.get_node("GameMenu").force_close_menu()
 await settle(90)
 var state:BaseGameplayController=base.get_node("BaseGameplayController")
 var player:GamePlayer=get_first_node_in_group("network_players")
 player.set_physics_process(false)
 # Freeze live hardware events alongside movement during manual fixtures.
 # The keyboard-routing check enables them only for its E press/release.
 player.set_process_unhandled_input(false)
 player.survival.set_physics_process(false)
 player.survival.debug_invincible=true
 var data=state.get_snapshot()
 data.day_index=3
 data.main_breaker_on=true
 data.fuel_delivered=true
 data.fuel_liters=20.0
 state._broadcast_snapshot(data)
 var corpses=get_nodes_in_group("medical_corpses")
 check(corpses.size()==2,"two native corpses on level 2")
 var a:MedicalCorpse=corpses[0]
 var b:MedicalCorpse=corpses[1]
 check(a.initialized and b.initialized and a.ragdoll.bodies.size()==17 and b.ragdoll.bodies.size()==17,"same skeletal ragdoll system: 17 physical bones each")
 print("SPAWN ROOTS ",a.ragdoll.root_body.global_position," / ",b.ragdoll.root_body.global_position)
 check(a.ragdoll.root_body.global_position.y>-35 and b.ragdoll.root_body.global_position.y>-38,"bridge and reservoir support both ragdolls")
 player.global_position=a.ragdoll.root_body.global_position+Vector3(0,0,1)
 a.network_interact(player.owner_peer_id,player)
 check(a.mode==MedicalCorpse.Mode.LIFTING and player.corpse_action_busy,"E starts native pickup animation and locks locomotion")
 b.network_interact(player.owner_peer_id,player)
 check(b.mode==MedicalCorpse.Mode.GROUND,"cannot pick a second corpse while carrying")
 await create_timer(1.8).timeout
 check(a.mode==MedicalCorpse.Mode.CARRIED and player.is_carrying_corpse() and not player.corpse_action_busy,"pickup finishes with corpse attached to shoulder")
 player._server_sprint=true
 player._server_move=Vector2(0,-1)
 player._update_sprint(0.1)
 check(not player._sprint_active,"carrying disables sprint")
 check(not player.pickup_world_item_authoritative(&"pistol",{}),"carrying reserves both hands")
 check(not player.perform_inventory_action_authoritative(&"equip_pistol"),"cannot equip during carry")
 var before=a.ragdoll.root_body.global_position
 player.global_position+=Vector3(3,0,0)
 await settle()
 check(a.ragdoll.root_body.global_position.distance_to(player.get_node("CorpseShoulder").global_position)<0.05,"root follows shoulder while loose limbs simulate")
 var spread=0.0
 for bone in a.ragdoll.bodies: spread=maxf(spread,bone.global_position.distance_to(a.ragdoll.root_body.global_position))
 check(spread<1.8,"teleport keeps body together without stretched limbs")
 check(not a.ragdoll.bodies[5].freeze,"limbs remain physical while carried")
 var worst_gap:=0.0
 for frame in 120:
  player.global_position+=Vector3(0.04,0,0)
  player.rotation.y+=0.025
  await settle(1)
  worst_gap=maxf(worst_gap,joint_gap(a))
 print("CARRY JOINT GAP ",worst_gap)
 check(worst_gap<0.05,"walking and turning transport the whole chain without stretching joints")
 await settle(480)
 var idle_pose:=a.ragdoll.capture()
 var idle_drift:=0.0
 var idle_speed:=0.0
 var idle_spin:=0.0
 for frame in 120:
  await settle(1)
  for index in a.ragdoll.bodies.size():
   var body:RigidBody3D=a.ragdoll.bodies[index]
   idle_drift=maxf(idle_drift,body.global_position.distance_to(idle_pose[index].origin))
   idle_speed=maxf(idle_speed,body.linear_velocity.length())
   idle_spin=maxf(idle_spin,body.angular_velocity.length())
 print("IDLE CARRY drift ",idle_drift," velocity ",idle_speed," spin ",idle_spin)
 check(idle_drift<0.015 and idle_speed<0.05 and idle_spin<0.25,"stationary shoulder carry settles without continuous repetitive shaking")
 player.rotation.y+=0.3
 player.global_position+=Vector3(0.15,0,0)
 await settle(3)
 check(not a.ragdoll.bodies[5].freeze and not a.ragdoll.bodies[5].sleeping,"moving carrier wakes loose limbs instead of leaving a rigid sleeping pose")
 check(state.maintenance.get("corpse_recovery",{}).get("picked_up",false),"pickup creates journal objective")
 var journal=root.get_node("QuestJournal")
 journal._refresh_content()
 check(journal.tasks_label.text.contains("признаки жизни"),"journal records examination note on pickup")
 var audio=player.get_node("PlayerAudio")
 audio.update_breathing(0.5,false,true,true)
 check(audio.recovery.playing and audio._recovery_left>0,"walking with corpse starts exertion breathing")
 check(not player.toggle_flashlight_authoritative(),"cannot pull flashlight into occupied hands")

 check(player.drop_current_item_authoritative(),"G releases corpse")
 check(a.mode==MedicalCorpse.Mode.GROUND and not player.is_carrying_corpse(),"drop restores ground physics and frees hands")
 var restored_physics:=true
 for index in a.ragdoll.bodies.size():
  var body:RigidBody3D=a.ragdoll.bodies[index]
  restored_physics=restored_physics and not body.freeze and is_equal_approx(body.linear_damp,a._ground_damping[index].x) and is_equal_approx(body.angular_damp,a._ground_damping[index].y)
 for link in a._joint_links:
  restored_physics=restored_physics and is_equal_approx(link.joint.swing_span,link.swing) and is_equal_approx(link.joint.twist_span,link.twist)
 check(restored_physics,"dropping restores all ground damping and original joint limits")
 player.global_position=a.ragdoll.root_body.global_position+Vector3(0,0,1)
 a.network_interact(player.owner_peer_id,player)
 await create_timer(1.8).timeout
 player.survival.dead=true
 await settle(3)
 check(a.mode==MedicalCorpse.Mode.GROUND and not player.is_carrying_corpse(),"carrier death releases corpse instead of moving it to respawn")
 player.survival.dead=false

 await settle(5)
 player.global_position=a.ragdoll.root_body.global_position+Vector3(0,0,1)
 a.network_interact(player.owner_peer_id,player)
 check(a.mode==MedicalCorpse.Mode.LIFTING,"body can be picked up again after carrier death settles")
 await create_timer(1.8).timeout
 check(a.mode==MedicalCorpse.Mode.CARRIED and player.is_carrying_corpse(),"carrier recovers the body before visiting first bed")
 var bed=base.get_node("Floor_0_Base_Blockout/East_Living/Art/MedicalRoomArt/Blockout/Medical_Room/Examination/Medical_Exam_Bed_Blockout")
 var bed2=base.get_node("Floor_0_Base_Blockout/East_Living/Art/MedicalRoomArt/Blockout/Medical_Room/Examination/Medical_Exam_Bed_Secondary_Blockout")
 check(await aim_at_bed(player,bed),"first bed is reachable through real interaction ray from all sides at frame and mattress heights")
 player.global_position=bed.global_position+Vector3(0,0,1.3)
 await press_e_at_bed(player,bed)
 player.set_physics_process(false)
 check(a.mode==MedicalCorpse.Mode.PLACING and player.corpse_action_busy and bed.is_occupied(),"bed interaction reserves bed and plays placement clip")
 var placement_gap:=0.0
 for frame in 100:
  await settle(1)
  placement_gap=maxf(placement_gap,joint_gap(a))
 await create_timer(0.4).timeout
 check(placement_gap<0.10,"placement animation keeps anatomical attachments connected")
 check(a.mode==MedicalCorpse.Mode.DELIVERED and not player.is_carrying_corpse(),"placement completes without throwing corpse")
 check(state.maintenance.get("corpse_recovery",{}).get("delivered",[]).has(a.corpse_id),"delivery progress saved in existing campaign state")
 await create_timer(2.5).timeout
 print("BED ROOT ",a.ragdoll.root_body.global_position," marker ",bed.get_node("RestPose").global_position)
 check(a.ragdoll.root_body.global_position.distance_to(bed.get_node("RestPose").global_position)<0.6,"corpse rests on actual native hospital bed")
 journal._refresh_content()
 check(journal.tasks_label.text.contains("1/1") and not journal.tasks_label.text.contains("/2"),"one bridge body completes delivery objective")
 check(b.mode==MedicalCorpse.Mode.GROUND and not b.recoverable and b.get_node("InteractionArea").collision_layer==0,"reservoir corpse stays scenery without pickup interaction")
 player.global_position=b.ragdoll.root_body.global_position+Vector3(0,0,1)
 b.network_interact(player.owner_peer_id,player)
 check(b.mode==MedicalCorpse.Mode.GROUND and not player.is_carrying_corpse(),"reservoir body cannot be collected even through direct interaction")
 # Reuse only the bridge body as an isolated fixture to test the other bed.
 a._broadcast_status(MedicalCorpse.Mode.CARRIED,player.owner_peer_id,NodePath(),a.ragdoll.capture(),0.0)
 check(await aim_at_bed(player,bed2),"second visible bed is reachable through real interaction ray from all sides")
 player.global_position=bed2.global_position+Vector3(0,0,1.3)
 await press_e_at_bed(player,bed2)
 await create_timer(2.0).timeout
 player.set_physics_process(false)
 check(a.mode==MedicalCorpse.Mode.DELIVERED and state.maintenance.get("corpse_recovery",{}).get("delivered",[]).size()==1,"keyboard E places the bridge body on second bed without requiring acid body")
 var next_day=state.get_snapshot()
 next_day.day_index=4
 state._broadcast_snapshot(next_day)
 journal._refresh_content()
 check(journal.tasks_label.text.contains("признаки жизни"),"examination note survives day transition")
 state.save_progress_authoritative()
 var saved=state.load_saved_snapshot()
 check(saved.maintenance.corpse_recovery.bodies["0"].poses.size()==17 and saved.maintenance.corpse_recovery.bodies["1"].mode==MedicalCorpse.Mode.GROUND,"checkpoint includes each full physical pose and bed")
 base.queue_free()
 await settle()
 base=load("res://scenes/levels/Base_Blockout_v03.tscn").instantiate()
 root.add_child(base)
 await settle(12)
 corpses=get_nodes_in_group("medical_corpses")
 check(corpses[0].mode==MedicalCorpse.Mode.DELIVERED and corpses[1].mode==MedicalCorpse.Mode.GROUND,"reload preserves delivered corpses rather than respawning on level 2")
 base.queue_free()
 await settle()
 var config:=ConfigFile.new()
 config.load(SAVE)
 var maintenance:Dictionary=config.get_value("base","maintenance",{}).duplicate(true)
 maintenance.corpse_recovery.bodies["0"].bed_path=NodePath("Floor_0_Base_Blockout/East_Living/Art/MedicalRoomArt/MedicalBedB")
 config.set_value("base","maintenance",maintenance)
 config.save(SAVE)
 base=load("res://scenes/levels/Base_Blockout_v03.tscn").instantiate()
 root.add_child(base)
 await settle(12)
 var restored:MedicalCorpse=get_nodes_in_group("medical_corpses")[0]
 var restored_bed=base.get_node("Floor_0_Base_Blockout/East_Living/Art/MedicalRoomArt/Blockout/Medical_Room/Examination/Medical_Exam_Bed_Secondary_Blockout")
 check(restored.bed_path==base.get_path_to(restored_bed) and restored_bed.is_occupied(),"old invisible-bed save paths migrate to actual visible beds")
 base.queue_free()
 await settle()
 DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
 print("RESULT FAILURES ",failures)
 quit(1 if failures else 0)
