extends SceneTree
var failures:Array[String]=[]
func _initialize(): run.call_deferred()
func check(value:bool,label:String):
 print("PASS " if value else "FAIL ",label)
 if not value: failures.append(label)
func run():
 ProjectSettings.set_setting(BaseGameplayController.TEST_SAVE_PATH_SETTING,"user://weapon_vehicle_audio_test.cfg")
 var base=load("res://scenes/levels/Base_Blockout_v03.tscn").instantiate()
 root.add_child(base)
 root.get_node("GameMenu").force_close_menu()
 await process_frame
 var player=get_first_node_in_group("network_players")
 var weapon:WeaponController=player.weapon
 weapon.set_physics_process(false)
 weapon.apply_state(&"pistol",2,0)
 var sound:AudioStreamPlayer3D=weapon.get_node("ShotAudio")
 weapon._play_effect(false,&"pistol")
 check(sound.playing and sound.stream==weapon.pistol_sound,"pistol event plays its supplied single shot")
 check(weapon.pistol_sound.get_length()<1.6 and weapon.rifle_sound.get_length()<0.4,"clips contain one shot rather than a recorded series")
 weapon._play_effect(false,&"m4a1")
 check(sound.playing and sound.stream==weapon.rifle_sound,"authoritative event selects rifle audio even before inventory state arrives")
 await create_timer(0.1).timeout
 weapon._play_effect(false,&"m4a1")
 check(sound.playing and sound.max_polyphony>=4,"automatic fire permits overlapping shot tails")
 sound.stop()
 weapon._play_effect(true,&"pistol")
 check(not sound.playing,"reload does not play a gunshot")
 weapon._play_effect(false,&"kitchen_knife")
 check(not sound.playing,"knife does not play a gunshot")
 var vehicle=load("res://scenes/objects/vehicles/snowmobile.tscn").instantiate()
 vehicle.set_physics_process(false)
 root.add_child(vehicle)
 await process_frame
 var start:AudioStreamPlayer3D=vehicle.get_node("EngineStartAudio")
 var loop:AudioStreamPlayer3D=vehicle.get_node("EngineLoopAudio")
 var idle:AudioStreamPlayer3D=vehicle.get_node("EngineIdleAudio")
 var stop:AudioStreamPlayer3D=vehicle.get_node("EngineStopAudio")
 check(loop.stream.loop,"engine driving stream loops natively")
 vehicle.driver_peer=1
 vehicle.fuel_liters=0
 vehicle._update_engine_audio(0.1)
 check(not start.playing and not loop.playing,"empty tank stays silent")
 vehicle.fuel_liters=2
 vehicle._update_engine_audio(0.1)
 check(start.playing,"occupied fueled vehicle starts engine once")
 await create_timer(0.15).timeout
 var position:=start.get_playback_position()
 vehicle._update_engine_audio(0.1)
 check(start.get_playback_position()>=position,"startup clip is not restarted each frame")
 await create_timer(maxf(0.0, start.stream.get_length() - 0.55)).timeout
 vehicle._update_engine_audio(0.1)
 check(start.playing and idle.playing,"ignition overlaps idle near the end rather than cutting abruptly")
 await create_timer(0.8).timeout
 vehicle._update_engine_audio(1.0)
 check(idle.playing and not start.playing,"startup naturally switches to dedicated engine idle loop")
 var idle_pitch:=loop.pitch_scale
 var idle_volume:=loop.volume_db
 vehicle._speed=vehicle.max_speed
 vehicle._update_engine_audio(1.0)
 check(loop.pitch_scale>idle_pitch and loop.volume_db>idle_volume,"acceleration raises engine pitch and volume")
 vehicle.driver_peer=0
 vehicle._update_engine_audio(0.1)
 check(not start.playing and stop.playing,"leaving seat plays engine shutdown")
 vehicle._update_engine_audio(4.0)
 check(not loop.playing and not idle.playing,"engine loops fade out after shutdown")
 vehicle._receive_state(vehicle.global_transform,2.0,4,8.0)
 vehicle._update_engine_audio(0.1)
 check(not start.playing and loop.playing,"late observer hears running engine without replaying ignition")
 vehicle.fuel_liters=0
 vehicle._update_engine_audio(0.1)
 check(not start.playing and stop.playing,"fuel exhaustion plays engine shutdown")
 vehicle._update_engine_audio(4.0)
 check(not loop.playing and not idle.playing,"fuel exhaustion fades out engine loops")
 print("RESULT ",failures)
 quit(0 if failures.is_empty() else 1)
